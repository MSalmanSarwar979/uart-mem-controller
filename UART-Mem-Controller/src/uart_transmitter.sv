module uart_transmitter #(
    parameter CLOCK_FREQ = 100_000_000,
    parameter BAUD_RATE = 115_200)
(
    input clk,
    input reset,

    input [7:0] data_in,
    input data_in_valid,
    output data_in_ready,

    output serial_out
);
    // see diagram in the lab guide
    localparam  SYMBOL_EDGE_TIME    =   CLOCK_FREQ / BAUD_RATE;
    localparam  CLOCK_COUNTER_WIDTH =   $clog2(SYMBOL_EDGE_TIME);

    // tx_shift holds {stop_bit, data[7:0], start_bit} = 10 bits
    wire [9:0] tx_shift_value;
    wire [9:0] tx_shift_next;
    wire tx_shift_load, tx_shift_ce;

    REGISTER_CE #(.N(10)) tx_shift (
        .q(tx_shift_value),
        .d(tx_shift_next),
        .ce(tx_shift_ce),
        .clk(clk)
    );

    // bit counter: counts 0..9 while transmitting
    wire [3:0] bit_counter_value;
    wire [3:0] bit_counter_next;
    wire bit_counter_ce, bit_counter_rst;

    REGISTER_R_CE #(.N(4), .INIT(0)) bit_counter (
        .q(bit_counter_value),
        .d(bit_counter_next),
        .ce(bit_counter_ce),
        .rst(bit_counter_rst),
        .clk(clk)
    );

    // clock counter: counts clock ticks per symbol
    wire [CLOCK_COUNTER_WIDTH-1:0] clock_counter_value;
    wire [CLOCK_COUNTER_WIDTH-1:0] clock_counter_next;
    wire clock_counter_ce, clock_counter_rst;

    REGISTER_R_CE #(.N(CLOCK_COUNTER_WIDTH), .INIT(0)) clock_counter (
        .q(clock_counter_value),
        .d(clock_counter_next),
        .ce(clock_counter_ce),
        .rst(clock_counter_rst),
        .clk(clk)
    );

    // 'busy' goes HIGH when a byte is latched, LOW when transmission completes
    wire busy;
    wire data_in_fire = data_in_valid & data_in_ready;
    wire symbol_edge  = (clock_counter_value == SYMBOL_EDGE_TIME - 1);
    wire done         = (bit_counter_value == 10 - 1) & symbol_edge;

    REGISTER_R_CE #(.N(1), .INIT(0)) busy_reg (
        .q(busy),
        .d(1'b1),
        .ce(data_in_fire),
        .rst(done | reset),
        .clk(clk)
    );

    // Load shift register when a new byte is accepted; shift right each symbol edge
    assign tx_shift_load = data_in_fire;
    assign tx_shift_ce   = tx_shift_load | (busy & symbol_edge);
    assign tx_shift_next = tx_shift_load ? {1'b1, data_in, 1'b0}       // load: stop, data, start
                                         : {1'b1, tx_shift_value[9:1]}; // shift right, fill MSB with 1

    assign bit_counter_next = bit_counter_value + 1;
    assign bit_counter_ce   = busy & symbol_edge;
    assign bit_counter_rst  = done | reset;

    assign clock_counter_next = clock_counter_value + 1;
    assign clock_counter_ce   = busy;
    assign clock_counter_rst  = symbol_edge | done | reset;

    assign serial_out    = busy ? tx_shift_value[0] : 1'b1;
    assign data_in_ready = ~busy;

endmodule
