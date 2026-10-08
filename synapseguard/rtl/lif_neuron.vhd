--------------------------------------------------------------------------------
-- SynapseGuard - lif_neuron  (FSD 14-19, 26)
--
-- Single Leaky Integrate-and-Fire neuron, fixed-width integer arithmetic.
--
-- Dynamics:
--   1. Immediate Integration: when synaptic input arrives (syn_in > 0),
--      Vmem increases by sum of weights. If Vmem >= SPIKE_THRESHOLD,
--      it generates snn_spike for 1 SNN timestep and resets to RESET_POTENTIAL.
--   2. Retention & 1-Second Step Leak: when idle (syn_in = 0), potential is held
--      (e.g. at 4 LEDs = level 5), and decrements by 1 LED level every LEAK_TICKS
--      (default 1000 ticks @ 1 kHz = 1.0 second per LED) until completely reaching 0.
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity lif_neuron is
    generic (
        MEMBRANE_WIDTH  : positive := 8;
        WEIGHT_VOLTAGE  : natural  := 3;
        WEIGHT_TEMP     : natural  := 2;
        WEIGHT_CLOCK    : natural  := 4;
        WEIGHT_MEMORY   : natural  := 5;
        SPIKE_THRESHOLD : natural  := 10;
        RESET_POTENTIAL : natural  := 0;
        LEAK_TICKS      : positive := 1000  -- 1000 SNN ticks @ 1 kHz = 1.0 second
    );
    port (
        clk                : in  std_logic;
        rst                : in  std_logic;
        tick               : in  std_logic;                     -- SNN clock enable
        gray_spike         : in  std_logic_vector(3 downto 0);
        synaptic_input     : out unsigned(MEMBRANE_WIDTH - 1 downto 0);
        membrane_potential : out unsigned(MEMBRANE_WIDTH - 1 downto 0);
        snn_spike          : out std_logic
    );
end entity lif_neuron;

architecture rtl of lif_neuron is

    constant VMAX       : natural := 2 ** MEMBRANE_WIDTH - 1;
    constant WEIGHT_SUM : natural := WEIGHT_VOLTAGE + WEIGHT_TEMP + WEIGHT_CLOCK + WEIGHT_MEMORY;

    signal syn_in     : natural range 0 to WEIGHT_SUM;
    signal vmem_r     : unsigned(MEMBRANE_WIDTH - 1 downto 0) := (others => '0');
    signal spike_r    : std_logic := '0';
    signal leak_timer : natural range 0 to LEAK_TICKS := 0;

    ----------------------------------------------------------------------------
    -- Helper function: decrements potential to the next lower LED level
    -- (Levels: 8->7->6->5->4->3->2->1->0 LEDs)
    ----------------------------------------------------------------------------
    function leak_step(v : natural) return natural is
    begin
        if v >= 9 then
            return 8;
        elsif v >= 8 then
            return 7;
        elsif v >= 7 then
            return 6;
        elsif v >= 6 then
            return 5;
        elsif v >= 4 then
            return 3;
        elsif v >= 3 then
            return 2;
        elsif v >= 2 then
            return 1;
        else
            return 0;
        end if;
    end function;

begin

    -- Elaboration-time parameter sanity checks
    assert WEIGHT_SUM <= VMAX
        report "lif_neuron: sum of weights exceeds membrane range" severity failure;
    assert RESET_POTENTIAL <= VMAX
        report "lif_neuron: RESET_POTENTIAL exceeds membrane range" severity failure;
    assert RESET_POTENTIAL < SPIKE_THRESHOLD
        report "lif_neuron: RESET_POTENTIAL should be below SPIKE_THRESHOLD" severity warning;
    assert SPIKE_THRESHOLD <= VMAX
        report "lif_neuron: SPIKE_THRESHOLD unreachable (> 2^MEMBRANE_WIDTH-1)" severity warning;

    ----------------------------------------------------------------------------
    -- Weighted synaptic sum
    ----------------------------------------------------------------------------
    syn_proc : process (gray_spike)
        variable s : natural range 0 to WEIGHT_SUM;
    begin
        s := 0;
        if gray_spike(0) = '1' then s := s + WEIGHT_VOLTAGE; end if;
        if gray_spike(1) = '1' then s := s + WEIGHT_TEMP;    end if;
        if gray_spike(2) = '1' then s := s + WEIGHT_CLOCK;   end if;
        if gray_spike(3) = '1' then s := s + WEIGHT_MEMORY;  end if;
        syn_in <= s;
    end process syn_proc;

    ----------------------------------------------------------------------------
    -- Leaky integration, threshold, reset, and 1-second per LED step leak
    ----------------------------------------------------------------------------
    lif_proc : process (clk)
        variable v_now  : natural range 0 to VMAX;
        variable v_next : natural range 0 to VMAX + WEIGHT_SUM;
    begin
        if rising_edge(clk) then
            if rst = '1' then
                vmem_r     <= (others => '0');
                spike_r    <= '0';
                leak_timer <= 0;
            elsif tick = '1' then
                v_now := to_integer(vmem_r);

                if syn_in > 0 then
                    -- New synaptic input: integrate and reset the 1-second leak timer
                    leak_timer <= 0;
                    v_next     := v_now + syn_in;
                    if v_next > VMAX then
                        v_next := VMAX;
                    end if;

                    if v_next >= SPIKE_THRESHOLD then
                        spike_r <= '1';
                        vmem_r  <= to_unsigned(RESET_POTENTIAL, MEMBRANE_WIDTH);
                    else
                        spike_r <= '0';
                        vmem_r  <= to_unsigned(v_next, MEMBRANE_WIDTH);
                    end if;
                else
                    -- Idle: retain potential, decrement 1 LED level every LEAK_TICKS ticks (1 second)
                    spike_r <= '0';
                    if v_now = 0 then
                        leak_timer <= 0;
                    elsif leak_timer = LEAK_TICKS - 1 then
                        leak_timer <= 0;
                        vmem_r     <= to_unsigned(leak_step(v_now), MEMBRANE_WIDTH);
                    else
                        leak_timer <= leak_timer + 1;
                    end if;
                end if;
            end if;
        end if;
    end process lif_proc;

    synaptic_input     <= to_unsigned(syn_in, MEMBRANE_WIDTH);
    membrane_potential <= vmem_r;
    snn_spike          <= spike_r;

end architecture rtl;
