`default_nettype none

// -----------------------------------------------------------------------------
// SPI  -  top level: sequencer + SPI_Master + SPI_Slave
//
// It endlessly repeats this test, with CS held low for each 3-byte frame:
//
//   Frame 0 (WRITE):  CS_N low | 0x02 | ADDR | wr_data | CS_N high
//   Frame 1 (READ) :  CS_N low | 0x0B | ADDR | 0x00    | CS_N high
//                                                ^ slave answers on MISO here
//
// Pins for the logic analyzer:  cs_n, sck, mosi, miso_mon
// -----------------------------------------------------------------------------
module SPI #(
    parameter CLK_HZ      = 50_000_000,
    parameter SPI_HZ      = 1_000_000,
    parameter LOOP_GAP_MS = 100,          // pause between test loops
    parameter [7:0] TEST_ADDR = 8'h05     // address used for write / read-back
)(
    input  wire       clk,

    // SPI bus
    output wire       sck,
    output wire       mosi,
    output reg        cs_n,
    output wire       miso_mon,           // MISO as seen by the master (for analyzer)

    // Status
    output wire [7:0] led,                // last byte read back from the slave
    output reg        led_ok              // 1 = read-back matched what was written
);

    // Same values as in SPI_Slave
    localparam [7:0] CMD_READ  = 8'h0B;
    localparam [7:0] CMD_WRITE = 8'h02;

    // Small timing guards around CS (in system clocks)
    localparam CS_SETUP_CLKS = 4;                               // CS low  -> first SCK
    localparam CS_HOLD_CLKS  = 4;                               // last SCK -> CS high
    localparam FRAME_GAP_CLKS = 32;                             // CS high between frames
    localparam LOOP_GAP_CLKS = (CLK_HZ / 1000) * LOOP_GAP_MS;

    // ---------------------------------------------------------------------
    // Power-on reset (no reset pin needed)
    // ---------------------------------------------------------------------
    reg [3:0] por_cnt = 4'd0;
    wire rst = ~(&por_cnt);
    always @(posedge clk)
        if (!(&por_cnt)) por_cnt <= por_cnt + 1'b1;

    // ---------------------------------------------------------------------
    // SPI Master
    // ---------------------------------------------------------------------
    reg        start_spi;
    reg  [7:0] data_to_send;
    wire [7:0] spi_data_out;
    wire       spi_busy;
    wire       spi_done;
    wire       miso_w;                    // line going into the master

    SPI_Master #(
        .CLK_HZ (CLK_HZ),
        .SPI_HZ (SPI_HZ)
    ) u_master (
        .clk      (clk),
        .rst      (rst),
        .start    (start_spi),
        .data_in  (data_to_send),
        .data_out (spi_data_out),
        .busy     (spi_busy),
        .new_data (spi_done),
        .sck      (sck),
        .mosi     (mosi),
        .miso     (miso_w)
    );

    wire [7:0] slave_rx_data;
    wire       slave_rx_valid;
    wire       slave_selected;
    wire       slave_miso;

    SPI_Slave u_slave (
        .clk      (clk),
        .rst      (rst),
        .sck      (sck),
        .mosi     (mosi),
        .cs_n     (cs_n),
        .miso     (slave_miso),
        .rx_data  (slave_rx_data),
        .rx_valid (slave_rx_valid),
        .selected (slave_selected)
    );

    assign miso_w = slave_miso;


    assign miso_mon = miso_w;

    // ---------------------------------------------------------------------
    // Sequencer: 2 frames x 3 bytes, CS stays low during a whole frame
    // ---------------------------------------------------------------------
    localparam [2:0] S_GAP       = 3'd0,   // idle between loops
                     S_CS_LOW    = 3'd1,   // CS low, wait setup time
                     S_LOAD      = 3'd2,   // load byte + pulse start
                     S_WAIT      = 3'd3,   // wait for master to finish the byte
                     S_CS_HOLD   = 3'd4,   // hold time after last byte
                     S_FRAME_GAP = 3'd5;   // CS high between frames

    reg [2:0]  state;
    reg        frame;                      // 0 = WRITE frame, 1 = READ frame
    reg [1:0]  byte_idx;                   // 0..2
    reg [31:0] wait_cnt;
    reg [7:0]  wr_data;
    reg [7:0]  read_data;

    assign led = read_data;

    // Byte table for the two frames
    function [7:0] tx_byte(input fr, input [1:0] idx, input [7:0] wdata);
        case (idx)
            2'd0:    tx_byte = fr ? CMD_READ : CMD_WRITE;
            2'd1:    tx_byte = TEST_ADDR;
            default: tx_byte = fr ? 8'h00 : wdata;   // READ: dummy byte to clock data out
        endcase
    endfunction

    always @(posedge clk) begin
        if (rst) begin
            state        <= S_GAP;
            frame        <= 1'b0;
            byte_idx     <= 2'd0;
            wait_cnt     <= 32'd0;
            wr_data      <= 8'h10;
            read_data    <= 8'h00;
            led_ok       <= 1'b0;
            cs_n         <= 1'b1;
            start_spi    <= 1'b0;
            data_to_send <= 8'h00;
        end else begin
            start_spi <= 1'b0;             // start is a 1-clock pulse

            case (state)

                S_GAP: begin
                    if (wait_cnt >= LOOP_GAP_CLKS - 1) begin
                        wait_cnt <= 0;
                        frame    <= 1'b0;
                        byte_idx <= 2'd0;
                        cs_n     <= 1'b0;                 // 1. activate slave
                        state    <= S_CS_LOW;
                    end else
                        wait_cnt <= wait_cnt + 1'b1;
                end

                S_CS_LOW: begin
                    if (wait_cnt == CS_SETUP_CLKS - 1) begin
                        wait_cnt <= 0;
                        state    <= S_LOAD;
                    end else
                        wait_cnt <= wait_cnt + 1'b1;
                end

                S_LOAD: begin
                    data_to_send <= tx_byte(frame, byte_idx, wr_data);
                    start_spi    <= 1'b1;
                    state        <= S_WAIT;
                end

                S_WAIT: begin
                    if (spi_done) begin
                        // Last byte of the READ frame carries the slave's answer
                        if (frame && byte_idx == 2'd2) begin
                            read_data <= spi_data_out;
                            led_ok    <= (spi_data_out == wr_data);
                        end

                        if (byte_idx == 2'd2) begin
                            wait_cnt <= 0;
                            state    <= S_CS_HOLD;        // frame finished
                        end else begin
                            byte_idx <= byte_idx + 1'b1;  // next byte, CS stays low
                            state    <= S_LOAD;
                        end
                    end
                end

                S_CS_HOLD: begin
                    if (wait_cnt == CS_HOLD_CLKS - 1) begin
                        wait_cnt <= 0;
                        cs_n     <= 1'b1;                 // deactivate slave
                        state    <= S_FRAME_GAP;
                    end else
                        wait_cnt <= wait_cnt + 1'b1;
                end

                S_FRAME_GAP: begin
                    if (wait_cnt == FRAME_GAP_CLKS - 1) begin
                        wait_cnt <= 0;
                        byte_idx <= 2'd0;
                        if (!frame) begin
                            frame <= 1'b1;                // WRITE done -> do READ
                            cs_n  <= 1'b0;
                            state <= S_CS_LOW;
                        end else begin
                            frame   <= 1'b0;              // loop done
                            wr_data <= wr_data + 1'b1;
                            state   <= S_GAP;
                        end
                    end else
                        wait_cnt <= wait_cnt + 1'b1;
                end

                default: state <= S_GAP;
            endcase
        end
    end

endmodule
