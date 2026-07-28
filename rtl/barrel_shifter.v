`timescale 1ns/1ps

module barrel_shifter #(
    parameter DATA_WIDTH = 64,
    parameter SHIFT_BITS = $clog2(DATA_WIDTH)
)(
    input  wire [DATA_WIDTH-1:0] data_address,
    input  wire [SHIFT_BITS-1:0] shift_amount,
    output wire [DATA_WIDTH-1:0] out_shifted_address
);

    /* verilator lint_off UNOPTFLAT */
    wire [DATA_WIDTH-1:0] stage [0:SHIFT_BITS];
    /* verilator lint_on UNOPTFLAT */
    assign stage[0] = data_address;

    genvar i;
    generate
        for (i = 0; i < SHIFT_BITS; i = i + 1) begin : g_shift
            localparam integer DISTANCE = (1 << i);
            assign stage[i+1] = shift_amount[i]
                              ? (stage[i] >> DISTANCE)
                              : stage[i];
        end
    endgenerate

    assign out_shifted_address = stage[SHIFT_BITS];

endmodule
