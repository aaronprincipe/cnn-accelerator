/*
    Make this generic first, then we can add the DWise Convolution
*/
module ir_controller #(
    parameter int ROW = 4,
    parameter int ADDR_WIDTH = 8,
    parameter int KERNEL_SIZE = 3,
    parameter int KERNEL_LENGTH = 9,
    parameter int SPAD_N = 8
) (
    input logic i_clk,
    input logic i_nrst,
    input logic i_en,
    input logic i_reg_clear,
    input logic i_pop_en,

    // Convolution mode - 0: PWise, 1: DWise
    input logic i_conv_mode,

    // Array dimensions
    input logic [ADDR_WIDTH-1:0] i_i_size,
    input logic [ADDR_WIDTH-1:0] i_o_size,
    input logic [ADDR_WIDTH-1:0] i_i_c_size,
    input logic [ADDR_WIDTH-1:0] i_i_c,
    input logic [ADDR_WIDTH-1:0] i_stride,
    input logic [ADDR_WIDTH-1:0] i_start_addr,

    // Data lane address assignment
    input logic [ADDR_WIDTH-1:0] i_slots,
    output logic [0:KERNEL_LENGTH-1][ADDR_WIDTH-1:0] o_dl_sw_addr,
    output logic [ADDR_WIDTH-1:0] o_dl_start_addr,
    output logic [ADDR_WIDTH-1:0] o_dl_end_addr,
    output logic [ROW-1:0] o_dl_id,
    output logic o_dl_addr_write_en,

    // Output router signals
    output logic [ADDR_WIDTH-1:0] o_x_s, o_x_e, o_y_s, o_y_e,
    output logic o_xy_valid,
    output logic [ADDR_WIDTH-1:0] o_xy_length,

    // Control signals
    output logic o_route_en, // enables tile reader and address comparator
    output logic o_pop_en,
    output logic o_reg_clear, // Clear everything
    output logic o_fifo_clear, // Clear only FIFO
    output logic o_tr_clear,
    output logic o_tr_stall,
    output logic o_cntr_clear,
    
    // Status signals
    input logic i_fifo_full,
    input logic i_fifo_route_done,
    input logic i_fifo_empty,
    input logic i_fifo_idle,
    output logic o_done,
    output logic o_context_done,
    output logic o_tile_done,
    output logic o_ready,
    output logic [2:0] o_state,
    output logic [ADDR_WIDTH-1:0] o_tile_addr,

    // To top level control
    output logic [ADDR_WIDTH-1:0] o_s_r,
    output logic [ADDR_WIDTH-1:0] o_t
);
    parameter int IDLE = 0;
    parameter int CLEAR = 1;
    parameter int ADDRESS_GENERATION = 2;
    parameter int XY_INCREMENT = 3;
    parameter int TILE_COMPARISON = 4;
    parameter int DATA_OUT = 5;
    
    logic [2:0] state;

    assign o_state = state;
    logic route_en;
    logic wr_o_reset;
    logic first_row;
    logic [ADDR_WIDTH-1:0] o_x, o_y, prev_addr, tile_addr;
    logic y_increment, x_increment, xy_increment, xy_done;

    logic clear_type; // 0 - Clear all, 1 - Clear only FIFO

    // Add logic for starting read address of tile reader
    // Should not go from the start everytime

    assign route_en = i_en & i_fifo_empty;
    assign x_increment = o_x < (i_o_size * i_stride) - i_stride;;
    assign y_increment = o_y < (i_o_size * i_stride) - i_stride;;
    assign xy_increment = x_increment || y_increment;

    logic [0:KERNEL_LENGTH-1][ADDR_WIDTH-1:0] addr;

    always_ff @(posedge i_clk or negedge i_nrst) begin
        if (~i_nrst) begin
            o_route_en <= 0;
            o_context_done <= 0;
            o_done <= 0;
            o_pop_en <= 0;
            o_reg_clear <= 0;
            o_fifo_clear <= 0;
            o_tr_clear <= 0;
            o_tr_stall <= 0;
            o_ready <= 0;
            o_dl_sw_addr <= 0;
            o_dl_start_addr <= 0;
            o_dl_end_addr <= 0;
            o_dl_id <= 0;
            o_dl_addr_write_en <= 0;
            o_tile_done <= 0;
            prev_addr <= 0;
            o_x <= 0;
            o_y <= 0;
            o_cntr_clear <= 0;
            xy_done <= 0;

            o_x_s <= 0;
            o_x_e <= 0;
            o_y_s <= 0;
            o_y_e <= 0;
            o_xy_valid <= 0;
            o_xy_length <= 0;

            first_row <= 0;
            o_s_r <= 0;
            o_t <= 0;
            state <= IDLE;
        end else if (i_reg_clear) begin
            o_route_en <= 0;
            o_context_done <= 0;
            o_done <= 0;
            o_pop_en <= 0;
            o_reg_clear <= 0;
            o_fifo_clear <= 0;
            o_tr_clear <= 0;
            o_tr_stall <= 0;
            o_ready <= 0;
            o_dl_sw_addr <= 0;
            o_dl_start_addr <= 0;
            o_dl_end_addr <= 0;
            o_dl_id <= 0;
            o_dl_addr_write_en <= 0;
            o_tile_done <= 0;
            prev_addr <= 0;
            o_x <= 0;
            o_y <= 0;
            o_cntr_clear <= 0;
            xy_done <= 0;

            o_x_s <= 0;
            o_x_e <= 0;
            o_y_s <= 0;
            o_y_e <= 0;
            o_xy_valid <= 0;
            o_xy_length <= 0;

            first_row <= 0;
            o_s_r <= 0;
            o_t <= 0;
            state <= IDLE;
        end else begin
            case (state)
                IDLE: begin
                    if (xy_done & i_fifo_route_done) begin
                        o_done <= 1;
                        // Reset Tile Reader
                        o_tr_clear <= 1;
                        o_tr_stall <= 0;
                    end else if (route_en) begin
                        if (i_conv_mode) begin
                            clear_type <= 0;
                            o_reg_clear <= 1;
                        end else begin
                            if (o_context_done & ~i_fifo_route_done) begin
                                clear_type <= 1;
                                o_reg_clear <= 0;
                            end else begin
                                clear_type <= 0;
                                o_reg_clear <= 1;
                            end
                        end
                        o_ready <= 0;
                        o_cntr_clear <= 0;
                        o_tr_stall <= 0;
                        state <= CLEAR;
                    end
                end

                CLEAR: begin
                    o_fifo_clear <= 0;
                    o_tr_clear <= 0;
                    o_reg_clear <= 0;
                    o_context_done <= 0;
                    o_tile_done <= 0;

                    if (clear_type) begin
                        o_xy_valid <= 1;
                        state <= TILE_COMPARISON;
                    end else begin
                        state <= ADDRESS_GENERATION;
                        o_x_s <= o_x;
                        o_y_s <= o_y;
                    end
                end

                ADDRESS_GENERATION: begin
                    if (i_conv_mode) begin
                        // Dwise
                        o_dl_sw_addr <= addr;
                        if (!first_row) begin
                            first_row <= 1;
                            tile_addr <= ((i_start_addr * SPAD_N) + ((o_x) * i_i_size + (o_y))) >> $clog2(SPAD_N);
                        end
                    end else begin
                        // Pwise
                        o_dl_end_addr <= (i_start_addr * SPAD_N) + o_x * (i_i_size * i_i_c_size) + (o_y * i_i_c_size) + (i_i_c_size);
                        prev_addr <= o_x * (i_i_size * i_i_c_size) + (o_y * i_i_c_size) + (i_i_c_size);
                        o_dl_start_addr <= prev_addr + (i_start_addr * SPAD_N);

                        if (!first_row) begin
                            first_row <= 1;
                            tile_addr <= (prev_addr + (i_start_addr * SPAD_N)) >> $clog2(SPAD_N);
                        end
                    end
                    o_dl_addr_write_en <= 1;
                    state <= XY_INCREMENT;
                end

                // This maps the Height and Width of ifmap to Systolic Array
                XY_INCREMENT: begin
                    o_dl_addr_write_en <= 0;
                    if (y_increment) begin
                        o_y <= o_y + i_stride;
                    end else begin
                        if (x_increment) begin
                            o_y <= 0;
                            o_x <= o_x + i_stride;
                            o_y_e <= o_y;
                        end else begin
                            o_x <= 0;
                            xy_done <= 1;
                            o_x_e <= o_x;
                            o_y_e <= o_y;
                            o_xy_length <= o_dl_id;
                            o_xy_valid <= 1;
                            state <= TILE_COMPARISON;
                        end
                    end

                    if (o_dl_id == ROW - 1) begin
                        o_dl_id <= 0;
                        o_x_e <= o_x;
                        if (o_y > o_y_e) begin
                            o_y_e <= o_y;
                        end
                        o_xy_length <= o_dl_id;
                        o_xy_valid <= 1;
                        o_s_r <= o_dl_id;
                        state <= TILE_COMPARISON;
                    end else if (xy_increment) begin
                        o_dl_id <= o_dl_id + 1;
                        state <= ADDRESS_GENERATION;
                    end
                end

                TILE_COMPARISON: begin
                    first_row <= 0;
                    o_xy_valid <= 0;
                    o_y_s <= 0;
                    o_x_s <= 0;
                    o_y_e <= 0;
                    o_x_e <= 0;
                    // If FIFO is full - reuse weights in Weight FIFO
                    // If FIFO route done - new set of weights
                    if (i_fifo_route_done || i_fifo_full || i_fifo_idle) begin
                        o_route_en <= 0;
                        o_ready <= 1;
                        o_t <= i_slots;
                        state <= DATA_OUT;
                    end else begin
                        o_route_en <= 1;
                    end
                end

                DATA_OUT: begin
                    if (i_fifo_empty) begin
                        o_pop_en <= 0;
                        o_ready <= 0;
                        o_context_done <= 1;
                       
                        o_fifo_clear <= 1;
                        o_cntr_clear <= 1;

                        if (i_fifo_route_done) begin
                            o_tile_done <= 1;
                        end

                        o_tr_clear <= 1;


                        state <= IDLE;
                    end else if (i_pop_en) begin
                        o_pop_en <= 1;
                    end
                end
            endcase
        end
    end

    // Dwise sliding window address generation
    genvar x, y;
    generate  
        for (x = 0; x < KERNEL_SIZE; x = x + 1) begin : gen_x
            for (y = 0; y < KERNEL_SIZE; y = y + 1) begin : gen_y
                localparam int addr_idx = x * KERNEL_SIZE + y;
                always_comb begin
                    if (i_conv_mode) begin
                    // offset_nchw(n, c, h, w) = c * HW + h * W + w
                    // Uncomment if using NCHW format
                    addr[addr_idx] = (i_start_addr * SPAD_N) + ((o_x + x) * i_i_size + (o_y + y));

                    // offset_nhwc(n, c, h, w) = h * WC + w * C + c
                    // Uncomment if using NHWC format
                        // addr[addr_idx] = (i_start_addr * SPAD_N) + (o_x + x) * i_i_size * i_i_c_size + (o_y + y) * i_i_c_size + i_i_c;
                    end else begin
                        addr[addr_idx] = '0;
                    end
                end
            end
        end
    endgenerate

    assign o_tile_addr = tile_addr;
endmodule
