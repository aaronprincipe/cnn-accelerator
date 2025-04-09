set power_enable_analysis true
set power_analysis_mode time_based
set search_path "$search_path mapped lib cons rtl sim"
set target_library /cad/tools/libraries/dwc_logic_in_gf22fdx_sc7p5t_116cpp_base_csc20l/GF22FDX_SC7P5T_116CPP_BASE_CSC20L_FDK_RELV02R80/model/timing/db/GF22FDX_SC7P5T_116CPP_BASE_CSC20L_TT_0P80V_0P00V_0P00V_0P00V_25C.db
set link_library "* $target_library"
# Read the synthesized netlist
read_verilog top_mapped.v
current_design top
link_design
# Define simulation environment
set_units -time ps -resistance kOhm -capacitance fF -voltage V -current mA
create_clock -period 10000 -name CLK [get_ports i_clk]
read_vcd "top.dump" -strip_path "tb_top/dut"
check_power
set_power_analysis_options -waveform_format fsdb -waveform_output vcd
update_power
report_power -hierarchy > top_pt_power.rpt
