module tile_reader #(
    parameter int ADDR_WIDTH = 8,
    parameter int DATA_WIDTH = 64
) (
    input logic i_clk,
    input logic i_nrst, 
    input logic i_en,
    input logic i_reg_clear,
    input logic i_stall,

    // Address Reference
    input logic [ADDR_WIDTH-1:0] i_start_addr,
    input logic [ADDR_WIDTH-1:0] i_addr_end,  
    
    // SPAD signals
    input logic [DATA_WIDTH-1:0] i_data_in,
    input logic i_data_in_valid,
    output logic o_spad_read_en,
    output logic o_spad_read_done,
    // output logic o_valid_addr,
    output logic [ADDR_WIDTH-1:0] o_spad_read_addr,

    // Router signal outputs
    output logic [ADDR_WIDTH-1:0] o_addr,
    output logic [DATA_WIDTH-1:0] o_data,
    output logic o_data_valid
);
    logic [ADDR_WIDTH-1:0] reg_counter, reg_read_addr, reg_prev_read_addr;

    always_ff @(posedge i_clk or negedge i_nrst) begin
        if (~i_nrst) begin
            reg_counter <= 0;
            reg_read_addr <= 0;
            o_spad_read_done <= 0;
            o_spad_read_en <= 0;
        end else begin
            if (i_reg_clear) begin
                reg_counter <= 0;
                reg_read_addr <= 0;
                o_spad_read_done <= 0;
                o_spad_read_en <= 0;
            end else if (i_en & ~o_spad_read_done) begin
                if (reg_read_addr < i_addr_end) begin
                    o_spad_read_en <= 1;
                    reg_read_addr <= i_start_addr + reg_counter;
                    reg_counter <= reg_counter + 1;
                end else begin
                    o_spad_read_en <= 0;
                    reg_counter <= 0;
                    reg_read_addr <= 0;
                    o_spad_read_done <= 1;
                end
            end
        end
    end

    always_ff @(posedge i_clk or negedge i_nrst) begin
        if (~i_nrst) begin
            reg_prev_read_addr <= 0;
        end else begin
            if (i_reg_clear) begin
                reg_prev_read_addr <= 0;
            end else if (i_en & ~o_spad_read_done) begin
                if (reg_read_addr < i_addr_end + 1) begin
                    reg_prev_read_addr <= reg_read_addr;
                end
            end
        end
    end

    always_comb begin
        o_data = i_data_in;
        o_data_valid = i_data_in_valid;
        o_spad_read_addr = reg_read_addr;
        o_addr = reg_prev_read_addr;
    end
endmodule