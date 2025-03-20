module d_data_selector #(
    parameter int SPAD_DATA_WIDTH = 64,
    parameter int DATA_WIDTH = 8,
    parameter int ADDR_WIDTH = 8,
    parameter int SPAD_N = SPAD_DATA_WIDTH / DATA_WIDTH,
    parameter int MPP_DEPTH = 9
) (
    input logic i_clk,
    input logic i_nrst,
    input logic i_reg_clear,
    input logic i_en,

    // Controller signals
    // Write to MPP FIFO
    input [0:MPP_DEPTH-1][ADDR_WIDTH-1:0] i_sw_addr,
    input logic i_addr_write_en,

    // Spad signals
    input logic [SPAD_DATA_WIDTH-1:0] i_spad_data,
    input logic [0:SPAD_N-1][ADDR_WIDTH-1:0] i_spad_addr,
    input logic i_data_valid,

    // Data selector signals
    // Write to MISO FIFO
    output logic [SPAD_N-1:0] o_data_hit,
    output logic [SPAD_DATA_WIDTH-1:0] o_data,
    output logic o_route_done
);
    logic [0:SPAD_N-1][DATA_WIDTH-1:0] spad_data;
    logic [0:SPAD_N-1][ADDR_WIDTH-1:0] spad_addr;
    logic [SPAD_N-1:0][ADDR_WIDTH-1:0] peek_addr;
    logic [SPAD_N-1:0] peek_valid;

    genvar ii;
    generate
        for (ii=0; ii < SPAD_N; ii++) begin
            assign spad_data[ii] = i_spad_data[ii*DATA_WIDTH+:DATA_WIDTH];
        end
    endgenerate

    assign spad_addr = i_spad_addr;

    logic [SPAD_N-1:0] addr_hit [SPAD_N-1:0];
    logic [SPAD_N-1:0] f_addr_hit;
    logic [SPAD_N-1:0][DATA_WIDTH-1:0] data_hit, f_data_hit;

    logic mpp_pop_en;
    assign mpp_pop_en = f_addr_hit[0];

    mpp_fifo #(
        .DEPTH(MPP_DEPTH),
        .DATA_WIDTH(ADDR_WIDTH),
        .DATA_LENGTH(MPP_DEPTH),
        .PEEK_WIDTH(SPAD_N)
    ) mpp_fifo (
        .i_clk(i_clk),
        .i_nrst(i_nrst),
        .i_clear(i_reg_clear),
        .i_write_en(i_addr_write_en),
        .i_data_in(i_sw_addr),
        .i_pop_en(mpp_pop_en),
        .i_data_hit(f_addr_hit),
        .o_peek_data(peek_addr),
        .o_peek_valid(peek_valid),
        .o_empty(o_route_done),
        .o_full()
    );

    // Address comparator
    always_comb begin
        if (i_en & i_data_valid) begin
            for (int i = 0; i < SPAD_N; i++) begin
                for (int j = 0; j < SPAD_N; j++) begin
                    if ((spad_addr[i] == peek_addr[j]) & peek_valid[j]) begin
                        addr_hit[j][i] = 1;
                        data_hit[j] = spad_data[i];
                    end else begin
                        addr_hit[j][i] = 0;
                    end
                end
            end
        end else begin
            for (int i = 0; i < SPAD_N; i++) begin
                for (int j = 0; j < SPAD_N; j++) begin
                    addr_hit[j][i] = 0;
                end
            end

            for (int i = 0; i < SPAD_N; i++) begin
                data_hit[i] = 0;
            end
        end

        for (int j = 0; j < SPAD_N; j++) begin
            f_addr_hit[j] = | addr_hit[j];
        end

        for (int i = 0; i < SPAD_N; i++) begin
            if(f_addr_hit[i]) begin
                f_data_hit[i] = data_hit[i];
            end else begin
                f_data_hit[i] = 0;
            end
            
        end
    end
    
    always_comb begin
        o_data_hit = f_addr_hit;
        o_data = f_data_hit; 
    end
endmodule