`timescale 1ns/1ps

module axi4_full_read_master #(
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 32
)(
    input  wire                  clk,
    input  wire                  rst_n,

    input  wire                  cmd_valid,
    output wire                  cmd_ready,
    input  wire [ADDR_WIDTH-1:0] cmd_addr,
    input  wire [7:0]            cmd_len,

    output wire [DATA_WIDTH-1:0] data,
    output wire                  data_valid,
    input  wire                  data_ready,
    output wire                  data_last,

    output wire                  busy,
    output reg                   done,
    output reg                   error,

    output wire [ADDR_WIDTH-1:0] m_axi_araddr,
    output wire [7:0]            m_axi_arlen,
    output wire [2:0]            m_axi_arsize,
    output wire [1:0]            m_axi_arburst,
    output wire                  m_axi_arvalid,
    input  wire                  m_axi_arready,

    input  wire [DATA_WIDTH-1:0] m_axi_rdata,
    input  wire [1:0]            m_axi_rresp,
    input  wire                  m_axi_rlast,
    input  wire                  m_axi_rvalid,
    output wire                  m_axi_rready
);

    localparam [1:0]
        IDLE      = 2'd0,
        READ_ADDR = 2'd1,
        READ_DATA = 2'd2;

    localparam integer BYTE_WIDTH = DATA_WIDTH / 8;
    localparam [2:0] AXI_SIZE = $clog2(BYTE_WIDTH);

    reg [1:0] state;
    reg [ADDR_WIDTH-1:0] addr_reg;
    reg [7:0] len_reg;
    reg [7:0] beat_count;
    reg error_latched;

    wire expected_last = (beat_count == len_reg);
    wire read_handshake = m_axi_rvalid && m_axi_rready;

    assign cmd_ready = (state == IDLE);
    assign busy      = (state != IDLE);

    assign m_axi_araddr  = addr_reg;
    assign m_axi_arlen   = len_reg;
    assign m_axi_arsize  = AXI_SIZE;
    assign m_axi_arburst = 2'b01;
    assign m_axi_arvalid = (state == READ_ADDR);

    assign data       = m_axi_rdata;
    assign data_valid = (state == READ_DATA) && m_axi_rvalid;
    assign data_last  = expected_last;
    assign m_axi_rready = (state == READ_DATA) && data_ready;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state         <= IDLE;
            addr_reg      <= {ADDR_WIDTH{1'b0}};
            len_reg       <= 8'd0;
            beat_count    <= 8'd0;
            error_latched <= 1'b0;
            done          <= 1'b0;
            error         <= 1'b0;
        end else begin
            done  <= 1'b0;
            error <= 1'b0;

            case (state)
                IDLE: begin
                    if (cmd_valid && cmd_ready) begin
                        addr_reg      <= cmd_addr;
                        len_reg       <= cmd_len;
                        beat_count    <= 8'd0;
                        error_latched <= 1'b0;
                        state         <= READ_ADDR;
                    end
                end

                READ_ADDR: begin
                    if (m_axi_arvalid && m_axi_arready)
                        state <= READ_DATA;
                end

                READ_DATA: begin
                    if (read_handshake) begin
                        if (m_axi_rresp != 2'b00)
                            error_latched <= 1'b1;

                        if (m_axi_rlast || expected_last) begin
                            done <= 1'b1;
                            error <= error_latched |
                                     (m_axi_rresp != 2'b00) |
                                     (m_axi_rlast != expected_last);
                            state <= IDLE;
                        end else begin
                            beat_count <= beat_count + 1'b1;
                        end
                    end
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule
