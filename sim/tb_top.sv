`timescale 1ns / 1ps
`include "../rtl/global.svh"
`include "tb_top.svh"

module tb_top;
    localparam int SRAM_DATA_WIDTH = `SPAD_DATA_WIDTH;
    localparam int ADDR_WIDTH = `ADDR_WIDTH;
    localparam int DATA_WIDTH = `DATA_WIDTH;
    localparam int SPAD_N = `SPAD_N;

    // Counters
    int counter = 0; // counter initialization
    int write_spad_counter = 0;
    int activation_routing_counter = 0; // 2
    int compute_counter = 0; // 3 & 4
    int output_routing_counter = 0; // 5
    int no_or_counter = 0;
    int memory_read_counter = 0;
    int precision_display = 0;
    

    // File-related variables
    integer file, r, output_file;
    integer cycle_stats;
    int input_size, input_channels, output_channels, output_size, stride, precision, layer_identifier, depth_mult;


    string input_file, weight_file, cycle_file, out_file;

    logic [SRAM_DATA_WIDTH-1:0] mem_data;

    // Signals
    logic i_clk, i_nrst, i_reg_clear, i_write_en, i_route_en, re_route_flag;
    logic i_conv_mode;
    logic [1:0] p_mode;
    logic [SRAM_DATA_WIDTH-1:0] i_data_in;
    logic [ADDR_WIDTH-1:0] i_write_addr;
    logic [ADDR_WIDTH-1:0] i_i_start_addr, i_i_addr_end;
    logic [ADDR_WIDTH-1:0] i_size, o_size, i_stride, i_c_size, i_c, o_c_size, i_depth_mult; 
    logic [ADDR_WIDTH-1:0] i_w_start_addr, i_w_addr_end, i_route_size;
    logic [SRAM_DATA_WIDTH-1:0] o_word;
    logic o_word_valid;
    logic [ADDR_WIDTH-1:0] o_word_addr;
    logic [SPAD_N-1:0] o_word_byte_offset;
    logic [ADDR_WIDTH-1:0] o_o_x, o_o_y, o_o_c;
    
    logic [SRAM_DATA_WIDTH-1:0] o_or_data_out;
    logic i_or_read_en;
    logic [ADDR_WIDTH-1:0] i_or_addr;

    logic [DATA_WIDTH*2-1:0] o_ofmap;
    logic o_ofmap_valid, o_done, o_or_en, o_route_en;

    logic i_spad_select;

    logic [2:0] o_top_state;

    // Clock generation
    initial i_clk = 0;
    always #5 i_clk = ~i_clk; // 10ns clock period

    top dut (
        .i_clk(i_clk),
        .i_nrst(i_nrst),
        .i_reg_clear(i_reg_clear),
        .i_conv_mode(i_conv_mode),
        .i_data_in(i_data_in),
        .i_write_addr(i_write_addr),
        .i_spad_select(i_spad_select),
        .i_write_en(i_write_en),
        .i_route_en(i_route_en),
        .i_p_mode(p_mode),
        .i_i_size(i_size),
        .i_o_size(o_size),
        .i_i_c_size(i_c_size),
        .i_o_c_size(o_c_size),
        //.i_i_c(i_c),
        .i_stride(i_stride),
        .i_depth_mult(i_depth_mult),
        .i_i_start_addr(i_i_start_addr),
        .i_i_addr_end(i_i_addr_end),
        .i_w_start_addr(i_w_start_addr),
        .i_w_addr_end(i_w_addr_end),
        .i_or_addr(i_or_addr),
        .i_or_read_en(i_or_read_en),
        .o_or_data_out(o_or_data_out),
        .o_ofmap(o_ofmap),
        .o_ofmap_valid(o_ofmap_valid),
        .o_done(o_done),
        .o_word(o_word),
        .o_word_valid(o_word_valid),
        .o_o_x(o_o_x),
        .o_o_y(o_o_y),
        .o_o_c(o_o_c),
        .o_or_en(o_or_en),
        .o_top_state(o_top_state),
        .o_word_addr(o_word_addr),
        .o_word_byte_offset(o_word_byte_offset),
        .o_route_en(o_route_en)
    );

    initial begin
        // Iverilog

        // VCS 
        // $vcdplusfile("tb_top.vpd");
        // $vcdpluson;
        // $sdf_annotate("../mapped/top_mapped.sdf", dut);
        // // Prime Time        
        // $dumpfile("top.dump");
        // $dumpvars(0, tb_top);
    end

    // Testbench initialization
    initial begin
        //$set_toggle_region(dut);
        //$toggle_start();
        // Default values
        i_nrst = 0;
        i_reg_clear = 0;
        i_spad_select = 0;
        i_write_addr = 0;
        i_data_in = 0;
        i_i_start_addr = 0;
        i_i_addr_end = 0;
        i_w_start_addr = 0;
        i_w_addr_end = 1;
        i_route_size = 9;
        i_route_en = 0;
        i_or_read_en = 0;
        i_or_addr = 0;

        /*
        if (!$value$plusargs("CONV_MODE=%d", i_conv_mode)) i_conv_mode = 0;
        if (!$value$plusargs("INPUT_SIZE=%d", input_size)) input_size = 0;
        if (!$value$plusargs("INPUT_CHANNELS=%d", input_channels)) input_channels = 0;
        if (!$value$plusargs("OUTPUT_CHANNELS=%d", output_channels)) output_channels = 0;
        if (!$value$plusargs("OUTPUT_SIZE=%d", output_size)) output_size = 0;
        if (!$value$plusargs("STRIDE=%d", stride)) stride = 1;
        if (!$value$plusargs("PRECISION=%d", precision)) precision = 0;
        */
        i_conv_mode = `CONV_MODE;
        input_size = `INPUT_SIZE;
        input_channels = `INPUT_CHANNELS;
        output_channels = `OUTPUT_CHANNELS;
        output_size = `OUTPUT_SIZE;
        stride = `STRIDE;
        precision = `PRECISION;
        depth_mult = `DEPTH_MULT;
        
        if (!$value$plusargs("LAYER_IDENTIFIER=%d", layer_identifier)) layer_identifier = 0;

        // Strings (for file paths)
        if (!$value$plusargs("INPUT_FILE=%s", input_file)) input_file = "inputs.txt";
        if (!$value$plusargs("WEIGHT_FILE=%s", weight_file)) weight_file = "weights.txt";
        if (!$value$plusargs("CYCLE_FILE=%s", cycle_file)) cycle_file = "default_cycle.txt";
        if (!$value$plusargs("OUTPUT_FILE=%s", out_file)) out_file = "output.txt";

        i_size = input_size;
        i_c_size = input_channels;
        o_c_size = output_channels;
        //i_c = 0;
        o_size = output_size;
        i_stride = stride;
        p_mode = precision;
        i_depth_mult = depth_mult;

        write_spad_counter = 0;
        #200;
        i_nrst = 1;
        
        // Open output file
        output_file = $fopen("C:/Users/Aaron/Documents/EEE196/ps-cnn-accelerator/sim/output.txt", "w");
        if (output_file == 0) begin
            $display("Error opening output file!");
            $finish;
        end
        
        cycle_stats = $fopen(cycle_file, "a");
        if (cycle_stats == 0) begin
            $display("ERROR: Failed to open file.");
            $finish;
        end

        //$fwrite(cycle_stats, "Layer, total_cycles, no_or_cycles, write_spad_cycles, ar_cycles, compute_cycles, or_cycles\n");

        // Write to weight SRAM
        file = $fopen(weight_file, "r");
        if (file == 0) begin
            $display("Error opening file 1");
            $finish;
        end

        while (!$feof(file)) begin
            r = $fscanf(file, "%h\n", mem_data);
            if (r != 1) begin
                $display("Error reading data from file!");
                $finish;
            end
            i_write_en = 1;
            i_spad_select = 0;
            i_data_in = mem_data;
            #10; // Wait for one clock cycle
            i_write_addr = i_write_addr + 1;
        end
        i_w_addr_end = i_write_addr - 1;
        i_write_en = 0;
        #10;
        i_write_addr = 0;
        $fclose(file);

        // Write to input SRAM
        file = $fopen(input_file, "r");
        if (file == 0) begin
            $display("Error opening file 2");
            $finish;
        end

        while (!$feof(file)) begin
            r = $fscanf(file, "%h\n", mem_data);
            if (r != 1) begin
                $display("Error reading data from file!");
                $finish;
            end
            i_write_en = 1;
            i_spad_select = 1;
            i_data_in = mem_data;
            #10; // Wait for one clock cycle
            i_write_addr = i_write_addr + 1;
        end
        i_i_addr_end = i_write_addr - 1;
        i_write_en = 0;
        #10;
        i_write_addr = 0;
        $fclose(file);

        @(posedge i_clk); // wait for one clock cycle
        i_route_en = 1;
    end

    // Monitor and write to output file whenever o_ofmap_valid is high
    always @(posedge i_clk) begin
        if (o_word_valid) begin
            //$fwrite(output_file, "%h, %h, %h, %h, %h, %b\n", o_o_x, o_o_y, o_o_c, o_word_addr, o_word, o_word_byte_offset);
            $display("%h, %h, %h, %h, %h, %b", o_o_x, o_o_y, o_o_c, o_word_addr, o_word, o_word_byte_offset);
            //$write("%h\n", o_word);
        end
    end

    always @(posedge i_clk) begin
        if (i_write_en == 1) begin
            write_spad_counter++;
        end
    end

    always @(posedge i_clk) begin
        if (i_route_en) begin
            counter++;

            if (!o_or_en) no_or_counter++;

            if (o_top_state == 2) begin
                activation_routing_counter++;
            end else if (o_top_state == 3 || o_top_state == 4) begin
                compute_counter++;
            end else if (o_top_state == 5) begin
                output_routing_counter++;
            end

            if (o_route_en) begin
                memory_read_counter++;
            end
        end
    end

    // // Terminate simulation when o_done is high
    always @(posedge i_clk) begin
        if (o_done) /*begin
            if (i_conv_mode && (i_c < i_c_size - 1)) begin
                i_c <= i_c + 1;
                i_nrst <= 0;
                #200;
                i_nrst <= 1;
                i_route_en <= 1;
            end
            else */begin            
                //$toggle_stop();
                //$toggle_report("toggle_report.saif",1e-12, dut);
                $display("Simulation completed: o_done asserted.");
                $display("Total cycles: %d", counter);

                if (precision == 0) begin
                    precision_display = 8;
                end else if (precision == 1) begin
                    precision_display = 4;
                end else if (precision == 2) begin
                    precision_display = 2;
                end            

                $fwrite(cycle_stats, "%0d, %0d, %0d, %0d, %0d, %0d, %0d, %0d, %0d\n", layer_identifier, precision_display, counter, no_or_counter, write_spad_counter, activation_routing_counter, compute_counter, output_routing_counter, memory_read_counter);
                
                $fclose(cycle_stats);
                
                
                for (int i = 0; i < ((output_size*output_size*output_channels+SPAD_N-1)/SPAD_N); i++) begin
                    i_or_addr = i;
                    i_or_read_en = 1;
                    #10; // Wait for one clock cycle
                    $fdisplay(output_file, "%h", o_or_data_out);
                end
                i_or_read_en = 0;
                i_or_addr = 0;

                /*
                for (int i = 0; i < (input_size*input_size*input_channels/SPAD_N); i++) begin
                    $write("Row %0d: %h\n", i, tb_top.dut.ir_inst.ir_spad.buffer[i]);
                end
                */
                $fclose(output_file);
                $finish;
            end
        end
    //end
endmodule
