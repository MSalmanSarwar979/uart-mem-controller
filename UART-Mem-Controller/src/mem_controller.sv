module mem_controller #(
  parameter FIFO_WIDTH = 8
) (
  input clk,
  input rst,
  input rx_fifo_empty,
  input tx_fifo_full,
  input [FIFO_WIDTH-1:0] din,

  output rx_fifo_rd_en,
  output tx_fifo_wr_en,
  output [FIFO_WIDTH-1:0] dout,
  output [5:0] state_leds
);

  localparam MEM_WIDTH = 8;
  localparam MEM_DEPTH = 256;
  localparam NUM_BYTES_PER_WORD = MEM_WIDTH/8;
  localparam MEM_ADDR_WIDTH = $clog2(MEM_DEPTH);

  // FSM states
  localparam IDLE           = 3'd0;
  localparam READ_CMD       = 3'd1;  // assert rd_en, wait for cmd byte
  localparam READ_ADDR      = 3'd2;  // assert rd_en, wait for addr byte
  localparam READ_DATA_BYTE = 3'd3;  // write path: assert rd_en, wait for data byte
  localparam WRITE_MEM      = 3'd4;  // write path: pulse mem_we, go to IDLE
  localparam READ_MEM_VAL   = 3'd5;  // read path:  present addr, wait 1 cycle for sync RAM
  localparam ECHO_TO_TX     = 3'd6;  // read path:  write mem_dout to TX FIFO

  // Memory signals (reg so they can be driven from always@(*))
  reg [NUM_BYTES_PER_WORD-1:0] mem_we;
  wire [MEM_ADDR_WIDTH-1:0] mem_addr;
  wire [MEM_WIDTH-1:0]      mem_din;
  wire [MEM_WIDTH-1:0]      mem_dout;

  SYNC_RAM_WBE #(
    .DWIDTH(MEM_WIDTH),
    .AWIDTH(MEM_ADDR_WIDTH)
  ) mem (
    .clk(clk),
    .en(1'b1),
    .wbe(mem_we),
    .addr(mem_addr),
    .d(mem_din),
    .q(mem_dout)
  );

  // State register
  wire [2:0] state;
  wire [2:0] state_next;
  REGISTER_R_CE #(.N(3), .INIT(IDLE)) state_reg (
    .q(state), .d(state_next), .ce(1'b1), .rst(rst), .clk(clk)
  );

  // Stored command byte
  wire [7:0] cmd_reg;
  wire       cmd_ce;
  REGISTER_R_CE #(.N(8), .INIT(0)) cmd_r (
    .q(cmd_reg), .d(din), .ce(cmd_ce), .rst(rst), .clk(clk)
  );

  // Stored address byte
  wire [7:0] addr_reg;
  wire       addr_ce;
  REGISTER_R_CE #(.N(8), .INIT(0)) addr_r (
    .q(addr_reg), .d(din), .ce(addr_ce), .rst(rst), .clk(clk)
  );

  // Stored data byte (write path)
  wire [7:0] data_reg;
  wire       data_ce;
  REGISTER_R_CE #(.N(8), .INIT(0)) data_r (
    .q(data_reg), .d(din), .ce(data_ce), .rst(rst), .clk(clk)
  );

  // Connect mem ports
  assign mem_addr = addr_reg;
  assign mem_din  = data_reg;

  // FSM outputs (combinational)
  reg rx_fifo_rd_en_r;
  reg tx_fifo_wr_en_r;
  reg [7:0] dout_r;
  reg cmd_ce_r, addr_ce_r, data_ce_r;

  assign rx_fifo_rd_en = rx_fifo_rd_en_r;
  assign tx_fifo_wr_en = tx_fifo_wr_en_r;
  assign dout          = dout_r;
  assign cmd_ce        = cmd_ce_r;
  assign addr_ce       = addr_ce_r;
  assign data_ce       = data_ce_r;
  assign state_leds    = {{3{1'b0}}, state};

  // Next-state + output logic
  reg [2:0] state_next_r;
  assign state_next = state_next_r;

  always @(*) begin
    // defaults
    state_next_r    = state;
    rx_fifo_rd_en_r = 1'b0;
    tx_fifo_wr_en_r = 1'b0;
    dout_r          = 8'd0;
    cmd_ce_r        = 1'b0;
    addr_ce_r       = 1'b0;
    data_ce_r       = 1'b0;
    mem_we          = {NUM_BYTES_PER_WORD{1'b0}};

    case (state)

      IDLE: begin
        if (!rx_fifo_empty) begin
          rx_fifo_rd_en_r = 1'b1;
          state_next_r    = READ_CMD;
        end
      end

      // cmd byte is clocking in this cycle (rd_en was asserted last cycle)
      // din is valid now; capture it and move to READ_ADDR
      READ_CMD: begin
        cmd_ce_r     = 1'b1;          // latch din as command
        if (!rx_fifo_empty) begin
          rx_fifo_rd_en_r = 1'b1;     // start reading address byte
          state_next_r    = READ_ADDR;
        end else begin
          state_next_r = READ_CMD;    // stall: wait for FIFO
        end
      end

      // addr byte is clocking in; capture it then branch on command
      READ_ADDR: begin
        addr_ce_r = 1'b1;             // latch din as address
        if (cmd_reg == 8'd49) begin   // WRITE
          if (!rx_fifo_empty) begin
            rx_fifo_rd_en_r = 1'b1;
            state_next_r    = READ_DATA_BYTE;
          end else begin
            state_next_r = READ_ADDR; // stall
          end
        end else begin                // READ (8'd48)
          state_next_r = READ_MEM_VAL;
        end
      end

      // data byte is clocking in; capture it
      READ_DATA_BYTE: begin
        data_ce_r    = 1'b1;
        state_next_r = WRITE_MEM;
      end

      // pulse mem_we to write data_reg into mem[addr_reg]
      WRITE_MEM: begin
        mem_we       = {NUM_BYTES_PER_WORD{1'b1}};
        state_next_r = IDLE;
      end

      // present addr to RAM; mem_dout will be valid next cycle
      READ_MEM_VAL: begin
        state_next_r = ECHO_TO_TX;
      end

      // mem_dout is now valid; write to TX FIFO if not full
      ECHO_TO_TX: begin
        if (!tx_fifo_full) begin
          tx_fifo_wr_en_r = 1'b1;
          dout_r          = mem_dout;
          state_next_r    = IDLE;
        end
        // else stall
      end

      default: state_next_r = IDLE;
    endcase
  end

endmodule
