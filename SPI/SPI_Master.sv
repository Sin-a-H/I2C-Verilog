`default_nettype none

module SPI_Master #(
    parameter CLK_HZ = 50_000_000,
    parameter SPI_HZ = 1_000_000   // 1 MHz
)(
    input wire clk,
    input wire rst,
    input wire start,
    input wire [7:0] data_in,    // Data to send (MOSI)
    output reg [7:0] data_out,   // Received data (MISO)
    output reg busy,             // 1 while transmitting
    output reg new_data,         // Pulse when done

    // Physical Pins
    output reg sck,
    output reg mosi,
    input wire miso
    // Chip Select controlled by higher modules
);

    // 1. SPI Clock Generator (SCK)
    // SCK must be 2x the SPI_HZ frequency to have both rising and falling edges
    localparam DIVIDER = CLK_HZ / (2 * SPI_HZ);
    localparam COUNT_WIDTH = (DIVIDER <= 1) ? 1 : $clog2(DIVIDER);
    reg [COUNT_WIDTH-1:0] clk_count;

    // States
    localparam IDLE = 0;
    localparam WORK = 1;
    reg state;

    reg [2:0] bit_cnt;      // Bit counter 0-7
    reg [7:0] shift_reg_tx; // Transmit shift register
    reg [7:0] shift_reg_rx; // Receive shift register

    // Clock divider logic
    wire sck_rise = (clk_count == DIVIDER-1) && (sck == 0);
    wire sck_fall = (clk_count == DIVIDER-1) && (sck == 1);

    always @(posedge clk) begin
        if (rst) begin
            state <= IDLE;
            sck <= 0; // CPOL = 0
            mosi <= 0;
            busy <= 0;
            new_data <= 0;
            clk_count <= 0;
        end else begin
            new_data <= 0; // Pulse defaults to off

            case (state)
                IDLE: begin
                    sck <= 0;
                    busy <= 0;
                    clk_count <= 0;

                    if (start) begin
                        state <= WORK;
                        busy <= 1;
                        shift_reg_tx <= data_in; // Load data
                        shift_reg_rx <= 0;
                        bit_cnt <= 7;            // MSB First
                        mosi <= data_in[7];      // Output the first bit immediately
                        // Prepare for the first rising edge
                    end
                end

                WORK: begin
                    // Clock divider management
                    if (clk_count == DIVIDER-1) begin
                        clk_count <= 0;
                        sck <= ~sck; // Toggle the clock
                    end else begin
                        clk_count <= clk_count + 1;
                    end

                    // Events on SCK edges

                    // A. RISING Edge: SAMPLE MISO
                    if (sck_rise) begin
                        shift_reg_rx <= {shift_reg_rx[6:0], miso};
                    end

                    // B. FALLING Edge: UPDATE MOSI (Shift)
                    if (sck_fall) begin
                        if (bit_cnt == 0) begin
                            // All 8 bits are complete!
                            state <= IDLE;
                            busy <= 0;
                            new_data <= 1;
                            data_out <= shift_reg_rx; // The last bit was captured on the previous edge
                        end else begin
                            // Prepare next bit
                            bit_cnt <= bit_cnt - 1;
                            shift_reg_tx <= {shift_reg_tx[6:0], 1'b0}; // Shift left
                            mosi <= shift_reg_tx[6]; // Output the next bit (now at index 6 after shift)
                        end
                    end
                end
            endcase
        end
    end

endmodule