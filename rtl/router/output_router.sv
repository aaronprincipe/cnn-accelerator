
module output_router #(
    parameter int SPAD_WIDTH = 64,
    parameter int DATA_WIDTH = 8,
    parameter int SPAD_N = SPAD_WIDTH / DATA_WIDTH,
    parameter int ADDR_WIDTH = 8,
    parameter int ROWS = 4,
    parameter int COLUMNS = 4
) (
    input  logic i_clk,
    input  logic i_nrst,
    input  logic i_reg_clear,
    input  logic i_en,
    input logic i_conv_mode,

    // Systolic Array inputs
    input  logic [0:COLUMNS-1][4*DATA_WIDTH-1:0] i_ifmap,
    input  logic [0:COLUMNS-1]                   i_valid,       // not used in top.sv
    output logic                                 o_shift_en,
    // Quantization parameters
    input  logic              [  SPAD_WIDTH-1:0] i_quant_sh,    // comes from spad, we'll just extract the relevant value based on computed offset
    input  logic              [  SPAD_WIDTH-1:0] i_quant_m0,    // same as above
    input  logic signed       [  SPAD_WIDTH-1:0] i_quant_bias,  // same as above
    input  logic              [  DATA_WIDTH-1:0] i_zero_point,  // comes from top module input directly since it's only one value per layer, we'll just broadcast it to all quant units
    // Address generation
    // Top module inputs
    input logic  [ADDR_WIDTH-1:0] i_o_size,
    input logic  [ADDR_WIDTH-1:0] i_o_c_size,
    input logic  [ADDR_WIDTH-1:0] i_i_c,
    input logic  [ADDR_WIDTH-1:0] i_depth_mult, // Only used for DW. Ignored for PW.
    // Input router inputs (tile xy dimensions)
    input  logic [ADDR_WIDTH-1:0] i_x_s,
    input  logic [ADDR_WIDTH-1:0] i_x_e,
    input  logic [ADDR_WIDTH-1:0] i_y_s,
    input  logic [ADDR_WIDTH-1:0] i_y_e,
    input  logic [ADDR_WIDTH-1:0] i_xy_length,
    input  logic                  i_xy_valid,
    // Weight router inputs (tile c dimension)
    input  logic [ADDR_WIDTH-1:0] i_c_s,
    input  logic [ADDR_WIDTH-1:0] i_c_e,
    input  logic                  i_c_valid,
    // SPAD 
    output logic [ADDR_WIDTH-1:0] o_addr,
    output logic [SPAD_WIDTH-1:0] o_data_out,
    output logic [SPAD_N-1:0]     o_write_mask,
    output logic                  o_valid,
    output logic                  o_done,
    // For bias, scale, shift spads
    output logic o_quant_read_en,
    output logic [ADDR_WIDTH-1:0] o_bias_addr,
    output logic [ADDR_WIDTH-1:0] o_mul_addr, 
    output logic [ADDR_WIDTH-1:0] o_shift_addr,
    // For debug
    output logic [SPAD_WIDTH-1:0] o_word,
    output logic                  o_word_valid,
    output logic [ADDR_WIDTH-1:0] o_o_x,
    output logic [ADDR_WIDTH-1:0] o_o_y,
    output logic [ADDR_WIDTH-1:0] o_o_c
);
    logic [$clog2(COLUMNS*ROWS):0] num_input_valid;
    logic [$clog2(COLUMNS)-1:0] quant_idx; // which quant unit to store reg for
    // Parallel quant
    logic                                 quant_en;
    logic                                 quant_store_reg;
    logic [0:COLUMNS-1][4*DATA_WIDTH-1:0] quant_i_act;
    logic [0:COLUMNS-1][  DATA_WIDTH-1:0] quant_o_act;
    logic [0:COLUMNS-1]                   quant_valid;
    logic                                 quant_all_valid;
    // data buffer to SPAD
    logic        [SPAD_WIDTH-1:0]         data_buffer;  // buffer data to be written to spad
    logic        [COLUMNS*DATA_WIDTH-1:0] data_left;    // leftover data not written to spad
    logic signed [$clog2(COLUMNS)+1:0]    data_left_cnt;
    logic        [$clog2(SPAD_N):0]       bytes_to_write;
    logic        [$clog2(SPAD_N):0]       bytes_in_buffer;
    // 
    logic [ADDR_WIDTH-1:0] current_x, current_y, current_c, output_c, counter;
    logic [ADDR_WIDTH-1:0] prev_x, prev_y;
    logic [ADDR_WIDTH-1:0] start_x, start_y, start_c;
    logic [ADDR_WIDTH-1:0] limit_x, limit_y, limit_c, limit_xy;
    logic [ADDR_WIDTH-1:0] xy_count;
    // SPAD address
    logic [$clog2(SPAD_N)+ADDR_WIDTH-1:0] byte_addr;   // which byte in the SPAD
    logic [ADDR_WIDTH-1:0] word_addr;   // which word in the SPAD
    logic [SPAD_N-1:0] byte_offset;     // which byte in the word
    // address = n*HWC + h*WC + w*C + c
    always_comb begin
        output_c    = i_i_c * i_depth_mult + current_c;
        byte_addr   = (current_x * i_o_size + current_y) * i_o_c_size + output_c;
        word_addr   = byte_addr >> $clog2(SPAD_N);
        byte_offset = byte_addr % SPAD_N;
    end

    // Assume 32b word, 32b bias, 32b multiplier, 8b shift for now. 
    // Can be extended as long as SPAD_N_BIAS is a multiple of 2 (for %clog2(*) to work correctly). Fix this later!
    parameter int SPAD_N_BIAS = SPAD_WIDTH / (DATA_WIDTH * 4);  // number of bias values we can store in one SPAD word
    parameter int SPAD_N_MUL = SPAD_WIDTH / (DATA_WIDTH * 4);   // number of multiplier values we can store in one SPAD word
    parameter int SPAD_N_SHIFT = SPAD_WIDTH / DATA_WIDTH;       // number of shift values we can store in one SPAD word
    
    logic [SPAD_N_BIAS-1:0] bias_offset;
    logic [SPAD_N_MUL-1:0] mul_offset;
    logic [SPAD_N_SHIFT-1:0] shift_offset;
    logic [ADDR_WIDTH-1:0] quant_addr;
    /*
    always_comb begin
        o_bias_addr = quant_addr >> $clog2(SPAD_N_BIAS);
        o_mul_addr = quant_addr >> $clog2(SPAD_N_MUL);
        o_shift_addr = quant_addr >> $clog2(SPAD_N_SHIFT);
    end
    */

    genvar q;
    generate
        for (q=0; q<COLUMNS; q=q+1) begin: quat_parallel_gen
            quant #(
                .DATA_WIDTH(DATA_WIDTH)
            ) quant_inst (
                .i_clk      (i_clk),
                .i_nrst     (i_nrst),
                .i_en       (quant_en),
                .i_store_reg(quant_store_reg && (q == quant_idx)),
                .i_act      (quant_i_act[q]), 
                .i_sh       (i_quant_sh[shift_offset*DATA_WIDTH +: DATA_WIDTH]),
                .i_m0       (i_quant_m0[mul_offset*4*DATA_WIDTH +: 4*DATA_WIDTH]),
                .i_bias     (i_quant_bias[bias_offset*4*DATA_WIDTH +: 4*DATA_WIDTH]),
                .i_zero_point(i_zero_point),
                .o_act      (quant_o_act[q]),
                .o_valid    (quant_valid[q])
            );
        end
    endgenerate
    // quant data is only valid when all data is valid;
    assign quant_all_valid = &quant_valid;

    always_comb begin
        bytes_in_buffer = SPAD_N - byte_offset;
        bytes_to_write = (data_left_cnt < bytes_in_buffer) ? data_left_cnt : bytes_in_buffer;
    end

    always_comb begin
        // o_addr     = word_addr;
        o_data_out = data_buffer;
    end

    // debug
    always_comb begin
        o_word       = o_data_out;
        o_word_valid = o_valid;
        o_o_x        = current_x;
        o_o_y        = current_y;
        o_o_c        = current_c;
    end

    parameter int IDLE_STATE = 0;
    parameter int PRELOAD_QUANT = 1;
    parameter int QUANT_DATA = 2;
    parameter int COLLECT_IN = 3;
    parameter int SPAD_WRITE = 4;
    parameter int NEXT_ADDR  = 5;
    parameter int DONE_STATE = 6;

    logic [2:0] state;

    always_ff @(posedge i_clk) begin
        if (~i_nrst) begin
            state           <= IDLE_STATE;
            
            num_input_valid <= 0;

            quant_en        <= 0;
            quant_store_reg <= 0;
            quant_i_act     <= 0;

            data_buffer     <= 0;
            data_left       <= 0;
            data_left_cnt   <= 0;

            current_x       <= 0;
            current_y       <= 0;
            prev_x          <= 0;
            prev_y          <= 0;
            start_x         <= 0;
            start_y         <= 0;
            limit_x         <= 0;
            limit_y         <= 0;
            xy_count        <= 0;
            limit_xy        <= 0;
            current_c       <= 0;
            start_c         <= 0;
            limit_c         <= 0;

            o_addr          <= 0;
            o_write_mask    <= 0;
            o_valid         <= 0;
            o_shift_en      <= 0;
            o_done          <= 0;

            quant_idx       <= 0;
            o_quant_read_en <= 0;
            quant_addr      <= 0;
            bias_offset     <= 0;
            mul_offset      <= 0;
            shift_offset    <= 0;
            counter         <= 0;

            o_bias_addr <= 0;
            o_mul_addr <= 0;
            o_shift_addr <= 0;
        end else if(i_reg_clear) begin
            state           <= IDLE_STATE;
            
            num_input_valid <= 0;

            quant_en        <= 0;
            quant_store_reg <= 0;
            quant_i_act     <= 0;

            data_buffer     <= 0;
            data_left       <= 0;
            data_left_cnt   <= 0;

            current_x       <= 0;
            current_y       <= 0;
            prev_x          <= 0;
            prev_y          <= 0;
            start_x         <= 0;
            start_y         <= 0;
            limit_x         <= 0;
            limit_y         <= 0;
            xy_count        <= 0;
            limit_xy        <= 0;
            current_c       <= 0;
            start_c         <= 0;
            limit_c         <= 0;

            o_addr          <= 0;
            o_write_mask    <= 0;
            o_valid         <= 0;
            o_shift_en      <= 0;
            o_done          <= 0;

            quant_idx       <= 0;
            o_quant_read_en <= 0;
            quant_addr      <= 0;
            counter         <= 0;
            bias_offset     <= 0;
            mul_offset      <= 0;
            shift_offset    <= 0;

            o_bias_addr <= 0;
            o_mul_addr <= 0;
            o_shift_addr <= 0;
        end else begin
            case (state)
                IDLE_STATE: begin
                    if (i_xy_valid) begin
                        current_x <= i_x_s;
                        current_y <= i_y_s;
                        prev_x    <= i_x_s;
                        prev_y    <= i_y_s;
                        start_x   <= i_x_s;
                        start_y   <= i_y_s;
                        limit_x   <= i_x_e;
                        limit_y   <= i_y_e;
                        limit_xy  <= i_xy_length;
                        xy_count  <= 0;
                    end
                    
                    if (i_c_valid) begin
                        current_c <= i_c_s;
                        start_c   <= i_c_s;
                        limit_c   <= i_c_e;
                    end
                    
                    if (i_en && !o_done) begin
                        state           <= PRELOAD_QUANT;
                        quant_addr      <= (i_conv_mode) ? (i_i_c * i_depth_mult) + i_c_s : i_c_s; // if DW, we need to offset by i_i_c * i_depth_mult
                        o_quant_read_en <= 1;

                        o_bias_addr <= ((i_conv_mode) ? (i_i_c * i_depth_mult) + i_c_s : i_c_s) >> $clog2(SPAD_N_BIAS);
                        o_mul_addr <= ((i_conv_mode) ? (i_i_c * i_depth_mult) + i_c_s : i_c_s) >> $clog2(SPAD_N_MUL);
                        o_shift_addr <= ((i_conv_mode) ? (i_i_c * i_depth_mult) + i_c_s : i_c_s) >> $clog2(SPAD_N_SHIFT);

                        num_input_valid <= (limit_xy+1) * (limit_c - start_c + 1);
                    end 
                    else 
                        o_done <= 0;
                end

                PRELOAD_QUANT: begin
                    // For n columns, iterate idx from 0 to n-1, each time store the data for that column into the quant reg
                    if (counter <= limit_c - start_c) begin
                        quant_idx <= (COLUMNS - 1) - counter;               // reversed order, check with quant_i_act assignment in generate block
                        quant_store_reg <= 1'b1;

                        quant_addr <= quant_addr + 1;                       // we can start reading the next quant data in the same cycle as storing the current quant result since the quant result is only valid in the next cycle
                        o_quant_read_en <= (quant_addr < limit_c) ? 1 : 0;  // stop reading quant data once we have read all the necessary quant data for the current tile
                        
                        o_bias_addr <= (quant_addr+1) >> $clog2(SPAD_N_BIAS);
                        o_mul_addr <= (quant_addr+1) >> $clog2(SPAD_N_MUL);
                        o_shift_addr <= (quant_addr+1) >> $clog2(SPAD_N_SHIFT);
                        
                        bias_offset  <= quant_addr % SPAD_N_BIAS;
                        mul_offset   <= quant_addr % SPAD_N_MUL;
                        shift_offset <= quant_addr % SPAD_N_SHIFT;

                        counter <= counter + 1;
                    end else begin
                        quant_idx <= 0;
                        quant_store_reg <= 0;

                        o_quant_read_en <= 0;
                        quant_addr <= 0;

                        o_bias_addr <= 0;
                        o_mul_addr <= 0;
                        o_shift_addr <= 0;

                        bias_offset  <= 0;
                        mul_offset   <= 0;
                        shift_offset <= 0;

                        counter <= 0;                        
                        state <= QUANT_DATA;
                    end
                end

                QUANT_DATA: begin
                    if (o_shift_en) begin
                        o_shift_en <= 0; // wait for one cycle for the shift to take effect
                    end
                    else begin
                        if (num_input_valid > 0) begin
                            if (quant_all_valid) begin
                                state         <= COLLECT_IN;
                                quant_en      <= 0;
                                data_left     <= quant_o_act;
                                data_left_cnt <= (limit_c - start_c + 1 < COLUMNS)? limit_c - start_c + 1 : COLUMNS;
                            end else begin
                                quant_en      <= 1'b1;
                                for(int i=0; i<COLUMNS; i=i+1) quant_i_act[i] <= i_ifmap[COLUMNS-i-1];
                            end
                        end 
                        else 
                            state <= DONE_STATE;
                    end
                end

                COLLECT_IN: begin
                    if (data_left_cnt > 0) begin
                        state <= SPAD_WRITE;
                        {data_left, data_buffer} <= data_left << (byte_offset * DATA_WIDTH);
                        o_addr <= word_addr;
                        o_write_mask <= ({SPAD_N{1'b1}} >> (SPAD_N - bytes_to_write)) << byte_offset;
                        current_c       <= current_c       + bytes_to_write;
                        num_input_valid <= num_input_valid - bytes_to_write;
                        data_left_cnt   <= data_left_cnt   - bytes_to_write;
                    end 
                    else begin
                        state <= NEXT_ADDR;
                    end
                end

                SPAD_WRITE: begin
                    if (!o_valid) begin
                        o_valid <= 1;
                    end
                    else begin
                        o_valid         <= 0;
                        // o_write_mask    <= 0;
                        // current_c       <= current_c       + bytes_to_write;
                        state           <= NEXT_ADDR;
                    end
                end

                NEXT_ADDR: begin
                    if (current_c > limit_c || data_left_cnt <= 0) begin
                        current_c <= start_c;

                        if (current_y >= limit_y) begin
                            current_y <= 0;
                            if (current_x >= limit_x) begin
                                current_x <= 0;
                            end else begin
                                current_x <= current_x + 1;
                                xy_count <= xy_count + 1;
                            end
                        end else begin
                            current_y <= current_y + 1;
                            xy_count <= xy_count + 1;
                        end

                        // if (current_x == limit_x && current_y == limit_y) begin
                        if (xy_count == limit_xy) begin
                            state <= DONE_STATE;
                        end
                        else begin 
                            state <= QUANT_DATA;
                            o_shift_en <= 1;
                        end
                    end else begin
                        state <= COLLECT_IN;
                        o_shift_en <= 0;
                    end
                end

                DONE_STATE: begin
                    if (~o_done) begin
                        state  <= IDLE_STATE;
                        o_shift_en <= 0;
                        o_done <= 1;
                    end
                end

                default: state <= IDLE_STATE;
            endcase
        end
    end

endmodule
