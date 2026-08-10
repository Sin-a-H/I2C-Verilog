`default_nettype none

module I2C (
    // input wire RST,
    input wire CLK,

    inout tri1 scl_master,
    inout tri1 sda_master,
    inout tri1 scl_slave,
    inout tri1 sda_slave,

    output wire [4:0] LED,
    // output wire [7:0] debugWires
    inout tri1 [7:0] debugWires
);

    assign LED = 4'hf;
    wire RST = 1'b0;

    wire clk1MHz;
    wire locked;

    PLL myPLL (
        .areset(1'b0),
        .inclk0(CLK),
        .c0(clk1MHz),
        .locked(locked)
    );

    reg set_enable;
    reg [9:0] clk_count = 'b0;

    always @(posedge clk1MHz) begin
        clk_count <= clk_count + 1;
        if (clk_count[9] == 1'b1) begin
            set_enable <= 1'b1;
            clk_count <= 'b0;
        end
        // set_enable <= clk_count[7];
        if (set_enable)
            set_enable <= 1'b0;
    end

    I2C_Master # (
        .maxByteSize(3)
    ) myMaster (
        .RST(RST),
        .clk(clk1MHz),
        .scl(scl_master),
        .sda(sda_master),

        .enable(set_enable),
        .addr(7'h5e),
        .rw(1'b0),

        .dataBytes(2'b11),
        .data_in(24'b11001100_10101010_11000011),
        .data_out(),

        .debugWires()
    );

    I2C_Slave # (
        .maxByteSize(3)
    ) mySlave (
        .RST(RST),
        .clk(clk1MHz),
        .scl(scl_slave),
        .sda(sda_slave),
        .ADDRESS(7'h5e),

        .dataBytes(2'b11),
        .data_in(),
        .data_out(24'b00001111_11110000_00110011),

        .debugWires(debugWires)
    );

endmodule
