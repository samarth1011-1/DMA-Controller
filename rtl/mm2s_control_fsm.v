`timescale 1ns/1ps

module mm2s_control_fsm #(
    parameter ADDR_WIDTH = 32,
    parameter BURST_MAX  = 16
)(
    input  wire                  clk,
    input  wire                  rst_n,

    input  wire [31:0]           mm2s_ctrl,
    input  wire [ADDR_WIDTH-1:0] src_addr,
    input  wire [31:0]           mm2s_len,

    output wire                  cmd_valid,
    input  wire                  cmd_ready,
    output wire [ADDR_WIDTH-1:0] cmd_addr,
    output wire [7:0]            cmd_len,
    input  wire                  read_done,
    input  wire                  read_error,

    output reg                   align_start,
    output reg [1:0]             align_offset,
    output reg [31:0]            align_length,
    output reg [31:0]            align_raw_beats,
    input  wire                  align_done,

    output reg [31:0]            mm2s_status,
    output reg                   mm2s_done
);

    localparam [2:0]
        IDLE       = 3'd0,
        ISSUE_CMD  = 3'd1,
        WAIT_READ  = 3'd2,
        WAIT_ALIGN = 3'd3,
        COMPLETE   = 3'd4;

    reg [2:0] state;
    reg [ADDR_WIDTH-1:0] current_addr;
    reg [31:0] beats_remaining;
    reg [8:0] current_burst;
    reg error_latched;

    reg [8:0] planned_burst;
    reg [12:0] boundary_bytes;
    reg [10:0] boundary_beats;

    always @* begin
        boundary_bytes = 13'd4096 - {1'b0, current_addr[11:0]};
        boundary_beats = boundary_bytes >> 2;

        if (beats_remaining < BURST_MAX)
            planned_burst = beats_remaining[8:0];
        else if (BURST_MAX > 256)
            planned_burst = 9'd256;
        else
            planned_burst = BURST_MAX;

        if (planned_burst > boundary_beats)
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
            align_raw_beats <= 32'd0;
            mm2s_status     <= 32'd0;
            mm2s_done       <= 1'b0;
        end else begin
            align_start <= 1'b0;
            mm2s_done   <= 1'b0;

            case (state)
                IDLE: begin
                    if (mm2s_ctrl[1]) begin
                        mm2s_status <= 32'd0;
                    end else if (mm2s_ctrl[0] && (mm2s_len != 0)) begin
                        current_addr <= {
                            src_addr[ADDR_WIDTH-1:2], 2'b00
                        };
                        beats_remaining <=
                            ({30'd0, src_addr[1:0]} + mm2s_len + 3) >> 2;
                        align_offset <= src_addr[1:0];
                        align_length <= mm2s_len;
                        align_raw_beats <=
                            ({30'd0, src_addr[1:0]} + mm2s_len + 3) >> 2;
                        align_start   <= 1'b1;
                        error_latched <= 1'b0;
                        mm2s_status   <= 32'b001;
                        state         <= ISSUE_CMD;
                    end
                end

                ISSUE_CMD: begin
                    if (cmd_valid && cmd_ready) begin
                        current_burst <= planned_burst;
                        state         <= WAIT_READ;
                    end
                end

                WAIT_READ: begin
                    if (read_done) begin
                        if (read_error) begin
                            error_latched <= 1'b1;
                            state         <= COMPLETE;
                        end else if (beats_remaining <= current_burst) begin
                            state <= WAIT_ALIGN;
                        end else begin
                            beats_remaining <= beats_remaining - current_burst;
                            current_addr <= current_addr + (current_burst << 2);
                            state <= ISSUE_CMD;
                        end
                    end
                end

                WAIT_ALIGN: begin
                    if (align_done)
                        state <= COMPLETE;
                end

                COMPLETE: begin
                    mm2s_status <= {
                        29'd0,
                        error_latched,
                        1'b1,
                        1'b0
                    };
                    mm2s_done <= 1'b1;
                    state     <= IDLE;
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule
