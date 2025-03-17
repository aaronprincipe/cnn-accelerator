`timescale 1ns/1ps

module tb_weight_router;

    // Parameters
    parameter DATA_WIDTH = 8;
    parameter SPAD_DATA_WIDTH = 64;
    parameter SPAD_N = SPAD_DATA_WIDTH / DATA_WIDTH;
    parameter ADDR_WIDTH = 8;
    parameter COUNT = 4;
    parameter MISO_DEPTH = 8;

    // DUT signals
    logic i_clk, i_nrst, i_en, i_reg_clear, i_fifo_pop_en, i_fifo_reset;
    logic [1:0] i_p_mode;
    logic i_conv_mode;
    logic [ADDR_WIDTH-1:0] i_i_c_size, i_o_c_size;
    logic i_spad_write_en;
    logic [SPAD_DATA_WIDTH-1:0] i_spad_data_in;
    logic [ADDR_WIDTH-1:0] i_spad_write_addr;
    logic [ADDR_WIDTH-1:0] i_start_addr, i_addr_end;
    logic o_read_done;
    logic [COUNT-1:0][DATA_WIDTH-1:0] o_data;
    logic [COUNT-1:0] o_data_valid;
    logic o_ready, o_context_done, o_done, o_wr_reset;

    integer file, r;
    reg [SPAD_DATA_WIDTH-1:0] file_data;
    int addr_cnt;

    // DUT instance
    weight_router #(
        .DATA_WIDTH(DATA_WIDTH),
        .SPAD_DATA_WIDTH(SPAD_DATA_WIDTH),
        .SPAD_N(SPAD_N),
        .ADDR_WIDTH(ADDR_WIDTH),
        .COUNT(COUNT),
        .MISO_DEPTH(MISO_DEPTH)
    ) dut (
        .*
    );

    // Clock generation
    always #5 i_clk = ~i_clk;

    initial begin
        $dumpfile("tb.vcd");
        $dumpvars;

        // Default reset values
        i_clk = 0;
        i_nrst = 0;
        i_en = 0;
        i_reg_clear = 0;
        i_fifo_pop_en = 0;
        i_fifo_reset = 0;
        i_p_mode = 0;
        i_conv_mode = 0;
        i_i_c_size = 0;
        i_o_c_size = 0;
        i_spad_write_en = 0;
        i_spad_data_in = 0;
        i_spad_write_addr = 0;
        i_start_addr = 0;
        i_addr_end = 0;

        // Reset pulse
        #20 i_nrst = 1;

        // Write to SPAD (you can replace "weights.txt" with your file)
        file = $fopen("kernel.txt", "r");
        if (file == 0) begin
            $display("Error opening weights.txt");
            $finish;
        end

        addr_cnt = 0;
        while (!$feof(file)) begin
            r = $fscanf(file, "%h\n", file_data);
            i_spad_write_en = 1;
            i_spad_data_in = file_data;
            #10;
            i_spad_write_addr = i_spad_write_addr + 1;
        end
        @(posedge i_clk);
        i_spad_write_en = 0;

        $fclose(file);

        // Setup routing parameters
        i_i_c_size = 10; // Example values
        i_o_c_size = 10;
        i_start_addr = 0;
        i_addr_end = i_spad_write_addr - 1;

        // Enable routing
        @(posedge i_clk);
        i_en = 1;

        wait (o_context_done == 1);
        i_fifo_reset = 1;
        #500;
        $finish;
        // Wait until routing finishes
        wait (o_done == 1);
        $display("Weight routing done!");

        #50;
        $finish;
    end

endmodule
