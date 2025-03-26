module pe #(
    parameter int DATA_WIDTH = 8
) (
    input logic i_clk, i_nrst, 
    input logic [1:0] i_mode,

    // Data Inputs 
    input logic [DATA_WIDTH-1:0] i_ifmap, i_weight,
    input logic [DATA_WIDTH*2-1:0] i_psum,

    // Control Inputs
    input logic i_reg_clear, // Clear register
    input logic i_pe_en,  // Enable PE to perform multiply-and-accumulate

    // Enable one cycle after last computation to 
    // output partial sum to the next PE
    // Performs a shift operation to the left
    input logic i_psum_out_en, i_scan_en,

    // Data Outputs
    output logic [DATA_WIDTH-1:0] o_ifmap, o_weight,
    output logic [DATA_WIDTH*2-1:0] o_ofmap
);
    logic [DATA_WIDTH-1:0] reg_ifmap, reg_weight;
    logic [DATA_WIDTH*2-1:0] reg_psum, o_multiplier, reg_psum_out;

    always_ff @(posedge i_clk or negedge i_nrst) begin
        if (~i_nrst) begin
            reg_ifmap <= 0;
            reg_weight <= 0;
        end else begin
            if (i_reg_clear) begin
                reg_ifmap <= 0;
                reg_weight <= 0;
            end else if (i_pe_en) begin
                reg_ifmap <= i_ifmap;
                reg_weight <= i_weight;
            end
        end
    end

    mFU mfu (
        .clk(i_clk),
        .nrst(i_nrst),
        .a(i_ifmap),
        .b(i_weight),
        .mode(i_mode),
        .p(o_multiplier)
    );

    logic mac_en;
    assign mac_en = i_pe_en;
    // Multiplier and Accumulator
    always_ff @(posedge i_clk or negedge i_nrst) begin
        if(~i_nrst) begin
            reg_psum <= 0;
        end else begin
            if (i_reg_clear) begin
                reg_psum <= 0;
            end else if(mac_en) begin
                reg_psum <= reg_psum + o_multiplier;
            end 
        end
    end

    // Output partial sum to the next PE
    always_ff @(posedge i_clk or negedge i_nrst) begin
        if(~i_nrst) begin
            reg_psum_out <= 0;
        end else begin
            if (i_reg_clear) begin
                reg_psum_out <= 0;
            end else if (i_scan_en) begin
                reg_psum_out <= i_psum;
            end else if (i_psum_out_en) begin
                reg_psum_out <= reg_psum;
            end
        end
    end

    always_comb begin
        o_ifmap = reg_ifmap;
        o_weight = reg_weight;
        o_ofmap = reg_psum_out;
    end

endmodule