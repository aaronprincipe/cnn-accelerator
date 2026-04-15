module quant #(
    parameter DATA_WIDTH = 8
) (
    input  logic i_clk, i_nrst, i_en, i_store_reg,
    input  logic [  DATA_WIDTH-1:0] i_sh,
    input  logic [2*DATA_WIDTH-1:0] i_m0,
    input  logic signed [4*DATA_WIDTH-1:0] i_act,
    input  logic signed [  DATA_WIDTH-1:0] i_zero_point,
    output logic signed [  DATA_WIDTH-1:0] o_act,
    output logic o_valid
);
    logic [  DATA_WIDTH-1:0] sh;
    logic [2*DATA_WIDTH-1:0] m0;
    logic signed [4*DATA_WIDTH-1:0] act;
    logic signed [4*DATA_WIDTH-1:0] p, q;

    always_ff @(posedge i_clk) begin
        if (!i_nrst) begin
            sh  <= 0;
            m0  <= 0;
            act <= 0;
            o_valid <= 0;
        end else begin
            if (i_store_reg) begin
                sh <= i_sh;
                m0 <= i_m0;
            end
            if (i_en) begin
                act <= i_act;
                o_valid <= 1;
            end else begin
                act <= 0;
                o_valid <= 0;
            end
        end
    end

    assign p = m0 * act;
    assign q = (i_zero_point) + (p >>> (2*DATA_WIDTH + sh));

    always_comb begin
        if (q < -128) begin
            o_act = -128;
        end else if (q > 127) begin
            o_act = 127;
        end else begin
            o_act = q[DATA_WIDTH-1:0];
        end
    end

endmodule
