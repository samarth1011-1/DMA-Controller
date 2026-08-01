# synthesis & bitstream Script for fpga
# cmd: vivado -mode batch -source build_zynq_bitstream.tcl
source create_zynq_project.tcl
set_property top zynq_dma_bd_wrapper [current_fileset]
update_compile_order -fileset sources_1
puts "1. Running Synthesis"
launch_runs synth_1 -jobs 4
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] ne "100%"} {
    puts "SYNTHESIS FAILED"
    exit 1
}
puts "2. Running Implementation"
launch_runs impl_1 -jobs 4
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] ne "100%"} {
    puts "IMPLEMENTATION FAILED"
    exit 1
}
puts "3. Generating Bitstream"
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
puts "BITSTREAM BUILD COMPLETED SUCCESSFULLY"
puts "bitstream path:"
puts "[file normalize ./vivado_blackboard_hw/dma_blackboard_hw.runs/impl_1/zynq_dma_bd_wrapper.bit]"
