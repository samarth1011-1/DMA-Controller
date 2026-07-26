`timescale 1ns/1ps

module dma_controller_dual #(
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 32,
    parameter BURST_MAX  = 16
)(
    input  wire                  clk,
    input  wire                  rst_n,

    input  wire [31:0]           s_axi_awaddr,
    input  wire                  s_axi_awvalid,
    output wire                  s_axi_awready,
    input  wire [31:0]           s_axi_wdata,
    input  wire [3:0]            s_axi_wstrb,
    input  wire                  s_axi_wvalid,
    output wire                  s_axi_wready,
    output wire [1:0]            s_axi_bresp,
    output wire                  s_axi_bvalid,
    input  wire                  s_axi_bready,
    input  wire [31:0]           s_axi_araddr,
    input  wire                  s_axi_arvalid,
    output wire                  s_axi_arready,
    output wire [31:0]           s_axi_rdata,
    output wire [1:0]            s_axi_rresp,
    output wire                  s_axi_rvalid,
    input  wire                  s_axi_rready,

    input  wire [DATA_WIDTH-1:0] s_axis_tdata,
    input  wire                  s_axis_tvalid,
    input  wire                  s_axis_tlast,
    output wire                  s_axis_tready,

    output wire [DATA_WIDTH-1:0] m_axis_tdata,
    output wire [3:0]            m_axis_tkeep,
    output wire                  m_axis_tvalid,
    input  wire                  m_axis_tready,
    output wire                  m_axis_tlast,

    output wire [ADDR_WIDTH-1:0] m_axi_awaddr,
    output wire [7:0]            m_axi_awlen,
    output wire [2:0]            m_axi_awsize,
    output wire [1:0]            m_axi_awburst,
    output wire                  m_axi_awvalid,
    input  wire                  m_axi_awready,
    output wire [DATA_WIDTH-1:0] m_axi_wdata,
    output wire [3:0]            m_axi_wstrb,
    output wire                  m_axi_wlast,
    output wire                  m_axi_wvalid,
    input  wire                  m_axi_wready,
    input  wire [1:0]            m_axi_bresp,
    input  wire                  m_axi_bvalid,
    output wire                  m_axi_bready,

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

    output wire [31:0]           mm2s_status,
    output wire [31:0]           s2mm_status,
    output wire                  mm2s_done,
    output wire                  s2mm_done
);

    wire [31:0] mm2s_src_addr;
    wire [31:0] mm2s_length;
    wire [31:0] mm2s_control;
    wire [31:0] s2mm_dst_addr;
    wire [31:0] s2mm_length;
    wire [31:0] s2mm_control;
    wire mm2s_grant;
    wire s2mm_grant;

    wire [31:0] mm2s_channel_control = {
        mm2s_control[31:2], mm2s_control[1], mm2s_grant
    };
    wire [31:0] s2mm_channel_control = {
        s2mm_control[31:2], s2mm_control[1], s2mm_grant
    };

    axi4_lite_slave u_registers (
        .clk(clk),
        .rst_n(rst_n),
        .s_axi_awaddr(s_axi_awaddr),
        .s_axi_awvalid(s_axi_awvalid),
        .s_axi_awready(s_axi_awready),
        .s_axi_wdata(s_axi_wdata),
        .s_axi_wstrb(s_axi_wstrb),
        .s_axi_wvalid(s_axi_wvalid),
        .s_axi_wready(s_axi_wready),
        .s_axi_bresp(s_axi_bresp),
        .s_axi_bvalid(s_axi_bvalid),
        .s_axi_bready(s_axi_bready),
        .s_axi_araddr(s_axi_araddr),
        .s_axi_arvalid(s_axi_arvalid),
        .s_axi_arready(s_axi_arready),
        .s_axi_rdata(s_axi_rdata),
        .s_axi_rresp(s_axi_rresp),
        .s_axi_rvalid(s_axi_rvalid),
        .s_axi_rready(s_axi_rready),
        .mm2s_src_addr(mm2s_src_addr),
        .mm2s_length(mm2s_length),
        .mm2s_control(mm2s_control),
        .s2mm_dst_addr(s2mm_dst_addr),
        .s2mm_length(s2mm_length),
        .s2mm_control(s2mm_control),
        .mm2s_status(mm2s_status),
        .s2mm_status(s2mm_status)
    );

    arbitration_unit #(
        .ALLOW_SIMULTANEOUS(1)
    ) u_start_policy (
        .clk(clk),
        .rst_n(rst_n),
        .mm2s_request(mm2s_control[0]),
        .s2mm_request(s2mm_control[0]),
        .mm2s_busy(mm2s_status[0]),
        .s2mm_busy(s2mm_status[0]),
        .mm2s_grant(mm2s_grant),
        .s2mm_grant(s2mm_grant)
    );

    mm2s_channel #(
        .DATA_WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH),
        .BURST_MAX(BURST_MAX)
    ) u_mm2s (
        .clk(clk),
        .rst_n(rst_n),
        .m_axis_tdata(m_axis_tdata),
        .m_axis_tkeep(m_axis_tkeep),
        .m_axis_tvalid(m_axis_tvalid),
        .m_axis_tready(m_axis_tready),
        .m_axis_tlast(m_axis_tlast),
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
        .m_axi_rready(m_axi_rready),
        .mm2s_ctrl(mm2s_channel_control),
        .src_addr(mm2s_src_addr[ADDR_WIDTH-1:0]),
        .mm2s_len(mm2s_length),
        .mm2s_status(mm2s_status),
        .mm2s_done(mm2s_done)
    );

    s2mm_channel #(
        .DATA_WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH),
        .BURST_MAX(BURST_MAX)
    ) u_s2mm (
        .clk(clk),
        .rst_n(rst_n),
        .s_axis_tdata(s_axis_tdata),
        .s_axis_tvalid(s_axis_tvalid),
        .s_axis_tlast(s_axis_tlast),
        .s_axis_tready(s_axis_tready),
        .m_axi_awready(m_axi_awready),
        .m_axi_wready(m_axi_wready),
        .m_axi_bvalid(m_axi_bvalid),
        .m_axi_bresp(m_axi_bresp),
        .m_axi_awvalid(m_axi_awvalid),
        .m_axi_awaddr(m_axi_awaddr),
        .m_axi_awlen(m_axi_awlen),
        .m_axi_awsize(m_axi_awsize),
        .m_axi_awburst(m_axi_awburst),
        .m_axi_wvalid(m_axi_wvalid),
        .m_axi_wdata(m_axi_wdata),
        .m_axi_wstrb(m_axi_wstrb),
        .m_axi_wlast(m_axi_wlast),
        .m_axi_bready(m_axi_bready),
        .s2mm_ctrl(s2mm_channel_control),
        .dst_addr(s2mm_dst_addr[ADDR_WIDTH-1:0]),
        .s2mm_len(s2mm_length),
        .s2mm_status(s2mm_status),
        .s2mm_done(s2mm_done)
    );

endmodule
