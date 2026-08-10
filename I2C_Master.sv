`default_nettype none

module I2C_Master #(
    parameter maxByteSize = 1,
    parameter timeout = 10000 // clk cycles
) (
    input wire RST,
    input wire clk, // 1MHz Clock
    // output wire scl,
    inout wire scl,
    inout wire sda,

    input wire enable,
    input wire [6:0] addr,
    input wire rw,

    input wire [$clog2(maxByteSize):0] dataBytes,
    input wire [(maxByteSize * 8 - 1):0] data_in,
    output reg [(maxByteSize * 8 - 1):0] data_out,

    output wire [7:0] debugWires
);

    assign debugWires[7:0] = {scl, sda, state[2:0], counter};
    // assign debugWires[7:0] = {scl, sda, data_out[8+5:8+0]};
    // assign debugWires[7:0] = {scl, sda, start_detect, state[2:0], addr[1:0]};
    // assign debugWires[7:0] = {scl, sda, i2c_clk, clk, enable, counter};

    localparam IDLE = 0;
    localparam START = 1;
    localparam SEND_ADDRESS = 2;
    localparam READ_ACK = 3;
    localparam WRITE_DATA = 4;
    localparam READ_DATA = 5;
    localparam READ_ACK2 = 6;
    localparam SEND_ACK = 7;
    localparam STOP = 8;
    localparam STOP2 = 9;

    (* preserve *) reg [2:0] counter;
    (* preserve *) reg [3:0] clk_counter;
    (* preserve *) reg [3:0] state = 4'b0;

    reg i2c_clk = 1'b1;
    reg sda_out = 1'b1;
    reg sda_in = 1'b1;

    wire [7:0] saved_addr = {addr, rw};

    reg i2c_enable = 1'b0;
    reg write_enable = 1'b0;

    reg [$clog2(maxByteSize):0] byteCounter = 'b0;
    wire [($clog2(maxByteSize) + 3):0] bitCounter;
    assign bitCounter = {byteCounter, counter};

    // Timeout logic
    reg [31:0] timeout_cnt;
    wire timeout_triggered = (timeout_cnt >= timeout);

    // control scl, sda
    assign scl = (i2c_enable == 1'b1 && i2c_clk == 1'b0) ? 1'b0 : 1'bz;
    assign sda = (write_enable == 1'b1 && sda_out == 1'b0) ? 1'b0 : 1'bz;

    ///////////////////////////////////////////////////////
    ////////////////////// I2C Clock //////////////////////
    ///////////////////////////////////////////////////////
    always @(posedge clk) begin
        if (state == IDLE || RST) timeout_cnt <= 0;
        else timeout_cnt <= timeout_cnt + 1;

        if (clk_counter == 4) begin
            i2c_clk <= ~i2c_clk;
            clk_counter <= 4'b0;
        end
        else clk_counter <= clk_counter + 1'b1;
    end

    ///////////////////////////////////////////////////////
    ///////////////// Sampling and Write //////////////////
    ///////////////////////////////////////////////////////
    always @ (posedge i2c_clk) begin
        if(RST) sda_in <= 1'b0;
        else begin
            sda_in <= sda;

            if (state == READ_DATA) begin
                data_out[bitCounter] <= sda;
            end else if (state == START) begin
                data_out = 'b0;
            end
        end
    end

    ///////////////////////////////////////////////////////
    //////////////////// State Machine ////////////////////
    ///////////////////////////////////////////////////////
    always @(negedge i2c_clk) begin

        if (RST || timeout_triggered) begin
            state <= IDLE;
            counter <= 3'b111;
            byteCounter <= 'b0;
        end

        else begin
            if(counter > 3'b0)
                counter <= counter - 3'b001;

            case(state)

                IDLE: begin
                    if (enable) state <= START;
                    else state <= IDLE;
                end

                START: begin
                    counter <= 3'b111;
                    byteCounter <= 'b0;
                    state <= SEND_ADDRESS;
                end

                SEND_ADDRESS: begin
                    if(counter == 0)
                        state <= READ_ACK;
                end

                READ_ACK: begin
                    if (sda_in == 1'b0) begin
                        counter <= 3'b111;
                        if (rw == 1'b0)
                            state <= WRITE_DATA;
                        else
                            state <= READ_DATA;
                    end
                    else state <= STOP;
                end

                WRITE_DATA: begin
                    if(counter == 3'b0) begin
                        if (byteCounter == dataBytes - 1) begin
                            byteCounter <= 'b0;
                            state <= READ_ACK2;
                        end
                        else begin
                            byteCounter <= byteCounter + 1;
                            state <= READ_ACK;
                        end
                    end
                end

                READ_ACK2: begin
                    // TODO: Add failed or done signal for checking after sending
                    state <= STOP;
                end

                READ_DATA: begin
                    if(counter == 3'b0)
                        state <= SEND_ACK;
                end

                SEND_ACK: begin
                    if (byteCounter == dataBytes - 1) begin
                        byteCounter <= 'b0;
                        state <= IDLE;
                    end
                    else begin
                        counter <= 3'b111;
                        byteCounter <= byteCounter + 1;
                        state <= READ_DATA;
                    end
                end

                STOP: begin
                    state <= STOP2;
                end

                STOP2: begin
                    state <= IDLE;
                end

                default: begin
                    state <= IDLE;
                end
            endcase
        end
    end

    always @(*) begin
        if (RST) begin
            sda_out = 1'b1;
            write_enable = 1'b0;
            i2c_enable = 1'b0;
        end

        else begin
            case(state)

                IDLE: begin
                    i2c_enable = 1'b0;
                    write_enable = 1'b0;
                    sda_out = 1'b1;
                end

                START: begin
                    i2c_enable = 1'b0;
                    write_enable = 1'b1;
                    sda_out = 1'b0;
                end

                SEND_ADDRESS: begin
                    i2c_enable = 1'b1;
                    write_enable = 1'b1;
                    sda_out = saved_addr[counter];
                end

                READ_ACK: begin
                    i2c_enable = 1'b1;
                    write_enable = 1'b0;
                    sda_out = 1'b1;
                end

                WRITE_DATA: begin
                    i2c_enable = 1'b1;
                    write_enable = 1'b1;
                    sda_out = data_in[bitCounter];
                end

                READ_ACK2: begin
                    i2c_enable = 1'b1;
                    write_enable = 1'b0;
                    sda_out = 1'b1;
                end

                READ_DATA: begin
                    i2c_enable = 1'b1;
                    write_enable = 1'b0;
                    sda_out = 1'b1;
                end

                SEND_ACK: begin
                    i2c_enable = 1'b1;
                    write_enable = 1'b1;
                    sda_out = 1'b0;
                end

                STOP: begin
                    i2c_enable = 1'b1;
                    write_enable = 1'b1;
                    sda_out = 1'b0;
                end

                STOP2: begin
                    i2c_enable = 1'b0;
                    write_enable = 1'b0;
                    sda_out = 1'b0;
                end

                default: begin
                    i2c_enable = 1'b0;
                    write_enable = 1'b0;
                    sda_out = 1'b1;
                end
            endcase
        end
    end

endmodule