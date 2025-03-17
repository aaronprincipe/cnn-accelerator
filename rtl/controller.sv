/*
    - When both IR and WR are ready, send pop_en signal to both
    - When route is enabled, send en signal to both
    - When IR (context_done or done) and WR (done) are ready:
        - Estimate when calculation is done
        - Send psum_out signal
        - Send en signal to output router
*/


module top_controller # (
    parameter int ROWS = 2,
    parameter int COLUMNS = 2,
    parameter int ADDR_WIDTH = 8
) (
    input logic i_clk,
    input logic i_nrst,
    input logic i_reg_clear,

    // SPAD related signals
    // input logic i_spad_write_en,
    // input logic i_spad_select, // 0 for weight, 1 for input
    // output logic o_spad_w_write_en,
    // output logic o_spad_i_write_en,

    // Enable signals
    input logic i_route_en,
    output logic o_ir_en,
    output logic o_wr_en,
    output logic o_ir_pop_en,
    output logic o_wr_pop_en,

    // Ready to Pop signals
    input logic i_ir_ready,
    input logic i_wr_ready,

    // Start computing
    input logic i_ir_context_done,
    input logic i_wr_context_done,

    // Finished input tile, reset weight router
    input logic i_ir_tile_done,
    output logic o_ir_reg_clear,
    output logic o_wr_reg_clear,

    // Dimensions
    output logic [ADDR_WIDTH-1:0] o_o_c,

    // Finished computing
    input logic i_ir_done,
    input logic i_wr_done,
    output logic o_done
);
    logic [2:0] state;
    parameter int IDLE = 0;
    parameter int CLEAR = 1;
    parameter int ACTIVATION_ROUTING = 2;
    parameter int FIFO_POP = 3;
    parameter int COMPUTE = 4;
    parameter int OUTPUT_ROUTING = 5;
    parameter int DONE = 6;

    // Create an FSM to control the entire process
    /*
        IDLE:
        ACTIVATION_ROUTING: when route is enabled, then route
        BOTH_ROUTE: when both weight and input routers are ready then pop
        COMPUTE: when input router finished popping, then stop
        OUTPUT_ROUTING
        DONE
    */

    always_ff @(posedge i_clk or negedge i_nrst) begin
        if(~i_nrst) begin
            o_wr_en <= 0;
            o_ir_pop_en <= 0;
            o_wr_pop_en <= 0;
            o_ir_reg_clear <= 0;
            o_wr_reg_clear <= 0;
            o_o_c <= 0;
            o_done <= 0;
            state <= IDLE;
        end else if (i_reg_clear) begin
            o_wr_en <= 0;
            o_ir_pop_en <= 0;
            o_wr_pop_en <= 0;
            o_ir_reg_clear <= 0;
            o_wr_reg_clear <= 0;
            o_o_c <= 0;
            o_done <= 0;
            state <= IDLE;
        end else begin
            case (state)
                IDLE: begin
                    if (i_ir_done & i_wr_done) begin
                        o_done <= 1;
                    end else if (i_route_en) begin
                        if (i_ir_done) begin
                            o_ir_reg_clear <= 1;
                            o_o_c <= o_o_c + COLUMNS;
                        end else begin
                            o_o_c <= o_o_c;
                        end

                        if (i_ir_tile_done) begin
                            o_wr_reg_clear <= 1;
                        end
                        state <= CLEAR;
                    end
                end

                CLEAR: begin
                    o_wr_reg_clear <= 0;
                    o_ir_reg_clear <= 0;
                    o_ir_en <= 1;
                    o_wr_en <= 1;
                    state <= ACTIVATION_ROUTING;
                end

                ACTIVATION_ROUTING: begin
                    // Set to low to prevent router to autoroute after compute
                    o_ir_en <= 0;
                    o_wr_en <= 0;
                    if (i_ir_ready & i_wr_ready) begin
                        o_ir_pop_en <= 1;
                        o_wr_pop_en <= 1;
                        state <= FIFO_POP;
                    end
                end

                FIFO_POP: begin
                    // Done popping from both routers
                    if (i_ir_context_done & i_wr_context_done) begin
                        state <= COMPUTE;
                    end
                end
                
                // Given row and column, estimate how many cycles it will take to compute
                // For now, we will assume it takes 1 cycle to compute
                COMPUTE: begin
                    o_ir_pop_en <= 0;
                    o_wr_pop_en <= 0;
                    state <= IDLE;
                end
            endcase
        end
    end

endmodule