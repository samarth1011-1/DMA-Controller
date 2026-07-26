`timescale 1ns/1ps

module mm2s_datapath #(
    parameter DATA_WIDTH = 32
)(
    input  wire                  clk,
    input  wire                  rst_n,

    input  wire                  start,
    input  wire [1:0]            src_offset,
    input  wire [31:0]           transfer_len,
    input  wire [31:0]           raw_beats,

    input  wire [DATA_WIDTH-1:0] data,
    input  wire                  data_valid,
    output wire                  data_ready,

    output wire [DATA_WIDTH-1:0] m_axis_tdata,
    output wire [3:0]            m_axis_tkeep,
    output wire                  m_axis_tvalid,
    input  wire                  m_axis_tready,
    output wire                  m_axis_tlast,

    output reg                   active,
    output reg                   done
);

    reg [1:0]            offset_reg;
    reg [31:0]           bytes_remaining;
    reg [31:0]           raw_beats_remaining;
    reg [DATA_WIDTH-1:0] previous_data;
    reg                  have_previous;
    reg                  flush_pending;

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

    wire [2:0] output_bytes =
        (bytes_remaining >= 4) ? 3'd4 : {1'b0, bytes_remaining[1:0]};
    wire [5:0] shift_amount = {1'b0, offset_reg, 3'b000};
    wire [63:0] shift_input =
        flush_pending
            ? {32'd0, previous_data}
            : {data, previous_data};
    wire [63:0] shifted_window;

    barrel_shifter #(
        .DATA_WIDTH(64),
        .SHIFT_BITS(6)
    ) u_aligner (
        .data_address(shift_input),
        .shift_amount(shift_amount),
        .out_shifted_address(shifted_window)
    );

    wire aligned_mode = (offset_reg != 0);
    wire collecting_first = aligned_mode && !have_previous;

    assign m_axis_tdata =
        aligned_mode ? shifted_window[DATA_WIDTH-1:0] : data;
    assign m_axis_tkeep  = byte_mask(output_bytes);
    assign m_axis_tlast  = (bytes_remaining <= 4);
    assign m_axis_tvalid =
        active &&
        (flush_pending || (!collecting_first && data_valid));

    assign data_ready =
        active && !flush_pending &&
        (collecting_first || m_axis_tready);

    wire raw_handshake = data_valid && data_ready;
    wire output_handshake = m_axis_tvalid && m_axis_tready;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            offset_reg          <= 2'd0;
            bytes_remaining     <= 32'd0;
            raw_beats_remaining <= 32'd0;
            previous_data       <= {DATA_WIDTH{1'b0}};
            have_previous       <= 1'b0;
            flush_pending       <= 1'b0;
            active              <= 1'b0;
            done                <= 1'b0;
        end else begin
            done <= 1'b0;

            if (start) begin
                offset_reg          <= src_offset;
                bytes_remaining     <= transfer_len;
                raw_beats_remaining <= raw_beats;
                previous_data       <= {DATA_WIDTH{1'b0}};
                have_previous       <= 1'b0;
                flush_pending       <= 1'b0;
                active              <= (transfer_len != 0);
            end else if (active) begin
                if (collecting_first && raw_handshake) begin
                    previous_data       <= data;
                    have_previous       <= 1'b1;
                    raw_beats_remaining <= raw_beats_remaining - 1'b1;
                    if (raw_beats_remaining == 1)
                        flush_pending <= 1'b1;
                end else if (flush_pending && output_handshake) begin
                    bytes_remaining <= bytes_remaining - output_bytes;
                    flush_pending   <= 1'b0;
                    active          <= 1'b0;
                    done            <= 1'b1;
                end else if (output_handshake) begin
                    bytes_remaining <= bytes_remaining - output_bytes;

                    if (raw_handshake) begin
                        previous_data       <= data;
                        have_previous       <= 1'b1;
                        raw_beats_remaining <= raw_beats_remaining - 1'b1;
                    end

                    if (bytes_remaining <= output_bytes) begin
                        active <= 1'b0;
                        done   <= 1'b1;
                    end else if (aligned_mode &&
                                 raw_handshake &&
                                 (raw_beats_remaining == 1)) begin
                        flush_pending <= 1'b1;
                    end
                end
            end
        end
    end

endmodule
