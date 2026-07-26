if {$tcl_platform(platform) eq "windows"} {
    set root_dir [string trim [exec cmd /c cd]]
} else {
    set root_dir [pwd]
}

set build_dir [file join $::env(TEMP) dma_controller_regression]
file mkdir $build_dir

# idk if this will store the files in the correct place
# change the code if no files pop up
set tests [list \
    [list tb_axi4_lite_slave [list \
        tb/axi4_test.v \
        rtl/axi4_lite_slave.v]] \
    [list fifo_tb [list \
        tb/fifo_tb.v \
        rtl/fifo.v]] \
    [list tb_axi4_full_read_master [list \
        tb/tb_axi4_full_read_master.v \
        rtl/axi4_full_read_master.v]] \
    [list tb_axi4_full_write_master [list \
        tb/tb_axi4_full_write_master.v \
        rtl/axi4_full_write_master.v]] \
    [list tb_s2mm_datapath [list \
        tb/tb_s2mm_datapath.v \
        rtl/s2mm_datapath.v \
        rtl/barrel_shifter.v]] \
    [list tb_s2mm_control_fsm [list \
        tb/tb_s2mm_control_fsm.v \
        rtl/s2mm_control_fsm.v]] \
    [list tb_s2mm_channel [list \
        tb/tb_s2mm_channel.v \
        rtl/s2mm_channel.v \
        rtl/s2mm_control_fsm.v \
        rtl/s2mm_datapath.v \
        rtl/axi4_full_write_master.v \
        rtl/barrel_shifter.v]] \
    [list tb_dma_controller_s2mm [list \
        tb/tb_dma_controller_s2mm.v \
        rtl/dma_controller_s2mm.v \
        rtl/axi4_lite_slave.v \
        rtl/s2mm_channel.v \
        rtl/s2mm_control_fsm.v \
        rtl/s2mm_datapath.v \
        rtl/axi4_full_write_master.v \
        rtl/barrel_shifter.v]] \
    [list tb_alignment_matrix [list \
        tb/tb_alignment_matrix.v \
        rtl/s2mm_datapath.v \
        rtl/mm2s_datapath.v \
        rtl/barrel_shifter.v]] \
    [list tb_dma_controller_dual [list \
        tb/tb_dma_controller_dual.v \
        rtl/dma_controller_dual.v \
        rtl/axi4_lite_slave.v \
        rtl/arbitration_unit.v \
        rtl/mm2s_channel.v \
        rtl/mm2s_control_fsm.v \
        rtl/mm2s_datapath.v \
        rtl/axi4_full_read_master.v \
        rtl/s2mm_channel.v \
        rtl/s2mm_control_fsm.v \
        rtl/s2mm_datapath.v \
        rtl/axi4_full_write_master.v \
        rtl/barrel_shifter.v]]]

set failures 0

foreach test $tests {
    lassign $test top relative_sources
    set sources {}
    foreach source $relative_sources {
        lappend sources [file join $root_dir $source]
    }

    set executable [file join $build_dir "${top}.out"]
    set compile_command [concat \
        [list iverilog -g2012 -Wall -s $top -o $executable] \
        $sources]

    puts "\n=== $top ==="
    if {[catch {exec {*}$compile_command 2>@1} compile_output]} {
        puts $compile_output
        puts "COMPILE FAIL: $top"
        incr failures
        continue
    }
    if {$compile_output ne ""} {
        puts $compile_output
    }

    cd $build_dir
    set simulation_failed [catch \
        {exec vvp $executable 2>@1} simulation_output]
    puts $simulation_output

    if {$simulation_failed ||
        [regexp {(^|\n)(\[FAIL\]|FAIL:|TIMEOUT)} $simulation_output] ||
        [regexp {[1-9][0-9]* TEST\(S\) FAILED} $simulation_output]} {
        puts "SIMULATION FAIL: $top"
        incr failures
    } else {
        puts "REGRESSION PASS: $top"
    }
}

if {$failures != 0} {
    error "$failures regression test(s) failed"
}

puts "\nALL REGRESSION TESTS PASSED"
