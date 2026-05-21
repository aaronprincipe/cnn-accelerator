// Reset Synchronizer - Synchronizes asynchronous reset to clock domain
// Eliminates setup/hold violations on flip-flop inputs
module reset_sync (
    input logic i_clk,
    input logic i_nrst_async,
    output logic o_nrst_sync
);
    logic nrst_sync_r1, nrst_sync_r2;

    // Two-stage synchronizer for metastability protection
    always_ff @(posedge i_clk) begin
        nrst_sync_r1 <= i_nrst_async;
        nrst_sync_r2 <= nrst_sync_r1;
    end

    assign o_nrst_sync = nrst_sync_r2;
endmodule
