`timescale 1ns/1ps

module s2mm_channel #(
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 32,
    parameter FIFO_DEPTH = 16,
    parameter BURST_MAX  = 16
)(
    input  wire                  clk,
    input  wire                  rst_n,

    input  wire [DATA_WIDTH-1:0] s_axis_tdata,
    input  wire                  s_axis_tvalid,
    input  wire                  s_axis_tlast,
    output wire                  s_axis_tready,

    input  wire                  m_axi_awready,
    input  wire                  m_axi_wready,
    input  wire                  m_axi_bvalid,
    input  wire [1:0]            m_axi_bresp,
    output wire                  m_axi_awvalid,
    output wire [ADDR_WIDTH-1:0] m_axi_awaddr,
    output wire [7:0]            m_axi_awlen,
    output wire [2:0]            m_axi_awsize,
    output wire [1:0]            m_axi_awburst,
    output wire                  m_axi_wvalid,
    output wire [DATA_WIDTH-1:0] m_axi_wdata,
    output wire [3:0]            m_axi_wstrb,
    output wire                  m_axi_wlast,
    output wire                  m_axi_bready,

    input  wire [31:0]           s2mm_ctrl,
    input  wire [ADDR_WIDTH-1:0] dst_addr,
    input  wire [31:0]           s2mm_len,
    output wire [31:0]           s2mm_status,
    output wire                  s2mm_done
);

    wire                  cmd_valid;
    wire                  cmd_ready;
    wire [ADDR_WIDTH-1:0] cmd_addr;
    wire [7:0]            cmd_len;
    wire                  write_done;
    wire                  write_error;

    wire                  align_start;
    wire [1:0]            align_offset;
    wire [31:0]           align_length;
    wire [DATA_WIDTH-1:0] aligned_data;
    wire [3:0]            aligned_strb;
    wire                  aligned_valid;
    wire                  aligned_ready;
    wire                  align_error;

    s2mm_control_fsm #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .BURST_MAX(BURST_MAX)
    ) u_control (
        .clk(clk),
        .rst_n(rst_n),
        .s2mm_ctrl(s2mm_ctrl),
        .dst_addr(dst_addr),
        .s2mm_len(s2mm_len),
        .cmd_valid(cmd_valid),
        .cmd_ready(cmd_ready),
        .cmd_addr(cmd_addr),
        .cmd_len(cmd_len),
        .write_done(write_done),
        .write_error(write_error),
        .align_start(align_start),
        .align_offset(align_offset),
        .align_length(align_length),
        .align_error(align_error),
        .s2mm_status(s2mm_status),
        .s2mm_done(s2mm_done)
    );

    s2mm_datapath #(
        .DATA_WIDTH(DATA_WIDTH)
    ) u_datapath (
        .clk(clk),
        .rst_n(rst_n),
        .start(align_start),
        .dst_offset(align_offset),
        .transfer_len(align_length),
        .s_axis_tdata(s_axis_tdata),
        .s_axis_tvalid(s_axis_tvalid),
        .s_axis_tlast(s_axis_tlast),
        .s_axis_tready(s_axis_tready),
        .data(aligned_data),
        .data_strb(aligned_strb),
        .data_valid(aligned_valid),
        .data_ready(aligned_ready),
        .active(),
        .done(),
        .error(align_error)
    );

    axi4_full_write_master #(
        .DATA_WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) u_write_master (
        .clk(clk),
        .rst_n(rst_n),
        .cmd_valid(cmd_valid),
        .cmd_ready(cmd_ready),
        .cmd_addr(cmd_addr),
        .cmd_len(cmd_len),
        .data(aligned_data),
        .data_strb(aligned_strb),
        .data_valid(aligned_valid),
        .data_ready(aligned_ready),
        .busy(),
        .done(write_done),
        .error(write_error),
        .m_axi_awaddr(m_axi_awaddr),
        .m_axi_awlen(m_axi_awlen),
        .m_axi_awsize(m_axi_awsize),
        .m_axi_awburst(m_axi_awburst),
        .m_axi_awvalid(m_axi_awvalid),
        .m_axi_awready(m_axi_awready),
        .m_axi_wdata(m_axi_wdata),
        .m_axi_wstrb(m_axi_wstrb),
        .m_axi_wlast(m_axi_wlast),
        .m_axi_wvalid(m_axi_wvalid),
        .m_axi_wready(m_axi_wready),
        .m_axi_bresp(m_axi_bresp),
        .m_axi_bvalid(m_axi_bvalid),
        .m_axi_bready(m_axi_bready)
    );

endmodule
