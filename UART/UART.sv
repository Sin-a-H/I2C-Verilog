`default_nettype none

module UART (
    input wire CLK,

    output wire tx,
    output wire rx
);

    wire clk1MHz;
    wire locked;

    PLL myPLL (
        .areset(1'b0),
        .inclk0(CLK),
        .c0(clk1MHz),
        .locked(locked)
    );

    UART_Transmitter u_tx (
        .clk(clk1MHz),
        .reset_n(),
        .start(),
        .data_in(), // [DATA_WIDTH-1:0]
        .serial_out()
    );

    UART_Receiver u_rx (
        .clk(clk1MHz),
        .reset_n(),
        .serial_in(),
        .data_out(),
        .data_valid()
    );

endmodule