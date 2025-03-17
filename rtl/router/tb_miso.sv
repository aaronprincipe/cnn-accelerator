`timescale 1ns / 1ps

module tb_miso_fifo();

    parameter DEPTH = 16;
    parameter DATA_WIDTH = 8;
    parameter DATA_LENGTH = 8;
    parameter ADDR_WIDTH = $clog2(DEPTH);

    logic i_clk, i_nrst, i_clear, i_write_en, i_pop_en, i_r_pointer_reset;
    logic [1:0] i_p_mode;
    logic [DATA_LENGTH-1:0][DATA_WIDTH-1:0] i_data;       
    logic [DATA_LENGTH-1:0] i_valid;
    logic [DATA_WIDTH-1:0] o_data;
    logic o_empty, o_full, o_enough_slots, o_pop_valid;
    logic [ADDR_WIDTH-1:0] o_slots;

    miso_fifo #(
        .DEPTH(DEPTH),
        .DATA_WIDTH(DATA_WIDTH),
        .DATA_LENGTH(DATA_LENGTH)
    ) uut (
        .i_clk(i_clk),
        .i_nrst(i_nrst),
        .i_clear(i_clear),
        .i_write_en(i_write_en),
        .i_pop_en(i_pop_en),
        .i_r_pointer_reset(i_r_pointer_reset),
        .i_p_mode(i_p_mode),
        .i_data(i_data),
        .i_valid(i_valid),
        .o_data(o_data),
        .o_empty(o_empty),
        .o_full(o_full),
        .o_enough_slots(o_enough_slots),
        .o_pop_valid(o_pop_valid),
        .o_slots(o_slots)
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

        // Default values
        i_nrst = 0;
        i_clear = 0;
        i_write_en = 0;
        i_pop_en = 0;
        i_r_pointer_reset = 0;
        i_p_mode = 2'b00; // _8x8 mode
        i_data = '0;
        i_valid = '0;

        // Apply reset
        #10;
        i_nrst = 1;

        // Clear FIFO
        i_clear = 1; #10; i_clear = 0;

        // Write operation
        @(posedge i_clk);
        i_write_en = 1;
        i_valid = 8'b00001111; // all valid
        i_data[0] = 8'hA1;
        i_data[1] = 8'hB2;
        i_data[2] = 8'hC3;
        i_data[3] = 8'hD4;
        i_data[4] = 8'hE5;
        i_data[5] = 8'hF6;
        i_data[6] = 8'h07;
        i_data[7] = 8'h18;
        @(posedge i_clk);
        i_write_en = 0;
        i_valid = '0;

        #10;
        i_pop_en = 1;
        
        // Done
        #150;
        $finish;
    end

endmodule
