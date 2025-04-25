import subprocess
import csv

# 32-bit, 64-bit, 128-bit, 256-bit, 512-bit
spad_sizing = [(64,12)]
# spad_sizing = [(32,13)]
dimensions = [32, 64]
# dimensions = [8]

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


def write_testbench_parameters(input_size, 
                               input_channels, 
                               output_channels, 
                               stride, 
                               precision, 
                               layer_identifier,
                                input_file,
                                weight_file,
                                cycle_file,
                               ):
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
    `define PRECISION {p_mode}
    `define LAYER_IDENTIFIER {layer_identifier}
    `define INPUT_FILE "{input_file}"
    `define WEIGHT_FILE "{weight_file}"
    `define CYCLE_FILE "{cycle_file}"
    """

    with open("sim/tb_top.svh", "w") as file:
        file.write(header)


def generate_simv_command(
    conv_mode,
    input_size,
    input_channels,
    output_channels,
    output_size,
    stride,
    precision,
    layer_identifier,
    input_file,
    weight_file,
    cycle_file,
    output_file
):
    p_mode = 0
    if precision == 4:
        p_mode = 1
    elif precision == 2:
        p_mode = 2

    cmd = (
        f"./simv "
        f"+CONV_MODE={conv_mode} "
        f"+INPUT_SIZE={input_size} "
        f"+INPUT_CHANNELS={input_channels} "
        f"+OUTPUT_CHANNELS={output_channels} "
        f"+OUTPUT_SIZE={output_size} "
        f"+STRIDE={stride} "
        f"+PRECISION={p_mode} "
        f"+LAYER_IDENTIFIER={layer_identifier} "
        f'+INPUT_FILE="{input_file}" '
        f'+WEIGHT_FILE="{weight_file}" '
        f'+CYCLE_FILE="{cycle_file}" '
        f'+OUTPUT_FILE="{output_file}"'
    )
    return cmd


def main():
    csv_path = "vww/metadata.csv"

    for d in dimensions:
        for spad in spad_sizing:
            spad_data_width, addr_width = spad
            rows = d
            cols = d
            miso_depth = d
            mpp_depth = 9

            write_system_parameters(spad_data_width, addr_width, rows, cols, miso_depth, mpp_depth)
            # Synthesize design
            sim_command = "vcs -f ../filelist.txt -full64 -sverilog -debug_pp"
            subprocess.run(sim_command, shell=True)
            print(f"Compilation completed for {d}x{d}x{d} with SPAD data width {spad_data_width}\n")
            
            with open(csv_path, mode='r') as file:
                reader = csv.DictReader(file)
                for row in reader:
                    identifier = row['Identifier']
                    h = int(row['H/W'])
                    w = int(row['H/W'])
                    c_i = int(row['C'])
                    c_o = int(row['Oc'])
                    stride = int(row['Stride'])
                    type = row['Type']
                    
                    # 0 for Pointwise and 1 for Depthwise
                    conv_mode = 0 if type == "P" else 1

                    if conv_mode == 0:
                        continue
                    
                    out_size = h if type == "P" else ((h-3) // stride) + 1
                    i_filename = f"vww/{spad_data_width}_bits/inputs/{identifier}.txt"
                    w_filename = f"vww/{spad_data_width}_bits/weights/{identifier}.txt"
                    o_filename = f"{d}_{d}_{d}_{spad_data_width}_output.txt"

                    for precision in [2, 4, 8]:
                        cycle_file = f"{precision}b_{d}_{d}_{d}_{spad_data_width}_cycle.txt"
                        tb_cmd = generate_simv_command(
                            conv_mode,
                            h,
                            c_i,
                            c_o,
                            out_size,
                            stride,
                            precision,
                            identifier,
                            i_filename,
                            w_filename,
                            cycle_file,
                            o_filename
                        )
                        
                        print(f"Processing {identifier} with {precision}-bit precision and dimensions {h}x{w}x{c_i} and SPAD data width {spad_data_width}\n")
                        subprocess.run(tb_cmd, shell=True)

if __name__ == "__main__":
    main()