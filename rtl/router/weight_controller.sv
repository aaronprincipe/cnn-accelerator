module wr_controller #(
    parameter int COLUMN = 4,
    parameter int ADDR_WIDTH = 8
) (
    input logic i_clk,
    input logic i_nrst,
    input logic i_en,
    input logic i_reg_clear,
    input logic i_pop_en,

    // Array dimensions
    input logic [ADDR_WIDTH-1:0] i_o_c,
    input logic [ADDR_WIDTH-1:0] i_i_c_size,
    input logic [ADDR_WIDTH-1:0] i_o_c_size,
    input logic [ADDR_WIDTH-1:0] i_start_addr,

    // Data lane address assignment
    output logic [ADDR_WIDTH-1:0] o_dl_start_addr,
    output logic [ADDR_WIDTH-1:0] o_dl_end_addr,
    output logic [COLUMN-1:0] o_dl_id,
    output logic o_dl_addr_write_en,

    // Control signals
    output logic o_route_en, // enables tile reader and address comparator
    output logic o_pop_en,
    output logic o_reg_clear, // Clear everything
    output logic o_fifo_reset,
    output logic o_fifo_clear, // Clear only FIFO
    output logic o_tr_clear,
    output logic o_cntr_clear,
    
    // Status signals
    input logic i_fifo_full,
    input logic i_fifo_route_done,
    input logic i_fifo_empty,
    input logic i_fifo_idle,
    output logic o_done,
    output logic o_context_done,
    output logic o_ready
);
    parameter int IDLE = 0;
    parameter int CLEAR = 1;
    parameter int ADDRESS_GENERATION = 2;
    parameter int C_INCREMENT = 3;
    parameter int TILE_COMPARISON = 4;
    parameter int DATA_OUT = 5;
    
    logic [2:0] state;

    logic route_en;

    logic [ADDR_WIDTH-1:0] o_c;
    logic c_increment, c_done;

    logic clear_type; // 0 - Clear all, 1 - Clear only FIFO

    assign route_en = i_en & i_fifo_empty;
    assign c_increment = o_c < i_o_c_size - 1;

    logic [ADDR_WIDTH-1:0] prev_addr;

    always_ff @(posedge i_clk or negedge i_nrst) begin
        if (~i_nrst) begin
            o_route_en <= 0;
            o_context_done <= 0;
            o_done <= 0;
            o_pop_en <= 0;
            o_reg_clear <= 0;
            o_fifo_clear <= 0;
            o_tr_clear <= 0;
            o_ready <= 0;
            o_dl_start_addr <= 0;
            o_dl_end_addr <= 0;
            o_dl_id <= 0;
            o_dl_addr_write_en <= 0;
            o_fifo_reset <= 0;
            o_cntr_clear <= 0;
            prev_addr <= 0;
            o_c <= 0;
            c_done <= 0;
            state <= IDLE;
        end else if (i_reg_clear) begin
            o_route_en <= 0;
            o_context_done <= 0;
            o_done <= 0;
            o_pop_en <= 0;
            o_reg_clear <= 0;
            o_fifo_clear <= 0;
            o_tr_clear <= 0;
            o_ready <= 0;
            o_dl_start_addr <= 0;
            o_dl_end_addr <= 0;
            o_dl_id <= 0;
            o_dl_addr_write_en <= 0;
            o_fifo_reset <= 0;
            o_cntr_clear <= 0;
            prev_addr <= 0;
            o_c <= 0;
            c_done <= 0;
            state <= IDLE;
        end else begin
            case (state)
                IDLE: begin
                    // If we reset just reuse the weights
                    if (c_done & i_fifo_route_done) begin
                        o_done <= 1;
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
                        state <= CLEAR;
                    end
                end

                CLEAR: begin
                    
                    o_fifo_reset <= 0;
                    o_reg_clear <= 0;
                    o_dl_addr_write_en <= 0;
                    if (clear_type) begin
                        state <= TILE_COMPARISON;
                    end else begin
                        state <= ADDRESS_GENERATION;
                    end
                end

                ADDRESS_GENERATION: begin
                    o_dl_end_addr <= i_start_addr + (o_c+1) * i_i_c_size;
                    o_dl_start_addr <= i_start_addr + o_c * i_i_c_size;;
                    o_dl_addr_write_en <= 1;
                    state <= C_INCREMENT;
                end

                C_INCREMENT: begin
                    if (c_increment) begin
                        o_c <= o_c + 1;
                    end else begin
                        o_c <= 0;
                        c_done <= 1;
                        state <= TILE_COMPARISON;
                        o_dl_addr_write_en <= 0;
                    end

                    if (o_dl_id == COLUMN - 1) begin
                        o_dl_id <= 0;
                        o_dl_addr_write_en <= 0;
                        state <= TILE_COMPARISON;
                    end else if (c_increment) begin
                        o_dl_id <= o_dl_id + 1;
                        o_dl_addr_write_en <= 1;
                        state <= ADDRESS_GENERATION;
                    end
                end

                TILE_COMPARISON: begin
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
                        o_tr_clear <= 1;
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

endmodule
