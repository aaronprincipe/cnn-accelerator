// Write once and peek more than once
module mpp_fifo #(
    parameter int DEPTH = 9,  
    parameter int DATA_WIDTH = 8,
    parameter int DATA_LENGTH = 9,
    parameter int PEEK_WIDTH = 8,
    localparam ADDR_WIDTH = $clog2(DEPTH)
)(
    input logic i_clk, i_nrst, 
    input logic i_clear, i_write_en,
    input logic [0:DATA_LENGTH-1][DATA_WIDTH-1:0] i_data_in,

    // Pop related signals
    input logic i_pop_en,
    input logic [PEEK_WIDTH-1:0] i_data_hit,
  
    // Peek related signals
    // input logic i_peek_en,
    output logic [PEEK_WIDTH-1:0][DATA_WIDTH-1:0] o_peek_data,
    output logic [PEEK_WIDTH-1:0] o_peek_valid,
    output logic o_empty, o_full
);
    logic [ADDR_WIDTH-1:0] w_pointer, r_pointer, pop_offset;
    logic [DATA_WIDTH-1:0] fifo [DEPTH-1:0];
    logic write_done;

    // Write data
    always_ff @ (posedge i_clk) begin
        if (~i_nrst) begin
            w_pointer <= 0;
        end else if (i_clear) begin
            w_pointer <= 0;
        end else if (i_write_en & !o_full & !write_done) begin
            for (int i = 0; i < DATA_LENGTH; i = i + 1) begin
                fifo[w_pointer + i] <= i_data_in[i];
            end

            // Assume all the write data is valid
            w_pointer <= w_pointer + DATA_LENGTH;
        end
    end

    // Pop data
    always_comb begin
        pop_offset = 0;
        if (i_pop_en & !o_empty) begin
            for (int i = 0; i < PEEK_WIDTH; i++) begin
                if (i_data_hit[i]) begin
                    pop_offset = i;
                end
            end
        end
    end

    always_ff @ (posedge i_clk) begin
        if (~i_nrst) begin
            write_done <= 0;
        end else if (i_clear) begin
            write_done <= 0;
        end else if (i_write_en) begin
            write_done <= 1;
        end
    end

    always_ff @ (posedge i_clk) begin
        if (~i_nrst) begin
            r_pointer <= 0;
        end else if (i_clear) begin
            r_pointer <= 0;
        end else if (i_pop_en & !o_empty & (w_pointer-r_pointer > pop_offset)) begin
            r_pointer <= r_pointer + pop_offset + 1;
        end
    end

    // Peek data
    always_comb begin
        for (int i = 0; i < PEEK_WIDTH; i++) begin
            o_peek_data[i] = {DATA_WIDTH{1'b0}};
            o_peek_valid[i] = 0;
        end
        
        if (!o_empty) begin
            for (int i = 0; i < PEEK_WIDTH; i++) begin
                if (r_pointer + i < w_pointer) begin
                    o_peek_data[i] = fifo[r_pointer + i];
                    o_peek_valid[i] = 1;
                end
            end
        end
    end
    
    // Status signals
    always_comb begin
        o_full = (w_pointer == DEPTH - 1);
        o_empty = (w_pointer == r_pointer);
    end
endmodule
