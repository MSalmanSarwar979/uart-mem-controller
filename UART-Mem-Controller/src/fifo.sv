module fifo #(
    parameter WIDTH = 8,
    parameter DEPTH = 32,
    parameter POINTER_WIDTH = $clog2(DEPTH)
)
(
    // clock and reset
    input  logic clk,
    input  logic rst,
    // write interface
    input  logic [WIDTH-1:0] din,
    input  logic wr_en,
    output logic full,
    // read interface
    output logic [WIDTH-1:0] dout,
    input  logic rd_en,
    output logic empty
);

    // register array
    logic [WIDTH-1:0] mem [0:DEPTH-1];

    // read / write pointers
    logic [POINTER_WIDTH-1:0] r_ptr, w_ptr;

    // disambiguates full vs empty when pointers are equal
    logic last_was_write;

    // write logic
    always_ff @(posedge clk) begin
        if (rst) begin
            w_ptr <= '0;
        end else begin
            if (wr_en && !full) begin
                mem[w_ptr] <= din;
                w_ptr      <= w_ptr + 1'b1;
            end
        end
    end

    // read logic
    always_ff @(posedge clk) begin
        if (rst) begin
            r_ptr <= '0;
            dout  <= '0;
        end else begin
            if (rd_en && !empty) begin
                dout  <= mem[r_ptr];
                r_ptr <= r_ptr + 1'b1;
            end
        end
    end

    // last-operation tracker
    // reset default -> empty (last_was_write = 0)
    always_ff @(posedge clk) begin
        if (rst) begin
            last_was_write <= 1'b0;
        end else begin
            if (wr_en && !full)
                last_was_write <= 1'b1;
            else if (rd_en && !empty)
                last_was_write <= 1'b0;
        end
    end

    // full / empty flags
    assign full  = (w_ptr == r_ptr) &&  last_was_write;
    assign empty = (w_ptr == r_ptr) && !last_was_write;

endmodule : fifo
