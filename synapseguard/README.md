# SynapseGuard — Single-Neuron LIF SNN Anti-Tamper PoC

## FPGA target
* Device: **XC7A100T-CSG324-1** (Artix-7)
* Clock: 100 MHz on E3. No MMCM/PLL is used. The SNN timestep is a 1 kHz clock enable.
* Pins follow FSD §32/33 exactly. Those pins match the **Nexys A7-100T** board:

| Port | Pin | Nexys A7 label | Meaning |
|-|-|-|-|
| `SWA[0..3]` | V10, U11, U12, H6 | SW15, SW14, SW13, SW12 | Extreme V / T / Clk / Mem -> Direct GSR |
| `SWB[0..3]` | R15, M13, L16, J15 | SW3, SW2, SW1, SW0 | Gray-zone V / T / Clk / Mem -> SNN |
| `LED0` | V11 | LD15 | SNN warning (latched on 1st spike) |
| `BTN_MEM` | N17 | BTNC | Pushbutton: set memory latch to 1 |
| `LED_MEM` | N15 | LED16_R | Tri-color LED (Red): memory status (cleared by GSR) |
| `LED_VMEM[7..0]` | U16..H17 | LD7..LD0 | 8-LED bargraph for membrane potential accumulation |

## Structure
```
rtl/  synapseguard_top, input_conditioner, threshold_detector,
      gray_event_encoder, lif_neuron, penalty_gsr
tb/   tb_pkg, tb_lif_neuron, tb_synapseguard_top
constraints/synapseguard.xdc
scripts/create_project.tcl
```

## Vivado project setup
```
cd synapseguard
vivado -mode batch -source scripts/create_project.tcl
```
Then open `vivado/synapseguard.xpr` and run Synthesis → Implementation → Generate Bitstream.
All files are set to **VHDL 2008**. The testbenches need VHDL-2008 for external names and `std.env.finish`.

## Simulation
**Vivado:** *Run Simulation → Behavioral*. The default top is `tb_synapseguard_top`.
To run the unit test, set `tb_lif_neuron` as the sim top. Look for:
```
TB_SYNAPSEGUARD_TOP: PASS
TB_LIF_NEURON: PASS
```
**GHDL (optional):**
```
ghdl -a --std=08 rtl/*.vhd tb/tb_pkg.vhd tb/tb_lif_neuron.vhd tb/tb_synapseguard_top.vhd
ghdl -r --std=08 tb_lif_neuron
ghdl -r --std=08 tb_synapseguard_top
```
The system testbench passes `CLK_FREQ_HZ = 100_000` so that 1 SNN tick = 1 µs (behavior in ticks is unchanged).
It also passes `USE_STARTUPE2 = false`, so the GSR penalty is modelled as an internal synchronous reset.

## Demo procedure (board)
1. Program the board. All switches start down. LED LD15 is off.
2. **Scenario A (Layer 1):** flip SW15 (SWA0). `threshold_alert` goes high. LD15 stays off because no SNN spike occurred.
3. **Scenario B:** flip SW3 (SWB0, voltage) up. That is one event (+3), so no spike.
4. **Scenario C:** with everything down, flip SWB0, SWB1, then SWB3 up (3+2+5 = 10). The neuron fires and **LD15 turns on**.
5. Put all SWB down and wait about 50 ms. Then flip SWB0 + SWB1 + SWB3 up together (10). That is the second spike, so the **GSR penalty** fires: the FPGA state is reset and LD15 turns off.
6. Switches still up after the GSR do not re-trigger. Each one must go down and back up first, so there is no reset loop.

## Key generics (`synapseguard_top`)
`SNN_TICK_HZ=1000`, `DEBOUNCE_MS=20`, `MEMBRANE_WIDTH=8`, `WEIGHT_*=3/2/4/5`,
`SPIKE_THRESHOLD=10`, `RESET_POTENTIAL=0`, `LEAK_SHIFT=3`, `USE_SNN=true`,
`SPIKES_FOR_PENALTY=2`, `USE_STARTUPE2=true`, `CLK_FREQ_HZ=100_000_000`.
With `USE_SNN=false` (baseline), LED0 shows `threshold_alert`.
