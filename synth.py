import subprocess
from datetime import datetime

# Parameters
data_width = 8
spad_data_width = 64
spad_n = spad_data_width // data_width
addr_width = 8
rows = 4
columns = 4
miso_depth = 4
mpp_depth = 16

header = f"""`define DATA_WIDTH {data_width}
`define SPAD_DATA_WIDTH {spad_data_width}
`define SPAD_N (`SPAD_DATA_WIDTH / `DATA_WIDTH)
`define ADDR_WIDTH {addr_width}
`define ROWS {rows}
`define COLUMNS {columns}
`define MISO_DEPTH {miso_depth}
`define MPP_DEPTH {mpp_depth}"""

with open("rtl/global.svh", "w") as file:
    file.write(header)
    
print("global.svh file has been generated.")

subprocess.run("dc_shell -f compile.tcl -output_log_file logs/compile.log", shell=True)

# Filepaths
area_log_path = "logs/area_report.log"

with open(area_log_path, 'r', encoding='utf-8') as file: 
    area_data = file.readlines()

# Extract area information
combi_area = float(area_data[21].split()[-1])
buffinv_area = float(area_data[22].split()[-1])
noncombi_data = float(area_data[23].split()[-1])
total_area = float(area_data[27].split()[-1])

print("Combinational Area:", combi_area, "Buff/Inv Area:", buffinv_area, "Noncombinational Area:", noncombi_data)
print("Total Area:", total_area)

components = [
    ("Controller", "top_controller_inst"),
    ("Input SPAD", "ir_inst/ir_spad"), 
    ("Input Router", "ir_inst"), 
    ("Weight SPAD", "wr_inst/wr_spad"),
    ("Weight Router", "wr_inst"),
    ("Output Router", "or_inst"),
    ("Systolic Array", "systolic_array_inst"),
]

txt_filename = f"{spad_data_width}_{rows}.txt"
spad_area = 0
spad_percentage = 0
formatted_date = datetime.now().strftime("%a %b %e %H:%M:%S %Y")

# Write data to text file
with open(txt_filename, mode="w", newline="") as file:
    file.write("Top Level Report\n")
    file.write(f"Date: {formatted_date}\n\n")
    file.write("-------------Parameters-------------\n")
    file.write(f"data_width: {data_width}\n")
    file.write(f"spad_data_width: {spad_data_width}\n")
    file.write(f"spad_n: {spad_n}\n")
    file.write(f"addr_width: {addr_width}\n")
    file.write(f"rows: {rows}\n")
    file.write(f"columns: {columns}\n")
    file.write(f"miso_depth: {miso_depth}\n")
    file.write(f"mpp_depth: {mpp_depth}\n\n")
    
    file.write("--------Area Information------------------\n")
    file.write(f"Combinational Area: {combi_area}\n")
    file.write(f"Buff/Inv Area: {buffinv_area}\n")
    file.write(f"Noncombinational Area: {noncombi_data}\n")
    file.write(f"Total Area: {total_area}\n\n")
    
    file.write("Component\t| Absolute Area\t| Percentage\n")
    file.write("------------------------------------------\n")
    
    for name, identifier in components:
        area_info = next((line.strip() for line in area_data if identifier in line), None)

        if area_info:
            text = area_info.split()
            area = float(text[1])
            percentage = float(text[2])

            # Ensure that the SPAD area is not counted twice
            if name == "Input SPAD" or name == "Weight SPAD":
                spad_area = area
                spad_percentage = percentage
            
            if name == "Input Router" or name == "Weight Router":
                area -= spad_area
                percentage -= spad_percentage

            file.write(f"{name}\t| {area:.4f}\t| {percentage:.1f}\n")
        else:
            file.write(f"{name}\t| n/a\t| n/a\n")

print(f"Area data has been saved to {txt_filename}")

# Prepend with timescale on synthesized verilog file
mapped_path = "mapped/top_mapped.v"

with open(mapped_path, "r") as f:
    lines = f.readlines()

lines.insert(0, "`timescale 1ns / 1ps\n")

with open(mapped_path, "w") as f:
    f.writelines(lines)