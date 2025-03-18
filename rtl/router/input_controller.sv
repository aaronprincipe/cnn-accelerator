/*
    Make this generic first, then we can add the DWise Convolution
*/
module ir_controller #(
    parameter int ROW = 4,
    parameter int ADDR_WIDTH = 8
) (
    input logic i_clk,
    input logic i_nrst,
    input logic i_en,
    input logic i_reg_clear,
    input logic i_pop_en,

    // Array dimensions
    input logic [ADDR_WIDTH-1:0] i_i_size,
    input logic [ADDR_WIDTH-1:0] i_o_size,
    input logic [ADDR_WIDTH-1:0] i_i_c_size,
    input logic [ADDR_WIDTH-1:0] i_start_addr,

    // Data lane address assignment
    output logic [ADDR_WIDTH-1:0] o_dl_start_addr,
    output logic [ADDR_WIDTH-1:0] o_dl_end_addr,
    output logic [ROW-1:0] o_dl_id,
    output logic o_dl_addr_write_en,

    // Control signals
    output logic o_route_en, // enables tile reader and address comparator
    output logic o_pop_en,
    output logic o_reg_clear, // Clear everything
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
    output logic o_tile_done,
    output logic o_ready
);
    parameter int IDLE = 0;
    parameter int CLEAR = 1;
    parameter int ADDRESS_GENERATION = 2;
    parameter int XY_INCREMENT = 3;
    parameter int TILE_COMPARISON = 4;
    parameter int DATA_OUT = 5;
    
    logic [2:0] state;

    logic route_en;
    logic wr_o_reset;
    logic [ADDR_WIDTH-1:0] o_x, o_y, prev_addr;
    logic y_increment, x_increment, xy_increment, xy_done;

    logic clear_type; // 0 - Clear all, 1 - Clear only FIFO

    assign route_en = i_en & i_fifo_empty;
    assign x_increment = o_x < i_o_size - 1;
    assign y_increment = o_y < i_o_size - 1;
    assign xy_increment = x_increment || y_increment;

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
            o_tile_done <= 0;
            prev_addr <= 0;
            o_x <= 0;
            o_y <= 0;
            o_cntr_clear <= 0;
            xy_done <= 0;
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
            o_tile_done <= 0;
            prev_addr <= 0;
            o_x <= 0;
            o_y <= 0;
            o_cntr_clear <= 0;
            xy_done <= 0;
            state <= IDLE;
        end else begin
            case (state)
                IDLE: begin
                    if (xy_done & i_fifo_route_done) begin
                        o_done <= 1;
                    end else if (route_en) begin
                        if (o_context_done & ~i_fifo_route_done) begin
                            clear_type <= 1;
                            o_reg_clear <= 0;
                        end else begin
                            clear_type <= 0;
                            o_reg_clear <= 1;
                        end
                        o_ready <= 0;
                        o_cntr_clear <= 0;
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
                        state <= TILE_COMPARISON;
                    end else begin
                        state <= ADDRESS_GENERATION;
                    end
                end

                ADDRESS_GENERATION: begin
                    o_dl_end_addr <= i_start_addr + o_x * (i_i_size * i_i_c_size) + (o_y * i_i_c_size) + (i_i_c_size);
                    prev_addr <= i_start_addr + o_x * (i_i_size * i_i_c_size) + (o_y * i_i_c_size) + (i_i_c_size);
                    o_dl_start_addr <= prev_addr;
                    o_dl_addr_write_en <= 1;
                    state <= XY_INCREMENT;
                end

                // This maps the Height and Width of ifmap to Systolic Array
                XY_INCREMENT: begin
                    if (y_increment) begin
                        o_y <= o_y + 1;
                    end else begin
                        if (x_increment) begin
                            o_y <= 0;
                            o_x <= o_x + 1;
                        end else begin
                            o_x <= 0;
                            xy_done <= 1;
                            state <= TILE_COMPARISON;
                            o_dl_addr_write_en <= 0;
                        end
                    end

                    if (o_dl_id == ROW - 1) begin
                        o_dl_id <= 0;
                        o_dl_addr_write_en <= 0;
                        state <= TILE_COMPARISON;
                    end else if (xy_increment) begin
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

                        if (i_fifo_route_done) begin
                            o_tile_done <= 1;
                        end

                        state <= IDLE;
                    end else if (i_pop_en) begin
                        o_pop_en <= 1;
                    end
                end
            endcase
        end
    end

endmodule
