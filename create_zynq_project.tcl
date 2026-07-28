# vivado & block design script for Blackboard 
# board: RealDigital Blackboard (Xilinx XC7007S ZYNQ)
# target part: xc7z007sclg400-1
set project_name "dma_blackboard_hw"
set project_dir "./vivado_blackboard_hw"
set part_number "xc7z007sclg400-1"
close_project -quiet
create_project -force $project_name $project_dir -part $part_number
add_files -norecurse [glob ./rtl/*.v]
update_compile_order -fileset sources_1
create_bd_design "zynq_dma_bd"
create_bd_cell -type ip -vlnv xilinx.com:ip:processing_system7:5.5 ps7_0
apply_bd_automation -rule xilinx.com:bd_rule:processing_system7 -config {make_external "FIXED_IO, DDR" apply_axi_preset "1" Master "Disable" Slave "Disable" } [get_bd_cells ps7_0]
set_property -dict [list CONFIG.PCW_USE_S_AXI_HP0 {1}] [get_bd_cells ps7_0]
create_bd_cell -type module -reference dma_controller_dual dma_0
connect_bd_intf_net [get_bd_intf_pins dma_0/m_axis] [get_bd_intf_pins dma_0/s_axis]
apply_bd_automation -rule xilinx.com:bd_rule:axi4 -config { Slave "/ps7_0/S_AXI_HP0" intc_ip "Auto" Master "/dma_0/m_axi" clk "Auto" } [get_bd_intf_pins ps7_0/S_AXI_HP0]
apply_bd_automation -rule xilinx.com:bd_rule:axi4 -config { Master "/ps7_0/M_AXI_GP0" intc_ip "Auto" Slave "/dma_0/s_axi" clk "Auto" } [get_bd_intf_pins dma_0/s_axi]
assign_bd_address
validate_bd_design
save_bd_design
make_wrapper -files [get_files ./vivado_blackboard_hw/dma_blackboard_hw.srcs/sources_1/bd/zynq_dma_bd/zynq_dma_bd.bd] -top
add_files -norecurse ./vivado_blackboard_hw/dma_blackboard_hw.srcs/sources_1/bd/zynq_dma_bd/hdl/zynq_dma_bd_wrapper.v
set_property top zynq_dma_bd_wrapper [current_fileset]
puts "vivado project created"
puts "project name : $project_name"
puts "target device: XC7007S ($part_number)"
puts "top module   : zynq_dma_bd_wrapper"
