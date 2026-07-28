`timescale 1ns/1ps

module mm2s_channel #(
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 32,
    parameter BURST_MAX  = 16
)(
    input  wire                  clk,
    input  wire                  rst_n,

    output wire [DATA_WIDTH-1:0] m_axis_tdata,
    output wire [3:0]            m_axis_tkeep,
    output wire                  m_axis_tvalid,
    input  wire                  m_axis_tready,
    output wire                  m_axis_tlast,

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
    output wire                  m_axi_rready,

    input  wire [31:0]           mm2s_ctrl,
    input  wire [ADDR_WIDTH-1:0] src_addr,
    input  wire [31:0]           mm2s_len,
    output wire [31:0]           mm2s_status,
    output wire                  mm2s_done
);

    wire                  cmd_valid;
    wire                  cmd_ready;
    wire [ADDR_WIDTH-1:0] cmd_addr;
    wire [7:0]            cmd_len;
    wire                  read_done;
    wire                  read_error;

    wire                  align_start;
    wire [1:0]            align_offset;
    wire [31:0]           align_length;
    wire [31:0]           align_raw_beats;
    wire                  align_done;

    wire [DATA_WIDTH-1:0] raw_data;
    wire                  raw_valid;
    wire                  raw_ready;

    mm2s_control_fsm #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .BURST_MAX(BURST_MAX)
    ) u_control (
        .clk(clk),
        .rst_n(rst_n),
        .mm2s_ctrl(mm2s_ctrl),
        .src_addr(src_addr),
        .mm2s_len(mm2s_len),
        .cmd_valid(cmd_valid),
        .cmd_ready(cmd_ready),
        .cmd_addr(cmd_addr),
        .cmd_len(cmd_len),
        .read_done(read_done),
        .read_error(read_error),
        .align_start(align_start),
        .align_offset(align_offset),
        .align_length(align_length),
        .align_raw_beats(align_raw_beats),
        .align_done(align_done),
        .mm2s_status(mm2s_status),
        .mm2s_done(mm2s_done)
    );

    axi4_full_read_master #(
        .DATA_WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) u_read_master (
        .clk(clk),
        .rst_n(rst_n),
        .cmd_valid(cmd_valid),
        .cmd_ready(cmd_ready),
        .cmd_addr(cmd_addr),
        .cmd_len(cmd_len),
        .data(raw_data),
        .data_valid(raw_valid),
        .data_ready(raw_ready),
        .data_last(),
        .busy(),
        .done(read_done),
        .error(read_error),
        .m_axi_araddr(m_axi_araddr),
        .m_axi_arlen(m_axi_arlen),
        .m_axi_arsize(m_axi_arsize),
        .m_axi_arburst(m_axi_arburst),
        .m_axi_arvalid(m_axi_arvalid),
        .m_axi_arready(m_axi_arready),
        .m_axi_rdata(m_axi_rdata),
        .m_axi_rresp(m_axi_rresp),
        .m_axi_rlast(m_axi_rlast),
        .m_axi_rvalid(m_axi_rvalid),
        .m_axi_rready(m_axi_rready)
    );

    mm2s_datapath #(
        .DATA_WIDTH(DATA_WIDTH)
    ) u_datapath (
        .clk(clk),
        .rst_n(rst_n),
        .start(align_start),
        .src_offset(align_offset),
        .transfer_len(align_length),
        .raw_beats(align_raw_beats),
        .data(raw_data),
        .data_valid(raw_valid),
        .data_ready(raw_ready),
        .m_axis_tdata(m_axis_tdata),
        .m_axis_tkeep(m_axis_tkeep),
        .m_axis_tvalid(m_axis_tvalid),
        .m_axis_tready(m_axis_tready),
        .m_axis_tlast(m_axis_tlast),
        .active(),
        .done(align_done)
    );

endmodule
