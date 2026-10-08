--------------------------------------------------------------------------------
-- SynapseGuard - synapseguard_top
--
-- Single-neuron LIF SNN anti-tamper proof of concept.
-- Target: XC7A100T-CSG324 (Digilent Nexys A7-100T / Nexys 4 DDR).
--
-- Architecture:
--   * SWA[3:0] (extreme tamper) -> Layer-1 detector -> direct penalty/GSR (no warning LED)
--   * SWB[3:0] (gray-zone)      -> debounce -> event encoder -> LIF neuron
--   * SNN spike #1              -> warning_latched -> LED0 (V11)
--   * SNN spike #2              -> penalty_gsr (STARTUPE2 GSR + soft_rst)
--   * Memory demo               -> BTN_MEM (N17) sets memory latch -> LED_MEM (N15);
--                                  cleared only by GSR / soft_rst (zeroization demo)
--   * Accumulation bargraph     -> LED_VMEM[7:0] (U16..H17) expands towards H17
--                                  as LIF membrane potential fills up
--
-- SNN timestep = clock enable (snn_tick), 100 MHz / SNN_TICK_HZ.
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity synapseguard_top is
    generic (
        CLK_FREQ_HZ        : positive := 100_000_000;
        SNN_TICK_HZ        : positive := 1000;
        DEBOUNCE_MS        : positive := 20;

        MEMBRANE_WIDTH     : positive := 8;

        WEIGHT_VOLTAGE     : natural  := 3;
        WEIGHT_TEMP        : natural  := 2;
        WEIGHT_CLOCK       : natural  := 4;
        WEIGHT_MEMORY      : natural  := 5;

        SPIKE_THRESHOLD    : natural  := 10;
        RESET_POTENTIAL    : natural  := 0;
        LEAK_TICKS         : positive := 1000;

        USE_SNN            : boolean  := true;
        SPIKES_FOR_PENALTY : positive := 2;
        RESET_PULSE_CYCLES : positive := 32;
        USE_STARTUPE2      : boolean  := true
    );
    port (
        CLK100MHZ : in  std_logic;
        SWA       : in  std_logic_vector(3 downto 0);
        SWB       : in  std_logic_vector(3 downto 0);
        BTN_MEM   : in  std_logic := '0';
        LED0      : out std_logic;
        LED_MEM   : out std_logic;
        LED_VMEM  : out std_logic_vector(7 downto 0)
    );
end entity synapseguard_top;

architecture rtl of synapseguard_top is

    ----------------------------------------------------------------------------
    -- Derived constants
    ----------------------------------------------------------------------------
    constant TICK_DIV       : positive := CLK_FREQ_HZ / SNN_TICK_HZ;
    function max1(x : natural) return positive is
    begin
        if x < 1 then return 1; else return x; end if;
    end function;
    constant DEBOUNCE_TICKS : positive := max1((DEBOUNCE_MS * SNN_TICK_HZ) / 1000);

    ----------------------------------------------------------------------------
    -- Internal signals
    ----------------------------------------------------------------------------
    signal tick_cnt           : natural range 0 to TICK_DIV - 1 := 0;
    signal snn_tick           : std_logic := '0';
    signal soft_rst           : std_logic;

    signal swa_sync           : std_logic_vector(3 downto 0);
    signal swb_clean          : std_logic_vector(3 downto 0);

    signal threshold_alert    : std_logic;
    signal gray_spike         : std_logic_vector(3 downto 0);
    signal synaptic_input     : unsigned(MEMBRANE_WIDTH - 1 downto 0);
    signal membrane_potential : unsigned(MEMBRANE_WIDTH - 1 downto 0);
    signal snn_spike          : std_logic;
    signal snn_spike_gated    : std_logic;
    signal warning_latched    : std_logic := '0';
    signal penalty_request    : std_logic;

    signal snn_rst            : std_logic;

    -- Memory demonstration latch signals
    signal btn_mem_meta       : std_logic := '0';
    signal btn_mem_s          : std_logic := '0';
    signal mem_latched        : std_logic := '0';

    -- 8-LED membrane potential accumulation bargraph
    signal led_vmem_reg       : std_logic_vector(7 downto 0) := (others => '0');

    attribute ASYNC_REG : string;
    attribute ASYNC_REG of btn_mem_meta : signal is "TRUE";
    attribute ASYNC_REG of btn_mem_s    : signal is "TRUE";

    attribute DONT_TOUCH : string;
    attribute DONT_TOUCH of threshold_alert : signal is "TRUE";

    ----------------------------------------------------------------------------
    -- Helper function: Map membrane potential to 8-LED bargraph
    -- Bit 7 (U16) is leftmost, Bit 0 (H17) is rightmost
    ----------------------------------------------------------------------------
    function calc_vmem_bargraph(
        vmem   : unsigned;
        thresh : natural;
        spike  : std_logic
    ) return std_logic_vector is
        variable v    : natural;
        variable leds : std_logic_vector(7 downto 0);
    begin
        v    := to_integer(vmem);
        leds := (others => '0');

        if v >= 1 then
            leds(7) := '1'; -- U16 (LD7)
        end if;
        if v >= (thresh * 2) / 8 then
            leds(6) := '1'; -- U17 (LD6)
        end if;
        if v >= (thresh * 3) / 8 then
            leds(5) := '1'; -- V17 (LD5)
        end if;
        if v >= (thresh * 4) / 8 then
            leds(4) := '1'; -- R18 (LD4)
        end if;
        if v >= (thresh * 5) / 8 then
            leds(3) := '1'; -- N14 (LD3)
        end if;
        if v >= (thresh * 6) / 8 then
            leds(2) := '1'; -- J13 (LD2)
        end if;
        if v >= (thresh * 7) / 8 then
            leds(1) := '1'; -- K15 (LD1)
        end if;
        if v >= (thresh - 1) or spike = '1' then
            leds(0) := '1'; -- H17 (LD0)
        end if;

        return leds;
    end function;

begin

    assert TICK_DIV >= 2
        report "synapseguard_top: CLK_FREQ_HZ / SNN_TICK_HZ must be >= 2" severity failure;

    ----------------------------------------------------------------------------
    -- SNN tick generator: one-cycle clock enable every TICK_DIV clocks
    ----------------------------------------------------------------------------
    tick_proc : process (CLK100MHZ)
    begin
        if rising_edge(CLK100MHZ) then
            if soft_rst = '1' then
                tick_cnt <= 0;
                snn_tick <= '0';
            elsif tick_cnt = TICK_DIV - 1 then
                tick_cnt <= 0;
                snn_tick <= '1';
            else
                tick_cnt <= tick_cnt + 1;
                snn_tick <= '0';
            end if;
        end if;
    end process tick_proc;

    ----------------------------------------------------------------------------
    -- Input conditioning
    ----------------------------------------------------------------------------
    u_input_conditioner : entity work.input_conditioner
        generic map (
            DEBOUNCE_TICKS => DEBOUNCE_TICKS
        )
        port map (
            clk       => CLK100MHZ,
            rst       => soft_rst,
            tick      => snn_tick,
            swa_in    => SWA,
            swb_in    => SWB,
            swa_sync  => swa_sync,
            swb_clean => swb_clean
        );

    ----------------------------------------------------------------------------
    -- Layer 1: conventional threshold detector (extreme inputs)
    ----------------------------------------------------------------------------
    u_threshold_detector : entity work.threshold_detector
        port map (
            clk             => CLK100MHZ,
            rst             => soft_rst,
            swa             => swa_sync,
            threshold_alert => threshold_alert
        );

    ----------------------------------------------------------------------------
    -- Layer 2: SNN (held in reset when USE_SNN = false -> baseline mode)
    ----------------------------------------------------------------------------
    snn_rst <= '1' when (soft_rst = '1' or not USE_SNN) else '0';

    u_gray_event_encoder : entity work.gray_event_encoder
        port map (
            clk        => CLK100MHZ,
            rst        => snn_rst,
            tick       => snn_tick,
            gray_in    => swb_clean,
            gray_spike => gray_spike
        );

    u_lif_neuron : entity work.lif_neuron
        generic map (
            MEMBRANE_WIDTH  => MEMBRANE_WIDTH,
            WEIGHT_VOLTAGE  => WEIGHT_VOLTAGE,
            WEIGHT_TEMP     => WEIGHT_TEMP,
            WEIGHT_CLOCK    => WEIGHT_CLOCK,
            WEIGHT_MEMORY   => WEIGHT_MEMORY,
            SPIKE_THRESHOLD => SPIKE_THRESHOLD,
            RESET_POTENTIAL => RESET_POTENTIAL,
            LEAK_TICKS      => LEAK_TICKS
        )
        port map (
            clk                => CLK100MHZ,
            rst                => snn_rst,
            tick               => snn_tick,
            gray_spike         => gray_spike,
            synaptic_input     => synaptic_input,
            membrane_potential => membrane_potential,
            snn_spike          => snn_spike
        );

    snn_spike_gated <= snn_spike when USE_SNN else '0';

    ----------------------------------------------------------------------------
    -- Warning latch: set by an SNN spike, cleared only by reset / GSR
    ----------------------------------------------------------------------------
    warn_proc : process (CLK100MHZ)
    begin
        if rising_edge(CLK100MHZ) then
            if soft_rst = '1' then
                warning_latched <= '0';
            elsif snn_spike_gated = '1' then
                warning_latched <= '1';
            end if;
        end if;
    end process warn_proc;

    ----------------------------------------------------------------------------
    -- Penalty path: SWA direct GSR OR SWB penalty threshold -> STARTUPE2 GSR
    ----------------------------------------------------------------------------
    u_penalty_gsr : entity work.penalty_gsr
        generic map (
            SPIKES_FOR_PENALTY => SPIKES_FOR_PENALTY,
            RESET_PULSE_CYCLES => RESET_PULSE_CYCLES,
            USE_STARTUPE2      => USE_STARTUPE2
        )
        port map (
            clk             => CLK100MHZ,
            rst             => soft_rst,
            snn_spike       => snn_spike_gated,
            extreme_alert   => threshold_alert,
            penalty_request => penalty_request,
            soft_rst        => soft_rst
        );

    ----------------------------------------------------------------------------
    -- Memory demonstration: Button N17 sets memory latch, GSR/soft_rst clears it
    ----------------------------------------------------------------------------
    btn_sync_proc : process (CLK100MHZ)
    begin
        if rising_edge(CLK100MHZ) then
            btn_mem_meta <= BTN_MEM;
            btn_mem_s    <= btn_mem_meta;
        end if;
    end process btn_sync_proc;

    mem_proc : process (CLK100MHZ)
    begin
        if rising_edge(CLK100MHZ) then
            if soft_rst = '1' then
                mem_latched <= '0';
            elsif btn_mem_s = '1' then
                mem_latched <= '1';
            end if;
        end if;
    end process mem_proc;

    LED_MEM <= mem_latched;

    ----------------------------------------------------------------------------
    -- 8-LED Bargraph for LIF Membrane Potential Accumulation (U16 .. H17)
    ----------------------------------------------------------------------------
    vmem_led_proc : process (CLK100MHZ)
    begin
        if rising_edge(CLK100MHZ) then
            if soft_rst = '1' then
                led_vmem_reg <= (others => '0');
            else
                led_vmem_reg <= calc_vmem_bargraph(membrane_potential, SPIKE_THRESHOLD, snn_spike_gated);
            end if;
        end if;
    end process vmem_led_proc;

    LED_VMEM <= led_vmem_reg;

    ----------------------------------------------------------------------------
    -- Warning LED output (LED0)
    ----------------------------------------------------------------------------
    LED0 <= warning_latched;

end architecture rtl;
