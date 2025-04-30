`timescale 1ns/1ps

module tb_output_router;

    // Parameters
    parameter int SPAD_WIDTH = 64;
    parameter int DATA_WIDTH = 8;
    parameter int SPAD_N = SPAD_WIDTH / DATA_WIDTH;
    parameter int ADDR_WIDTH = 8;
    parameter int ROWS = 4;
    parameter int COLUMNS = 4;

    // Inputs
    logic i_clk;
    logic i_nrst;
    logic i_reg_clear;
    logic i_en;

    // Systolic Array inputs
    logic [0:COLUMNS-1][2*DATA_WIDTH-1:0] i_ifmap;
    logic [0:COLUMNS-1] i_valid;
    
    // Quantization parameters
    logic [0:COLUMNS-1][DATA_WIDTH-1:0] i_quant_sh;
    logic [0:COLUMNS-1][2*DATA_WIDTH-1:0] i_quant_m0;
    
    // Address generation
    logic [ADDR_WIDTH-1:0] i_i_size;
    logic [ADDR_WIDTH-1:0] i_c_size;
    
    // Input router inputs (tile xy dimensions)
    logic [ADDR_WIDTH-1:0] i_x_s;
    logic [ADDR_WIDTH-1:0] i_x_e;
    logic [ADDR_WIDTH-1:0] i_y_s;
    logic [ADDR_WIDTH-1:0] i_y_e;
    logic [ADDR_WIDTH-1:0] i_xy_length;
    logic i_xy_valid;
    
    // Weight router inputs (tile c dimension)
    logic [ADDR_WIDTH-1:0] i_c_s;
    logic [ADDR_WIDTH-1:0] i_c_e;
    logic i_c_valid;

    // Outputs
    logic o_shift_en;
    logic [ADDR_WIDTH-1:0] o_addr;
    logic [SPAD_WIDTH-1:0] o_data_out;
    logic [SPAD_N-1:0] o_write_mask;
    logic o_valid;
    logic o_done;

    // Instantiate the DUT
    output_router_1 #(
        .SPAD_WIDTH(SPAD_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .SPAD_N(SPAD_N),
        .ADDR_WIDTH(ADDR_WIDTH),
        .ROWS(ROWS),
        .COLUMNS(COLUMNS)
    ) dut (
        .i_clk(i_clk),
        .i_nrst(i_nrst),
        .i_reg_clear(i_reg_clear),
        .i_en(i_en),
        .i_ifmap(i_ifmap),
        .i_valid(i_valid),
        .o_shift_en(o_shift_en),
        .i_quant_sh(i_quant_sh),
        .i_quant_m0(i_quant_m0),
        .i_i_size(i_i_size),
        .i_c_size(i_c_size),
        .i_x_s(i_x_s),
        .i_x_e(i_x_e),
        .i_y_s(i_y_s),
        .i_y_e(i_y_e),
        .i_xy_length(i_xy_length),
        .i_xy_valid(i_xy_valid),
        .i_c_s(i_c_s),
        .i_c_e(i_c_e),
        .i_c_valid(i_c_valid),
        .o_addr(o_addr),
        .o_data_out(o_data_out),
        .o_write_mask(o_write_mask),
        .o_valid(o_valid),
        .o_done(o_done)
    );

    // Clock generation
    always #5 i_clk = ~i_clk;

    // Initialization
    initial begin
        // Dump waveform
        $dumpfile("tb.vcd");
        $dumpvars;

        // Initialize
        i_clk = 0;
        i_nrst = 0;
        i_reg_clear = 0;
        i_en = 0;
        i_ifmap = '0;
        i_valid = '0;
        for (int i=0; i<COLUMNS; i++) i_quant_sh[i] = 8'h04;    // Example quantization shift value
        for (int i=0; i<COLUMNS; i++) i_quant_m0[i] = 16'h0100; // Example quantization multiplier
        i_i_size = 6;
        i_c_size = 6;
        
        // Initialize tile dimensions
        i_x_s = 0;
        i_x_e = 1;
        i_y_s = 0;
        i_y_e = 2;
        i_xy_length = 6;
        i_xy_valid = 0;
        
        // Initialize channel dimensions
        i_c_s = 0;
        i_c_e = 5;
        i_c_valid = 0;

        // Reset
        #10;
        i_nrst = 1;
        
        // Set valid tile dimensions
        @(posedge i_clk);
        i_xy_valid = 1;
        @(posedge i_clk);
        i_xy_valid = 0;
        
        // Set valid channel dimensions
        @(posedge i_clk);
        i_c_valid = 1;
        @(posedge i_clk);
        i_c_valid = 0;

        // Set valid data input test data
        @(posedge i_clk);
        i_ifmap[0] = 16'h00A1;
        i_ifmap[1] = 16'h00B2;
        i_ifmap[2] = 16'h00C3;
        i_ifmap[3] = 16'h00D4;
        i_valid = 4'b1111;
        i_en = 1;
        @(posedge i_clk);
        i_en = 0;

        // Hold for a few cycles to allow processing
        repeat(5) @(posedge i_clk);
        
        // Deassert valid but keep enable
        i_valid = 4'b0000;
        
        // Wait until done
        wait(o_done);

        // Hold a few more cycles to observe outputs
        repeat(5) @(posedge i_clk);

        $finish;
    end

endmodule
