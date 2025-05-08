set search_path "$search_path mapped lib cons rtl"
set target_library /cad/tools/libraries/dwc_logic_in_gf22fdx_sc7p5t_116cpp_base_csc20l/GF22FDX_SC7P5T_116CPP_BASE_CSC20L_FDK_RELV02R80/model/timing/db/GF22FDX_SC7P5T_116CPP_BASE_CSC20L_TT_0P80V_0P00V_0P00V_0P00V_25C.db
set link_library "* $target_library"
set_host_options -max_cores 16

read_file ./rtl/ -autoread -recursive -format sverilog -top top
current_design top
link
check_design > logs/check_design.log
source timing.con
check_timing > logs/check_timing.log
compile
report_constraint -all_violators > logs/constraint_report.log
report_area -hierarchy > logs/area_report.log
report_timing -hierarchy > logs/timing_report.log
report_power -hierarchy  > logs/power_report.log
write_file -format verilog -hierarchy -output mapped/top_mapped.v
write_file -format ddc -hierarchy -output mapped/top_mapped.ddc
write_sdf mapped/top_mapped.sdf
write_sdc mapped/top_mapped.sdc
quit
