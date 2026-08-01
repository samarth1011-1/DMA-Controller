`timescale 1ns/1ps

module arbitration_unit #(
    parameter ALLOW_SIMULTANEOUS = 1
)(
    input  wire clk,
    input  wire rst_n,
    input  wire mm2s_request,
    input  wire s2mm_request,
    input  wire mm2s_busy,
    input  wire s2mm_busy,
    output reg  mm2s_grant,
    output reg  s2mm_grant
);

    reg last_grant;

    always @* begin
        mm2s_grant = 1'b0;
        s2mm_grant = 1'b0;

        if (ALLOW_SIMULTANEOUS) begin
            mm2s_grant = mm2s_request && !mm2s_busy;
            s2mm_grant = s2mm_request && !s2mm_busy;
        end else if (mm2s_request && s2mm_request) begin
            if (last_grant) begin
                mm2s_grant = !mm2s_busy;
            end else begin
                s2mm_grant = !s2mm_busy;
            end
        end else begin
            mm2s_grant = mm2s_request && !mm2s_busy;
            s2mm_grant = s2mm_request && !s2mm_busy;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            last_grant <= 1'b0;
        else if (mm2s_grant)
            last_grant <= 1'b0;
        else if (s2mm_grant)
            last_grant <= 1'b1;
    end

endmodule
