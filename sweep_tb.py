import subprocess
import csv

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

    sweep = [(16,32,13), (16, 64, 12), (16, 128, 11), (16, 256, 10), (16, 512, 9), 
             (32, 32, 13), (32, 64, 12), (32, 128, 11), (32, 256, 10), (32, 512, 9), 
             (64, 32, 13), (64, 64, 12), (64, 128, 11), (64, 256, 10), (64, 512, 9), 
             (128, 32, 13), (128, 64, 12), (128, 128, 11), (128, 256, 10), (128, 512, 9),
             (256, 32, 13), (256, 64, 12), (256, 128, 11), (256, 256, 10), (256, 512, 9),
             (512, 32, 13), (512, 64, 12), (512, 128, 11), (512, 256, 10), (512, 512, 9),
             (1024, 32, 13), (1024, 64, 12), (1024, 128, 11), (1024, 256, 10), (1024, 512, 9),
             ]

    for d, spad_data_width, addr_width in sweep:
        rows = cols = miso_depth = d
        mpp_depth = 9
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
                
                out_size = h if type == "P" else ((h-3) // stride) + 1
                i_filename = f"vww/{spad_data_width}_bits/inputs/{identifier}.txt"
                w_filename = f"vww/{spad_data_width}_bits/weights/{identifier}.txt"
                o_filename = f"data/out/{d}_{d}_{d}_{spad_data_width}_output.txt"

                for precision in [2, 4, 8]:
                    cycle_file = f"data/cycles/{precision}b_{d}_{d}_{d}_{spad_data_width}_cycle.txt"
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
                    
                    print(f"Processing {identifier} with {precision}-bit precision and dimensions {d}x{d}x{d} and SPAD data width {spad_data_width}\n")
                    subprocess.run(tb_cmd, shell=True)

                    with open("simulation_log.txt", "a") as log_file:
                        log_file.write(f"Finished {identifier} with {precision}-bit precision and dimensions {d}x{d}x{d} and SPAD data width {spad_data_width}\n")

if __name__ == "__main__":
    main()