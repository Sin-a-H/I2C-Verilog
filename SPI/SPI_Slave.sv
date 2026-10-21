`default_nettype none

// SPI_Slave  -  SPI mode 0 (CPOL=0, CPHA=0), MSB first, 8-bit bytes
//   Requirement: CLK_HZ must be comfortably faster than SCK
//   (rule of thumb: SPI_HZ <= CLK_HZ / 8, i.e. SPI_Master DIVIDER >= 4).

// Frame protocol (what the slave does with the bytes):
//
//   byte 0 : command   0x0B = READ,  0x02 = WRITE  (anything else is ignored)
//   byte 1 : address
//   byte 2 : READ  -> slave shifts out mem[addr] on MISO (master sends dummy)
//            WRITE -> slave stores this byte in mem[addr]
//   byte 3+: same as byte 2, address auto-increments after every byte
//
// The memory is pre-loaded with  mem[i] = 8'hA0 + i  so a READ gives a known
// value even before anything was written.
//
// MISO is driven all the time (0 while CS_N is high). This is fine for a
// one-master / one-slave test. For a shared bus you would add a tri-state.

module SPI_Slave #(
    parameter ADDR_W = 4           // memory depth = 2**ADDR_W bytes
)(
    input wire clk,                // FPGA system clock
    input wire rst,

    // Physical Pins
    input wire sck,
    input wire mosi,
    input wire cs_n,
    output wire miso,

    // Debug
    output reg [7:0] rx_data,      // last received byte
    output reg rx_valid,           // 1-clk pulse when rx_data is new
    output wire selected           // 1 while CS_N is low
);

    localparam [7:0] CMD_READ  = 8'h0B;
    localparam [7:0] CMD_WRITE = 8'h02;

    // 1. Input synchronizers + edge detection
    reg [2:0] sck_q;
    reg [2:0] cs_q;
    reg [1:0] mosi_q;

    always @(posedge clk) begin
        if (rst) begin
            sck_q  <= 3'b000;            // SCK idles low (CPOL = 0)
            cs_q   <= 3'b111;            // CS idles high
            mosi_q <= 2'b00;
        end else begin
            sck_q  <= {sck_q[1:0],  sck};
            cs_q   <= {cs_q[1:0],   cs_n};
            mosi_q <= {mosi_q[0],   mosi};
        end
    end

    wire cs_idle  = cs_q[1];
    wire sck_rise = (sck_q[2:1] == 2'b01);
    wire sck_fall = (sck_q[2:1] == 2'b10);

    assign selected = ~cs_idle;

    // 2. Memory
    reg [7:0] mem [0:(1<<ADDR_W)-1];
    integer i;
    initial begin
        for (i = 0; i < (1<<ADDR_W); i = i + 1)
            mem[i] = 8'hA0 + i;
    end

    // 3. Shift registers + command handling
    reg [2:0] bit_cnt;                   // bits received in the current byte
    reg [1:0] byte_cnt;                  // 0,1,2 (stays at 2 for 2nd byte onward)
    reg [7:0] cmd;
    reg [ADDR_W-1:0] addr;
    reg [7:0] rx_shift;
    reg [7:0] tx_shift;                  // MSB is on MISO
    reg [7:0] tx_next;                   // byte to load at the next byte boundary

    wire [7:0]        rx_byte  = {rx_shift[6:0], mosi_q[1]};  // completes on 8th rising edge
    wire [ADDR_W-1:0] addr_inc = addr + 1'b1;

    assign miso = tx_shift[7];

    always @(posedge clk) begin
        if (rst) begin
            bit_cnt  <= 0;
            byte_cnt <= 0;
            cmd      <= 8'h00;
            addr     <= 0;
            rx_shift <= 8'h00;
            tx_shift <= 8'h00;
            tx_next  <= 8'h00;
            rx_data  <= 8'h00;
            rx_valid <= 1'b0;
        end else begin
            rx_valid <= 1'b0;

            if (cs_idle) begin
                // Not selected: get ready for the next frame
                bit_cnt  <= 0;
                byte_cnt <= 0;
                tx_shift <= 8'h00;
                tx_next  <= 8'h00;
            end else begin

                // ---- SCK rising edge: sample MOSI --------------------------
                if (sck_rise) begin
                    rx_shift <= rx_byte;

                    if (bit_cnt == 3'd7) begin
                        // A whole byte has arrived
                        bit_cnt  <= 0;
                        rx_data  <= rx_byte;
                        rx_valid <= 1'b1;
                        if (byte_cnt != 2'd2) byte_cnt <= byte_cnt + 1'b1;

                        case (byte_cnt)
                            2'd0: begin                       // command
                                cmd     <= rx_byte;
                                tx_next <= 8'h00;
                            end
                            2'd1: begin                       // address
                                addr    <= rx_byte[ADDR_W-1:0];
                                // Prepare the first data byte for a READ
                                tx_next <= (cmd == CMD_READ) ? mem[rx_byte[ADDR_W-1:0]]
                                                             : 8'h00;
                            end
                            default: begin                    // data bytes
                                if (cmd == CMD_WRITE)
                                    mem[addr] <= rx_byte;
                                addr    <= addr_inc;
                                tx_next <= (cmd == CMD_READ) ? mem[addr_inc]
                                                             : 8'h00;
                            end
                        endcase
                    end else begin
                        bit_cnt <= bit_cnt + 1'b1;
                    end
                end

                // ---- SCK falling edge: update MISO -------------------------
                // bit_cnt == 0 here means the previous byte just finished,
                // so load the next byte; otherwise shift to the next bit.
                if (sck_fall) begin
                    if (bit_cnt == 3'd0) tx_shift <= tx_next;
                    else                 tx_shift <= {tx_shift[6:0], 1'b0};
                end
            end
        end
    end

endmodule
