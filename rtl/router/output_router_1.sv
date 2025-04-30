
module output_router_1 #(
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
    // Systolic Array inputs
    input  logic [0:COLUMNS-1][2*DATA_WIDTH-1:0] i_ifmap,
    input  logic [0:COLUMNS-1]                   i_valid,       // not used in top.sv
    output logic                                 o_shift_en,
    // Qunatization parameters
    input  logic [0:COLUMNS-1][  DATA_WIDTH-1:0] i_quant_sh,
    input  logic [0:COLUMNS-1][2*DATA_WIDTH-1:0] i_quant_m0,
    // Address generation
    // Top module inputs
    input logic  [ADDR_WIDTH-1:0] i_i_size,
    input logic  [ADDR_WIDTH-1:0] i_c_size,
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
    // For debug
    output logic [SPAD_WIDTH-1:0] o_word,
    output logic                  o_word_valid,
    output logic [ADDR_WIDTH-1:0] o_o_x,
    output logic [ADDR_WIDTH-1:0] o_o_y,
    output logic [ADDR_WIDTH-1:0] o_o_c
);
    logic [0:COLUMNS-1]       input_valid;
    logic [$clog2(COLUMNS):0] num_input_valid;
    // Parallel quant
    logic                                 quant_en;
    logic [0:COLUMNS-1]                   quant_store_reg;
    logic [0:COLUMNS-1][2*DATA_WIDTH-1:0] quant_i_act;
    logic [0:COLUMNS-1][  DATA_WIDTH-1:0] quant_o_act;
    logic [0:COLUMNS-1]                   quant_valid;
    logic                                 quant_all_valid;
    // data buffer to SPAD
    logic        [SPAD_WIDTH-1:0]         data_buffer;  // buffer data to be written to spad
    logic        [COLUMNS*DATA_WIDTH-1:0] data_left;    // leftover data not written to spad
    logic signed [$clog2(COLUMNS+1):0]    data_left_cnt;
    // 
    logic [ADDR_WIDTH-1:0] current_x, current_y, current_c;
    logic [ADDR_WIDTH-1:0] start_x, start_y, start_c;
    logic [ADDR_WIDTH-1:0] limit_x, limit_y, limit_c;
    // SPAD address
    logic [ADDR_WIDTH-1:0] byte_addr;    // which byte in the SPAD
    logic [ADDR_WIDTH-1:0] word_addr;    // which word in the SPAD
    logic [ADDR_WIDTH-1:0] byte_offset;  // which byte in the word
    // address = n*HWC + h*WC + w*C + c
    always_comb begin
        byte_addr   = (current_x * i_i_size + current_y) * i_c_size + current_c;
        word_addr   = byte_addr >> $clog2(SPAD_N);
        byte_offset = byte_addr % SPAD_N;
    end

    genvar q;
    generate
        for (q=0; q<COLUMNS; q=q+1) begin: quat_parallel_gen
            quant #(
                .DATA_WIDTH(DATA_WIDTH)
            ) quant_inst (
                .i_clk      (i_clk),
                .i_nrst     (i_nrst),
                .i_en       (quant_en),
                .i_store_reg(quant_store_reg[q]),
                .i_sh       (i_quant_sh[q]),
                .i_m0       (i_quant_m0[q]),
                .i_act      (quant_i_act[q]),
                .o_act      (quant_o_act[q]),
                .o_valid    (quant_valid[q])
            );
        end
    endgenerate
    // quant data is only valid when all data is valid;
    assign quant_all_valid = &quant_valid;

    always@(input_valid)begin
        num_input_valid = 0;
        for (int i=0; i<COLUMNS; i=i+1) num_input_valid = num_input_valid + input_valid[i]; 
    end

    always_comb begin
        o_word       = o_data_out;
        o_word_valid = o_valid;
        o_o_x        = current_x;
        o_o_y        = current_y;
        o_o_c        = current_c;
    end

    parameter int IDLE_STATE = 0;
    parameter int QUANT_DATA = 1;
    parameter int COLLECT_IN = 2;
    parameter int SPAD_WRITE = 3;
    parameter int NEXT_ADDR  = 4;
    parameter int DONE_STATE = 5;

    logic [2:0] state;

    always_ff @(posedge i_clk) begin
        if (!i_nrst || i_reg_clear) begin
            state           <= IDLE_STATE;
            
            input_valid     <= 0;

            quant_en        <= 0;
            quant_store_reg <= 0;
            quant_i_act     <= 0;

            data_buffer     <= 0;
            data_left       <= 0;
            data_left_cnt   <= 0;

            current_x       <= 0;
            current_y       <= 0;
            current_c       <= 0;
            start_x         <= 0;
            start_y         <= 0;
            start_c         <= 0;
            limit_x         <= 0;
            limit_y         <= 0;
            limit_c         <= 0;

            o_addr          <= 0;
            o_data_out      <= 0;
            o_write_mask    <= 0;
            o_valid         <= 0;
            o_shift_en      <= 0;
            o_done          <= 0;
        end else begin
            case (state)
                IDLE_STATE: begin
                    if (i_xy_valid) begin
                        current_x <= i_x_s;
                        current_y <= i_y_s;
                        start_x   <= i_x_s;
                        start_y   <= i_y_s;
                        limit_x   <= i_x_e;
                        limit_y   <= i_y_e;
                    end

                    if (i_c_valid) begin
                        current_c <= i_c_s;
                        start_c   <= i_c_s;
                        limit_c   <= i_c_e;
                    end
                    
                    if (i_en && !o_done) begin
                        state         <= QUANT_DATA;
                        input_valid   <= i_valid;
                        for(int i=0; i<COLUMNS; i=i+1) quant_store_reg[i] <= 1'b1;
                    end 
                    else 
                        o_done <= 0;
                end

                QUANT_DATA: begin
                    if (num_input_valid > 0) begin
                        for(int i=0; i<COLUMNS; i=i+1) quant_store_reg[i] <= 1'b0;
                        if (quant_all_valid) begin
                            state         <= COLLECT_IN;
                            quant_en      <= 0;
                            data_left     <= quant_o_act;
                            data_left_cnt <= (num_input_valid < COLUMNS)? num_input_valid : COLUMNS;
                        end else begin
                            quant_en      <= 1'b1;
                            quant_i_act   <= i_ifmap;
                        end
                    end 
                    else 
                        state <= DONE_STATE;
                end

                COLLECT_IN: begin
                    state <= SPAD_WRITE;
                    o_valid      <= 1;
                    o_write_mask <= input_valid;
                    if (byte_offset != 0) begin
                        // {data_left, data_buffer} <= data_left << (byte_offset * DATA_WIDTH);
                        data_buffer <= data_left << (byte_offset * DATA_WIDTH);
                        data_left   <= data_left >> (SPAD_WIDTH - byte_offset * DATA_WIDTH);
                        data_left_cnt <= data_left_cnt - SPAD_N + byte_offset;
                        input_valid <= input_valid >> (SPAD_N - byte_offset);
                    end 
                    else begin
                        // {data_left, data_buffer} <= data_left;
                        data_buffer <= data_left;
                        data_left   <= data_left >> (SPAD_WIDTH);
                        data_left_cnt <= data_left_cnt - SPAD_N;
                        input_valid <= input_valid >> (SPAD_N);
                    end
                end

                SPAD_WRITE: begin
                    o_valid      <= 0;
                    o_write_mask <= 0;
                    if (data_left_cnt <= 0) begin
                        state <= NEXT_ADDR;
                    end else begin
                        state <= COLLECT_IN;
                        o_addr       <= word_addr;
                        o_data_out   <= data_buffer;
                    end
                end

                NEXT_ADDR: begin
                    if (current_c >= limit_c) begin
                        if (current_x == limit_x && current_y == limit_y) begin
                            state <= DONE_STATE;
                            o_shift_en <= 1;
                        end
                        else begin 
                            state <= QUANT_DATA;
                            current_c <= start_c;
                        end

                        if (current_y >= limit_y) begin
                            current_y <= start_y;
                            if (current_x >= limit_x) begin
                                current_x <= start_x;
                            end else begin
                                current_x <= current_x + 1;
                            end
                        end else begin
                            current_y <= current_y + 1;
                        end
                    end else begin
                        current_c <= current_c + SPAD_N;
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
