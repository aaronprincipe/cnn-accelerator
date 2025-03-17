`timescale 1ns / 1ps

module tb_data_lane();

    parameter SPAD_DATA_WIDTH = 32;
    parameter DATA_WIDTH = 8;
    parameter ADDR_WIDTH = 8;
    parameter MISO_DEPTH = 10;

    logic i_clk, i_nrst, i_reg_clear;
    logic i_ac_en, i_miso_pop_en, i_fifo_ptr_reset;
    logic [ADDR_WIDTH-1:0] i_start_addr, i_end_addr;
    logic i_addr_write_en;
    logic [SPAD_DATA_WIDTH-1:0] i_data;
    logic i_data_valid;
    logic [ADDR_WIDTH-1:0] i_addr;
    logic [1:0] i_p_mode;
    logic [DATA_WIDTH-1:0] o_data;
    logic o_miso_empty, o_miso_full, o_route_done, o_valid;

    data_lane #(
        .SPAD_DATA_WIDTH(SPAD_DATA_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH),
        .MISO_DEPTH(MISO_DEPTH)
    ) uut (
        .i_clk(i_clk),
        .i_nrst(i_nrst),
        .i_reg_clear(i_reg_clear),
        .i_ac_en(i_ac_en),
        .i_miso_pop_en(i_miso_pop_en),
        .i_fifo_ptr_reset(i_fifo_ptr_reset),
        .i_start_addr(i_start_addr),
        .i_end_addr(i_end_addr),
        .i_addr_write_en(i_addr_write_en),
        .i_data(i_data),
        .i_data_valid(i_data_valid),
        .i_addr(i_addr),
        .i_p_mode(i_p_mode),
        .o_data(o_data),
        .o_miso_empty(o_miso_empty),
        .o_miso_full(o_miso_full),
        .o_route_done(o_route_done),
        .o_valid(o_valid)
    );

    // Clock generation
    initial begin
        i_clk = 0;
        forever #5 i_clk = ~i_clk; // 100MHz clock
    end

    // Stimulus
    initial begin
        $dumpfile("tb.vcd");
        $dumpvars;

        // Initialize inputs
        i_nrst = 0;
        i_reg_clear = 0;
        i_ac_en = 0;
        i_miso_pop_en = 0;
        i_fifo_ptr_reset = 0;
        i_addr_write_en = 0;
        i_data = 0;
        i_data_valid = 0;
        i_addr = 0;
        i_p_mode = 2'b00; // _8x8 mode for MISO FIFO pops

        // Apply reset
        #20;
        i_nrst = 1;

        // Set start and end address = 0 to 10
        @(posedge i_clk);
        i_start_addr = 0;
        i_end_addr = 10;
        i_addr_write_en = 1;
        @(posedge i_clk);
        i_addr_write_en = 0;

        // Enable address comparison logic
        i_ac_en = 1;

        // Send valid data with addr = 0
        // spad_addr will be {0, 1, 2, 3}
        i_addr = 0;
        i_data = 32'hAABBCCDD;
        i_data_valid = 1;
        @(posedge i_clk);
        i_data_valid = 0;

        // Send another data with addr = 1
        // spad_addr will be {4, 5, 6, 7}
        i_addr = 1;
        i_data = 32'h11223344;
        i_data_valid = 1;
        @(posedge i_clk);
        i_data_valid = 0;

        // Send another data with addr = 2
        // spad_addr will be {8, 9, 10, 11}
        i_addr = 2;
        i_data = 32'h55667788;
        i_data_valid = 1;
        @(posedge i_clk);
        i_data_valid = 0;

        #10;
        i_miso_pop_en = 1;
        #150;
        $finish;
    end

endmodule
