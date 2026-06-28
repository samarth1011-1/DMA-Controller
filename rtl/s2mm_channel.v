module s2mm_channel#(
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 32,
    parameter FIFO_DEPTH = 16,
    parameter BURST_MAX = 8
)(
    input clk,rst_n,

    // AXI-Stream slave
    input [DATA_WIDTH-1:0] s_axis_tdata,
    input s_axis_tvalid,
    input s_axis_tlast,
    output s_axis_tready,

    // AXI4-Full write master
    input m_axi_awready,
    input m_axi_wready,
    input m_axi_bvalid,
    input [1:0] m_axi_bresp,
    output m_axi_awvalid,
    output [ADDR_WIDTH-1:0] m_axi_awaddr,
    output [7:0] m_axi_awlen,
    output [2:0] m_axi_awsize,
    output [1:0] m_axi_awburst,
    output m_axi_wvalid,
    output [DATA_WIDTH-1:0] m_axi_wdata,
    output [3:0] m_axi_wstrb,
    output m_axi_wlast,
    output m_axi_bready,

    // Control / Status
    input [31:0] s2mm_ctrl,
    input [ADDR_WIDTH-1:0] dst_addr,
    input [31:0] s2mm_len,
    output [31:0] s2mm_status,
    output s2mm_done
);

// internal fifo interconnect wires
wire fifo_wr_en;
wire [DATA_WIDTH-1:0] fifo_wr_data;
wire fifo_full;
wire fifo_rd_en;
wire [DATA_WIDTH-1:0] fifo_rd_data;
wire fifo_empty;
wire [4:0] fifo_count; // 5-bit wide as it counts upto 31 bits 

// s2mm_datapath 
s2mm_datapath #(
    .DATA_WIDTH(DATA_WIDTH)
) u_datapath (
    .clk(clk),
    .rst_n(rst_n),
    .s_axis_tdata(s_axis_tdata),
    .s_axis_tvalid(s_axis_tvalid),
    .s_axis_tready(s_axis_tready),
    .s_axis_tlast(s_axis_tlast),
    .fifo_wr_en(fifo_wr_en),
    .fifo_wr_data(fifo_wr_data),
    .fifo_full(fifo_full)
);

// fifo
fifo #(
    .DATA_WIDTH(DATA_WIDTH),
    .DEPTH(FIFO_DEPTH)
) u_fifo (
    .clk(clk),
    .rst_n(rst_n),
    .wr_en(fifo_wr_en),
    .wr_data(fifo_wr_data),
    .full(fifo_full),
    .rd_en(fifo_rd_en),
    .rd_data(fifo_rd_data),
    .empty(fifo_empty),
    .count(fifo_count)
);

// control fsm
s2mm_control_fsm #(
    .DATA_WIDTH(DATA_WIDTH),
    .ADDR_WIDTH(ADDR_WIDTH),
    .BURST_MAX(BURST_MAX)
) u_fsm (
    .clk(clk),
    .rst_n(rst_n),
    .s2mm_ctrl(s2mm_ctrl),
    .dst_addr(dst_addr),
    .s2mm_len(s2mm_len),
    .fifo_empty(fifo_empty),
    .fifo_count(fifo_count),
    .fifo_rdata(fifo_rd_data),
    .fifo_rd_en(fifo_rd_en),
    .m_axi_awvalid(m_axi_awvalid),
    .m_axi_awready(m_axi_awready),
    .m_axi_awaddr(m_axi_awaddr),
    .m_axi_awlen(m_axi_awlen),
    .m_axi_awsize(m_axi_awsize),
    .m_axi_awburst(m_axi_awburst),
    .m_axi_wvalid(m_axi_wvalid),
    .m_axi_wready(m_axi_wready),
    .m_axi_wdata(m_axi_wdata),
    .m_axi_wstrb(m_axi_wstrb),
    .m_axi_wlast(m_axi_wlast),
    .m_axi_bvalid(m_axi_bvalid),
    .m_axi_bresp(m_axi_bresp),
    .m_axi_bready(m_axi_bready),
    .s2mm_status(s2mm_status),
    .s2mm_done(s2mm_done)
);

endmodule



/*
                                          fifo write        fifo write    
                                       _______|______ _________|_________
                                      |             | |                  |
AXI-Stream (axi4_lite_slave) --- s2mm_datapath -> FIFO -> s2mm_control_fsm --- AXI-Full ----> { Writes to memory }
|________________________|     |___________________________________________|
            |                                       |
        Stream input                              S2mm Channel     
      (things to put into           
          memory)                                          
*/
