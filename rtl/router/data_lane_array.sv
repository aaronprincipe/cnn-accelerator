module data_lane_array #(
    parameter int COUNT = 4,
    parameter int SPAD_DATA_WIDTH = 64,
    parameter int ADDR_WIDTH = 8,
    parameter int DATA_WIDTH = 8,
    parameter int SPAD_N = SPAD_DATA_WIDTH / DATA_WIDTH,
    parameter int MISO_DEPTH = 16,
    parameter int MPP_DEPTH = 9
) (
    input logic i_clk,
    input logic i_nrst,
    input logic i_reg_clear,
    input logic i_cntr_clear,
    input logic i_fifo_clear,
    input logic i_fifo_ptr_reset,
    input logic i_conv_mode, // Convolution mode - 0: PWise, 1: DWise

    // Address Reference
    input logic [COUNT-1:0] i_id,
    input [0:MPP_DEPTH-1][ADDR_WIDTH-1:0] i_sw_addr,
    input logic [ADDR_WIDTH-1:0] i_start_addr,
    input logic [ADDR_WIDTH-1:0] i_end_addr,
    input logic i_addr_write_en,

    // Address Comparator
    input logic i_ac_en,
    input logic [SPAD_DATA_WIDTH-1:0] i_data,
    input logic [ADDR_WIDTH-1:0] i_addr,
    input logic i_data_valid,

    // MISO FIFO
    input i_miso_pop_en,
    input logic [1:0] i_p_mode,
    output logic [COUNT-1:0][DATA_WIDTH-1:0] o_data,

    // Status signals
    output logic [COUNT-1:0] o_data_valid,
    output logic o_fifo_full,
    output logic o_fifo_empty,
    output logic o_route_done,
    output logic o_idle
);
    logic [COUNT-1:0] counter, rr_pop_en;
    logic [COUNT-1:0] rr_data_empty, rr_data_valid, rr_miso_full, rr_route_done, rr_idle;

    // Stalled popping logic
    always_ff @ (posedge i_clk or negedge i_nrst) begin
        if (~i_nrst) begin
            rr_pop_en <= 0;
            counter <= 0;
        end else begin
            if (i_reg_clear || i_cntr_clear) begin
                rr_pop_en <= 0;
                counter <= 0;
            end else if (i_miso_pop_en) begin
                for (int i = 0; i < COUNT; i = i + 1) begin
                    if (counter >= i) begin
                        rr_pop_en[i] <= 1;
                    end else begin
                        rr_pop_en[i] <= 0;
                    end 
                end

                if (counter != COUNT) begin
                    counter <= counter + 1;
                end
            end
        end
    end

    genvar ii;
    generate
        for (ii = 0; ii < COUNT; ii++) begin
            data_lane #(
                .SPAD_DATA_WIDTH(SPAD_DATA_WIDTH),
                .DATA_WIDTH(DATA_WIDTH),
                .ADDR_WIDTH(ADDR_WIDTH),
                .SPAD_N(SPAD_N),
                .MISO_DEPTH(MISO_DEPTH),
                .MPP_DEPTH(MPP_DEPTH),
                .INDEX(ii)
            ) data_lane (
                .i_clk(i_clk),
                .i_nrst(i_nrst),
                .i_reg_clear(i_reg_clear),
                .i_fifo_clear(i_fifo_clear),
                .i_ac_en(i_ac_en),
                .i_miso_pop_en(rr_pop_en[ii]),
                .i_fifo_ptr_reset(i_fifo_ptr_reset),
                .i_conv_mode(i_conv_mode),
                .i_start_addr(i_start_addr),
                .i_end_addr(i_end_addr),
                .i_sw_addr(i_sw_addr),
                .i_addr_write_en(i_addr_write_en & (i_id == ii)),
                .i_data(i_data),
                .i_data_valid(i_data_valid),
                .i_addr(i_addr),
                .i_p_mode(i_p_mode),
                .o_data(o_data[ii]),
                .o_miso_empty(rr_data_empty[ii]),
                .o_miso_full(rr_miso_full[ii]),
                .o_route_done(rr_route_done[ii]),
                .o_idle(rr_idle[ii]),
                .o_valid(rr_data_valid[ii])
            );
        end
    endgenerate

    always_comb begin
        o_fifo_empty = &rr_data_empty;
        o_fifo_full = &rr_miso_full;
        o_data_valid = rr_data_valid;
        o_route_done = &rr_route_done;
        o_idle = &rr_idle;
    end

endmodule