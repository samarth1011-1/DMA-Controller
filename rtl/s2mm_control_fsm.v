`timescale 1ns/1ps

module s2mm_control_fsm #(
    parameter ADDR_WIDTH = 32,
    parameter BURST_MAX  = 16
)(
    input  wire                  clk,
    input  wire                  rst_n,

    input  wire [31:0]           s2mm_ctrl,
    input  wire [ADDR_WIDTH-1:0] dst_addr,
    input  wire [31:0]           s2mm_len,

    output wire                  cmd_valid,
    input  wire                  cmd_ready,
    output wire [ADDR_WIDTH-1:0] cmd_addr,
    output wire [7:0]            cmd_len,
    input  wire                  write_done,
    input  wire                  write_error,

    output reg                   align_start,
    output reg [1:0]             align_offset,
    output reg [31:0]            align_length,
    input  wire                  align_error,

    output reg [31:0]            s2mm_status,
    output reg                   s2mm_done
);

    localparam [1:0]
        IDLE       = 2'd0,
        ISSUE_CMD  = 2'd1,
        WAIT_WRITE = 2'd2,
        COMPLETE   = 2'd3;

    reg [1:0] state;
    reg [ADDR_WIDTH-1:0] current_addr;
    reg [31:0] beats_remaining;
    reg [8:0] current_burst;
    reg error_latched;

    reg [8:0] planned_burst;
    reg [12:0] boundary_bytes;
    reg [10:0] boundary_beats;

    always @* begin
        boundary_bytes = 13'd4096 - {1'b0, current_addr[11:0]};
        boundary_beats = boundary_bytes[12:2];

        if (beats_remaining < BURST_MAX)
            planned_burst = beats_remaining[8:0];
        else if (BURST_MAX > 256)
            planned_burst = 9'd256;
        else
            planned_burst = BURST_MAX;

        if ({2'b00, planned_burst} > boundary_beats)
            planned_burst = boundary_beats[8:0];
        if (planned_burst == 0)
            planned_burst = 9'd1;
    end

    assign cmd_valid = (state == ISSUE_CMD);
    assign cmd_addr  = current_addr;
    assign cmd_len   = planned_burst[7:0] - 1'b1;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state           <= IDLE;
            current_addr    <= {ADDR_WIDTH{1'b0}};
            beats_remaining <= 32'd0;
            current_burst   <= 9'd0;
            error_latched   <= 1'b0;
            align_start     <= 1'b0;
            align_offset    <= 2'd0;
            align_length    <= 32'd0;
            s2mm_status     <= 32'd0;
            s2mm_done       <= 1'b0;
        end else begin
            align_start <= 1'b0;
            s2mm_done   <= 1'b0;

            case (state)
                IDLE: begin
                    if (s2mm_ctrl[1]) begin
                        s2mm_status <= 32'd0;
                    end else if (s2mm_ctrl[0] && (s2mm_len != 0)) begin
                        current_addr <= {
                            dst_addr[ADDR_WIDTH-1:2], 2'b00
                        };
                        beats_remaining <=
                            ({30'd0, dst_addr[1:0]} + s2mm_len + 3) >> 2;
                        align_offset  <= dst_addr[1:0];
                        align_length  <= s2mm_len;
                        align_start   <= 1'b1;
                        error_latched <= 1'b0;
                        s2mm_status   <= 32'b001;
                        state         <= ISSUE_CMD;
                    end
                end

                ISSUE_CMD: begin
                    if (cmd_valid && cmd_ready) begin
                        current_burst <= planned_burst;
                        state         <= WAIT_WRITE;
                    end
                end

                WAIT_WRITE: begin
                    if (write_done) begin
                        if (write_error) begin
                            error_latched <= 1'b1;
                            state         <= COMPLETE;
                        end else if (beats_remaining <= current_burst) begin
                            state <= COMPLETE;
                        end else begin
                            beats_remaining <= beats_remaining - {23'd0, current_burst};
                            current_addr <= current_addr + {21'd0, current_burst, 2'b00};
                            state <= ISSUE_CMD;
                        end
                    end
                end

                COMPLETE: begin
                    s2mm_status <= {
                        29'd0,
                        error_latched | align_error,
                        1'b1,
                        1'b0
                    };
                    s2mm_done <= 1'b1;
                    state     <= IDLE;
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule
