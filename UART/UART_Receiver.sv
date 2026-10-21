`default_nettype none

module Receiver #(
    parameter DATA_WIDTH = 4
    ) (
    input logic clk,
    input logic reset_n,
    input logic serial_in,
    output logic signed [DATA_WIDTH-1:0] data_out,
    output logic data_valid
);

    typedef enum logic [2:0] {
        IDLE,
        START,
        BIT0,
        BIT1,
        BIT2,
        BIT3,
        STOP,
        DONE
    } state_t;

    state_t state, next_state;

    logic serial_in_prev;
    logic signed [DATA_WIDTH-1:0] shift_reg;

    always_ff @(posedge clk or negedge reset_n) begin // Sequential block
        if (!reset_n) begin
            state <= IDLE;
        end
        else begin
            state <= next_state;
        end
    end

    always_ff @(posedge clk or negedge reset_n) begin // not part of the 3-block FSM
        if (!reset_n) begin
            serial_in_prev <= 1'b1;
            shift_reg <= 'b0;
        end
        else begin
            serial_in_prev <= serial_in;
            if (next_state == BIT0 || next_state == BIT1 || next_state == BIT2 || next_state == BIT3)
                shift_reg <= {serial_in, shift_reg[DATA_WIDTH - 1:1]};
        end
    end

    always_comb begin // Combinational next-state block
        case (state)
            IDLE: next_state = (!serial_in && serial_in_prev)? START : IDLE;
            START: next_state = BIT0;
            BIT0: next_state = BIT1;
            BIT1: next_state = BIT2;
            BIT2: next_state = BIT3;
            BIT3: next_state = STOP;
            STOP: next_state = serial_in? DONE : IDLE;
            DONE: next_state = IDLE;
            default: next_state = IDLE;
        endcase
    end

    always_comb begin // Combinational output block
        case (state)
            IDLE: begin data_valid = 1'b0; end
            START: begin data_valid = 1'b0; end
            BIT0: begin data_valid = 1'b0; end
            BIT1: begin data_valid = 1'b0; end
            BIT2: begin data_valid = 1'b0; end
            BIT3: begin data_valid = 1'b0; end
            STOP: begin data_valid = 1'b0; end
            DONE: begin data_valid = 1'b1; end
            default: begin data_valid = 1'b0; end
        endcase
    end

    assign data_out = shift_reg;

endmodule