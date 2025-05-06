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

    print("global.svh file has been generated.")


def write_compile_tcl(dimension, spad_width):
    """
    Generate a Synopsys Design Compiler script (compile.tcl)
    with the given array dimension and SPAD width.
    """
    tcl_template = """set search_path "$search_path mapped lib cons rtl"
set target_library /cad/tools/libraries/dwc_logic_in_gf22fdx_sc7p5t_116cpp_base_csc20l/GF22FDX_SC7P5T_116CPP_BASE_CSC20L_FDK_RELV02R80/model/timing/db/GF22FDX_SC7P5T_116CPP_BASE_CSC20L_TT_0P80V_0P00V_0P00V_0P00V_25C.db
set link_library "* $target_library"

read_file ./rtl/ -autoread -recursive -format sverilog -top top
current_design top
link
check_design > logs/{dimension}_{spad_width}_check_design.log
source timing.con
check_timing > logs/{dimension}_{spad_width}_check_timing.log
compile
report_constraint -all_violators > logs/{dimension}_{spad_width}_constraint_report.log
report_area -hierarchy > logs/{dimension}_{spad_width}_area_report.log
report_timing > logs/{dimension}_{spad_width}_timing_report.log
report_power -hierarchy > logs/{dimension}_{spad_width}_power_report.log
write_file -format verilog -hierarchy -output mapped/{dimension}_{spad_width}_mapped.v
write_file -format ddc -hierarchy -output mapped/{dimension}_{spad_width}_mapped.ddc
write_sdf mapped/{dimension}_{spad_width}_mapped.sdf
write_sdc mapped/{dimension}_{spad_width}_mapped.sdc
quit
"""
    with open("compile.tcl", "w") as f:
        f.write(tcl_template.format(dimension=dimension, spad_width=spad_width))

def main():
    # 32-bit, 64-bit, 128-bit, 256-bit, 512-bit
    spad_sizing = [(32,13), (64,12), (128,11), (256,10), (512,9)]
    dimensions = [16, 32, 64, 128]


    for d in dimensions:
        for spad_data_width, addr_width in spad_sizing:
            rows = cols = miso_depth = d
            mpp_depth = 9

            write_system_parameters(spad_data_width, addr_width, rows, cols, miso_depth, mpp_depth)
            write_compile_tcl(d, spad_data_width)

            # Run synthesis
            sim_command = "dc_shell -f compile.tcl -output_log_file logs/compile.log"
            subprocess.run(sim_command, shell=True)
            print(f"Synthesis completed for {d}x{d}x{d} with SPAD width {spad_data_width}")


if __name__ == "__main__":
    main()