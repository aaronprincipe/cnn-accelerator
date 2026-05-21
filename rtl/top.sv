`timescale 1ns / 1ps
`include "../rtl/global.svh"

module top #(
    // ---- Constants ----
    parameter int DATA_WIDTH = `DATA_WIDTH,

    // ---- Configurable parameters ----
    parameter int SPAD_DATA_WIDTH = `SPAD_DATA_WIDTH,
    parameter int SPAD_N = `SPAD_N,  // This will also be the Peek Width
    parameter int ADDR_WIDTH = `ADDR_WIDTH,  // This will determine depth
    parameter int ROWS = `ROWS,
    parameter int COLUMNS = `COLUMNS,
    parameter int MISO_DEPTH = `MISO_DEPTH,
    parameter int MPP_DEPTH = `MPP_DEPTH
    //parameter int BIAS_WIDTH = `BIAS_WIDTH,
    //parameter int SCALE_WIDTH = `SCALE_WIDTH,
    //parameter int SHIFT_WIDTH = `SHIFT_WIDTH
)(
    input logic i_clk,
    input logic i_nrst,
    input logic i_reg_clear,                            // for resetting the controllers

    // Host-side 
    input logic [SPAD_DATA_WIDTH-1:0] i_data_in,        // data to be written into SPADs
    input logic [ADDR_WIDTH-1:0] i_write_addr,          // address to write data into SPADs
    input logic [SPAD_N-1:0] i_write_mask,              // byte-level write mask for writing into SPADs
    input logic [2:0] i_spad_select,                    // Select between weight (0), input (1), bias (2), mul (3), shift (4) spads
    input logic i_write_en,                             // Write enable for writing into SPADs. This will be used in conjunction with i_spad_select and i_write_addr
    input logic i_route_en,                             // Enable after the SPADs have been loaded with the necessary data to start routing and computation
    input logic [1:0] i_p_mode,                         // 00 for 8-bit, 01 for 4-bit, 10 for 2-bit precision.

    // Convolution parameters
    input logic i_conv_mode,                            // 0: PWise, 1: DWise,
    input logic [ADDR_WIDTH-1:0] i_i_size,              // Input feature map size (assuming square). Ex: for 3x3xCi input, i_i_size = 3
    input logic [ADDR_WIDTH-1:0] i_i_c_size,            // Number of input channels
    input logic [ADDR_WIDTH-1:0] i_o_c_size,            // Number of output channels
    input logic [ADDR_WIDTH-1:0] i_o_size,              // Output feature map size (assuming square). Ex: for 3x3xCo output, i_o_size = 3
    input logic [ADDR_WIDTH-1:0] i_stride,              // Stride size
    input logic [ADDR_WIDTH-1:0] i_depth_mult,          // Only used for DW. Ignored for PW.
    input logic [DATA_WIDTH-1:0] zero_point,            // Output zero point for quantization

    // Input router parameters
    input logic [ADDR_WIDTH-1:0] i_i_start_addr,        // Starting address in the input SPAD for the input router to read from
    input logic [ADDR_WIDTH-1:0] i_i_addr_end,          // Address in the input SPAD for the input router to stop reading from, *inclusive*

    // Weight router parameters
    input logic [ADDR_WIDTH-1:0] i_w_start_addr,        // Starting address in the weight SPAD for the weight router to read from
    input logic [ADDR_WIDTH-1:0] i_w_addr_end,          // Address in the weight SPAD for the weight router to stop reading from, *inclusive*

    // Output router parameters
    output logic o_done,                                // Convolution operation is done. Output feature map is now stored in the output SPAD.
    input logic [ADDR_WIDTH-1:0] i_or_addr,             // Address in the output SPAD to read from
    input logic i_or_read_en,                           // Read enable for reading from output SPAD
    output logic [SPAD_DATA_WIDTH-1:0] o_or_data_out,   // Data read out from output SPAD
    output logic o_or_data_out_valid,                   // Valid signal for o_or_data_out
    
    // For debug/temp verification - Ignore this in the final version
    output logic [DATA_WIDTH*4-1:0] o_ofmap,
    output logic o_ofmap_valid,
    output logic [SPAD_DATA_WIDTH-1:0] o_word,
    output logic o_word_valid,
    output logic [ADDR_WIDTH-1:0] o_word_addr,
    output logic [SPAD_N-1:0] o_word_byte_offset,
    output logic [ADDR_WIDTH-1:0] o_o_x, o_o_y, o_o_c,
    output logic [2:0] o_top_state,
    output logic o_or_en,
    output logic o_pe_en,
    output logic o_route_en

);
    logic spad_w_write_en, spad_i_write_en, spad_b_write_en, spad_sc_write_en, spad_sh_write_en;
    // weight, ifmap, bias, scale, shift
    
    parameter weights = 3'b000, ifmaps = 3'b001, bias = 3'b010, scale = 3'b011, shift = 3'b100;
    // Select which SRAM to write to
    always_comb begin
        case (i_spad_select) 
            weights: begin
                // Weight SRAM
                spad_w_write_en = i_write_en;
                spad_i_write_en = 1'b0;
                spad_b_write_en = 1'b0;
                spad_sc_write_en = 1'b0;
                spad_sh_write_en = 1'b0;
                end
            ifmaps: begin
                // Input SRAM
                spad_w_write_en = 1'b0;
                spad_i_write_en = i_write_en;
                spad_b_write_en = 1'b0;
                spad_sc_write_en = 1'b0;
                spad_sh_write_en = 1'b0;
                end
            bias: begin
                // Bias SRAM
                spad_w_write_en = 1'b0;
                spad_i_write_en = 1'b0;
                spad_b_write_en = i_write_en;
                spad_sc_write_en = 1'b0;
                spad_sh_write_en = 1'b0;
                end
            scale: begin
                // Scale SRAM
                spad_w_write_en = 1'b0;
                spad_i_write_en = 1'b0;
                spad_b_write_en = 1'b0;
                spad_sc_write_en = i_write_en;
                spad_sh_write_en = 1'b0;
                end
            shift: begin
                // Shift SRAM
                spad_w_write_en = 1'b0;
                spad_i_write_en = 1'b0;
                spad_b_write_en = 1'b0;
                spad_sc_write_en = 1'b0;
                spad_sh_write_en = i_write_en;
                end
            default: begin
                spad_w_write_en = 1'b0;
                spad_i_write_en = 1'b0;
                spad_b_write_en = 1'b0;
                spad_sc_write_en = 1'b0;
                spad_sh_write_en = 1'b0;
                end
        endcase
    end

    // Instantiate top controller
    logic ir_en, wr_en, or_en;
    logic ir_pop_en, wr_pop_en;
    logic ir_ready, wr_ready;
    logic ir_context_done, wr_context_done;
    logic ir_done, wr_done, or_done;
    logic ir_tile_done, wr_tile_done;
    logic ir_reg_clear, wr_reg_clear, s_reg_clear, or_reg_clear;
    logic pe_en, psum_out_en, scan_en;
    logic output_done;
    logic [ADDR_WIDTH-1:0] o_c, i_c;

    // Instantiate input router
    logic [ROWS-1:0] ir_data_valid;
    logic [ROWS-1:0][DATA_WIDTH-1:0] ir_ifmap;
    logic [0:ROWS-1][DATA_WIDTH-1:0] s_ifmap;
    logic [0:ROWS-1] s_ifmap_valid;

    genvar ii;
    generate
        for (ii=0; ii < ROWS; ii++) begin
            assign s_ifmap[ii] = ir_ifmap[ii];
            assign s_ifmap_valid[ii] = ir_data_valid[ii];
        end
    endgenerate

    // Instantiate weight router
    logic [COLUMNS-1:0] wr_data_valid;
    logic [COLUMNS-1:0][DATA_WIDTH-1:0] wr_weight;
    logic [0:COLUMNS-1][DATA_WIDTH-1:0] s_weight;
    logic [0:COLUMNS-1] s_weight_valid;

    genvar jj;
    generate
        for (ii=0; ii < COLUMNS; ii++) begin
            assign s_weight[ii] = wr_weight[ii];
            assign s_weight_valid[ii] = wr_data_valid[ii];
        end
    endgenerate

    logic [0:COLUMNS-1][DATA_WIDTH*4-1:0] ofmap;

    // Input router to Output router
    logic [ADDR_WIDTH-1:0] x_s, x_e, y_s, y_e;
    logic xy_valid;

    // Weight router to Output router
    logic [ADDR_WIDTH-1:0] c_s, c_e;
    logic c_valid;

    logic s_shift_en;

    logic [ADDR_WIDTH-1:0] or_addr;
    logic [SPAD_DATA_WIDTH-1:0] or_data_out;;
    logic [SPAD_N-1:0] or_write_mask;
    logic or_valid;

    logic [ADDR_WIDTH-1:0] xy_length;

    // Quantization parameters
    logic [SPAD_DATA_WIDTH-1:0] quant_shift;
    logic [SPAD_DATA_WIDTH-1:0] quant_scale;
    logic [SPAD_DATA_WIDTH-1:0] quant_bias;
    logic quant_bias_valid, quant_scale_valid, quant_shift_valid, quant_read_en;
    logic [ADDR_WIDTH-1:0] bias_addr;
    logic [ADDR_WIDTH-1:0] mul_addr;
    logic [ADDR_WIDTH-1:0] shift_addr;

    logic [ADDR_WIDTH-1:0] s_r, s_c, s_t;

    // Reset synchronizer to eliminate setup/hold violations
    logic o_nrst_sync;
    reset_sync reset_sync_inst (
        .i_clk(i_clk),
        .i_nrst_async(i_nrst),
        .o_nrst_sync(o_nrst_sync)
    );

    top_controller #(
        .ROWS(ROWS),
        .COLUMNS(COLUMNS),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) top_controller_inst (
        .i_clk(i_clk),
        .i_nrst(o_nrst_sync),
        .i_reg_clear(i_reg_clear),
        .i_route_en(i_route_en),
        .o_ir_en(ir_en),
        .o_wr_en(wr_en),
        .o_or_en(or_en),
        .o_ir_pop_en(ir_pop_en),
        .o_wr_pop_en(wr_pop_en),
        .o_pe_en(pe_en),
        .o_psum_out_en(psum_out_en),
        .o_scan_en(scan_en),
        .i_ir_ready(ir_ready),
        .i_wr_ready(wr_ready),
        .i_ir_context_done(ir_context_done),
        .i_wr_context_done(wr_context_done),
        .i_ir_tile_done(ir_tile_done),
        .o_ir_reg_clear(ir_reg_clear),
        .o_wr_reg_clear(wr_reg_clear),
        .o_s_reg_clear(s_reg_clear),
        .o_or_reg_clear(or_reg_clear),
        .o_o_c(o_c),
        .o_i_c(i_c),
        .i_i_c_size(i_i_c_size),
        .i_conv_mode(i_conv_mode),
        .i_ir_done(ir_done),
        .i_wr_done(wr_done),
        .i_or_done(or_done),
        .o_done(o_done),
        .i_s_r(s_r),
        .i_s_c(s_c),
        .i_t(s_t),
        .o_state(o_top_state),
        .i_p_mode(i_p_mode)
    );

    input_router #(
        .DATA_WIDTH(DATA_WIDTH),
        .SPAD_DATA_WIDTH(SPAD_DATA_WIDTH),
        .SPAD_N(SPAD_N),
        .ADDR_WIDTH(ADDR_WIDTH),
        .COUNT(ROWS),
        .MISO_DEPTH(MISO_DEPTH)
    ) ir_inst (
        .i_clk(i_clk),
        .i_nrst(o_nrst_sync),
        .i_en(ir_en),
        .i_reg_clear(ir_reg_clear || i_reg_clear),
        .i_fifo_pop_en(ir_pop_en),
        .i_fifo_ptr_reset(),
        .i_p_mode(i_p_mode),
        .i_conv_mode(i_conv_mode),
        .i_i_size(i_i_size),
        .i_o_size(i_o_size),
        .i_i_c_size(i_i_c_size),
        .i_i_c(i_c),
        .i_stride(i_stride),
        .i_spad_write_en(spad_i_write_en),
        .i_spad_data_in(i_data_in),
        .i_spad_write_addr(i_write_addr),
        .i_spad_write_mask(i_write_mask),
        .i_start_addr(i_i_start_addr),
        .i_addr_end(i_i_addr_end),
        .o_read_done(), 
        .o_data(ir_ifmap),
        .o_data_valid(ir_data_valid),
        .o_x_s(x_s),
        .o_x_e(x_e),
        .o_y_s(y_s),
        .o_y_e(y_e),
        .o_xy_valid(xy_valid),
        .o_xy_length(xy_length),
        .o_ready(ir_ready),
        .o_context_done(ir_context_done),
        .o_done(ir_done),
        .o_tile_done(ir_tile_done),
        .o_s_r(s_r),
        .o_t(s_t),
        .o_route_en(o_route_en)
    );

    weight_router #(
        .DATA_WIDTH(DATA_WIDTH),
        .SPAD_DATA_WIDTH(SPAD_DATA_WIDTH),
        .SPAD_N(SPAD_N),
        .ADDR_WIDTH(ADDR_WIDTH),
        .COUNT(COLUMNS),
        .MISO_DEPTH(MISO_DEPTH)
    ) wr_inst (
        .i_clk(i_clk),
        .i_nrst(o_nrst_sync),
        .i_en(ir_en),
        .i_reg_clear(wr_reg_clear || i_reg_clear),
        .i_fifo_pop_en(wr_pop_en),
        .i_fifo_ptr_reset(),
        .i_p_mode(i_p_mode),
        .i_conv_mode(i_conv_mode),
        .i_o_c(o_c),
        .i_i_c_size(i_i_c_size),
        .i_o_c_size(i_o_c_size),
        .i_i_c(i_c),
        .i_depth_mult(i_depth_mult),
        .i_spad_write_en(spad_w_write_en),
        .i_spad_data_in(i_data_in),
        .i_spad_write_addr(i_write_addr),
        .i_spad_write_mask(i_write_mask),
        .i_start_addr(i_w_start_addr),
        .i_addr_end(i_w_addr_end),
        .o_read_done(), 
        .o_data(wr_weight),
        .o_data_valid(wr_data_valid),
        .o_c_s(c_s),
        .o_c_e(c_e),
        .o_c_valid(c_valid),
        .o_ready(wr_ready),
        .o_context_done(wr_context_done),
        .o_done(wr_done),
        .o_s_c(s_c)
    );

    systolic_array #(
        .DATA_WIDTH(DATA_WIDTH),
        .WIDTH(COLUMNS),
        .HEIGHT(ROWS)
    ) systolic_array_inst (
        .i_clk(i_clk),
        .i_nrst(o_nrst_sync),
        .i_mode(i_p_mode),
        .i_reg_clear(i_reg_clear || s_reg_clear), 
        .i_pe_en(pe_en),
        .i_psum_out_en(psum_out_en),
        .i_scan_en(s_shift_en),
        .i_ifmap(s_ifmap),
        .i_weight(s_weight),
        .o_ofmap(ofmap)
    );

    output_router #(
        .SPAD_WIDTH(SPAD_DATA_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .SPAD_N(SPAD_N),
        .ADDR_WIDTH(ADDR_WIDTH),
        .ROWS(ROWS),
        .COLUMNS(COLUMNS)
    ) or_inst (
        .i_clk(i_clk),
        .i_nrst(o_nrst_sync),
        .i_reg_clear(i_reg_clear || or_reg_clear),
        .i_en(or_en),
        .i_conv_mode(i_conv_mode),
        .i_ifmap(ofmap),
        .i_valid(),
        .o_shift_en(s_shift_en),
        .i_o_size(i_o_size),
        .i_o_c_size(i_o_c_size),
        .i_depth_mult(i_depth_mult),
        .i_x_s(x_s),
        .i_x_e(x_e),
        .i_y_s(y_s),
        .i_y_e(y_e),
        .i_xy_valid(xy_valid),
        .i_xy_length(xy_length),
        .i_i_c(i_c),
        .i_c_s(c_s),
        .i_c_e(c_e),
        .i_c_valid(c_valid),
        .i_zero_point(zero_point),
        .i_quant_sh(quant_shift),
        .i_quant_m0(quant_scale),
        .i_quant_bias(quant_bias),
        .o_bias_addr(bias_addr),
        .o_mul_addr(mul_addr),
        .o_shift_addr(shift_addr),
        .o_quant_read_en(quant_read_en),
        .o_addr(or_addr),
        .o_data_out(or_data_out),
        .o_write_mask(or_write_mask),
        .o_valid(or_valid),
        .o_done(or_done),
        .o_word(o_word),
        .o_word_valid(o_word_valid),
        .o_o_x(o_o_x),
        .o_o_y(o_o_y),
        .o_o_c(o_o_c)
    );

    spad #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .SPAD_WIDTH(SPAD_DATA_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .SPAD_N(SPAD_N)
    ) or_spad (
        .i_clk(i_clk),
        .i_nrst(o_nrst_sync),
        .i_write_en(or_valid),
        .i_read_en(i_or_read_en),
        .i_data_in(or_data_out),
        .i_write_mask(or_write_mask),
        .i_write_addr(or_addr),
        .i_read_addr(i_or_addr),
        .o_data_out(o_or_data_out),
        .o_data_out_valid(o_or_data_out_valid)
    );

    spad #(
        .ADDR_WIDTH(8), // hardcode for now 
        .SPAD_WIDTH(SPAD_DATA_WIDTH),
        .DATA_WIDTH(4*DATA_WIDTH), 
        .SPAD_N(SPAD_DATA_WIDTH / (4*DATA_WIDTH)) 
    ) bias_spad (
        .i_clk(i_clk),
        .i_nrst(o_nrst_sync),
        .i_write_en(spad_b_write_en),
        .i_read_en(quant_read_en),
        .i_data_in(i_data_in),
        .i_write_mask(i_write_mask),
        .i_write_addr(i_write_addr),
        .i_read_addr(bias_addr),
        .o_data_out(quant_bias),
        .o_data_out_valid(quant_bias_valid)
    );

    spad #(
        .ADDR_WIDTH(8), // hardcode for now = exact for 256 elements.
        .SPAD_WIDTH(SPAD_DATA_WIDTH),
        .DATA_WIDTH(4*DATA_WIDTH),  // 32b multiplier
        .SPAD_N(SPAD_DATA_WIDTH / (4*DATA_WIDTH))
    ) scale_spad (
        .i_clk(i_clk),
        .i_nrst(o_nrst_sync),
        .i_write_en(spad_sc_write_en),
        .i_read_en(quant_read_en),
        .i_data_in(i_data_in),
        .i_write_mask(i_write_mask),
        .i_write_addr(i_write_addr),
        .i_read_addr(mul_addr),
        .o_data_out(quant_scale),
        .o_data_out_valid(quant_scale_valid)
    );

    spad #(
        .ADDR_WIDTH(8), 
        .SPAD_WIDTH(SPAD_DATA_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .SPAD_N(SPAD_DATA_WIDTH / DATA_WIDTH)
    ) shift_spad (
        .i_clk(i_clk),
        .i_nrst(o_nrst_sync),
        .i_write_en(spad_sh_write_en),
        .i_read_en(quant_read_en),
        .i_data_in(i_data_in),
        .i_write_mask(i_write_mask),
        .i_write_addr(i_write_addr),
        .i_read_addr(shift_addr),
        .o_data_out(quant_shift),
        .o_data_out_valid(quant_shift_valid)
    );

    assign o_or_en = or_en;
    assign o_pe_en = pe_en;
    assign o_word_addr = or_addr;
    assign o_word_byte_offset = or_write_mask;
endmodule