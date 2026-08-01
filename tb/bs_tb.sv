parameter DATA_WIDTH = 4;                    
parameter SHIFT_BITS = 2 ;

class sb_test;
    rand logic [DATA_WIDTH-1:0] data_addr;
    rand logic [SHIFT_BITS-1:0] shift_amt;

    function logic [DATA_WIDTH-1:0] expected_out();
        return data_addr >> shift_amt;
    endfunction

    function void display(logic [DATA_WIDTH-1:0] dut_out);
        if(dut_out === expected_out())
            $display("PASS | addr=%0b  shift=%0b  got=%0b  exp=%0b",
                      data_addr, shift_amt, dut_out, expected_out());
        else
            $display("FAIL | addr=%0b  shift=%0b  got=%0b  exp=%0b",
                      data_addr, shift_amt, dut_out, expected_out());
    endfunction

endclass


module tb_sb;

sb_test sb;

logic [DATA_WIDTH-1:0] data_addr;
logic [SHIFT_BITS-1:0] shift_amt;
logic [DATA_WIDTH-1:0] shifted_addr;

barrel_shifter #(
    .DATA_WIDTH(DATA_WIDTH),
    .SHIFT_BITS(SHIFT_BITS)
) dut (
    .data_address(data_addr),
    .shift_amount(shift_amt),
    .out_shifted_address(shifted_addr)
);

int pass=0;
int fail=0;

initial begin
    sb = new();

    repeat(100)begin
        if(!sb.randomize()) $fatal("RANDOMIZATION FAILED");

        data_addr = sb.data_addr;
        shift_amt = sb.shift_amt;
        #10;

        sb.display(shifted_addr);

        if(shifted_addr === sb.expected_out()) pass++;
        else fail++;
    end
    $display("----------------------------");
    $display("Passed : %0d",pass);
    $display("Failed : %0d",fail);
    $display("----------------------------");
    $finish;
end
endmodule