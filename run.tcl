set rtl_files [glob -nocomplain rtl/*.v]

# for any specific file change rtl/*.v to rtl/<file_name>.v

set tb_files [glob -nocomplain tb/*.v]

# for any specific file, change tb/*.v to tb/<file_name>.v

set all_files [concat $rtl_files $tb_files]

eval exec iverilog -o output $all_files

set sim_out [exec vvp output]

puts $sim_out

