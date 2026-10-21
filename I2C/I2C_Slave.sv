`default_nettype none

module I2C_Slave #(
    parameter maxByteSize = 1,
    parameter timeout = 10000 // clk cycles
) (
    input wire RST,
    input wire clk,

    inout wire scl,
    inout wire sda,
    input wire [6:0] ADDRESS,

    input wire [$clog2(maxByteSize):0] dataBytes,
    output reg [(maxByteSize * 8 - 1):0] data_in,
    input wire [(maxByteSize * 8 - 1):0] data_out,

    output wire [7:0] debugWires
);

    assign debugWires[7:0] = {scl, sda, state[2:0], counter};
    // assign debugWires[7:0] = {scl, sda, data_in[16+5:16+0]};
    // assign debugWires[7:0] = {scl, sda, addr[5:0]};
    // assign debugWires[7:0] = {start_detect, start_resetter, state[2:0], counter};

    localparam IDLE = 0;
    localparam READ_ADDR = 1;
    localparam SEND_ACK = 2;
    localparam READ_DATA = 3;
    localparam WRITE_DATA = 4;
    localparam SEND_ACK2 = 5;
    localparam RECIEVE_ACK = 6;

    reg start_detect;
    reg start_resetter;

    reg [7:0] addr;
    (* preserve *) reg [2:0] counter;
    (* preserve *) reg [2:0] state = 3'b0;

    reg sda_out = 1'b1;
    reg sda_in = 1'b1;
    reg write_enable = 1'b0;

    reg [$clog2(maxByteSize):0] byteCounter = 'b0;
    wire [($clog2(maxByteSize) + 3):0] bitCounter;
    assign bitCounter = {byteCounter, counter};

    // Timeout logic
    reg [31:0] timeout_cnt;
    wire timeout_triggered = (timeout_cnt >= timeout);

    // control sda
    // assign sda = (write_enable == 1'b1) ? sda_out : 'bz;
    assign sda = (write_enable == 1'b1 && sda_out == 1'b0) ? 1'b0 : 1'bz;

    ///////////////////////////////////////////////////////
    /////////////////// Start Detection ///////////////////
    ///////////////////////////////////////////////////////
    always @(negedge sda) begin
        if(start_resetter || RST)
            start_detect <= 1'b0;
        else
            start_detect <= scl;
    end
    always @(posedge scl) begin
        start_resetter <= start_detect;
    end
    // reg sda_prev;
    // always @(posedge clk) begin
    //     sda_prev <= sda;
    //     if (sda_prev && !sda && scl)  // falling sda while scl high
    //         start_detect <= 1'b1;
    //     else if (!scl)   // reset when scl falls
    //         start_detect <= 1'b0;
    // end

    // Timeout logic
    always @(posedge clk) begin
        if (state == IDLE || RST) timeout_cnt <= 0;
        else timeout_cnt <= timeout_cnt + 1;
    end

    ///////////////////////////////////////////////////////
    ///////////////// Sampling and Write //////////////////
    ///////////////////////////////////////////////////////
    always @ (posedge scl) begin
        if(RST) sda_in <= 1'b0;
        else begin
            sda_in <= sda;

            if (state == READ_ADDR) begin
                addr[counter] <= sda;
            end else if (state == IDLE) begin
                addr <= 8'b0;
            end

            if (state == READ_DATA) begin
                data_in[bitCounter] <= sda;
            end else if (state == READ_ADDR) begin
                data_in <= 'b0;
            end
        end
    end

    ///////////////////////////////////////////////////////
    //////////////////// State Machine ////////////////////
    ///////////////////////////////////////////////////////
    always @(negedge scl) begin

        if (RST || timeout_triggered) begin
            state <= IDLE;
            counter <= 3'b111;
            byteCounter <= 'b0;
        end

        else if (start_detect && state == IDLE) begin
            state <= READ_ADDR;
            counter <= 3'b111;
        end

        else begin
            if(counter > 3'b0)
                counter <= counter - 3'b001;

            case(state)

                IDLE: begin
                    state <= IDLE;
                end

                READ_ADDR: begin
                    if(counter == 0) begin
                        if(addr[7:1] == ADDRESS || addr[7:0] == 8'b00000000)
                            state <= SEND_ACK;
                        else
                            state <= IDLE;
                    end
                end

                SEND_ACK: begin
                    counter <= 3'b111;

                    if(addr[0] == 0)
                        state <= READ_DATA;
                    else
                        state <= WRITE_DATA;
                end

                READ_DATA: begin
                    if(counter == 0) begin
                        if (byteCounter == dataBytes - 1) begin
                            byteCounter <= 'b0;
                            state <= SEND_ACK2;
                        end
                        else begin
                            byteCounter <= byteCounter + 1;
                            state <= SEND_ACK;
                        end
                    end
                end

                SEND_ACK2: begin
                    state <= IDLE;
                end

                WRITE_DATA: begin
                    if(counter == 0)
                        state <= RECIEVE_ACK;
                end

                RECIEVE_ACK: begin
                    counter <= 3'b111;

                    if (sda_in == 1'b0) begin
                        if (byteCounter == dataBytes - 1) begin
                            byteCounter <= 'b0;
                            state <= IDLE;
                        end
                        else begin
                            byteCounter <= byteCounter + 1;
                            state <= WRITE_DATA;
                        end
                    end
                    else begin
                        byteCounter <= 'b0;
                        state <= IDLE;
                    end
                end

                default: begin
                    state <= IDLE;
                end
            endcase
        end
    end

    always @(*) begin
        sda_out = 1'b1;

        if (RST) begin
            write_enable = 1'b0;
        end

        else begin
            case(state)

                IDLE: begin
                    write_enable = 1'b0;
                end

                READ_ADDR: begin
                    write_enable = 1'b0;
                end

                SEND_ACK: begin
                    sda_out = 1'b0;
                    write_enable = 1'b1;
                end

                READ_DATA: begin
                    write_enable = 1'b0;
                end

                SEND_ACK2: begin
                    sda_out = 1'b0;
                    write_enable = 1'b1;
                end

                WRITE_DATA: begin
                    sda_out = data_out[bitCounter];
                    write_enable = 1'b1;
                end

                RECIEVE_ACK: begin
                    write_enable = 1'b0;
                end

                default: begin
                    write_enable = 1'b0;
                end
            endcase
        end
    end

endmodule
