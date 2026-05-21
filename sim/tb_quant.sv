// ============================================================
//  tb_quant.sv  –  Testbench for quant.sv
//
//  Timing model of the DUT
//  ─────────────────────────────────────────────────────────
//  i_store_reg=1  → sh / m0 / bias latched on next posedge
//  i_en=1         → act / o_valid latched on next posedge
//  o_act          → combinational from latched act/m0/bias/sh
//                   + live i_zero_point  (NOT registered)
//
//  Run with any IEEE 1800 simulator, e.g.
//    iverilog -g2012 -o sim tb_quant.sv quant.sv && vvp sim
//    vsim -do "run -all" tb_quant
// ============================================================

`timescale 1ns/1ps

module tb_quant;

    // ─── Parameters ──────────────────────────────────────────
    localparam int  DW       = 8;
    localparam int  CLK_HALF = 20;   // 40 ns period
    localparam int  FPB      = 4*DW - 1;  // 31

    // ─── DUT ports ───────────────────────────────────────────
    logic                        clk, nrst, en, store_reg;
    logic        [  DW-1:0]      i_sh;
    logic signed [4*DW-1:0]     i_m0, i_act, i_bias;
    logic signed [  DW-1:0]     i_zp;
    logic signed [  DW-1:0]     o_act;
    logic                        o_valid;

    // ─── DUT instantiation ───────────────────────────────────
    quant #(.DATA_WIDTH(DW)) dut (
        .i_clk       (clk),
        .i_nrst      (nrst),
        .i_en        (en),
        .i_store_reg (store_reg),
        .i_sh        (i_sh),
        .i_m0        (i_m0),
        .i_act       (i_act),
        .i_bias      (i_bias),
        .i_zero_point(i_zp),
        .o_act       (o_act),
        .o_valid     (o_valid)
    );

    // ─── Clock ───────────────────────────────────────────────
    initial clk = 0;
    always  #CLK_HALF clk = ~clk;

    // ─── Scorecard ───────────────────────────────────────────
    int pass_cnt = 0;
    int fail_cnt = 0;

    // Shadow registers – track what the DUT has stored
    logic        [  DW-1:0] s_sh;
    logic signed [4*DW-1:0] s_m0, s_bias;

    // ─────────────────────────────────────────────────────────
    //  Reference model
    //  Mirrors the combinational datapath exactly, including
    //  the double-rounding used in TFLite:
    //    round_offset = (1 << (FPB+sh-1)) + (1 << (FPB-1))
    // ─────────────────────────────────────────────────────────
    function automatic logic signed [DW-1:0] ref_quant(
        input logic signed [4*DW-1:0] f_act,
        input logic signed [4*DW-1:0] f_m0,
        input logic signed [4*DW-1:0] f_bias,
        input logic        [  DW-1:0] f_sh,
        input logic signed [  DW-1:0] f_zp
    );
        logic signed [4*DW-1:0]  act_biased;
        logic signed [8*DW-1:0]  scaled;
        logic signed [8*DW-1:0]  round_offset;
        logic signed [4*DW-1:0]  shifted;
        logic signed [4*DW-1:0]  q;

        act_biased   = f_act + f_bias;
        scaled       = 64'(signed'(f_m0)) * 64'(signed'(act_biased));
        round_offset = (64'h1 << (FPB + f_sh - 1)) + (64'h1 << (FPB - 1));
        shifted      = (scaled + round_offset) >>> (FPB + f_sh);
        q            = shifted + 32'(signed'(f_zp));

        if      (q < -128) return -128;
        else if (q >  127) return  127;
        else               return q[DW-1:0];
    endfunction

    // ─────────────────────────────────────────────────────────
    //  Task: latch new quantisation parameters
    // ─────────────────────────────────────────────────────────
    task automatic store_params(
        input logic        [  DW-1:0] t_sh,
        input logic signed [4*DW-1:0] t_m0,
        input logic signed [4*DW-1:0] t_bias
    );
        @(negedge clk);
        store_reg = 1'b1;
        i_sh  = t_sh;
        i_m0  = t_m0;
        i_bias = t_bias;
        @(posedge clk); #1;
        store_reg = 1'b0;
        // Mirror into shadow registers
        s_sh   = t_sh;
        s_m0   = t_m0;
        s_bias = t_bias;
    endtask

    // ─────────────────────────────────────────────────────────
    //  Task: apply one activation and check against reference
    // ─────────────────────────────────────────────────────────
    task automatic run_test(
        input logic signed [4*DW-1:0] t_act,
        input logic signed [  DW-1:0] t_zp,
        input string                  name
    );
        logic signed [DW-1:0] exp;

        @(negedge clk);
        en    = 1'b1;
        i_act = t_act;
        i_zp  = t_zp;          // i_zero_point is live (not registered)

        @(posedge clk); #3;    // DUT captures act, asserts o_valid
        en = 1'b0;

        exp = ref_quant(t_act, s_m0, s_bias, s_sh, t_zp);

        // Check o_valid
        if (o_valid !== 1'b1) begin
            $display("  [FAIL] %-44s | o_valid=0 (expected 1)", name);
            fail_cnt++;
            return;
        end
        // Check o_act
        if (o_act !== exp) begin
            $display("  [FAIL] %-44s | got=%4d  exp=%4d  (act=%0d m0=0x%08h bias=%0d sh=%0d zp=%0d)",
                      name, o_act, exp, t_act, s_m0, s_bias, s_sh, t_zp);
            fail_cnt++;
        end else begin
            $display("  [PASS] %-44s | o_act=%4d", name, o_act);
            pass_cnt++;
        end
    endtask

    // ─────────────────────────────────────────────────────────
    //  Task: assert en=0 and verify o_valid deasserts
    // ─────────────────────────────────────────────────────────
    task automatic check_idle(input string name);
        @(negedge clk);
        en = 1'b0;
        @(posedge clk); #3;
        if (o_valid !== 1'b0) begin
            $display("  [FAIL] %-44s | o_valid=%0b (expected 0)", name, o_valid);
            fail_cnt++;
        end else begin
            $display("  [PASS] %-44s | o_valid=0 ✓", name);
            pass_cnt++;
        end
    endtask

    // ─────────────────────────────────────────────────────────
    //  Task: verify o_valid=0 and act=0 after reset
    // ─────────────────────────────────────────────────────────
    task automatic check_reset(input string name);
        @(negedge clk); nrst = 1'b0;
        @(posedge clk); #3;
        if (o_valid !== 1'b0) begin
            $display("  [FAIL] %-44s | o_valid=%0b after reset", name, o_valid);
            fail_cnt++;
        end else begin
            $display("  [PASS] %-44s | o_valid=0 after reset ✓", name);
            pass_cnt++;
        end
        @(negedge clk); nrst = 1'b1;
        @(posedge clk); #3;
    endtask

    // ─────────────────────────────────────────────────────────
    //  Main test body
    // ─────────────────────────────────────────────────────────
    initial begin
        $dumpfile("tb_quant.vcd");
        $dumpvars(0, tb_quant);

        // ── Initialise ───────────────────────────────────────
        {nrst, en, store_reg}  = '0;
        {i_sh, i_m0, i_act, i_bias, i_zp} = '0;
        {s_sh, s_m0, s_bias}   = '0;

        // ── Reset pulse ──────────────────────────────────────
        repeat(3) @(posedge clk);
        nrst = 1'b1;
        @(posedge clk);

        $display("\n════════════════════════════════════════════════════════");
        $display("  quant.sv  testbench  (DATA_WIDTH=%0d)", DW);
        $display("════════════════════════════════════════════════════════\n");


        // ══════════════════════════════════════════════════════
        //  GROUP 1 – Basic arithmetic
        //  m0 = 0x4000_0000 (= 2^30, ~0.5 in Q31)
        // ══════════════════════════════════════════════════════
        $display("── Group 1: Basic arithmetic ─────────────────────────");
        store_params(.t_sh(0), .t_m0(32'h4000_0000), .t_bias(0));
        run_test(.t_act(0),  .t_zp(0), .name("act=0,  no bias, no zp"));
        run_test(.t_act(10), .t_zp(0), .name("act=10, no bias, no zp"));
        run_test(.t_act(-10),.t_zp(0), .name("act=-10 (negative activation)"));

        // ══════════════════════════════════════════════════════
        //  GROUP 2 – Bias
        // ══════════════════════════════════════════════════════
        $display("\n── Group 2: Bias ─────────────────────────────────────");
        store_params(.t_sh(0), .t_m0(32'h4000_0000), .t_bias(20));
        run_test(.t_act(10), .t_zp(0), .name("act=10, bias=+20"));

        store_params(.t_sh(0), .t_m0(32'h4000_0000), .t_bias(-10));
        run_test(.t_act(10), .t_zp(0), .name("act=10, bias=-10"));

        store_params(.t_sh(0), .t_m0(32'h4000_0000), .t_bias(-100));
        run_test(.t_act(10), .t_zp(0), .name("act=10, bias=-100 (large neg bias)"));

        // ══════════════════════════════════════════════════════
        //  GROUP 3 – Zero-point offset
        // ══════════════════════════════════════════════════════
        $display("\n── Group 3: Zero-point ───────────────────────────────");
        store_params(.t_sh(0), .t_m0(32'h4000_0000), .t_bias(0));
        run_test(.t_act(10), .t_zp(5),    .name("zp=+5"));
        run_test(.t_act(10), .t_zp(-5),   .name("zp=-5"));
        run_test(.t_act(10), .t_zp(127),  .name("zp=127  (max positive zp)"));
        run_test(.t_act(10), .t_zp(-128), .name("zp=-128 (min zp)"));

        // ══════════════════════════════════════════════════════
        //  GROUP 4 – Right-shift (sh)
        // ══════════════════════════════════════════════════════
        $display("\n── Group 4: Right-shift (sh) ─────────────────────────");
        store_params(.t_sh(1), .t_m0(32'h4000_0000), .t_bias(0));
        run_test(.t_act(100), .t_zp(0), .name("sh=1, act=100"));

        store_params(.t_sh(2), .t_m0(32'h4000_0000), .t_bias(0));
        run_test(.t_act(100), .t_zp(0), .name("sh=2, act=100"));

        store_params(.t_sh(4), .t_m0(32'h4000_0000), .t_bias(0));
        run_test(.t_act(200), .t_zp(0), .name("sh=4, act=200"));

        store_params(.t_sh(8), .t_m0(32'h4000_0000), .t_bias(0));
        run_test(.t_act(32'h0000_7FFF), .t_zp(0), .name("sh=8, act=0x7FFF"));

        // ══════════════════════════════════════════════════════
        //  GROUP 5 – Near-unity multiplier  (m0 ≈ 1.0 in Q31)
        // ══════════════════════════════════════════════════════
        $display("\n── Group 5: Near-unity multiplier ────────────────────");
        store_params(.t_sh(0), .t_m0(32'h7FFF_FFFF), .t_bias(0));
        run_test(.t_act(50),  .t_zp(0), .name("m0~1.0, act=50"));
        run_test(.t_act(-50), .t_zp(0), .name("m0~1.0, act=-50"));

        // ══════════════════════════════════════════════════════
        //  GROUP 6 – Output saturation / clamping
        // ══════════════════════════════════════════════════════
        $display("\n── Group 6: Saturation ───────────────────────────────");
        store_params(.t_sh(0), .t_m0(32'h7FFF_FFFF), .t_bias(0));
        run_test(.t_act(32'h0000_0200), .t_zp(100),  .name("Saturate HIGH  → +127"));
        run_test(.t_act(-32'sh200),     .t_zp(-100), .name("Saturate LOW   → -128"));

        // Just over boundary
        store_params(.t_sh(0), .t_m0(32'h4000_0000), .t_bias(0));
        run_test(.t_act(32'h0000_00FF), .t_zp(120),  .name("Near +127 boundary"));
        run_test(.t_act(-32'sh00FF),    .t_zp(-120), .name("Near -128 boundary"));

        // ══════════════════════════════════════════════════════
        //  GROUP 7 – Rounding edge cases
        // ══════════════════════════════════════════════════════
        $display("\n── Group 7: Rounding edge cases ──────────────────────");
        store_params(.t_sh(0), .t_m0(32'h4000_0000), .t_bias(1));
        run_test(.t_act(1), .t_zp(0), .name("Rounding: act=1, bias=1"));

        store_params(.t_sh(1), .t_m0(32'h7FFF_FFFF), .t_bias(0));
        run_test(.t_act(1),  .t_zp(0), .name("Rounding: sh=1, m0~1, act=1"));
        run_test(.t_act(-1), .t_zp(0), .name("Rounding: sh=1, m0~1, act=-1"));

        // ══════════════════════════════════════════════════════
        //  GROUP 8 – Control-path / timing
        // ══════════════════════════════════════════════════════
        $display("\n── Group 8: Control path ─────────────────────────────");

        // i_en=0 → o_valid deasserts, internal act=0
        check_idle("en=0 → o_valid deasserts");

        // Reset during active computation
        @(negedge clk); en = 1'b1; i_act = 99;
        @(posedge clk); #1; en = 1'b0;
        check_reset("Reset clears o_valid");

        // store_reg while en is low – registers should update
        store_params(.t_sh(0), .t_m0(32'h4000_0000), .t_bias(5));
        run_test(.t_act(20), .t_zp(0), .name("Post-reset store then en"));

        // Consecutive store_reg then immediate en in adjacent cycles
        $display("\n  -- Sequential store→enable pipelining --");
        begin
            logic signed [DW-1:0] exp_a, exp_b;
            @(negedge clk);
            // Cycle A: assert store_reg
            store_reg = 1'b1;
            i_sh = 0; i_m0 = 32'h4000_0000; i_bias = 0;
            @(posedge clk); #1;
            store_reg = 1'b0;
            s_sh = 0; s_m0 = 32'h4000_0000; s_bias = 0;
            // Cycle B: assert en immediately after store
            @(negedge clk);
            en = 1'b1; i_act = 40; i_zp = 0;
            @(posedge clk); #3;
            en = 1'b0;
            exp_a = ref_quant(40, 32'h4000_0000, 0, 0, 0);
            if (o_act !== exp_a || o_valid !== 1'b1)
                $display("  [FAIL] Store→en back-to-back | got=%0d exp=%0d valid=%0b",
                          o_act, exp_a, o_valid);
            else begin
                $display("  [PASS] %-44s | o_act=%4d", "Store→en back-to-back", o_act);
                pass_cnt++;
            end
        end

        // Back-to-back activations (en stays high; act changes every cycle)
        $display("\n  -- Back-to-back activations (en held high) --");
        store_params(.t_sh(0), .t_m0(32'h4000_0000), .t_bias(0));
        begin
            logic signed [4*DW-1:0] acts [0:3] = '{10, -5, 0, 50};
            @(negedge clk); en = 1'b1; i_zp = 0;
            foreach (acts[k]) begin
                i_act = acts[k];
                @(posedge clk); #3;
                begin
                    automatic logic signed [DW-1:0] exp_v = ref_quant(acts[k], s_m0, s_bias, s_sh, 0);
                    if (o_act !== exp_v || o_valid !== 1'b1)
                        $display("  [FAIL] Back-to-back act=%4d | got=%4d exp=%4d valid=%0b",
                                  acts[k], o_act, exp_v, o_valid);
                    else begin
                        $display("  [PASS] %-44s | o_act=%4d",
                                  $sformatf("Back-to-back act=%0d", acts[k]), o_act);
                        pass_cnt++;
                    end
                end
            end
            @(negedge clk); en = 1'b0;
        end

        // ══════════════════════════════════════════════════════
        //  SUMMARY
        // ══════════════════════════════════════════════════════
        $display("");
        $display("════════════════════════════════════════════════════════");
        $display("  PASSED: %0d   FAILED: %0d   TOTAL: %0d",
                  pass_cnt, fail_cnt, pass_cnt + fail_cnt);
        $display("════════════════════════════════════════════════════════");
        if (fail_cnt == 0)
            $display("  ✓  ALL TESTS PASSED");
        else
            $display("  ✗  FAILURES DETECTED – see log above");
        $display("");
        $finish;
    end

    // ─── Watchdog ────────────────────────────────────────────
    initial begin
        #500_000;
        $display("[WATCHDOG] Simulation timed out after 500 us");
        $finish;
    end

endmodule