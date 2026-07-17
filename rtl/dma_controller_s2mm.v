module dma_controller_s2mm #(
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 32,
    parameter FIFO_DEPTH = 16,
    parameter BURST_MAX  = 8
)(
    input wire clk,
    input wire rst_n,

    input wire [31:0] s_axi_awaddr,
    input wire s_axi_awvalid,
    output wire s_axi_awready,
    input wire [31:0] s_axi_wdata,
    input wire [3:0] s_axi_wstrb,
    input wire s_axi_wvalid,
    output wire s_axi_wready,
    output wire [1:0] s_axi_bresp,
    output wire s_axi_bvalid,
    input wire s_axi_bready,
    input wire [31:0] s_axi_araddr,
    input wire s_axi_arvalid,
    output wire s_axi_arready,
    output wire [31:0] s_axi_rdata,
    output wire [1:0] s_axi_rresp,
    output wire s_axi_rvalid,
    input wire s_axi_rready,

    // AXI4-Stream input
    input wire [DATA_WIDTH-1:0] s_axis_tdata,
    input wire s_axis_tvalid,
    input wire s_axis_tlast,
    output wire s_axis_tready,

    // AXI4-Full write master
    output wire [ADDR_WIDTH-1:0] m_axi_awaddr,
    output wire [7:0] m_axi_awlen,
    output wire [2:0] m_axi_awsize,
    output wire [1:0] m_axi_awburst,
    output wire m_axi_awvalid,
    output wire [DATA_WIDTH-1:0] m_axi_wdata,
    output wire [3:0] m_axi_wstrb,
    output wire m_axi_wlast,
    output wire m_axi_wvalid,
    output wire m_axi_bready,
    input wire m_axi_bvalid,
    input wire m_axi_wready,
    input wire [1:0] m_axi_bresp,
    input wire m_axi_awready,

    // Direct status outputs
    output wire [31:0] s2mm_status,
    output wire s2mm_done
);

    wire [31:0] mm2s_src_addr_unused;
    wire [31:0] mm2s_length_unused;
    wire [31:0] mm2s_control_unused;
    wire [31:0] s2mm_dst_addr;
    wire [31:0] s2mm_length;
    wire [31:0] s2mm_control;

  axi4_lite_slave DUT (
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
        .mm2s_src_addr(mm2s_src_addr_unused),
        .mm2s_length(mm2s_length_unused),
        .mm2s_control(mm2s_control_unused),
        .s2mm_dst_addr(s2mm_dst_addr),
        .s2mm_length(s2mm_length),
        .s2mm_control(s2mm_control),
        .mm2s_status(32'd0),
        .s2mm_status(s2mm_status)
    );

    s2mm_channel #(
        .DATA_WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH),
        .FIFO_DEPTH(FIFO_DEPTH),
        .BURST_MAX(BURST_MAX)
    ) DUT1 (
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
        .s2mm_ctrl(s2mm_control),
        .dst_addr(s2mm_dst_addr[ADDR_WIDTH-1:0]),
        .s2mm_len(s2mm_length),
        .s2mm_status(s2mm_status),
        .s2mm_done(s2mm_done)
    );

endmodule
