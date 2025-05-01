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
)(
    input logic i_clk,
    input logic i_nrst,
    input logic i_reg_clear,

    // Host-side 
    input logic [SPAD_DATA_WIDTH-1:0] i_data_in,
    input logic [ADDR_WIDTH-1:0] i_write_addr,
    input logic i_spad_select, // Select between weight and input SRAM
    input logic i_write_en,
    input logic i_route_en,
    input logic [1:0] i_p_mode,

    // Convolution parameters
    input logic i_conv_mode, // 0: PWise, 1: DWise,
    input logic [ADDR_WIDTH-1:0] i_i_size,
    input logic [ADDR_WIDTH-1:0] i_i_c_size,
    input logic [ADDR_WIDTH-1:0] i_o_c_size,
    input logic [ADDR_WIDTH-1:0] i_i_c,
    input logic [ADDR_WIDTH-1:0] i_o_size,
    input logic [ADDR_WIDTH-1:0] i_stride,

    // Input router parameters
    input logic [ADDR_WIDTH-1:0] i_i_start_addr, 
    input logic [ADDR_WIDTH-1:0] i_i_addr_end,

    // Weight router parameters
    input logic [ADDR_WIDTH-1:0] i_w_start_addr,
    input logic [ADDR_WIDTH-1:0] i_w_addr_end,

    // Output
    output logic [DATA_WIDTH*2-1:0] o_ofmap,
    output logic o_ofmap_valid,
    output logic o_done,

    // For temp verification
    output logic [SPAD_DATA_WIDTH-1:0] o_word,
    output logic o_word_valid,
    output logic [ADDR_WIDTH-1:0] o_word_addr,
    output logic [ADDR_WIDTH-1:0] o_word_byte_offset,
    output logic [ADDR_WIDTH-1:0] o_o_x, o_o_y, o_o_c,

    input logic [ADDR_WIDTH-1:0] i_or_addr,
    input logic i_or_read_en,
    output logic [SPAD_DATA_WIDTH-1:0] o_or_data_out,
    output logic o_or_data_out_valid,
    output logic [2:0] o_top_state,
    output logic o_or_en,
    output logic o_pe_en

);
    logic spad_w_write_en, spad_i_write_en;

    // Select which SRAM to write to
    always_comb begin
        if (~i_spad_select) begin
            // Weight SRAM
            spad_w_write_en = i_write_en;
            spad_i_write_en = 1'b0;
        end else begin
            // Input SRAM
            spad_w_write_en = 1'b0;
            spad_i_write_en = i_write_en;
        end
    end

    // Instantiate top controller
    logic ir_en, wr_en, or_en;
    logic ir_pop_en, wr_pop_en;
    logic ir_ready, wr_ready;
    logic ir_context_done, wr_context_done;
    logic ir_done, wr_done, or_done;
    logic ir_tile_done, wr_tile_done;
    logic ir_reg_clear, wr_reg_clear, s_reg_clear;
    logic pe_en, psum_out_en, scan_en;
    logic output_done;
    logic [ADDR_WIDTH-1:0] o_c;

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

    logic [0:ROWS-1][DATA_WIDTH*2-1:0] ofmap;

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

    logic [  DATA_WIDTH-1:0] quant_sh = {8'h05};
    logic [2*DATA_WIDTH-1:0] quant_m0 = {16'h9c8c};

    logic [ADDR_WIDTH-1:0] s_r, s_c, s_t;

    top_controller #(
        .ROWS(ROWS),
        .COLUMNS(COLUMNS),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) top_controller_inst (
        .i_clk(i_clk),
        .i_nrst(i_nrst),
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
        .o_o_c(o_c),
        .i_ir_done(ir_done),
        .i_wr_done(wr_done),
        .i_or_done(or_done),
        .o_done(o_done),
        .i_s_r(s_r),
        .i_s_c(s_c),
        .i_t(s_t),
        .o_state(o_top_state)
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
        .i_nrst(i_nrst),
        .i_en(ir_en),
        .i_reg_clear(ir_reg_clear || i_reg_clear),
        .i_fifo_pop_en(ir_pop_en),
        .i_fifo_ptr_reset(),
        .i_p_mode(i_p_mode),
        .i_conv_mode(i_conv_mode),
        .i_i_size(i_i_size),
        .i_o_size(i_o_size),
        .i_i_c_size(i_i_c_size),
        .i_i_c(i_i_c),
        .i_stride(i_stride),
        .i_spad_write_en(spad_i_write_en),
        .i_spad_data_in(i_data_in),
        .i_spad_write_addr(i_write_addr),
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
        .o_t(s_t)
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
        .i_nrst(i_nrst),
        .i_en(ir_en),
        .i_reg_clear(wr_reg_clear || i_reg_clear),
        .i_fifo_pop_en(wr_pop_en),
        .i_fifo_ptr_reset(),
        .i_p_mode(i_p_mode),
        .i_conv_mode(i_conv_mode),
        .i_o_c(o_c),
        .i_i_c_size(i_i_c_size),
        .i_o_c_size(i_o_c_size),
        .i_i_c(i_i_c),
        .i_spad_write_en(spad_w_write_en),
        .i_spad_data_in(i_data_in),
        .i_spad_write_addr(i_write_addr),
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
        .i_nrst(i_nrst),
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
        .i_nrst(i_nrst),
        .i_reg_clear(i_reg_clear),
        .i_en(or_en),
        .i_ifmap(ofmap),
        .i_valid(),
        .o_shift_en(s_shift_en),
        .i_i_size(i_i_size),
        .i_c_size(i_o_c_size),
        .i_x_s(x_s),
        .i_x_e(x_e),
        .i_y_s(y_s),
        .i_y_e(y_e),
        .i_xy_valid(xy_valid),
        .i_xy_length(xy_length),
        .i_c_s(c_s),
        .i_c_e(c_e),
        .i_c_valid(c_valid),
        .i_quant_sh(quant_sh),
        .i_quant_m0(quant_m0),
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
        .i_nrst(i_nrst),
        .i_write_en(or_valid),
        .i_read_en(i_or_read_en),
        .i_data_in(or_data_out),
        .i_write_mask(or_write_mask),
        .i_write_addr(or_addr),
        .i_read_addr(i_or_addr),
        .o_data_out(o_or_data_out),
        .o_data_out_valid(o_or_data_out_valid)
    );

    assign o_or_en = or_en;
    assign o_pe_en = pe_en;
    assign o_word_addr = or_addr;
    assign o_word_byte_offset = or_write_mask;
endmodule