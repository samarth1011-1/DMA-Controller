module s2mm_datapath #(
    parameter DATA_WIDTH = 32
)(
    input clk,
    input rst_n,

    // AXI-Stream slave
    input [DATA_WIDTH-1:0] s_axis_tdata,
    input s_axis_tvalid,
    output reg s_axis_tready,
    input s_axis_tlast,    // ts not used anywhere

    // FIFO write interface
    output reg fifo_wr_en,
    output reg [DATA_WIDTH-1:0] fifo_wr_data,
    input fifo_full
);

/*
a transfer happens only when data is available and the FIFO is not full
so we use !fifo_full directly instead of delayed ready signal which avoids 
1-cycle delay and prevents wrong transfers
*/

wire axis_handshake = s_axis_tvalid && !fifo_full;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        s_axis_tready <= 1'b0;
        fifo_wr_en <= 1'b0;
        fifo_wr_data <= {DATA_WIDTH{1'b0}};
    end else begin
            // tready: tell upstream whether we can accept next cycle
        s_axis_tready <= !fifo_full;
            // wr_en: mirrors the handshake — high for exactly one cycle
        fifo_wr_en <= axis_handshake;
            // wr_data: captured only when a handshake actually occurs
        if(axis_handshake) fifo_wr_data <= s_axis_tdata;
    end
    end

endmodule