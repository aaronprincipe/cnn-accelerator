module quant #(
    parameter DATA_WIDTH = 8
) (
    input  logic i_clk, i_nrst, i_en, i_store_reg,
    input  logic [  DATA_WIDTH-1:0] i_sh,
    input  logic [2*DATA_WIDTH-1:0] i_m0,
    input  logic [2*DATA_WIDTH-1:0] i_act,
    output logic [  DATA_WIDTH-1:0] o_act,
    output logic o_valid
);
    logic [  DATA_WIDTH-1:0] sh;
    logic [2*DATA_WIDTH-1:0] m0;
    logic [2*DATA_WIDTH-1:0] act;
    logic [4*DATA_WIDTH-1:0] p, q;

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
    assign q = p >> (2*DATA_WIDTH + sh);
    assign o_act = (q > {DATA_WIDTH{1'b1}})? {DATA_WIDTH{1'b1}} : q[DATA_WIDTH-1:0];

endmodule
