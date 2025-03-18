`include "rtl/global.svh"

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
    output logic o_done
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
    logic ir_done, wr_done;
    logic ir_tile_done, wr_tile_done;
    logic ir_reg_clear, wr_reg_clear;
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
        .o_o_c(o_c),
        .i_ir_done(ir_done),
        .i_wr_done(wr_done),
        .o_done(o_done)
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
        .i_reg_clear(ir_reg_clear),
        .i_fifo_pop_en(ir_pop_en),
        .i_fifo_ptr_reset(),
        .i_p_mode(i_p_mode),
        .i_conv_mode(i_conv_mode),
        .i_i_size(i_i_size),
        .i_o_size(i_o_size),
        // .i_stride(i_stride),
        .i_i_c_size(i_i_c_size),
        // .i_i_c(),
        .i_spad_write_en(spad_i_write_en),
        .i_spad_data_in(i_data_in),
        .i_spad_write_addr(i_write_addr),
        .i_start_addr(i_i_start_addr),
        .i_addr_end(i_i_addr_end),
        .o_read_done(), 
        .o_data(ir_ifmap),
        .o_data_valid(ir_data_valid),
        .o_ready(ir_ready),
        .o_context_done(ir_context_done),
        .o_done(ir_done),
        .o_tile_done(ir_tile_done)
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
        .i_reg_clear(wr_reg_clear),
        .i_fifo_pop_en(wr_pop_en),
        .i_p_mode(i_p_mode),
        .i_conv_mode(i_conv_mode),
        .i_o_c(o_c),
        .i_i_c_size(i_i_c_size),
        .i_o_c_size(i_o_c_size),
        .i_spad_write_en(spad_w_write_en),
        .i_spad_data_in(i_data_in),
        .i_spad_write_addr(i_write_addr),
        .i_start_addr(i_w_start_addr),
        .i_addr_end(i_w_addr_end),
        .o_read_done(), 
        .o_data(wr_weight),
        .o_data_valid(wr_data_valid),
        .o_ready(wr_ready),
        .o_context_done(wr_context_done),
        .o_done(wr_done)
    );

    systolic_array #(
        .DATA_WIDTH(DATA_WIDTH),
        .WIDTH(COLUMNS),
        .HEIGHT(ROWS)
    ) systolic_array_inst (
        .i_clk(i_clk),
        .i_nrst(i_nrst),
        .i_mode(i_p_mode),
        .i_reg_clear(i_reg_clear), 
        .i_pe_en(pe_en),
        .i_psum_out_en(psum_out_en),
        .i_scan_en(scan_en),
        .i_ifmap(s_ifmap),
        .i_ifmap_valid(s_ifmap_valid),
        .i_weight(s_weight),
        .i_weight_valid(s_weight_valid),
        .o_ofmap(ofmap),
        .o_ofmap_valid()
    );

    output_router #(
        .SPAD_ADDR_WIDTH(ADDR_WIDTH),
        .SPAD_DATA_WIDTH(16),
        .ROWS(ROWS),
        .DATA_WIDTH(DATA_WIDTH)
    ) or_inst (
        .i_clk(i_clk),
        .i_nrst(i_nrst),
        .i_en(or_en),
        .i_ifmap(ofmap),
        .i_valid({ROWS{1'b1}}),
        .o_data_out(o_ofmap),
        .o_valid(o_ofmap_valid),
        .o_done()
    );
endmodule