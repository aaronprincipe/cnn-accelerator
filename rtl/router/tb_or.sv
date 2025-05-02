`timescale 1ns/1ps

module tb_output_router;

    // Parameters
    parameter int SPAD_WIDTH = 32;
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
    // logic [0:COLUMNS-1] i_valid;
    
    // Quantization parameters
    logic [DATA_WIDTH-1:0] i_quant_sh;
    logic [2*DATA_WIDTH-1:0] i_quant_m0;
    
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

    // Debug
    logic [SPAD_WIDTH-1:0] o_word;
    logic                  o_word_valid;
    logic [ADDR_WIDTH-1:0] o_o_x;
    logic [ADDR_WIDTH-1:0] o_o_y;
    logic [ADDR_WIDTH-1:0] o_o_c;

    // Instantiate the DUT
    output_router #(
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
        // .i_valid(i_valid),
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
        .o_done(o_done),
        .o_word(o_word),
        .o_word_valid(o_word_valid),
        .o_o_x(o_o_x),
        .o_o_y(o_o_y),
        .o_o_c(o_o_c)
    );

    // Clock generation
    always #5 i_clk = ~i_clk;

    integer output_file;
    string out_file;
    // Initialization
    initial begin
        // Dump waveform
        $dumpfile("tb.vcd");
        $dumpvars;
        
        if (!$value$plusargs("OUTPUT_FILE=%s", out_file)) out_file = "output.txt";
        // Open output file
        output_file = $fopen(out_file, "w");
        if (output_file == 0) begin
            $display("Error opening output file!");
            $finish;
        end

        // Initialize
        i_clk = 0;
        i_nrst = 0;
        i_reg_clear = 0;
        i_en = 0;
        i_ifmap = '0;
        // i_valid = '0;
        // for (int i=0; i<COLUMNS; i++) i_quant_sh[i] = 8'h04;    // Example quantization shift value
        // for (int i=0; i<COLUMNS; i++) i_quant_m0[i] = 16'h0100; // Example quantization multiplier
        i_quant_sh = 8'h05;
        i_quant_m0 = 16'h9c8c;
        i_i_size = 3;
        i_c_size = 3;
        
        // Initialize tile dimensions
        i_x_s = 0;
        i_x_e = 1;
        i_y_s = 0;
        i_y_e = 1;
        i_xy_length = 4;
        i_xy_valid = 0;
        
        // Initialize channel dimensions
        i_c_s = 0;
        i_c_e = 1;
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
        i_ifmap[0] = 16'h0A01;
        i_ifmap[1] = 16'h0B02;
        // i_ifmap[2] = 16'h0C03;
        // i_ifmap[3] = 16'h0D04;
        // i_valid = 4'b1111;
        i_en = 1;
        @(posedge i_clk);
        i_en = 0;

        // Hold for a few cycles to allow processing
        // repeat(5) @(posedge i_clk);/
        wait (o_shift_en);
        @(posedge i_clk);
        i_ifmap[0] = 16'h0C03;
        i_ifmap[1] = 16'h0D04;
        @(posedge i_clk);
        
        wait (o_shift_en);
        @(posedge i_clk);
        i_ifmap[0] = 16'h0E05;
        i_ifmap[1] = 16'h0F06;
        @(posedge i_clk);
        
        wait (o_shift_en);
        @(posedge i_clk);
        i_ifmap[0] = 16'h1007;
        i_ifmap[1] = 16'h2008;
        @(posedge i_clk);
        
        
        // Deassert valid but keep enable
        // i_valid = 4'b0000;
        
        // Wait until done
        wait(o_done);

        // Hold a few more cycles to observe outputs
        repeat(5) @(posedge i_clk);

        $finish;
    end
    
    // Monitor and write to output file whenever o_ofmap_valid is high
    always @(posedge i_clk) begin
        if (o_word_valid) begin
            $fwrite(output_file, "%h %h %h %h %h %h\n",o_o_x,o_o_y,o_o_c,o_addr,o_write_mask,o_word);
            // $fwrite(output_file, "%d\n",o_word);
        end
    end

endmodule
