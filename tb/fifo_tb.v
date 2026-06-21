`timescale 1ns/1ps
module fifo_tb;
parameter DATA_WIDTH = 32;
parameter DEPTH      = 16;
reg clk,rst_n,wr_en,rd_en;
reg [DATA_WIDTH-1:0] wr_data;
wire [DATA_WIDTH-1:0] rd_data;
wire full;
wire empty;
wire [$clog2(DEPTH+1)-1:0] count;
fifo #(
    .DATA_WIDTH(DATA_WIDTH),
    .DEPTH(DEPTH)
) dut (.clk(clk),.rst_n(rst_n),.wr_en(wr_en),.wr_data(wr_data),
    .rd_en(rd_en),.rd_data(rd_data),.full(full),.empty(empty),.count(count)
);
initial begin
    clk = 0;
    forever #5 clk = ~clk;
end
initial begin
    $dumpfile("fifo.vcd");
    $dumpvars(0, fifo_tb);
end

task write_fifo;
    input [DATA_WIDTH-1:0] data;
begin
    @(posedge clk);
    wr_en   <= 1;
    wr_data <= data;
    @(posedge clk);
    wr_en   <= 0;
end
endtask

task read_fifo;
begin
    @(posedge clk);
    rd_en <= 1;
    @(posedge clk);
    rd_en <= 0;
end
endtask

integer i;

initial begin
    rst_n   = 0;
    wr_en   = 0;
    rd_en   = 0;
    wr_data = 0;
    repeat(3) @(posedge clk);
    rst_n = 1;

    $display("\n RESET COMPLETE : ");
    #1;
    if(empty !== 1)
        $display("FAIL: EMPTY should be 1 after reset");
    if(full !== 0)
        $display("FAIL: FULL should be 0 after reset");
    if(count !== 0)
        $display("FAIL: COUNT should be 0 after reset");

    $display("\n FILL FIFO : ");
    for(i=0;i<DEPTH;i=i+1)
        write_fifo(i);
    #1;

    $display("Count = %0d", count);
    if(full !== 1)
        $display("FAIL: FULL not asserted");
    if(count !== DEPTH)
        $display("FAIL: COUNT incorrect");

    $display("\n WRITE WHEN FULL : ");
    write_fifo(32'hAAEEEAAA);
    #1;
    $display("Count = %0d", count);
    if(count !== DEPTH)
        $display("FAIL: Count changed while full");

    $display("\n READ BACK : ");
    for(i=0;i<DEPTH;i=i+1) begin
        read_fifo();
        #1;
        if(rd_data !== i)
            $display(
                "FAIL: Expected %0d Got %0d",
                i,
                rd_data
            );
        else
            $display(
                "PASS: Read %0d",
                rd_data
            );
    end
    #1;
    if(empty !== 1)
        $display("FAIL: EMPTY not asserted");

    if(count !== 0)
        $display("FAIL: COUNT not zero");

    $display("\nREAD WHEN EMPTY");
    read_fifo();
    #1;
    if(count !== 0)
        $display("FAIL: Count changed while empty");

    $display("\n ORDER TEST : ");
    write_fifo(32'h11);
    write_fifo(32'h22);
    write_fifo(32'h33);
    write_fifo(32'h44);
    read_fifo();
    #1;
    if(rd_data !== 32'h11)
        $display("FAIL");

    read_fifo();
    #1;
    if(rd_data !== 32'h22)
        $display("FAIL");

    read_fifo();
    #1;
    if(rd_data !== 32'h33)
        $display("FAIL");
    read_fifo();
    #1;
    if(rd_data !== 32'h44)
        $display("FAIL");

    $display("\n SIMULTANEOUS R/W : ");
    write_fifo(32'hAA);
    write_fifo(32'hBB);
    @(posedge clk);
    wr_en   <= 1;
    rd_en   <= 1;
    wr_data <= 32'hCC;
    @(posedge clk);
    wr_en <= 0;
    rd_en <= 0;
    #1;$display("Count = %0d", count);
    #20;$display("\n TEST COMPLETE : ");
    $finish;
end
endmodule