`default_nettype none

module Transmitter #(
    parameter DATA_WIDTH = 4
    ) (
    input logic clk,
    input logic reset_n,
    input logic start, // pulse to start transmission
    input logic signed [DATA_WIDTH-1:0] data_in, // parallel signed data
    output logic serial_out
);

    typedef enum logic [2:0] {
        IDLE,
        START,
        BIT0,
        BIT1,
        BIT2,
        BIT3,
        STOP
    } state_t;

    state_t state, next_state;

    always_ff @(posedge clk or negedge reset_n) begin // Sequential block
        if (!reset_n) begin
            state <= IDLE;
        end
        else begin
            state <= next_state;
        end
    end

    always_comb begin // Combinational next-state block
        case (state)
            IDLE: next_state = start? START : IDLE;
            START: next_state = BIT0;
            BIT0: next_state = BIT1;
            BIT1: next_state = BIT2;
            BIT2: next_state = BIT3;
            BIT3: next_state = STOP;
            STOP: next_state = IDLE;
            default: next_state = IDLE;
        endcase
    end

    always_comb begin // Combinational output block
        case (state)
            IDLE: serial_out = 1'b1;
            START: serial_out = 1'b0;
            BIT0: serial_out = data_in[0];
            BIT1: serial_out = data_in[1];
            BIT2: serial_out = data_in[2];
            BIT3: serial_out = data_in[3];
            STOP: serial_out = 1'b1;
            default: serial_out = 1'b1;
        endcase
    end

endmodule