module wr_controller #(
    parameter int COLUMN = 4,
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
    input logic [ADDR_WIDTH-1:0] i_o_c,
    input logic [ADDR_WIDTH-1:0] i_i_c_size,
    input logic [ADDR_WIDTH-1:0] i_o_c_size,
    input logic [ADDR_WIDTH-1:0] i_i_c,
    input logic [ADDR_WIDTH-1:0] i_start_addr,

    // Data lane address assignment
    output logic [0:KERNEL_LENGTH-1][ADDR_WIDTH-1:0] o_dl_sw_addr,
    output logic [ADDR_WIDTH-1:0] o_dl_start_addr,
    output logic [ADDR_WIDTH-1:0] o_dl_end_addr,
    output logic [COLUMN-1:0] o_dl_id,
    output logic o_dl_addr_write_en,

    // Output router signals
    output logic [ADDR_WIDTH-1:0] o_c_s, o_c_e,
    output logic o_c_valid,

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
    output logic o_ready,
    output logic [2:0] o_state
);
    parameter int IDLE = 0;
    parameter int CLEAR = 1;
    parameter int ADDRESS_GENERATION = 2;
    parameter int C_INCREMENT = 3;
    parameter int TILE_COMPARISON = 4;
    parameter int DATA_OUT = 5;
    
    logic [2:0] state;
    assign o_state = state;
    logic route_en;

    logic [ADDR_WIDTH-1:0] o_c;
    logic c_increment, c_done;

    logic clear_type; // 0 - Clear all, 1 - Clear only FIFO

    assign route_en = i_en & i_fifo_empty;
    assign c_increment = o_c < i_o_c_size - 1;

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
            o_cntr_clear <= 0;
            o_c <= 0;
            c_done <= 0;
            o_c_s <= 0;
            o_c_e <= 0;
            o_c_valid <= 0;
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
            o_cntr_clear <= 0;
            o_c <= 0;
            c_done <= 0;
            o_c_s <= 0;
            o_c_e <= 0;
            o_c_valid <= 0;
            state <= IDLE;
        end else begin
            case (state)
                IDLE: begin
                    // If we reset just reuse the weights
                    if (c_done & i_fifo_route_done) begin
                        o_done <= 1;
                        o_tr_clear <= 1;
                        o_tr_stall <= 0;
                    end else if (route_en) begin
                        if (o_context_done & ~i_fifo_route_done) begin
                            clear_type <= 1;
                            o_reg_clear <= 0;
                        end else begin
                            clear_type <= 0;
                            o_reg_clear <= 1;
                        end
                        o_c <= i_o_c;
                        o_cntr_clear <= 0;
                        o_fifo_clear <= 0;
                        o_tr_clear <= 0;
                        o_ready <= 0;
                        o_context_done <= 0;
                        o_tr_stall <= 0;
                        state <= CLEAR;
                    end
                end

                CLEAR: begin
                    o_reg_clear <= 0;
                    o_dl_addr_write_en <= 0;
                    if (clear_type) begin
                        o_c_valid <= 1;
                        state <= TILE_COMPARISON;
                    end else begin
                        state <= ADDRESS_GENERATION;
                        o_c_s <= o_c;
                    end
                end

                ADDRESS_GENERATION: begin
                    if(i_conv_mode) begin
                        // Dwise
                        o_dl_sw_addr <= addr;
                    end else begin
                        // Pwise
                        o_dl_end_addr <= (i_start_addr * SPAD_N) + (o_c + 1) * i_i_c_size;
                        o_dl_start_addr <= (i_start_addr * SPAD_N) + o_c * i_i_c_size;;
                    end

                    o_dl_addr_write_en <= 1;
                    state <= C_INCREMENT;
                end

                C_INCREMENT: begin
                    o_dl_addr_write_en <= 0;
                    if (i_conv_mode) begin
                        // Dwise
                        // We don't need to increment the channel
                        // Since we need only one channel at a time
                        o_dl_id <= 0;
                        o_done <= 1;
                        state <= TILE_COMPARISON;
                    end else begin
                        // Pwise
                        if (c_increment) begin
                            o_c <= o_c + 1;
                        end else begin
                            o_c <= 0;
                            o_c_e <= o_c;
                            o_c_valid <= 1;
                            c_done <= 1;
                            state <= TILE_COMPARISON;
                        end

                        if (o_dl_id == COLUMN - 1) begin
                            o_dl_id <= 0;
                            o_c_e <= o_c;
                            o_c_valid <= 1;
                            state <= TILE_COMPARISON;
                        end else if (c_increment) begin
                            o_dl_id <= o_dl_id + 1;
                            state <= ADDRESS_GENERATION;
                        end
                    end


                end

                TILE_COMPARISON: begin
                    o_c_valid <= 0;
                    // If FIFO is full - reuse weights in Weight FIFO
                    // If FIFO route done - new set of weights
                    if (i_fifo_route_done || i_fifo_full || i_fifo_idle) begin
                        o_route_en <= 0;
                        o_ready <= 1;
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
                        o_tr_stall <= 1;
                        o_fifo_clear <= 1;
                        o_cntr_clear <= 1;
                        state <= IDLE;
                    end else if (i_pop_en) begin
                        o_pop_en <= 1;
                    end
                end
            endcase
        end
    end

    // Fetch the address of the weights in NCHW/OHWI format
    // In theory we could expand to a standard convolution
    genvar x, y;
    generate  
        for (x = 0; x < KERNEL_SIZE; x = x + 1) begin : gen_x
            for (y = 0; y < KERNEL_SIZE; y = y + 1) begin : gen_y
                localparam int addr_idx = x * KERNEL_SIZE + y;
                always_comb begin
                    if (i_conv_mode) begin
                        // o_c, i_i_c, i_i_c_size
                        addr[addr_idx] = (i_start_addr * SPAD_N) + (addr_idx * KERNEL_SIZE) + i_i_c;
                    end else begin
                        addr[addr_idx] = '0;
                    end
                end
            end
        end
    endgenerate

endmodule
