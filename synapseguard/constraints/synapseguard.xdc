## =============================================================================
## SynapseGuard - board constraints
## Device : XC7A100T-CSG324 (-1)
## Board  : Digilent Nexys A7-100T (and Nexys 4 DDR)
## =============================================================================

## Clock - 100 MHz
set_property -dict { PACKAGE_PIN E3  IOSTANDARD LVCMOS33 } [get_ports CLK100MHZ]
create_clock -add -name sys_clk_pin -period 10.00 -waveform {0 5} [get_ports CLK100MHZ]

## Extreme / threshold switches (Layer 1) -> SWA triggers immediate GSR
set_property -dict { PACKAGE_PIN V10 IOSTANDARD LVCMOS33 } [get_ports {SWA[0]}]
set_property -dict { PACKAGE_PIN U11 IOSTANDARD LVCMOS33 } [get_ports {SWA[1]}]
set_property -dict { PACKAGE_PIN U12 IOSTANDARD LVCMOS33 } [get_ports {SWA[2]}]
set_property -dict { PACKAGE_PIN H6  IOSTANDARD LVCMOS33 } [get_ports {SWA[3]}]

## Gray-zone switches (SNN inputs)
set_property -dict { PACKAGE_PIN R15 IOSTANDARD LVCMOS33 } [get_ports {SWB[0]}]
set_property -dict { PACKAGE_PIN M13 IOSTANDARD LVCMOS33 } [get_ports {SWB[1]}]
set_property -dict { PACKAGE_PIN L16 IOSTANDARD LVCMOS33 } [get_ports {SWB[2]}]
set_property -dict { PACKAGE_PIN J15 IOSTANDARD LVCMOS33 } [get_ports {SWB[3]}]

## Warning LED (LED0 -> LD15 on far left)
set_property -dict { PACKAGE_PIN V11 IOSTANDARD LVCMOS33 } [get_ports LED0]

## Memory Demonstration Button and LED (GSR zeroization visualization)
## Button N17 (BTNC) sets the memory state to 1
set_property -dict { PACKAGE_PIN N17 IOSTANDARD LVCMOS33 } [get_ports BTN_MEM]
## LED N15 (LED16_R) reflects memory state; cleared only by GSR / reset
set_property -dict { PACKAGE_PIN N15 IOSTANDARD LVCMOS33 } [get_ports LED_MEM]

## 8 Membrane Potential Accumulation LEDs (LD7..LD0 from U16 on left to H17 on right)
set_property -dict { PACKAGE_PIN U16 IOSTANDARD LVCMOS33 } [get_ports {LED_VMEM[7]}]
set_property -dict { PACKAGE_PIN U17 IOSTANDARD LVCMOS33 } [get_ports {LED_VMEM[6]}]
set_property -dict { PACKAGE_PIN V17 IOSTANDARD LVCMOS33 } [get_ports {LED_VMEM[5]}]
set_property -dict { PACKAGE_PIN R18 IOSTANDARD LVCMOS33 } [get_ports {LED_VMEM[4]}]
set_property -dict { PACKAGE_PIN N14 IOSTANDARD LVCMOS33 } [get_ports {LED_VMEM[3]}]
set_property -dict { PACKAGE_PIN J13 IOSTANDARD LVCMOS33 } [get_ports {LED_VMEM[2]}]
set_property -dict { PACKAGE_PIN K15 IOSTANDARD LVCMOS33 } [get_ports {LED_VMEM[1]}]
set_property -dict { PACKAGE_PIN H17 IOSTANDARD LVCMOS33 } [get_ports {LED_VMEM[0]}]

## Asynchronous inputs are synchronized in RTL (2-FF, ASYNC_REG)
set_false_path -from [get_ports {SWA[*]}]
set_false_path -from [get_ports {SWB[*]}]
set_false_path -from [get_ports BTN_MEM]

## Static LED outputs
set_false_path -to   [get_ports LED0]
set_false_path -to   [get_ports LED_MEM]
set_false_path -to   [get_ports {LED_VMEM[*]}]

## Configuration bank voltage
set_property CFGBVS VCCO        [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]
