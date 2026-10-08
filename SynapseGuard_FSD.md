# Functional Specification Document (FSD)

## SynapseGuard — Single-Neuron LIF SNN Proof of Concept

**Target FPGA:** Digilent Arty A7-100T  
**FPGA Device:** XC7A100T-CSG324  
**HDL:** VHDL  
**Toolchain:** AMD Vivado  
**Architecture:** 4 extreme inputs + 4 gray-zone inputs → single LIF neuron → spike → Warning + GSR

\---

## 1\. Purpose

Implement a single-neuron Spiking Neural Network (SNN) on an Artix-7 FPGA to demonstrate that combinations and repeated patterns of several tampering-related parameters can be detected even when each individual parameter remains in a gray zone.

The four simulated parameters are:

1. Voltage
2. Temperature
3. Clock
4. Memory Integrity

The parameters are **not read from physical sensors** in this proof of concept. They are simulated using physical FPGA inputs.

The PoC uses:

* 4 onboard slide switches for extreme/threshold conditions.
* 4 onboard slide switches for gray-zone conditions.
* One LIF neuron.
* Manual input hand-crafted weights.
* A configurable leak and firing threshold.
* LED warning output after 1 spike.
* GSR penalty response through `STARTUPE2` after 2 spikes.

The SNN is a **secondary detection layer**. The first layer represents conventional threshold detection.



The FSD is intended to be consumed by an AI code-generation system.



The AI shall generate:

1\. Complete synthesizable VHDL RTL.

2\. Complete functional VHDL testbench.

3\. Board-level XDC constraints.

4\. Simulation-ready project structure.

5\. Testbench stimulus and self-checking assertions.



The generated testbench shall not be a placeholder or empty simulation wrapper.

It shall actively verify the functional behavior of the RTL.

\---

## 2\. System Architecture

```text
                   EXTREME / THRESHOLD
                 +---------------------+
SWA0 - Voltage -->|                     |
SWA1 - Temp ----->| Layer 1             |-----------------------+
SWA2 - Clock ---->| Threshold Detector  |                       |
SWA3 - Memory --->|                     |                       |
                 +---------------------+                       |
                                                               | Direct GSR
                    GRAY-ZONE EVENTS                           | (No Warning LED)
                 +---------------------+                       |
SWB0 - Voltage -->|                     |                       |
SWB1 - Temp ----->| Event / Spike       |                       |
SWB2 - Clock ---->| Encoding            |                       |
SWB3 - Memory --->|                     |                       |
                 +----------+----------+                       |
                            |                                  |
                            v                                  |
                    +---------------+                          |
                    | Hand-crafted  |                          |
                    | Synaptic      |                          |
                    | Weights       |                          |
                    +-------+-------+                          |
                            |                                  |
                            v                                  |
                    +---------------+                          |
                    | Single LIF    |                          |
                    | Neuron        |                          |
                    |               |---+                      |
                    | Vmem          |   |                      |
                    | Leak          |   v                      |
                    | Threshold     |  LED_VMEM[7:0] (U16..H17)|
                    +-------+-------+  (Accumulation Bargraph) |
                            |                                  |
                         snn\_spike                             |
                            |                                  |
                  +---------+---------+                        |
                  |                   |                        |
                  v                   v                        |
             WARNING LED           PENALTY <-------------------+
             LED0 (V11)           STARTUPE2
            (1st Spike)               |
                                      v
                                     GSR (2nd Spike or SWA=1)
                                      |
       +------------------------------+
       v
   LED_MEM (N15) & Memory Register Cleared
   (BTN_MEM / N17 sets memory latch)
```

The Layer 1 threshold detector triggers immediate GSR penalty upon any extreme input (SWA = 1) without asserting warning. Gray-zone events (SWB) are processed by the SNN (1st spike -> warning LED0; 2nd spike -> GSR penalty).


\---





## 3\. Hardware Target

The implementation MUST target:

```text
Board:   Digilent Arty A7-100T
FPGA:    XC7A100T
Package: CSG324
Family:  Artix-7
```

The design MUST use the official Arty A7-100T pin mapping.

\---

## 4\. Top-Level Entity

The top-level VHDL entity MUST be:

```vhdl
synapseguard\_top
```

Top-level interface:

```vhdl
entity synapseguard\_top is
    port (
        CLK100MHZ : in  std\_logic;
        SWA       : in  std\_logic\_vector(3 downto 0);
        SWB       : in  std\_logic\_vector(3 downto 0);
        BTN_MEM   : in  std\_logic := '0';
        LED0      : out std\_logic;
        LED_MEM   : out std\_logic;
        LED_VMEM  : out std\_logic\_vector(7 downto 0)
    );
end entity;
```

External ports comprise:
* `CLK100MHZ`: 100 MHz oscillator
* `SWA[3:0]`: 4 slide switches for extreme condition detection (triggers immediate GSR)
* `SWB[3:0]`: 4 slide switches for gray-zone condition detection (feeds LIF SNN)
* `BTN_MEM`: Pushbutton (N17 / BTNC) to set memory demo state to 1
* `LED0`: Warning LED (V11 / LD15) latched on 1st SNN spike
* `LED_MEM`: Memory status LED (N15 / LED16_R) cleared only by GSR zeroization
* `LED_VMEM[7:0]`: 8-LED bargraph (U16..H17 / LD7..LD0) displaying LIF membrane potential accumulation


The design MUST NOT require:

* UART
* DDR3
* Ethernet
* AXI
* Processor
* XADC
* Seven-segment display
* RGB LED
* External clock
* External reset button

\---

## 5\. Physical Input Mapping

### 5.1 Extreme Inputs

The four onboard slide switches represent extreme conditions.

|FPGA Input|Parameter|Meaning|
|-|-|-|
|`SWA\\\[0]`|Voltage|Extreme voltage|
|`SWA\\\[1]`|Temperature|Extreme temperature|
|`SWA\\\[2]`|Clock|Extreme clock|
|`SWA\\\[3]`|Memory Integrity|Extreme memory integrity anomaly|

Input convention:

```text
0 = normal
1 = extreme anomaly
```

Extreme inputs go directly to the threshold detector.

They MUST NOT be used as SNN inputs in this PoC.

\---

### 5.2 Gray-Zone Inputs

The FOUR SWB pins represent gray-zone conditions.

|FPGA Input|Parameter|Meaning|
|-|-|-|
|`SWB\\\[0]`|Voltage|Gray-zone voltage|
|`SWB\\\[1]`|Temperature|Gray-zone temperature|
|`SWB\\\[2]`|Clock|Gray-zone clock|
|`SWB\\\[3]`|Memory Integrity|Gray-zone memory integrity|

Input convention:

```text
0 = normal
1 = gray-zone condition active
```

Gray-zone inputs are converted into events/spikes and then processed by the LIF neuron.

\---

## 6\. Clock

The Arty A7-100T onboard clock is:

```text
CLK100MHZ = 100 MHz
```

The design MUST use this clock as the primary FPGA clock.

Clock constraint:

```text
PACKAGE\\\_PIN E3
IOSTANDARD LVCMOS33
```

Clock period:

```text
10 ns
```

The SNN MUST NOT use a separate generated clock.

The SNN timestep MUST be implemented using a **clock enable**.

\---

## 7\. SNN Processing Rate

Default SNN timestep:

```text
SNN\\\_TICK\\\_HZ = 1000 Hz
```

Therefore:

```text
FPGA clock = 100 MHz
SNN tick   = 1 kHz
```

The clock-enable divider is:

```text
100,000 FPGA clock cycles = 1 SNN timestep
```

Conceptually:

```vhdl
if counter = 99\\\_999 then
    counter  <= 0;
    snn\\\_tick <= '1';
else
    counter  <= counter + 1;
    snn\\\_tick <= '0';
end if;
```

The SNN state MUST only be updated when:

```text
snn\\\_tick = '1'
```

Do not create a new physical clock for the SNN.

\---

## 8\. Physical Input Conditioning

All physical inputs MUST be synchronized to `CLK100MHZ`.

At minimum, use a two-flip-flop synchronizer for external asynchronous inputs.

Gray-zone switches MUST also be debounced.

Default:

```text
DEBOUNCE\\\_MS = 20
```

At 1-kHz SNN sampling this corresponds to:

```text
20 SNN ticks
```

The debounce implementation may use a counter.

The purpose is to prevent mechanical switch bouncing from creating multiple false events.

\---

## 9\. Gray-Zone Event Encoding

The SNN must operate on events rather than persistent switch levels.

A gray-zone switch transition:

```text
0 -> 1
```

MUST generate exactly one event.

A persistent:

```text
1 -> 1
```

MUST NOT generate repeated events.

A new event may only occur after:

```text
1 -> 0 -> 1
```

The encoder output is:

```text
gray\\\_spike(3 downto 0)
```

Mapping:

```text
gray\\\_spike(0) = Voltage
gray\\\_spike(1) = Temperature
gray\\\_spike(2) = Clock
gray\\\_spike(3) = Memory Integrity
```

Each event is represented as:

```text
0 = no event
1 = event during the current SNN timestep
```

\---

## 10\. Layer 1 — Threshold Detector

Layer 1 represents the conventional threshold-based tamper detector.

For the PoC:

```text
threshold\\\_alert =
    SWA\\\[0] OR
    SWA\\\[1] OR
    SWA\\\[2] OR
    SWA\\\[3]
```

Therefore:

```text
threshold\\\_alert = 1
```

whenever any extreme condition is active.

This layer is intentionally simple.

It exists to provide a baseline against which the SNN layer can be demonstrated.

The threshold detector MUST NOT depend on the SNN.

\---

## 11\. SNN Input

The LIF neuron receives the four gray-zone event signals:

```text
gray\\\_spike\\\[3:0]
```

The input values are binary:

```text
spike\\\_i ∈ {0,1}
```

No analog value is required.

No ADC is required.

No floating-point processing is required.

\---

## 12\. Hand-Crafted Synaptic Weights

Training is explicitly out of scope.

All synaptic weights MUST be manually specified as VHDL generics or constants.

Default weights:

|Parameter|Input|Weight|
|-|-|-:|
|Voltage|`SWB\\\[0]`|3|
|Temperature|`SWB\\\[1]`|2|
|Clock|`SWB\\\\\[2]`|4|
|Memory Integrity|`SWB\\\[3]`|5|

Therefore:

```text
W = \\\[3, 2, 4, 5]
```

All weights are positive/excitatory.

The intended relative influence is:

```text
Memory Integrity > Clock > Voltage > Temperature
```

The weights are proof-of-concept values and are not the result of machine-learning training.

\---

## 13\. Weight Configuration

Weights MUST be configurable without modifying the LIF architecture.

Recommended generics:

```vhdl
generic (
    WEIGHT\\\_VOLTAGE : integer := 3;
    WEIGHT\\\_TEMP    : integer := 2;
    WEIGHT\\\_CLOCK   : integer := 4;
    WEIGHT\\\_MEMORY  : integer := 5
);
```

The implementation MUST use synthesizable integer/fixed-width arithmetic only.

Do not use floating-point arithmetic.

\---

## 14\. Single LIF Neuron

Only one neuron is required for this PoC.

Neuron model:

```text
Leaky Integrate-and-Fire (LIF)
```

The main state variable is:

```text
membrane\\\_potential
```

Default width:

```text
MEMBRANE\\\_WIDTH = 8 bits
```

Recommended range:

```text
0 ... 255
```

\---

## 15\. LIF Parameters

All parameters below MUST be configurable.

```text
MEMBRANE_WIDTH
SPIKE_THRESHOLD
RESET_POTENTIAL
LEAK_TICKS
```

Default values:

```text
MEMBRANE_WIDTH  = 8
SPIKE_THRESHOLD = 10
RESET_POTENTIAL = 0
LEAK_TICKS      = 1000  (1000 SNN ticks @ 1 kHz = 1.0 second per LED)
```

\---

## 16\. LIF Computation

At every `SNN_TICK`, calculate the weighted synaptic input:

```text
synaptic_input =
    gray_spike[0] * WEIGHT_VOLTAGE +
    gray_spike[1] * WEIGHT_TEMP +
    gray_spike[2] * WEIGHT_CLOCK +
    gray_spike[3] * WEIGHT_MEMORY
```

Integration and Leaky Behavior:
1. **Immediate Integration:** When synaptic input arrives (`synaptic_input > 0`), it is immediately added to the membrane potential, and the 1-second leak timer is reset.
2. **Retention and 1-Second Step Leak:** When idle (`synaptic_input = 0`), the potential is held (e.g. at 4 LEDs for single events like Memory = 5). Every `LEAK_TICKS` ticks (1.0 second), the membrane potential decrements to the next lower LED level:
   $$4\text{ LEDs } (V_{mem}=5) \xrightarrow{1\text{s}} 3\text{ LEDs } (V_{mem}=3) \xrightarrow{1\text{s}} 2\text{ LEDs } (V_{mem}=2) \xrightarrow{1\text{s}} 1\text{ LED } (V_{mem}=1) \xrightarrow{1\text{s}} 0\text{ (All OFF)}$$
   This causes exactly 1 LED to turn off each second until the membrane potential returns to zero.

If:

```text
Vmem_next >= SPIKE_THRESHOLD
```


then:

```text
snn\\\_spike = 1
membrane\\\_potential = RESET\\\_POTENTIAL
```

Otherwise:

```text
snn\\\_spike = 0
membrane\\\_potential = Vmem\\\_next
```

The spike MUST only be asserted for one SNN timestep.

\---

## 17\. Expected LIF Behavior

Default parameters:

```text
Voltage      = 3
Temperature  = 2
Clock        = 4
Memory       = 5

Threshold    = 10
```

### 17.1 Single event

```text
Voltage       = 3
Temperature   = 2
Clock         = 4
Memory        = 5
```

Each individual event MUST NOT fire the neuron.

\---

### 17.2 Two simultaneous events

Maximum two-event combination:

```text
Clock + Memory
= 4 + 5
= 9
```

Since:

```text
9 < 10
```

the neuron MUST NOT fire immediately.

\---

### 17.3 Three-event combination

Example:

```text
Voltage + Temperature + Memory
= 3 + 2 + 5
= 10
```

Therefore:

```text
snn\\\_spike = 1
```

\---

## 18\. Temporal Accumulation

The LIF neuron MUST preserve part of its membrane potential between SNN timesteps.

Example pattern:

```text
t0: Voltage event
t1: no event
t2: Clock event
t3: Memory event
```

The neuron should retain residual membrane potential because of the leaky integration behavior.

The objective is to allow a sequence such as:

```text
Voltage -> Clock -> Memory
```

to produce a spike even though the individual events are below threshold.

This is the primary SNN proof-of-concept behavior.

\---

## 19\. Spike Output

The LIF neuron output is:

```text
snn\\\_spike
```

Behavior:

```text
0 = neuron did not fire
1 = neuron fired
```

When a spike occurs:

```text
membrane\\\_potential = RESET\\\_POTENTIAL
```

The spike is one SNN timestep wide.

\---

## 20\. Warning Output

The SNN spike MUST trigger the warning output:

```text
LED0
```

Physical LED:

```text
LED0 -> H5
```

IO standard:

```text
LVCMOS33
```

The warning LED MUST be latched for visibility.

Behavior:

```text
snn\\\_spike = 1
        |
        v
warning\\\_latched = 1
        |
        v
LED0 = ON
```

The warning state remains active until FPGA reset/reconfiguration.

\---

## 21\. Penalty Output — GSR

The SNN spike MUST also request a penalty action using the Artix-7 global reset mechanism.

Use:

```text
STARTUPE2
```

to access:

```text
GSR
```

Conceptually:

```text
snn\\\_spike
    |
    v
penalty\\\_request
    |
    v
STARTUPE2
    |
    v
GSR
```

Do NOT expose GSR as an external FPGA pin.

Do NOT implement GSR as a normal GPIO.

The `STARTUPE2` primitive must be instantiated in the penalty module.

Unused `STARTUPE2` inputs must be tied to safe constant values appropriate for the Artix-7 primitive.

\---

## 22\. GSR Behavior

When the SNN fires:

```text
snn\\\_spike = 1
```

the penalty path asserts GSR.

The expected effect is that FPGA sequential state returns to its initialized/reset state.

The implementation MUST avoid creating a permanent reset loop.

The intended sequence is:

```text
gray events
     |
     v
LIF spike
     |
     v
GSR assertion
     |
     v
FPGA state reset
     |
     v
SNN returns to initial state
```

GSR is used here as a proof-of-concept penalty/zeroization mechanism, not as a production security implementation.

\---

## 23\. Initial State

No external reset button is required.

Initial state after FPGA configuration:

```text
membrane\\\_potential = 0
snn\\\_spike          = 0
warning\\\_latched    = 0
previous\\\_gray      = 0
threshold\\\_alert    = 0
```

The FPGA configuration/reset mechanism provides the initial state.

\---

## 24\. Top-Level Module Structure

The RTL should be divided into the following modules:

```text
rtl/
├── synapseguard\\\_top.vhd
├── input\\\_conditioner.vhd
├── threshold\\\_detector.vhd
├── gray\\\_event\\\_encoder.vhd
├── lif\\\_neuron.vhd
└── penalty\\\_gsr.vhd
```

### `synapseguard\\\_top.vhd`

Responsibilities:

* Top-level ports.
* Clock distribution.
* SNN tick generation.
* Module instantiation.
* Inter-module signal connections.

### `input\\\_conditioner.vhd`

Responsibilities:

* Synchronize physical inputs.
* Debounce gray-zone switches.
* Provide clean input states.

### `threshold\\\_detector.vhd`

Responsibilities:

```text
SW\\\[3:0] -> threshold\\\_alert
```

### `gray\\\_event\\\_encoder.vhd`

Responsibilities:

```text
SWB\\\[3:0]
  |
  v
edge detection
  |
  v
gray\\\_spike\\\[3:0]
```

### `lif\\\_neuron.vhd`

Responsibilities:

```text
gray\\\_spike\\\[3:0]
       |
       v
weighted sum
       |
       v
leaky integration
       |
       v
threshold comparison
       |
       v
snn\\\_spike
```

### `penalty\\\_gsr.vhd`

Responsibilities:

```text
snn\\\_spike
    |
    v
STARTUPE2
    |
    v
GSR
```

\---

## 25\. Synthesizability Requirements

The RTL MUST:

* Be synthesizable by AMD Vivado.
* Target XC7A100T-CSG324.
* Use `numeric\\\_std`.
* Avoid floating-point arithmetic.
* Avoid `real` arithmetic.
* Avoid dynamic memory allocation.
* Avoid simulation-only file I/O.
* Avoid processor dependencies.
* Avoid AXI.
* Avoid XADC.
* Avoid MMCM/PLL.
* Avoid vendor-specific IP unless explicitly required.
* Use the 100-MHz board clock.
* Use clock-enable for the SNN timestep.
* Keep all SNN arithmetic fixed-width and synthesizable.

\---

## 26\. Weight Arithmetic

Because the inputs are binary spikes, multiplication is not required.

Preferred implementation:

```vhdl
synaptic\\\_input := 0;

if gray\\\_spike(0) = '1' then
    synaptic\\\_input := synaptic\\\_input + WEIGHT\\\_VOLTAGE;
end if;

if gray\\\_spike(1) = '1' then
    synaptic\\\_input := synaptic\\\_input + WEIGHT\\\_TEMP;
end if;

if gray\\\_spike(2) = '1' then
    synaptic\\\_input := synaptic\\\_input + WEIGHT\\\_CLOCK;
end if;

if gray\\\_spike(3) = '1' then
    synaptic\\\_input := synaptic\\\_input + WEIGHT\\\_MEMORY;
end if;
```

This is preferred over inferred multipliers for the PoC.

\---

## 27\. Tuning Parameters

The following parameters MUST be exposed as VHDL generics/constants:

```text
SNN\\\_TICK\\\_HZ

DEBOUNCE\\\_MS

MEMBRANE\\\_WIDTH

WEIGHT\\\_VOLTAGE
WEIGHT\\\_TEMP
WEIGHT\\\_CLOCK
WEIGHT\\\_MEMORY

SPIKE\\\_THRESHOLD
RESET\\\_POTENTIAL
LEAK\\\_SHIFT

USE\\\_SNN
```

Default values:

```text
SNN\\\_TICK\\\_HZ       = 1000
DEBOUNCE\\\_MS       = 20

MEMBRANE\\\_WIDTH    = 8

WEIGHT\\\_VOLTAGE    = 3
WEIGHT\\\_TEMP       = 2
WEIGHT\\\_CLOCK      = 4
WEIGHT\\\_MEMORY     = 5

SPIKE\\\_THRESHOLD   = 10
RESET\\\_POTENTIAL   = 0
LEAK\\\_SHIFT        = 3

USE\\\_SNN           = true
```

\---

## 28\. Baseline Mode

The design should support:

```text
USE\\\_SNN = false
```

for baseline testing.

### Baseline mode

Only the threshold detector is active:

```text
SW extreme -> threshold\\\_alert
```

The SNN layer is bypassed/disabled.

### SNN mode

```text
SW extreme -> threshold detector
SWB gray    -> LIF SNN
```

This allows direct comparison between:

```text
Threshold-only
```

and:

```text
Threshold + SNN
```





##### **30. Functional Testbench Requirements**

\## Functional Testbench Requirements



The AI shall generate a self-checking VHDL testbench for the complete

`synapseguard\_top` design.



The testbench shall:



\- Generate a 100 MHz clock.

\- Apply reset/initialization as required by the RTL.

\- Drive all SW\[3:0] and JA\[3:0] inputs.

\- Model the physical switch behavior.

\- Account for the SNN tick timing.

\- Account for input synchronization and debounce delays.

\- Verify threshold detector behavior.

\- Verify gray-zone event encoding.

\- Verify LIF membrane potential evolution.

\- Verify spike generation.

\- Verify warning LED behavior.

\- Verify GSR penalty trigger behavior using a simulation-safe representation.

\- Use VHDL assertions to detect incorrect behavior.

\- Produce a clear PASS/FAIL result.

\- End the simulation automatically after all test cases pass.





\## Testbench Reference Model



The testbench shall contain a simple behavioral reference model for the LIF

neuron.



For every SNN timestep:



&#x20;   Vmem\_next = Vmem - leak\_value + synaptic\_input



where:



&#x20;   leak\_value = Vmem >> LEAK\_SHIFT



If:



&#x20;   Vmem\_next >= SPIKE\_THRESHOLD



then:



&#x20;   spike = '1'

&#x20;   Vmem = RESET\_POTENTIAL



else:



&#x20;   spike = '0'

&#x20;   Vmem = Vmem\_next



The testbench shall compare the RTL output against this expected behavior

using VHDL assertions.



\## Simulation Safety Requirements



The GSR penalty mechanism shall not cause an uncontrolled simulation reset loop.



The AI shall provide a simulation-safe implementation or simulation abstraction

for the GSR penalty mechanism.



The functional testbench shall verify that a penalty event is generated when

the SNN produces a valid spike, without requiring the simulator itself to

terminate or permanently reset.



The actual FPGA implementation shall use the Artix-7 STARTUPE2 primitive

for GSR access.

\---

## 29\. Functional Test Cases

### TB-01 — Normal Operation

Inputs:

```text
SW = 0000
SWB = 0000
```

Expected:

```text
threshold\\\_alert = 0
snn\\\_spike        = 0
LED0             = OFF
GSR              = 0
```

\---

### TB-02 — Extreme Voltage

```text
SWA\\\[0] = 1
SWA\\\[3:1] = 000
```

Expected:

```text
threshold\\\_alert = 1
```

\---

### TB-03 — Extreme Temperature

```text
SWA\\\[1] = 1
```

Expected:

```text
threshold\\\_alert = 1
```

\---

### TB-04 — Extreme Clock

```text
SW\\\[2] = 1
```

Expected:

```text
threshold\\\_alert = 1
```

\---

### TB-05 — Extreme Memory Integrity

```text
SWA\\\[3] = 1
```

Expected:

```text
threshold\\\_alert = 1
```

\---

### TB-06 — Single Gray Event

Activate:

```text
SWB\\\[0]
```

Expected:

```text
gray\\\_spike = Voltage event
Vmem increases by approximately 3
snn\\\_spike = 0
```

\---

### TB-07 — Two Gray Events

Activate:

```text
SWB\\\[0]
SWB\\\[2]
```

Expected weighted input:

```text
3 + 4 = 7
```

Expected:

```text
snn\\\_spike = 0
```

\---

### TB-08 — Three Gray Events

Activate:

```text
SWB\\\[0]
SWB\\\[1]
SWB\\\[3]
```

Expected weighted input:

```text
3 + 2 + 5 = 10
```

Expected:

```text
snn\\\_spike = 1
```

Then:

```text
LED0 = ON
GSR requested
```

\---

### TB-09 — Repeated Same Parameter

Repeatedly toggle:

```text
SWB\\\[0]
```

with sufficient OFF time between events.

Expected:

* Each 0→1 transition generates one event.
* Persistent HIGH does not continuously generate events.
* LIF accumulates events over time according to leak.

\---

### TB-10 — Temporal Parameter Pattern

Example:

```text
Voltage -> Clock -> Memory
```

with each event separated by one or more SNN timesteps.

Expected:

```text
membrane\\\_potential accumulates
```

and, if threshold is reached:

```text
snn\\\_spike = 1
```

\---

### TB-11 — Post-Spike Reset

After:

```text
snn\\\_spike = 1
```

expected:

```text
membrane\\\_potential = RESET\\\_POTENTIAL
```

\---

### TB-12 — Penalty

After an SNN spike:

```text
penalty\\\_request = 1
```

and the `STARTUPE2` GSR path is activated.

\---

## 30\. Demo Scenarios

### Scenario A — Conventional Threshold Detection

Activate:

```text
SW\\\[0]
```

Expected:

```text
threshold\\\_alert = 1
```

This demonstrates the first detection layer.

\---

### Scenario B — Single Gray-Zone Parameter

Activate:

```text
SWB\\\[0]
```

Expected:

```text
No SNN spike
No warning
No penalty
```

This demonstrates gray-zone tolerance.

\---

### Scenario C — Gray-Zone Combination

Generate:

```text
SWB\\\[0] -> SWB\\\[1] -> SWB\\\[3]
```

Expected:

```text
3 + 2 + 5 = 10
```

Then:

```text
snn\\\_spike = 1
LED0      = ON
GSR       = asserted
```

This is the primary SNN demonstration.

\---

### Scenario D — Parameter Sweep

Generate a repeated pattern such as:

```text
SWB\\\[0] -> SWB\\\[2] -> SWB\\\[0] -> SWB\\\[3]
```

The LIF neuron should accumulate residual membrane potential across the events.

If the membrane potential reaches the threshold:

```text
snn\\\_spike = 1
```

This demonstrates temporal/pattern-based detection rather than a single threshold crossing.

\---

## 31\. Output Summary

|Condition|Threshold (SWA)|SNN Spike|Warning LED0 (V11)|GSR Penalty|Memory LED_MEM (N15)|Bargraph LED_VMEM (U16..H17)|
|-|-:|-:|-:|-:|-:|-:|
|Normal|0|0|OFF (0)|0|Retained / 1 (if set)|OFF (00000000)|
|Extreme parameter (SWA=1)|1|0|OFF (0)|1 (Direct GSR)|RESET to 0|Cleared to 0|
|One gray event (SWB)|0|0|OFF (0)|0|Retained|Partial (e.g. 11100000)|
|Two weak gray events|0|0|OFF (0)|0|Retained|Accumulated to right|
|SWB 1st spike (threshold)|0|1|ON (Latched 1)|0|Retained|Full -> resets to 0|
|SWB 2nd spike (penalty)|0|1|Cleared to OFF|1 (GSR)|RESET to 0|Cleared to 0|

\---

## 32\. Physical Pin Constraints

The XDC MUST use the following Digilent Nexys A7-100T mappings.

### Clock
```text
CLK100MHZ -> E3
IOSTANDARD -> LVCMOS33
```

### Onboard Extreme Switches (Layer 1 -> Direct GSR)
```text
SWA[0] -> V10
SWA[1] -> U11
SWA[2] -> U12
SWA[3] -> H6
IOSTANDARD LVCMOS33
```

### Switch SWB Gray-Zone Inputs (SNN)
```text
SWB[0] -> R15
SWB[1] -> M13
SWB[2] -> L16
SWB[3] -> J15
IOSTANDARD LVCMOS33
```

### Warning LED
```text
LED0 -> V11 (LD15)
IOSTANDARD -> LVCMOS33
```

### Memory Demonstration Input & Output (GSR Verification)
```text
BTN_MEM -> N17 (BTNC Pushbutton - Sets memory latch)
LED_MEM -> N15 (LED16_R Tri-color LED - Cleared only by GSR)
IOSTANDARD -> LVCMOS33
```

### 8-LED Membrane Potential Bargraph (Expanding towards H17)
```text
LED_VMEM[7] -> U16 (LD7, leftmost in group)
LED_VMEM[6] -> U17 (LD6)
LED_VMEM[5] -> V17 (LD5)
LED_VMEM[4] -> R18 (LD4)
LED_VMEM[3] -> N14 (LD3)
LED_VMEM[2] -> J13 (LD2)
LED_VMEM[1] -> K15 (LD1)
LED_VMEM[0] -> H17 (LD0, rightmost in group)
IOSTANDARD -> LVCMOS33
```

\---

## 33\. Required XDC

The implementation MUST provide:

```text
constraints/synapseguard.xdc
```

Minimum constraint content:

```tcl
set_property -dict { PACKAGE_PIN E3  IOSTANDARD LVCMOS33 } [get_ports CLK100MHZ]
create_clock -add -name sys_clk_pin -period 10.00 -waveform {0 5} [get_ports CLK100MHZ]

set_property -dict { PACKAGE_PIN V10 IOSTANDARD LVCMOS33 } [get_ports {SWA[0]}]
set_property -dict { PACKAGE_PIN U11 IOSTANDARD LVCMOS33 } [get_ports {SWA[1]}]
set_property -dict { PACKAGE_PIN U12 IOSTANDARD LVCMOS33 } [get_ports {SWA[2]}]
set_property -dict { PACKAGE_PIN H6  IOSTANDARD LVCMOS33 } [get_ports {SWA[3]}]

set_property -dict { PACKAGE_PIN R15 IOSTANDARD LVCMOS33 } [get_ports {SWB[0]}]
set_property -dict { PACKAGE_PIN M13 IOSTANDARD LVCMOS33 } [get_ports {SWB[1]}]
set_property -dict { PACKAGE_PIN L16 IOSTANDARD LVCMOS33 } [get_ports {SWB[2]}]
set_property -dict { PACKAGE_PIN J15 IOSTANDARD LVCMOS33 } [get_ports {SWB[3]}]

set_property -dict { PACKAGE_PIN V11 IOSTANDARD LVCMOS33 } [get_ports LED0]

set_property -dict { PACKAGE_PIN N17 IOSTANDARD LVCMOS33 } [get_ports BTN_MEM]
set_property -dict { PACKAGE_PIN N15 IOSTANDARD LVCMOS33 } [get_ports LED_MEM]

set_property -dict { PACKAGE_PIN U16 IOSTANDARD LVCMOS33 } [get_ports {LED_VMEM[7]}]
set_property -dict { PACKAGE_PIN U17 IOSTANDARD LVCMOS33 } [get_ports {LED_VMEM[6]}]
set_property -dict { PACKAGE_PIN V17 IOSTANDARD LVCMOS33 } [get_ports {LED_VMEM[5]}]
set_property -dict { PACKAGE_PIN R18 IOSTANDARD LVCMOS33 } [get_ports {LED_VMEM[4]}]
set_property -dict { PACKAGE_PIN N14 IOSTANDARD LVCMOS33 } [get_ports {LED_VMEM[3]}]
set_property -dict { PACKAGE_PIN J13 IOSTANDARD LVCMOS33 } [get_ports {LED_VMEM[2]}]
set_property -dict { PACKAGE_PIN K15 IOSTANDARD LVCMOS33 } [get_ports {LED_VMEM[1]}]
set_property -dict { PACKAGE_PIN H17 IOSTANDARD LVCMOS33 } [get_ports {LED_VMEM[0]}]
```


The AI MUST NOT invent alternative FPGA pin numbers for these signals while the target board remains nexys a7 100t

## 34\. Verification Requirements

The testbench MUST monitor at least:

```text
threshold\\\_alert
gray\\\_spike\\\[3:0]
synaptic\\\_input
membrane\\\_potential
snn\\\_spike
warning\\\_latched
penalty\\\_request
```

The testbench MUST verify:

1. Normal operation does not produce an SNN spike.
2. A single gray-zone event does not produce a spike.
3. Two weak events below threshold do not immediately produce a spike.
4. A combination reaching the threshold produces a spike.
5. Temporal accumulation works across multiple SNN timesteps.
6. A spike resets the membrane potential.
7. A spike produces the warning request.
8. A spike produces the penalty/GSR request.
9. Gray switch bouncing does not create multiple events.
10. Persistent gray switch HIGH does not continuously generate events.

\---

## 35\. Required Deliverables

The AI generating the implementation MUST produce at minimum:

```text
synapseguard/

├── rtl/

│   ├── synapseguard\_top.vhd

│   ├── input\_conditioner.vhd

│   ├── threshold\_detector.vhd

│   ├── gray\_event\_encoder.vhd

│   ├── lif\_neuron.vhd

│   └── penalty\_gsr.vhd

│

├── tb/

│   ├── tb\_synapseguard\_top.vhd

│   ├── tb\_lif\_neuron.vhd

│   └── tb\_pkg.vhd

│

├── constraints/

│   └── synapseguard.xdc

│

└── README.md```

Optional:

```text
README.md
```

The README, if generated, should only describe:

* Vivado project setup.
* FPGA target.
* Physical switch connection.
* Simulation procedure.
* Demo procedure.

\---

## 36\. Explicit Non-Requirements

The following MUST NOT be implemented in this PoC unless explicitly requested later:

* SNN training.
* Dataset generation.
* snnTorch.
* PyTorch.
* XADC.
* Real voltage sensing.
* Real temperature sensing.
* Real clock glitch generation.
* Real memory integrity monitoring.
* UART interface.
* DDR3.
* Ethernet.
* AXI.
* Processor.
* Multiple neurons.
* Hidden SNN layers.
* CNN.
* Floating-point arithmetic.
* Dynamic clock generation.
* MMCM/PLL.
* External reset button.
* Seven-segment display.
* RGB LED.
* DE10-Nano support.
* ASIC implementation.
* Physical fault injection.

\---

## 37\. Design Constraints Summary

The implementation is considered functionally compliant only if all of the following are true:

* \[ ] Target is `XC7A100T-CSG324`.
* \[ ] Target board is nexys a7 100t.
* \[ ] `CLK100MHZ` uses E3.
* \[ ] `SWA\\\[0]` represents extreme voltage.
* \[ ] `SWA\\\[1]` represents extreme temperature.
* \[ ] `SWA\\\[2]` represents extreme clock.
* \[ ] `SWA\\\[3]` represents extreme memory integrity.
* \[ ] `SWB\\\[0]` represents gray voltage.
* \[ ] `SWB\\\[1]` represents gray temperature.
* \[ ] `SWB\\\[2]` represents gray clock.
* \[ ] `SWB\\\[3]` represents gray memory integrity.
* \[ ] Gray inputs are debounced.
* \[ ] Gray inputs use edge/event encoding.
* \[ ] Only one LIF neuron is implemented.
* \[ ] LIF uses integer/fixed-width arithmetic.
* \[ ] Weights are manually specified.
* \[ ] Weights are configurable.
* \[ ] LIF threshold is configurable.
* \[ ] LIF leak is configurable.
* \[ ] LIF reset potential is configurable.
* \[ ] SNN timestep is configurable.
* \[ ] SNN uses clock enable rather than a generated clock.
* \[ ] SNN spike drives LED warning.
* \[ ] SNN spike drives GSR penalty.
* \[ ] GSR uses `STARTUPE2`.
* \[ ] LED0 uses v11.
* \[ ] Required XDC constraints are present.
* \[ ] Design is synthesizable in Vivado.
* \[ ] No training or external ML runtime is required.

\---

## 38\. Reference Basis

The project context describes the SNN/LIF layer as a secondary layer intended to accumulate small signals over time and across multiple sensor sources, especially for combined attacks and repeated parameter probing. It explicitly identifies hand-crafted weights and a single-neuron fallback as a suitable minimum proof-of-concept implementation.

Reference:

```text
https://github.com/Marco-Winzker/Spiking\\\_NN\\\_RGB\\\_FPGA
```

The referenced repository is used as an implementation reference for FPGA/VHDL SNN structure. Its original application-specific logic should not be copied into this project; only reusable SNN/VHDL implementation concepts should be adapted.

The physical pin mapping in this specification is based on the official Digilent nexys a7 100t

The GSR penalty mechanism is based on the nexys a7 100t `STARTUPE2` primitive.

