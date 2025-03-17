// Multiple Input Single Output (MISO) FIFO
module miso_fifo #(
    parameter int DEPTH = 16,  
    parameter int DATA_WIDTH = 8,
    parameter int DATA_LENGTH = 8,
    parameter int ADDR_WIDTH = $clog2(DEPTH),
    parameter int INDEX = 0
)(
    input logic i_clk, i_nrst, i_clear, i_write_en, i_pop_en, i_r_pointer_reset,
    input logic [1:0] i_p_mode,
    input logic [DATA_LENGTH-1:0][DATA_WIDTH-1:0] i_data,       
    input logic [DATA_LENGTH-1:0] i_valid,
    output logic [DATA_WIDTH-1:0] o_data,
    output logic o_empty, o_full, o_enough_slots, o_pop_valid,
    output logic [ADDR_WIDTH:0] o_slots
);
    localparam _8x8 = 2'b00;
    localparam _4x4 = 2'b01;
    localparam _2x2 = 2'b10;

    logic data_out_valid;
    logic [DATA_WIDTH-1:0] data_out;
    logic [ADDR_WIDTH:0] w_pointer, r_pointer, w_offset;
    logic [DATA_WIDTH-1:0] fifo [DEPTH-1:0];

    logic write_en;
    assign write_en = i_write_en & !o_full;

    // Generate 4x4 data
    logic [DATA_WIDTH-1:0] fb_data, fb_fifo;
    logic last_data_4b;
    assign last_data_4b = (r_pointer == w_pointer - 1);

    // Generate 2x2 data
    logic [DATA_WIDTH-1:0] tb_data;
    logic last_data_2b, llast_data_2b, lllast_data_2b;

    assign last_data_2b = (r_pointer == w_pointer - 1);
    assign llast_data_2b = (r_pointer == w_pointer - 2);
    assign lllast_data_2b = (r_pointer == w_pointer - 3);

    // reset or clear signals
    logic clear;
    assign clear = i_clear || i_r_pointer_reset;

    // Pop enable signals
    logic pop_en;
    assign pop_en = i_pop_en && !o_empty;

    // Write data
    always @ (posedge i_clk or negedge i_nrst) begin
        if (~i_nrst) begin
            w_pointer <= 0;
        end else if (i_clear) begin
            w_pointer <= 0;
        end else if (write_en) begin
            for (int i = 0; i < DATA_LENGTH; i = i + 1) begin
                if (i_valid[i] == 1) begin
                    fifo[w_pointer + i] <= i_data[i];
                end 
            end
            w_pointer <= w_offset + w_pointer;
        end
    end

    always_comb begin
        if (write_en) begin
            w_offset = 0;
            for (int i = 0; i < DATA_LENGTH; i = i + 1) begin
                w_offset = w_offset + i_valid[i];
            end
        end
    end

    // 4-bit pop logic
    always @(*) begin
        if (o_empty) begin
            fb_data = 0;
        end else if (last_data_4b) begin
            fb_data = fifo[r_pointer];
        end else begin
            fb_data = {fifo[r_pointer + 1][3:0], fifo[r_pointer][3:0]};
        end
    end

    // 2-bit pop logic
    always @(*) begin
        if (o_empty) begin
            tb_data = 0;
        end else if (last_data_2b) begin
            tb_data = fifo[r_pointer];
        end else if (llast_data_2b) begin
            tb_data = {fifo[r_pointer + 1][1:0], fifo[r_pointer][1:0]};
        end else if (lllast_data_2b) begin
            tb_data = {fifo[r_pointer + 2][1:0], fifo[r_pointer + 1][1:0], fifo[r_pointer][1:0]};
        end else begin
            tb_data = {fifo[r_pointer + 3][1:0], fifo[r_pointer + 2][1:0], fifo[r_pointer + 1][1:0], fifo[r_pointer][1:0]};
        end
    end

    // Pop data
    always_ff @ (posedge i_clk or negedge i_nrst) begin
        if (~i_nrst) begin
            r_pointer <= 0;
            o_data <= 0;
            o_pop_valid <= 0;
        end else if (clear) begin
            r_pointer <= 0;
            o_data <= 0;
            o_pop_valid <= 0;
        end else if (pop_en) begin
            case (i_p_mode)
                _8x8: begin
                    o_data <= fifo[r_pointer];
                    r_pointer <= r_pointer + 1;
                    o_pop_valid <= 1;
                end
                _4x4: begin
                    o_data <= fb_data;
                    if (last_data_4b) begin
                        r_pointer <= r_pointer + 1;
                    end else begin
                        r_pointer <= r_pointer + 2;
                    end
                    o_pop_valid <= 1;
                end
                _2x2: begin
                    o_data <= tb_data;
                    if (last_data_2b) begin
                        r_pointer <= r_pointer + 1;
                    end else if (llast_data_2b) begin
                        r_pointer <= r_pointer + 2;
                    end else if (lllast_data_2b) begin
                        r_pointer <= r_pointer + 3;
                    end else begin
                        r_pointer <= r_pointer + 4;
                    end
                    o_pop_valid <= 1;
                end
            endcase
        end else begin
            o_data <= 0;
            o_pop_valid <= 0;
        end
    end

    // Status signals
    always_comb begin
        o_full = (w_pointer == DEPTH);
        o_slots = w_pointer;
        o_empty = (w_pointer == r_pointer);
        o_enough_slots = (DEPTH - (w_pointer)) > DATA_LENGTH;
    end
endmodule