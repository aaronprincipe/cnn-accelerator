import argparse
import subprocess
import sys
import random
from time import time
import numpy as np

# adjusted for the person detection weights! please change the file name in the kernel portion to the layer weight

def generate_sequential_array(input_size, precision):
    max_value = 1 << precision
    total_elements = input_size * input_size
    array_1d = [(i+1) % max_value for i in range(total_elements)]
    
    array_2d = []
    for row_index in range(input_size):
        start = row_index * input_size
        end = start + input_size
        array_2d.append(array_1d[start:end])
    
    return array_2d

def generate_random_array(input_size, precision, max_value):
    limit = 1 << (precision-1)                  # account for signed values
    max_value_offset = min(max_value, limit-1) - 128   # account for zero point adjustment
    #print(f"Generating random array with max value {max_value_offset} to avoid overflow after quantization")
    
    total_elements = input_size * input_size
    array_1d = [int(random.uniform(-128,max_value_offset)) for _ in range(total_elements)] # without offset, values are [0, max_value]
    
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

def pointwise_convolution_nhwc(ifmap, kernel, TILING_C, TILING_HW, spad_n, m0, sh, stride=1, i_zero_point=-128, o_zero_point=-128):
    # Add support for biases
    
    H = len(ifmap)          # Input rows
    W = len(ifmap[0])       # Input columns
    C = len(ifmap[0][0])    # Input channels

    # For kernel with shape (C_out, C_in)
    C_out = len(kernel)
    C_in  = len(kernel[0])
    output_file = "golden_output.txt"

    # print input dimensions and parameters
    # print(f"Input dimensions: H={H}, W={W}, C={C}")
    # Output spatial dimensions for no-padding conv: floor((H - 1)/stride) + 1
    H_out = (H - 1) // stride + 1
    W_out = (W - 1) // stride + 1
    # print(stride)
    # print(f"Output dimensions will be: H_out={H_out}, W_out={W_out}, C_out={C_out}")

    # Allocate output matrix in HWC format (H_out x W_out x C_out)
    product = [[[0 for _ in range(C_out)] for _ in range(W_out)] for _ in range(H_out)]

    start = time()
    
    # 1) Compute outputs taking stride into account
    for h_out in range(H_out):
        h_in = h_out * stride
        for w_out in range(W_out):
            w_in = w_out * stride
            for c in range(C_out):
                result = 0
                # multiply across channels
                for i in range(len(ifmap[h_in][w_in])):
                    input_val  = to_precision(ifmap[h_in][w_in][i], 8) - i_zero_point
                    kernel_val = to_precision(kernel[c][i], 8)
                    result += input_val * kernel_val

                quant = ((to_precision(result, 16) * m0) >> (16 + sh)) + o_zero_point
                if quant < -128:
                    quant = -128
                elif quant > 127:
                    quant = 127
                
                # print(f"Output pixel ({h_out}, {w_out}, {c}): result={result}, quantized={quant}")
                product[h_out][w_out][c] = quant

    end = time()
    print(f"Golden output computed in {end - start:.10f} seconds")
    # print(product)
    
    # 2) Write to file grouping spad_n elements per line
    with open(output_file, "w") as f:
        line_buffer = []

        for h_out in range(H_out):
            for w_out in range(W_out):
                for c in range(C_out):
                    val = product[h_out][w_out][c]
                    line_buffer.append(f"{to_precision(val, 8, signed=False):02x}")

                    if len(line_buffer) == spad_n:
                        f.write("".join(reversed(line_buffer)) + "\n")
                        line_buffer = []

        # Write remaining elements if any
        if line_buffer:
            padding = spad_n - len(line_buffer)
            line_buffer.extend(["00"] * padding)  # Pad with zeros if needed
            f.write("".join(reversed(line_buffer)) + "\n")

    print("Golden output written successfully")

def depthwise_convolution_nhwc(ifmap, kernel, TILING_C, TILING_HW, spad_n, m0, sh, stride=1, i_zero_point=-128, o_zero_point=-128):
    # Modify this to account for changes in quantization, like in pointwise convolution
    H = len(ifmap)          # Input rows
    W = len(ifmap[0])       # Input columns
    C = len(ifmap[0][0])    # Input channels

    # For kernel with shape (C_out, C_in)
    C_in  = len(kernel[0])
    output_file = "golden_output.txt"

    # Output spatial dimensions for no-padding conv: floor((H - 3)/stride) + 1, assume input is already padded
    H_out = (H - 3) // stride + 1 # account for 3x3 kernel
    W_out = (W - 3) // stride + 1 # account for 3x3 kernel

    # Allocate output matrix in HWC format (H_out x W_out x C_out)
    product = [[[0 for _ in range(C_in)] for _ in range(W_out)] for _ in range(H_out)]

    start = time()

    # 1) Compute outputs taking stride into account
    for h in range(H_out):
        h_start = h * stride
        for w in range(W_out):
            w_start = w * stride
            for c in range(C_in):
                sum_value = 0
                # multiply across channels
                for ki in range(3):
                    for kj in range(3):
                        # print(f"Processing output pixel ({h}, {w}, {c}), kernel position ({ki}, {kj})")
                        input_val  = to_precision(ifmap[h_start + ki][w_start + kj][c], 8) - i_zero_point
                        kernel_val = to_precision(kernel[ki*3+kj][c], 8)
                        sum_value += input_val * kernel_val

                quant = ((to_precision(sum_value, 16) * m0) >> (16 + sh)) + o_zero_point
                if quant < -128:
                    quant = -128
                elif quant > 127:
                    quant = 127

                product[h][w][c] = quant

    end = time()
    print(f"Golden output computed in {end - start:.10f} seconds")

    # 2) Write to file grouping spad_n elements per line
    with open(output_file, "w") as f:
        line_buffer = []

        for h_out in range(H_out):
            for w_out in range(W_out):
                for c in range(C_in):
                    val = product[h_out][w_out][c]
                    line_buffer.append(f"{to_precision(val, 8, signed=False):02x}")

                    if len(line_buffer) == spad_n:
                        f.write("".join(reversed(line_buffer)) + "\n")
                        line_buffer = []

        # Write remaining elements if any
        if line_buffer:
            padding = spad_n - len(line_buffer)
            line_buffer.extend(["00"] * padding)  # Pad with zeros if needed
            f.write("".join(reversed(line_buffer)) + "\n")

    print("Golden output written successfully")

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
                hex_string = ''.join(f"{to_precision(x, 8, signed=False):02x}" for x in reversed(group))
                file.write(hex_string + '\n')
        
        print(f"Data successfully written to {filename}")
    except IOError as e:
        print(f"An error occurred while writing to the file: {e}")

def write_testbench_parameters(input_size, input_channels, output_channels, stride, precision, conv_mode):
    p_mode = 0
    if precision == 4:
        p_mode = 1
    elif precision == 2:
        p_mode = 2

    # compute output size for no-padding convolution, i.e. assume input is already padded
    if conv_mode == 0:
        output_size = (input_size - 1) // stride + 1
    else: 
        output_size = (input_size - 3) // stride + 1 # account for 3x3 kernel in depthwise conv

    header = f"""
`define INPUT_SIZE {input_size}
`define INPUT_CHANNELS {input_channels}
`define OUTPUT_CHANNELS {output_channels}
`define OUTPUT_SIZE {output_size}
`define STRIDE {stride}
`define PRECISION {p_mode}
`define CONV_MODE {conv_mode}"""

    with open("tb_top.svh", "w") as file:
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

    with open("../rtl/global.svh", "w") as file:
        file.write(header)

def load_mem_to_array(filename, shape): # this is new
    """Reverts sram_hex_to_mem formatting to load weights into Python."""
    data_8bit = []
    with open(filename, 'r') as f:
        for line in f:
            hex_str = line.strip()
            # Split into 2-character bytes and un-reverse them
            bytes_hex = [hex_str[i:i+2] for i in range(0, len(hex_str), 2)]
            for b in reversed(bytes_hex):
                val = int(b, 16)
                # Convert unsigned hex back to signed int8
                if val > 127: val -= 256 
                data_8bit.append(val)
    
    total_elements = 1
    for dim in shape: total_elements *= dim
    return np.array(data_8bit[:total_elements]).reshape(shape)

def main():
    parser = argparse.ArgumentParser(description="Process input parameters.")
    parser.add_argument("input_size"     , type=int, help="Size of input")
    parser.add_argument("input_channels" , type=int, help="Number of input channels")
    parser.add_argument("output_channels", type=int, help="Number of output channels")
    parser.add_argument("stride"         , type=int, help="Stride value")
    parser.add_argument("precision"      , type=int, help="Precision value")
    parser.add_argument("conv_mode"      , type=int, help="0 - pwise, 1 - dwise")
    parser.add_argument("type"           , type=str, help="Type of testbench to run")
    # parser.add_argument("c_tile"         , type=int, help="Size of C tile")
    # parser.add_argument("hw_tile"        , type=int, help="Size of HW tile")

    args = parser.parse_args()

    input_size = args.input_size
    input_channels = args.input_channels
    output_channels = args.output_channels
    stride = args.stride
    precision = args.precision
    tb_type = args.type
    conv_mode = args.conv_mode
    c_tile = 16
    hw_tile = 16
    m0 = 40076
    sh = 5

    # Fake Padding
    if conv_mode == 1: # depthwise convolution
        # padding = kernel - stride,         for input_size % stride == 0 (which is true for person detection model)
        padding = 3 - stride # assuming 3x3 kernel 
        input_size += padding
        # in reality, we would need to add zero padding to the input feature map 
        # but for simplicity we will just increase the input size and generate random data for the padded region.

    # Generate random input data
    ifmap = []
    if conv_mode == 0: # pointwise convolution
        ifmap_max_value = 127 / (input_channels*3*m0/2**(16+sh)) # to avoid overflow. assumes kernel values are in range [-3, 3]
    else: # depthwise convolution
        ifmap_max_value = 127 / (9*3*m0/2**(16+sh))              # to avoid overflow. assumes kernel values are in range [-3, 3] and 3x3=9 kernel size
    # print(ifmap_max_value)
    for _ in range(input_channels):
        # ifmap.append(generate_sequential_array(input_size, 8))
        ifmap.append(generate_random_array(input_size, 8, ifmap_max_value))

    ifmap = convert_nchw_to_nhwc(ifmap)

    # Generate random kernel data
    # Already in NHWC format
    # 1. Initialize kernel variable
    kernel = []

    # 2. Load Real Weights from your extracted file
    # For Layer 2 PW, ensure your output_channels=128 and input_channels=64
    weight_path = r"C:\Users\marie\person_tflite_weights\layer2_pw_weights.mem"
    
    if conv_mode == 0: # Pointwise
        # Shape: (OC, IC)
        kernel = load_mem_to_array(weight_path, (output_channels, input_channels))
        print(f"Loaded Pointwise weights from {weight_path}")
    else: # Depthwise
        # Shape: (9, IC) for your specific 3x3 implementation
        kernel = load_mem_to_array(weight_path, (9, input_channels))
        print(f"Loaded Depthwise weights from {weight_path}")

    # DO NOT use the random.uniform loops here anymore!
    # The kernel is already fully populated by load_mem_to_array.

    #print(f"ifmap: {ifmap}")
    #print(f"kernel: {kernel}")
    k_flat = flatten_2d_array(kernel)
    i_flat = flatten_3d_array(ifmap)


    # Write system parameters
    data_width = 8
    spad_data_width = 32
    spad_n = spad_data_width // 8
    addr_width = 16
    rows = hw_tile
    cols = c_tile
    miso_depth = 16
    mpp_depth = 9
    write_system_parameters(spad_data_width, addr_width, rows, cols, miso_depth, mpp_depth)
    print(f"System parameters written to rtl/global.svh")
    print("-" * 60)
    print(f"Data width: {data_width}, SPAD data width: {spad_data_width}, Address width: {addr_width}")
    print(f"Rows: {rows}, Columns: {cols}, MISO depth: {miso_depth}, MPP depth: {mpp_depth}")
    print("-" * 60)
    print(f"Testbench parameters written to sim/tb_top.svh")

    # Run Iverilog testbench
    write_testbench_parameters(input_size, input_channels, output_channels, stride, precision, conv_mode)

    
    sram_hex_to_mem(k_flat, spad_n, 'weights.txt')
    sram_hex_to_mem(i_flat, spad_n, 'inputs.txt' )

    # Write golden output (respect stride)
    if conv_mode == 0: # pointwise convolution
        golden_output = pointwise_convolution_nhwc(ifmap, kernel, c_tile, hw_tile, spad_n, m0, sh, stride, i_zero_point=-128, o_zero_point=-128)
    else: # depthwise convolution
        golden_output = depthwise_convolution_nhwc(ifmap, kernel, c_tile, hw_tile, spad_n, m0, sh, stride, i_zero_point=-128, o_zero_point=-128)

    return

    if tb_type == "l":
        # sim_command = "xargs -a ../filelist.txt iverilog -g2012 -o dsn"
        sim_command = "iverilog -g2012 -o dsn -f ../filelist.txt"
        subprocess.run(sim_command, shell=True)
        subprocess.run("vvp dsn"  , shell=True)
    else:
        vcs_cmd = "vcs tb_top.sv ../mapped/top_mapped.v /cad/tools/libraries/dwc_logic_in_gf22fdx_sc7p5t_116cpp_base_csc20l/GF22FDX_SC7P5T_116CPP_BASE_CSC20L_FDK_RELV02R80/model/verilog/GF22FDX_SC7P5T_116CPP_BASE_CSC20L.v /cad/tools/libraries/dwc_logic_in_gf22fdx_sc7p5t_116cpp_base_csc20l/GF22FDX_SC7P5T_116CPP_BASE_CSC20L_FDK_RELV02R80/model/verilog/prim.v -sverilog -full64 -debug_pp +neg_tchk -R -l v cs.log"
        subprocess.run(vcs_cmd    , shell=True)
    
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
