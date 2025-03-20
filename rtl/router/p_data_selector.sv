module p_data_selector #(
    parameter int SPAD_DATA_WIDTH = 64,
    parameter int DATA_WIDTH = 8,
    parameter int ADDR_WIDTH = 8,
    parameter int SPAD_N = SPAD_DATA_WIDTH / DATA_WIDTH,
    parameter int MISO_DEPTH = 9
) (
    input logic i_clk,
    input logic i_nrst,
    input logic i_reg_clear,
    input logic i_en,

    // Controller signals
    input [ADDR_WIDTH-1:0] i_start_addr,
    input [ADDR_WIDTH-1:0] i_end_addr,
    input logic i_addr_write_en,

    // Spad signals
    input logic [SPAD_DATA_WIDTH-1:0] i_spad_data,
    input logic [0:SPAD_N-1][ADDR_WIDTH-1:0] i_spad_addr,
    input logic i_data_valid,

    // Data selector signals
    // Write to MISO FIFO
    output logic [SPAD_N-1:0] o_data_hit,
    output logic [SPAD_DATA_WIDTH-1:0] o_data,
    output logic o_route_done,

    // MISO FIFO related signals
    input logic [$clog2(MISO_DEPTH):0] i_miso_slots,
    input logic i_miso_full
);
    logic [ADDR_WIDTH-1:0] start_addr, end_addr;
    logic [ADDR_WIDTH-1:0] addr_offset;
    logic [0:SPAD_N-1][ADDR_WIDTH-1:0] spad_addr;
    logic [SPAD_N-1:0] data_hit;

    logic [SPAD_N-1:0] lower_bit;
    logic [SPAD_N-1:0] f_data_hit, t_data_hit;
    logic [SPAD_DATA_WIDTH-1:0] f_data;
    logic [$clog2(MISO_DEPTH):0] slots;
    logic write_en, route_done;

    assign slots = i_miso_slots;
    assign spad_addr = i_spad_addr;
    assign write_en = i_data_valid & i_en;

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
    assign check = i_spad_addr * SPAD_N + SPAD_N - 1;

    // Check if done
    always_ff @(posedge i_clk or negedge i_nrst) begin
        if (~i_nrst) begin
            route_done <= 0;
        end else begin
            if (i_reg_clear) begin
                route_done <= 0;
            end else if (i_en) begin
                route_done <= (start_addr) >= end_addr;
            end
        end
    end

    // Address comparison and bit shifting
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
            f_data = i_spad_data >> lower_bit * SPAD_N;

            for (int i = 0; i < SPAD_N; i = i + 1) begin
                if (t_data_hit[i] & ((slots + i) < MISO_DEPTH ) & ~i_miso_full) begin
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

    always_comb begin
        o_data_hit = f_data_hit;
        o_data = f_data;
        o_route_done = route_done;
    end
endmodule