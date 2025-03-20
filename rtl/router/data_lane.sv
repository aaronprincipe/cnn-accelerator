module data_lane #(
    parameter int SPAD_DATA_WIDTH = 64,
    parameter int DATA_WIDTH = 8,
    parameter int ADDR_WIDTH = 8,
    parameter int SPAD_N = SPAD_DATA_WIDTH / DATA_WIDTH,
    parameter int MISO_DEPTH = 32,
    parameter int MPP_DEPTH = 9,
    parameter int INDEX = 0
) (
    input logic i_clk,
    input logic i_nrst,
    input logic i_reg_clear,
    input logic i_fifo_clear,

    // Control signals
    input logic i_ac_en,
    input logic i_miso_pop_en,
    input logic i_fifo_ptr_reset,
    input logic i_conv_mode, // Convolution mode - 0: PWise, 1: DWise
    
    input logic i_addr_write_en,

    // Pwise Address Reference
    input [ADDR_WIDTH-1:0] i_start_addr, i_end_addr,
    
    // Dwise Address Reference
    input [0:MPP_DEPTH-1][ADDR_WIDTH-1:0] i_sw_addr,
    
    // Tile Reader Signals
    input logic [SPAD_DATA_WIDTH-1:0] i_data,
    input logic [ADDR_WIDTH-1:0] i_addr,
    input logic i_data_valid,

    // MISO FIFO related signals
    input logic [1:0] i_p_mode,
    output logic [DATA_WIDTH-1:0] o_data,
    output logic o_miso_empty,
    output logic o_miso_full,
    output logic o_route_done,
    output logic o_idle,
    output logic o_valid
);
    // Reformat address from 2D to 1D
    logic [0:SPAD_N-1][ADDR_WIDTH-1:0] spad_addr;
    genvar ii;
    generate
        for (ii=0; ii < SPAD_N; ii++) begin
            assign spad_addr[ii] = i_addr * SPAD_N + ii;
        end
    endgenerate

    // Logic to select between Pwise and Dwise
    logic pds_en, dds_en;
    logic pds_addr_write_en, dds_addr_write_en;
    logic [SPAD_DATA_WIDTH-1:0] pds_data, dds_data;
    logic [SPAD_N-1:0] pds_data_hit, dds_data_hit;
    logic pds_route_done, dds_route_done;
    
    // Write to MISO FIFO
    logic [SPAD_DATA_WIDTH-1:0] f_data;
    logic [SPAD_N-1:0] f_data_hit;

    logic route_done;

    // Select between Pwise and Dwise
    always_comb begin
        if (i_conv_mode) begin
            // Dwise
            dds_en = i_ac_en;
            pds_en = 0;

            dds_addr_write_en = i_addr_write_en;
            pds_addr_write_en = 0;

            f_data_hit = dds_data_hit;
            f_data = dds_data;

            route_done = dds_route_done;

        end else begin
            // Pwise
            pds_en = i_ac_en;
            dds_en = 0;

            pds_addr_write_en = i_addr_write_en;
            dds_addr_write_en = 0;

            f_data_hit = pds_data_hit;
            f_data = pds_data;

            route_done = pds_route_done;
        end
    end

    logic [$clog2(MISO_DEPTH):0] slots;
    logic miso_full;

    p_data_selector #(
        .SPAD_DATA_WIDTH(SPAD_DATA_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH),
        .SPAD_N(SPAD_N),
        .MISO_DEPTH(MISO_DEPTH)
    ) pds (
        .i_clk(i_clk),
        .i_nrst(i_nrst),
        .i_reg_clear(i_reg_clear),
        .i_en(pds_en),
        .i_start_addr(i_start_addr),
        .i_end_addr(i_end_addr),
        .i_addr_write_en(pds_addr_write_en),
        .i_spad_data(i_data),
        .i_spad_addr(spad_addr),
        .i_data_valid(i_data_valid),
        .o_data_hit(pds_data_hit),
        .o_data(pds_data),
        .o_route_done(pds_route_done),
        .i_miso_slots(slots),
        .i_miso_full(miso_full)
    );

    d_data_selector #(
        .SPAD_DATA_WIDTH(SPAD_DATA_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH),
        .SPAD_N(SPAD_N),
        .MPP_DEPTH(MPP_DEPTH)
    ) dds (
        .i_clk(i_clk),
        .i_nrst(i_nrst),
        .i_reg_clear(i_reg_clear),
        .i_en(dds_en),
        .i_sw_addr(i_sw_addr),
        .i_addr_write_en(dds_addr_write_en),
        .i_spad_data(i_data),
        .i_spad_addr(spad_addr),
        .i_data_valid(i_data_valid),
        .o_data_hit(dds_data_hit),
        .o_data(dds_data),
        .o_route_done(dds_route_done)
    );

    miso_fifo #(
        .DEPTH(MISO_DEPTH),
        .DATA_WIDTH(DATA_WIDTH),
        .DATA_LENGTH(SPAD_N),
        .INDEX(INDEX)
    ) miso_fifo (
        .i_clk(i_clk),
        .i_nrst(i_nrst),
        .i_clear(i_fifo_clear),
        .i_write_en(f_data_hit[0]),
        .i_pop_en(i_miso_pop_en),
        .i_r_pointer_reset(i_fifo_ptr_reset),
        .i_p_mode(i_p_mode),
        .i_data(f_data),
        .i_valid(f_data_hit),
        .o_data(o_data),
        .o_empty(miso_empty),
        .o_full(miso_full),
        .o_pop_valid(o_valid),
        .o_slots(slots)
    );

    always_comb begin
        o_miso_empty = miso_empty;
        o_miso_full = miso_full;
        o_route_done = route_done;
        o_idle = miso_full || route_done;
    end
endmodule