import argparse
import subprocess
import sys

def generate_sequential_array(input_size, precision):
    max_value = 1 << precision
    total_elements = input_size * input_size
    array_1d = [i % max_value for i in range(total_elements)]
    
    array_2d = []
    for row_index in range(input_size):
        start = row_index * input_size
        end = start + input_size
        array_2d.append(array_1d[start:end])
    
    return array_2d

def convert_nchw_to_nhwc(nchw_array):
    channels = len(nchw_array)
    height = len(nchw_array[0])
    width = len(nchw_array[0][0])

    # Initialize NHWC array with shape (height, width, channels)
    nhwc_array = [[[nchw_array[c][h][w] for c in range(channels)] 
                   for w in range(width)] 
                   for h in range(height)]
    
    return nhwc_array

def poinwise_convolution_nhwc(ifmap, kernel, TILING_C, TILING_HW):
    H = len(ifmap)          # Number of rows
    W = len(ifmap[0])       # Number of columns
    C = len(ifmap[0][0])    # Number of channels

    # For kernel with shape (C_out, C_in)
    C_out = len(kernel)
    C_in  = len(kernel[0])
    output_file = "golden_output.txt"

    with open(output_file, "w") as f:
        for c0 in range(0, C_out, TILING_C):
            for hw0 in range(0, H * W, TILING_HW):
                for c in range(c0, min(c0 + TILING_C, C_out)):
                    for hw in range(hw0, min(hw0 + TILING_HW, H * W)):
                        h = hw // W
                        w = hw % W
                        
                        # Calculate the dot product
                        result = 0
                        for i in range(len(ifmap[h][w])):
                            input_val = to_precision(ifmap[h][w][i],8)
                            kernel_val= to_precision(kernel[c][i],8)
                            result += input_val*kernel_val
                        
                        quant = (to_precision(result,16,signed=False) * 40076)>>(16+5)
                        
                        f.write(f"{quant if quant < 256 else 255}\n")

def to_precision(num,bits,signed=True):
    n = num & ((1<<bits)-1)
    if (n & 1<<(bits-1)) and signed:
        n = n - (1<<(bits))
    return n

def flatten_3d_array(arr):
    return [item for row in arr for col in row for item in col]

def flatten_2d_array(a):
    return [i for r in a for i in r]

def sram_hex_to_mem(array, n, filename):
    if n <= 0:
        print("Group size must be greater than 0.")
        return
    
    try:
        with open(filename, 'w') as file:
            # Iterate through the array in steps of n
            for i in range(0, len(array), n):
                # Slice the array to get the group
                group = array[i:i + n]
                # Reverse the group, convert each element to hex, and join as a single string
                hex_string = ''.join(f"{x:02x}" for x in reversed(group))
                file.write(hex_string + '\n')
        
        print(f"Data successfully written to {filename}")
    except IOError as e:
        print(f"An error occurred while writing to the file: {e}")

def write_testbench_parameters(input_size, input_channels, output_channels, stride, precision):
    p_mode = 0
    if precision == 4:
        p_mode = 1
    elif precision == 2:
        p_mode = 2

    header = f"""
    `define INPUT_SIZE {input_size}
    `define INPUT_CHANNELS {input_channels}
    `define OUTPUT_CHANNELS {output_channels}
    `define OUTPUT_SIZE {input_size}
    `define STRIDE {stride}
    `define PRECISION {p_mode}"""

    with open("sim/tb_top.svh", "w") as file:
        file.write(header)

def write_system_parameters(spad_data_width, addr_width, rows, cols, miso_depth, mpp_depth):
    header = f"""
    `define DATA_WIDTH {8}
    `define SPAD_DATA_WIDTH {spad_data_width}
    `define SPAD_N {spad_data_width // 8}
    `define ADDR_WIDTH {addr_width}
    `define ROWS {rows}
    `define COLUMNS {cols}
    `define MISO_DEPTH {miso_depth}
    `define MPP_DEPTH {mpp_depth}"""

    with open("rtl/global.svh", "w") as file:
        file.write(header)

def main():
    parser = argparse.ArgumentParser(description="Process input parameters.")
    parser.add_argument("input_size", type=int, help="Size of input")
    parser.add_argument("input_channels", type=int, help="Number of input channels")
    parser.add_argument("output_channels", type=int, help="Number of output channels")
    parser.add_argument("stride", type=int, help="Stride value")
    parser.add_argument("precision", type=int, help="Precision value")
    parser.add_argument("type", type=str, help="Type of testbench to run")
    # parser.add_argument("c_tile", type=int, help="Size of C tile")
    # parser.add_argument("hw_tile", type=int, help="Size of HW tile")

    args = parser.parse_args()

    input_size = args.input_size
    input_channels = args.input_channels
    output_channels = args.output_channels
    stride = args.stride
    precision = args.precision
    tb_type = args.type
    c_tile = 10
    hw_tile = 10

    ifmap = []
    for _ in range(input_channels):
        ifmap.append(generate_sequential_array(input_size, 8))

    ifmap = convert_nchw_to_nhwc(ifmap)

    # Already in NHWC format
    kernel = []
    for i in range(output_channels):
        kernel.append([64*(i+1)] * input_channels)

    k_flat = flatten_2d_array(kernel)
    i_flat = flatten_3d_array(ifmap)


    # Write golden output
    poinwise_convolution_nhwc(ifmap, kernel, c_tile, hw_tile)

    # Write system parameters
    data_width = 8
    spad_data_width = 128
    spad_n = spad_data_width // 8
    addr_width = 16
    rows = c_tile
    cols = c_tile
    miso_depth = 16
    mpp_depth = 9
    write_system_parameters(spad_data_width, addr_width, rows, cols, miso_depth, mpp_depth)
    print(f"System parameters written to rtl/global.svh")
    print("-" * 60)
    print(f"Data width: {data_width}, SPAD data width: {spad_data_width}, Address width: {addr_width}\nRows: {rows}, Columns: {cols}, MISO depth: {miso_depth}, MPP depth: {mpp_depth}")
    print("-" * 60)
    print(f"Testbench parameters written to sim/tb_top.svh")

    # Run Iverilog testbench
    write_testbench_parameters(input_size, input_channels, output_channels, stride, precision)


    sram_hex_to_mem(k_flat, spad_n, 'kernel.mem')
    sram_hex_to_mem(i_flat, spad_n, 'ifmap.mem')

    if tb_type == "l":
        # sim_command = "xargs -a filelist.txt iverilog -g2012 -o dsn"
        sim_command = "iverilog -g2012 -o dsn -f filelist.txt"
        subprocess.run(sim_command, shell=True)
    
        subprocess.run("vvp dsn", shell=True)
    else:
        vcs_cmd = "vcs tb_top.sv ../mapped/top_mapped.v /cad/tools/libraries/dwc_logic_in_gf22fdx_sc7p5t_116cpp_base_csc20l/GF22FDX_SC7P5T_116CPP_BASE_CSC20L_FDK_RELV02R80/model/verilog/GF22FDX_SC7P5T_116    CPP_BASE_CSC20L.v /cad/tools/libraries/dwc_logic_in_gf22fdx_sc7p5t_116cpp_base_csc20l/GF22FDX_SC7P5T_116CPP_BASE_CSC20L_FDK_RELV02R80/model/verilog/prim.v -sverilog -full64 -debug_pp +neg_tchk -R -l v cs.log"
        subprocess.run(vcs_cmd, shell=True)
    
    # Check if the difference of output and golden_output
    sim_command = "diff output.txt golden_output.txt"
    # subprocess.run(sim_command, shell=True)
    print(f"System prope")
    try:
        with open("output.txt", "r") as o_file, open("golden_output.txt", "r") as go_file:
            print("\nVerifying output against golden output...")
            print("-" * 60)
            print(f"Input Size: {input_size}, Output Size: {input_size}\nInput Channels: {input_channels}, Output Channel: {output_channels}\nStride: {stride}, Precision Mode: {precision}")
            print("-" * 60)
            match = 0
            total = 0
            error = 0
            for result_line, golden_line in zip(o_file, go_file):
                result = result_line.strip() if result_line.strip() else None
                golden = golden_line.strip() if golden_line.strip() else None

                if result == golden:
                    match += 1
                    # print(f"OUTPUT MATCH {result} (result) == {golden} (golden)")
                else:
                    error += 1
                    # print(f"OUTPUT MISMATCH {result} (result) != {golden} (golden)")

                total += 1

            print(f"match rate: {match}/{total} ({(match / total) * 100:.2f}%)")
            # Check if one file is longer than the other
            extra_output = o_file.readline().strip()
            extra_golden = go_file.readline().strip()

            if extra_output:
                print("Warning: output.txt has extra lines not found in golden_output.txt.")
            if extra_golden:
                print("Warning: golden_output.txt has extra lines not found in output.txt.")

    except FileNotFoundError:
        print("Error opening output file!")
        sys.exit(1)


if __name__ == "__main__":
    main()
