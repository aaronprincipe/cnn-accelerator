module quant #(
    parameter DATA_WIDTH = 8
) (
    input  logic i_clk, i_nrst, i_en, i_store_reg,
    input  logic        [  DATA_WIDTH-1:0] i_sh,
    input  logic signed [4*DATA_WIDTH-1:0] i_m0,
    input  logic signed [4*DATA_WIDTH-1:0] i_act,
    input  logic signed [4*DATA_WIDTH-1:0] i_bias,
    input  logic signed [  DATA_WIDTH-1:0] i_zero_point, // really output zero point, just named i_zero_point because it's an input to this module
    output logic signed [  DATA_WIDTH-1:0] o_act,
    output logic o_valid
);
    logic        [  DATA_WIDTH-1:0] sh;
    logic signed [4*DATA_WIDTH-1:0] m0;
    //logic signed [4*DATA_WIDTH-1:0] act;
    logic signed [4*DATA_WIDTH-1:0] bias;
    
    always_ff @(posedge i_clk) begin
        if (!i_nrst) begin
            sh  <= 0;
            m0  <= 0;
            bias <= 0;
            //act <= 0;
            o_valid <= 0;
            o_act <= 0;
        end else begin
            if (i_store_reg) begin
                sh <= i_sh;
                m0 <= i_m0;
                bias <= i_bias;
            end
            if (i_en) begin
                //act <= i_act;
                o_valid <= 1;
                o_act <= clamped_act;
            end else begin
                //act <= 0;
                o_valid <= 0;
                o_act <= 0;
            end
        end
    end

    parameter int fixedPointBits = 4*DATA_WIDTH - 1; // 31 for signed 32b multiplier    
    
    logic signed [4*DATA_WIDTH-1:0] biased_act;
    logic signed [8*DATA_WIDTH-1:0] scaled_act;
    logic signed [4*DATA_WIDTH-1:0] shifted_act;
    logic signed [4*DATA_WIDTH-1:0] offset_act;
    logic signed [  DATA_WIDTH-1:0] clamped_act;
    assign biased_act = i_act + bias;
    assign scaled_act = m0 * biased_act;
    assign shifted_act = (scaled_act + (1 << (fixedPointBits + sh - 1)) + (1 << (fixedPointBits - 1))) >>> (fixedPointBits + sh); // double-rounding, as done in tflite.
    // round_offset = {(1 << (sh - 1)), (1 << (fixedPointBits - 1))} 
    assign offset_act = shifted_act + i_zero_point;

    always_comb begin
        if (offset_act < -128) begin
            clamped_act = -128;
        end else if (offset_act > 127) begin
            clamped_act = 127;
        end else begin
            clamped_act = offset_act[DATA_WIDTH-1:0];
        end
    end

endmodule
