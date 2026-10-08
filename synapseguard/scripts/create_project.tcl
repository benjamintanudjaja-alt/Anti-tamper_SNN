# =============================================================================
# SynapseGuard - Vivado project creation
# Usage (from the synapseguard/ directory):
#   vivado -mode batch -source scripts/create_project.tcl
# or in the Vivado Tcl console:
#   cd <path>/synapseguard ; source scripts/create_project.tcl
# =============================================================================
set root [file normalize [file dirname [info script]]/..]
set proj synapseguard

create_project $proj $root/vivado -part xc7a100tcsg324-1 -force

# RTL
add_files -fileset sources_1 [glob $root/rtl/*.vhd]
set_property top synapseguard_top [get_filesets sources_1]

# Constraints
add_files -fileset constrs_1 $root/constraints/synapseguard.xdc

# Testbenches
add_files -fileset sim_1 [glob $root/tb/*.vhd]

# Testbenches use VHDL-2008 (external names, std.env.finish)
set_property file_type {VHDL 2008} [get_files -of_objects [get_filesets sources_1] *.vhd]
set_property file_type {VHDL 2008} [get_files -of_objects [get_filesets sim_1] *.vhd]

set_property top tb_synapseguard_top [get_filesets sim_1]
set_property top_lib xil_defaultlib  [get_filesets sim_1]
set_property -name {xsim.simulate.runtime} -value {all} -objects [get_filesets sim_1]

update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

puts "SynapseGuard project created in $root/vivado"
