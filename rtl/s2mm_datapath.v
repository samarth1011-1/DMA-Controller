`timescale 1ns/1ps

module s2mm_datapath #(
    parameter DATA_WIDTH = 32
)(
    input  wire                  clk,
    input  wire                  rst_n,

    input  wire                  start,
    input  wire [1:0]            dst_offset,
    input  wire [31:0]           transfer_len,

    input  wire [DATA_WIDTH-1:0] s_axis_tdata,
    input  wire                  s_axis_tvalid,
    input  wire                  s_axis_tlast,
    output wire                  s_axis_tready,

    output wire [DATA_WIDTH-1:0] data,
    output wire [3:0]            data_strb,
    output wire                  data_valid,
    input  wire                  data_ready,

    output reg                   active,
    output reg                   done,
    output reg                   error
);

    reg [1:0]            offset_reg;
    reg [31:0]           bytes_remaining;
    reg [31:0]           input_bytes_remaining;
    reg [DATA_WIDTH-1:0] previous_data;
    reg                  first_beat;
    reg                  flush_pending;

    wire [2:0] first_capacity = 3'd4 - {1'b0, offset_reg};
    wire [2:0] beat_capacity =
        (first_beat && (offset_reg != 0)) ? first_capacity : 3'd4;
    wire [2:0] valid_bytes =
        (bytes_remaining >= beat_capacity)
            ? beat_capacity
            : {1'b0, bytes_remaining[1:0]};

    function [3:0] byte_mask;
        input [2:0] count;
        begin
            case (count)
                3'd1: byte_mask = 4'b0001;
                3'd2: byte_mask = 4'b0011;
                3'd3: byte_mask = 4'b0111;
                3'd4: byte_mask = 4'b1111;
                default: byte_mask = 4'b0000;
            endcase
        end
    endfunction

    wire [5:0] shift_amount =
        (offset_reg == 0) ? 6'd0 : ((6'd4 - offset_reg) << 3);
    wire [63:0] shift_input =
        flush_pending
            ? {32'd0, previous_data}
            : {s_axis_tdata,
               (first_beat && (offset_reg != 0)) ? 32'd0 : previous_data};
    wire [63:0] shifted_window;

    barrel_shifter #(
        .DATA_WIDTH(64),
        .SHIFT_BITS(6)
    ) u_aligner (
        .data_address(shift_input),
        .shift_amount(shift_amount),
        .out_shifted_address(shifted_window)
    );

    assign data =
        (offset_reg == 0 && !flush_pending)
            ? s_axis_tdata
            : shifted_window[DATA_WIDTH-1:0];
    assign data_strb =
        (first_beat && (offset_reg != 0))
            ? (byte_mask(valid_bytes) << offset_reg)
            : byte_mask(valid_bytes);
    assign data_valid = active && (flush_pending || s_axis_tvalid);
    assign s_axis_tready = active && !flush_pending && data_ready;

    wire output_handshake = data_valid && data_ready;
    wire input_is_last = (input_bytes_remaining <= 4);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            offset_reg            <= 2'd0;
            bytes_remaining       <= 32'd0;
            input_bytes_remaining <= 32'd0;
            previous_data         <= {DATA_WIDTH{1'b0}};
            first_beat            <= 1'b1;
            flush_pending         <= 1'b0;
            active                <= 1'b0;
            done                  <= 1'b0;
            error                 <= 1'b0;
        end else begin
            done <= 1'b0;

            if (start) begin
                offset_reg            <= dst_offset;
                bytes_remaining       <= transfer_len;
                input_bytes_remaining <= transfer_len;
                previous_data         <= {DATA_WIDTH{1'b0}};
                first_beat            <= 1'b1;
                flush_pending         <= 1'b0;
                active                <= (transfer_len != 0);
                error                 <= 1'b0;
            end else if (output_handshake) begin
                bytes_remaining <= bytes_remaining - valid_bytes;

                if (flush_pending) begin
                    flush_pending <= 1'b0;
                    active        <= 1'b0;
                    done          <= 1'b1;
                end else begin
                    previous_data <= s_axis_tdata;
                    first_beat    <= 1'b0;

                    if (input_bytes_remaining > 4)
                        input_bytes_remaining <= input_bytes_remaining - 4;
                    else
                        input_bytes_remaining <= 0;

                    if (s_axis_tlast != input_is_last)
                        error <= 1'b1;

                    if (bytes_remaining <= valid_bytes) begin
                        active <= 1'b0;
                        done   <= 1'b1;
                    end else if (input_is_last) begin
                        flush_pending <= 1'b1;
                    end
                end
            end
        end
    end

endmodule
