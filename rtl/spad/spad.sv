module spad # (
    parameter int ADDR_WIDTH = 8,
    parameter int SPAD_WIDTH = 64,
    parameter int DATA_WIDTH = 8,
    parameter int SPAD_N = SPAD_WIDTH / DATA_WIDTH
) (
    input logic i_clk, i_nrst, i_write_en, i_read_en,
    input logic [SPAD_WIDTH-1:0] i_data_in,
    input logic [SPAD_N-1:0] i_write_mask,
    input logic [ADDR_WIDTH-1:0] i_write_addr, i_read_addr,
    output logic [SPAD_WIDTH-1:0] o_data_out,
    output logic o_data_out_valid
);
    logic [SPAD_WIDTH-1:0] buffer [(2**ADDR_WIDTH)-1:0];

    // Read data
    always_ff @(posedge i_clk) begin
        if (i_read_en) begin
            o_data_out <= buffer[i_read_addr];
        end else begin
            o_data_out <= 0;
        end
    end

    always_ff @(posedge i_clk) begin
        if (~i_nrst) begin
            o_data_out_valid <= 0;
        end else begin
            if (i_read_en) begin
                o_data_out_valid <= 1;
            end else begin
                o_data_out_valid <= 0;
            end
        end
    end

    // Write data
    always_ff @(posedge i_clk) begin
        if (i_write_en) begin
            // buffer[i_write_addr] <= i_data_in;
            for (int i = 0; i < SPAD_N; i++) begin
                if (i_write_mask[i]) begin
                    buffer[i_write_addr][i*DATA_WIDTH +: DATA_WIDTH] <= i_data_in[i*DATA_WIDTH +: DATA_WIDTH];
                end
            end
        end
    end

endmodule