// This can either be for row or column
module data_lane #(
    parameter int SPAD_DATA_WIDTH = 64,
    parameter int DATA_WIDTH = 8,
    parameter int ADDR_WIDTH = 8,
    parameter int SPAD_N = SPAD_DATA_WIDTH / DATA_WIDTH,
    parameter int MISO_DEPTH = 32,
    parameter int INDEX = 0
) (
    input logic i_clk, i_nrst, i_reg_clear, i_fifo_clear,

    // Control signals
    input logic i_ac_en, i_miso_pop_en, i_fifo_ptr_reset,

    // Address Reference
    input [ADDR_WIDTH-1:0] i_start_addr, i_end_addr,
    input logic i_addr_write_en,

    // Tile Reader Signals
    input logic [SPAD_DATA_WIDTH-1:0] i_data,
    input logic i_data_valid,
    input logic [ADDR_WIDTH-1:0] i_addr,

    // MISO FIFO related signals
    input logic [1:0] i_p_mode,
    output logic [DATA_WIDTH-1:0] o_data,
    output logic o_miso_empty, o_miso_full, o_route_done, o_idle, o_valid
);
    logic [ADDR_WIDTH-1:0] start_addr, end_addr;
    logic [ADDR_WIDTH-1:0] addr_offset;
    logic [0:SPAD_N-1][ADDR_WIDTH-1:0] spad_addr;
    logic [SPAD_N-1:0] data_hit;

    // MISO related signals
    logic miso_full, miso_empty, miso_enough_slots, route_done;

    logic [SPAD_N-1:0] lower_bit;
    logic [SPAD_N-1:0] f_data_hit, t_data_hit;
    logic [SPAD_DATA_WIDTH-1:0] f_data;

    logic write_en;
    assign write_en = i_data_valid & i_ac_en;

    genvar ii;
    generate
        for (ii=0; ii < SPAD_N; ii++) begin
            assign spad_addr[ii] = i_addr * SPAD_N + ii;
        end
    endgenerate

    // Store reference address
    always_ff @(posedge i_clk or negedge i_nrst) begin
        if (~i_nrst) begin
            start_addr <= 0;
            end_addr <= 0;
        end else begin
            if (i_reg_clear) begin
                start_addr <= 0;
                end_addr <= 0;
            end else if (i_addr_write_en) begin
                start_addr <= i_start_addr;
                end_addr <= i_end_addr;
            end else if (write_en) begin
                start_addr <= start_addr + addr_offset;
            end
        end
    end

    logic [ADDR_WIDTH-1:0] check;
    assign check = i_addr * SPAD_N + SPAD_N - 1;

    // Compare address
    always_ff @(posedge i_clk or negedge i_nrst) begin
        if (~i_nrst) begin
            route_done <= 0;
        end else begin
            if (i_reg_clear) begin
                route_done <= 0;
            end else if (i_ac_en) begin
                route_done <= (start_addr) >= end_addr;
            end
        end
    end
    

    // We need a buffer fifo that will adjust the data to the correct format
    // depending on the data hit
    // BIT SHIFTING DUMB ASS
    // we need to figure out where the lower 1 bit
    always_comb begin
        if (write_en) begin
            for (int i = 0; i < SPAD_N; i = i + 1) begin
                // Its less than the last channel address, but greater than the last saved address
                if ((spad_addr[i] < end_addr) & (spad_addr[i] >= start_addr)) begin
                    data_hit[i] = 1;
                end else begin
                    data_hit[i] = 0;
                end
            end

            lower_bit = 0;
            for (int i = SPAD_N - 1; i >= 0; i--) begin
                if (data_hit[i]) begin
                    lower_bit = i;
                end
            end

            t_data_hit = data_hit >> lower_bit;
            f_data = i_data >> lower_bit * SPAD_N;

            for (int i = 0; i < SPAD_N; i = i + 1) begin
                if (t_data_hit[i] & ((slots + i) < MISO_DEPTH ) & ~miso_full) begin
                    f_data_hit[i] = 1;
                end else begin
                    f_data_hit[i] = 0;
                end
            end
        end else begin
            f_data_hit = 0;
            f_data = 0;
        end
    end

    // For updating the starting address
    always_comb begin
        if (write_en) begin
            addr_offset = 0;
            for (int i = 0; i < SPAD_N; i = i + 1) begin
                addr_offset = addr_offset + f_data_hit[i];
            end
        end
    end

    logic [$clog2(MISO_DEPTH):0] slots;

    miso_fifo #(
        .DEPTH(MISO_DEPTH),
        .DATA_WIDTH(DATA_WIDTH),
        .DATA_LENGTH(SPAD_N),
        .INDEX(INDEX)
    ) miso_fifo (
        .i_clk(i_clk),
        .i_nrst(i_nrst),
        .i_clear(i_fifo_clear),
        .i_write_en(f_data_hit[0] & write_en),
        .i_pop_en(i_miso_pop_en),
        .i_r_pointer_reset(i_fifo_ptr_reset),
        .i_p_mode(i_p_mode),
        .i_data(f_data),
        .i_valid(f_data_hit),
        .o_data(o_data),
        .o_empty(miso_empty),
        .o_full(miso_full),
        .o_pop_valid(o_valid),
        .o_enough_slots(miso_enough_slots),
        .o_slots(slots)
    );

    always_comb begin
        o_miso_empty = miso_empty;
        // Basically, if the FIFO is full or there are not enough slots, then the FIFO is full
        //o_miso_full = miso_full || ~miso_enough_slots;
        o_miso_full = miso_full;
        o_route_done = route_done;
        o_idle = miso_full || route_done;
    end
endmodule