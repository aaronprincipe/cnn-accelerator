/*
    1. Fetch start and end of tiles
    2. Fetch ifmap from systolic array
    3. Go through ifmap using start and end of tiles
    4. Generate addresses
    5. Write to SPAD
    6. if done with x and y tile then increment c and go back to 2 and shift_en
*/
module output_router #(
    parameter int SPAD_WIDTH = 64,
    parameter int DATA_WIDTH = 8,
    parameter int SPAD_N = SPAD_WIDTH / DATA_WIDTH,
    parameter int ADDR_WIDTH = 8,
    parameter int ROWS = 4,
    parameter int COLUMNS = 4
) (
    input logic i_clk,
    input logic i_nrst,
    input logic i_reg_clear,
    input logic i_en,
    
    // Data from systolic array
    input logic [0:ROWS-1][DATA_WIDTH*2-1:0] i_ifmap,
    input logic [ROWS-1:0] i_valid,
    output logic o_shift_en,
    output logic o_psum_out_en,

    // Address generation
    // from top level
    input logic [ADDR_WIDTH-1:0] i_i_size,
    input logic [ADDR_WIDTH-1:0] i_c_size,

    // from input router
    input logic [ADDR_WIDTH-1:0] i_x_s,
    input logic [ADDR_WIDTH-1:0] i_x_e,
    input logic [ADDR_WIDTH-1:0] i_y_s,
    input logic [ADDR_WIDTH-1:0] i_y_e,
    input logic [ADDR_WIDTH-1:0] i_xy_length,
    input logic i_xy_valid,

    // from weight router
    input logic [ADDR_WIDTH-1:0] i_c_s,
    input logic [ADDR_WIDTH-1:0] i_c_e,
    input logic i_c_valid,

    // quant
    input logic [  DATA_WIDTH-1:0] i_quant_sh,
    input logic [2*DATA_WIDTH-1:0] i_quant_m0,

    // Write to SPAD
    output logic [ADDR_WIDTH-1:0] o_addr,
    output logic [SPAD_WIDTH-1:0] o_data_out,
    output logic [SPAD_N-1:0] o_write_mask,
    output logic o_valid,
    output logic o_done,

    // For temp verification
    output logic [DATA_WIDTH-1:0] o_word,
    output logic o_word_valid,
    output logic [ADDR_WIDTH-1:0] o_o_x, o_o_y, o_o_c 
);
    logic [0:ROWS-1][DATA_WIDTH*2-1:0] ifmap;
    logic [ADDR_WIDTH-1:0] row_id;
    logic [ADDR_WIDTH-1:0] o_x, o_y, o_c;
    logic [ADDR_WIDTH-1:0] o_x_lim, o_y_lim, o_c_lim;
    logic [ADDR_WIDTH-1:0] prev_o_x, prev_o_y;
    logic [ADDR_WIDTH-1:0] xy_count;
    logic [2:0] state;
    logic context_done, column_done;

    logic [ADDR_WIDTH-1:0] byte_addr;
    logic [ADDR_WIDTH-1:0] word_addr;
    logic [ADDR_WIDTH-1:0] byte_offset;
    logic [SPAD_WIDTH-1:0] word_data;
    logic [SPAD_N-1:0] word_mask;

    logic                              quant_en;
    logic                              quant_store_reg;
    logic [DATA_WIDTH*2-1:0] quant_i_act;
    logic [DATA_WIDTH-1:0] quant_o_act;

    quant #(    
        .DATA_WIDTH(DATA_WIDTH)
    ) uut (
        .i_clk(i_clk),
        .i_nrst(i_nrst),
        .i_en(quant_en),
        .i_store_reg(quant_store_reg),
        .i_sh(i_quant_sh),
        .i_m0(i_quant_m0),
        .i_act(quant_i_act),
        .o_act(quant_o_act),
        .o_valid(quant_valid)
    );

    parameter int IDLE = 0;
    parameter int READ_IFMAP = 1;
    parameter int ADDRESS_GENERATION = 2;
    parameter int XY_INCREMENT = 3;
    parameter int C_INCREMENT = 4;
    parameter int SHIFT_STALL = 5;

    // Do quantization
    always_ff @(posedge i_clk or negedge i_nrst) begin
        if(~i_nrst) begin
            quant_en <= 0;
            quant_store_reg <= 0;
            
            xy_count <= 0;
            ifmap <= 0;
            row_id <= 0;
            o_x <= 0;
            o_y <= 0;
            o_c <= 0;
            o_x_lim <= 0;
            o_y_lim <= 0;
            o_c_lim <= 0;
            prev_o_x <= 0;
            prev_o_y <= 0;
            context_done <= 0;
            column_done <= 0;
            o_shift_en <= 0;
            o_psum_out_en <= 0;
            o_addr <= 0;
            o_data_out <= 0;
            o_write_mask <= 0;
            o_valid <= 0;
            o_done <= 0;
            o_word <= 0;
            o_word_valid <= 0;
            o_o_x <= 0;
            o_o_y <= 0;
            o_o_c <= 0;
            state <= IDLE;
        end else if (i_reg_clear) begin
            quant_en <= 0;
            quant_store_reg <= 0;

            xy_count <= 0;
            ifmap <= 0;
            row_id <= 0;
            o_x <= 0;
            o_y <= 0;
            o_c <= 0;
            o_x_lim <= 0;
            o_y_lim <= 0;
            o_c_lim <= 0;
            prev_o_x <= 0;
            prev_o_y <= 0;
            context_done <= 0;
            column_done <= 0;
            o_shift_en <= 0;
            o_psum_out_en <= 0;
            o_addr <= 0;
            o_data_out <= 0;
            o_write_mask <= 0;
            o_valid <= 0;
            o_done <= 0;
            o_word <= 0;
            o_word_valid <= 0;
            o_o_x <= 0;
            o_o_y <= 0;
            o_o_c <= 0;
            state <= IDLE;
        end else begin
            case(state)
                IDLE: begin
                    // o_done <= 0;
                    context_done <= 0;
                    column_done <= 0;
                    if(i_xy_valid) begin
                        o_x <= i_x_s;
                        o_y <= i_y_s;
                        prev_o_x <= i_x_s;
                        prev_o_y <= i_y_s;
                        o_x_lim <= i_x_e;
                        o_y_lim <= i_y_e;
                    end

                    if(i_c_valid) begin
                        o_c <= i_c_s;
                        o_c_lim <= i_c_e;
                    end

                    if (i_en & ~o_done) begin
                        o_psum_out_en <= 1;
                        state <= READ_IFMAP;
                    end else begin
                        o_done <= 0;
                    end
                end

                READ_IFMAP: begin

                    quant_store_reg <= 1;
                    ifmap <= i_ifmap;
                    
                    row_id <= 0;
                    o_x <= prev_o_x;
                    o_y <= prev_o_y;
                    column_done <= 0;
                    state <= ADDRESS_GENERATION;
                end

                ADDRESS_GENERATION: begin
                    o_shift_en <= 0;
                    // offset_nhwc(n, c, h, w) = n * HWC + h * WC + w * C + c
                    if (column_done) begin
                        column_done <= 0;
                        o_data_out <= 0;
                        o_valid <= 0;
                        o_addr <= 0;
                        o_write_mask <= 0;
                        state <= C_INCREMENT;
                        o_word <= 0;
                        o_o_x <= 0;
                        o_o_y <= 0;
                        o_o_c <= 0;
                        o_word_valid <= 0;
                    end else begin
                        if (!quant_valid) begin
                            quant_en <= 1;
                            quant_i_act <= ifmap[row_id];
                        end else begin
                            quant_en <= 0;
                            o_addr <= word_addr;
                            o_write_mask <= word_mask;
                            o_valid <= 1;
                            // This should be in 8-bits
                            o_data_out <= quant_o_act << byte_offset * SPAD_N;
                            row_id <= row_id + 1;
                            state <= XY_INCREMENT;
                            o_word <= quant_o_act;
                            o_o_x <= o_x;
                            o_o_y <= o_y;
                            o_o_c <= o_c;
                            o_word_valid <= 1;
                        end
                    end
                end

                XY_INCREMENT: begin
                    o_word <= 0;
                    o_o_x <= 0;
                    o_o_y <= 0;
                    o_o_c <= 0;
                    o_word_valid <= 0;
                    o_valid <= 0;
                    if(o_y >= o_y_lim) begin
                        o_y <= 0;
                        if(o_x >= o_x_lim) begin
                            o_x <= 0;
                            column_done <= 1;
                        end else begin
                            o_x <= o_x + 1;
                        end
                    end else begin
                        o_y <= o_y + 1;
                    end

                    if (xy_count == i_xy_length) begin
                        xy_count <= 0;
                        column_done <= 1;
                    end else begin
                        xy_count <= xy_count + 1;
                    end
                    state <= ADDRESS_GENERATION;
                end

                C_INCREMENT: begin
                    o_valid <= 0;
                    if (o_c >= o_c_lim) begin
                        o_done <= 1;
                        ifmap <= 0;
                        state <= IDLE;
                    end else begin
                        o_c <= o_c + 1;
                        o_shift_en <= 1;
                        state <= SHIFT_STALL;
                    end
                end

                SHIFT_STALL: begin
                    o_shift_en <= 0;
                    state <= READ_IFMAP;
                end
            endcase
        end
    end

    always_comb begin
        byte_addr = o_x * i_i_size * i_c_size + o_y * i_c_size + o_c;
        word_addr = byte_addr >> $clog2(SPAD_N);
        byte_offset = byte_addr % SPAD_N;
    end

    genvar ii;
    generate
        for (ii = 0; ii < SPAD_N; ii = ii + 1) begin
            always_comb begin
                if (ii == byte_offset) begin
                    word_mask[ii] = 1;
                end else begin
                    word_mask[ii] = 0;
                end
            end
        end
    endgenerate
endmodule