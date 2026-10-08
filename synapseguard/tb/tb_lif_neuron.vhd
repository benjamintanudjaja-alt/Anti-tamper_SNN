--------------------------------------------------------------------------------
-- SynapseGuard - tb_lif_neuron
--
-- Self-checking unit testbench for lif_neuron (default generics).
--
--  * A cycle-accurate reference model (tb_pkg.lif_step) runs in parallel and
--    checks membrane_potential, snn_spike and synaptic_input on EVERY clock.
--  * Directed tests: all single events, all pairs, all triples, all four,
--    temporal accumulation (V -> idle -> C -> M), leak decay, post-spike reset.
--  * Pseudo-random stimulus (LFSR) for 400 SNN timesteps.
--
-- Prints "TB_LIF_NEURON: PASS" or "TB_LIF_NEURON: FAIL" and stops.
-- VHDL-2008 (std.env.finish).
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.tb_pkg.all;

entity tb_lif_neuron is
end entity tb_lif_neuron;

architecture sim of tb_lif_neuron is

    constant TICK_EVERY : positive := 4;   -- clocks per SNN tick in this unit test

    signal clk                : std_logic := '0';
    signal rst                : std_logic := '1';
    signal tick               : std_logic := '0';
    signal gray_spike         : std_logic_vector(3 downto 0) := (others => '0');
    signal synaptic_input     : unsigned(C_MEMBRANE_WIDTH - 1 downto 0);
    signal membrane_potential : unsigned(C_MEMBRANE_WIDTH - 1 downto 0);
    signal snn_spike          : std_logic;

    signal model_errors : natural := 0;
    signal model_steps  : natural := 0;
    signal sim_done     : boolean := false;

begin

    ----------------------------------------------------------------------------
    -- Clock and tick
    ----------------------------------------------------------------------------
    clk <= not clk after CLK_PERIOD / 2 when not sim_done else '0';

    tick_gen : process (clk)
        variable cnt : natural range 0 to TICK_EVERY - 1 := 0;
    begin
        if rising_edge(clk) then
            if cnt = TICK_EVERY - 1 then
                cnt  := 0;
                tick <= '1';
            else
                cnt  := cnt + 1;
                tick <= '0';
            end if;
        end if;
    end process tick_gen;

    ----------------------------------------------------------------------------
    -- DUT
    ----------------------------------------------------------------------------
    dut : entity work.lif_neuron
        generic map (
            MEMBRANE_WIDTH  => C_MEMBRANE_WIDTH,
            WEIGHT_VOLTAGE  => C_WEIGHT_VOLTAGE,
            WEIGHT_TEMP     => C_WEIGHT_TEMP,
            WEIGHT_CLOCK    => C_WEIGHT_CLOCK,
            WEIGHT_MEMORY   => C_WEIGHT_MEMORY,
            SPIKE_THRESHOLD => C_SPIKE_THRESHOLD,
            RESET_POTENTIAL => C_RESET_POTENTIAL,
            LEAK_SHIFT      => C_LEAK_SHIFT
        )
        port map (
            clk                => clk,
            rst                => rst,
            tick               => tick,
            gray_spike         => gray_spike,
            synaptic_input     => synaptic_input,
            membrane_potential => membrane_potential,
            snn_spike          => snn_spike
        );

    ----------------------------------------------------------------------------
    -- Reference model checker (every clock)
    ----------------------------------------------------------------------------
    model_proc : process
        variable m_vmem  : natural   := 0;
        variable m_spike : std_logic := '0';
        variable p_rst   : std_logic;
        variable p_tick  : std_logic;
        variable p_gs    : std_logic_vector(3 downto 0);
        variable p_syn   : natural;
        variable errs    : natural := 0;
        variable steps   : natural := 0;
    begin
        wait until rising_edge(clk);
        -- values seen by the DUT at this edge (pre-update)
        p_rst  := rst;
        p_tick := tick;
        p_gs   := gray_spike;
        p_syn  := to_integer(synaptic_input);

        if p_rst = '1' then
            m_vmem  := 0;
            m_spike := '0';
        elsif p_tick = '1' then
            check(p_syn = weighted_sum(p_gs),
                  "synaptic_input=" & integer'image(p_syn) & " expected " &
                  integer'image(weighted_sum(p_gs)) & " for gray_spike=" & to_str(p_gs), errs);
            lif_step(m_vmem, weighted_sum(p_gs), m_spike);
            steps := steps + 1;
        end if;

        wait for 1 ns;
        check(to_integer(membrane_potential) = m_vmem,
              "membrane_potential=" & integer'image(to_integer(membrane_potential)) &
              " model=" & integer'image(m_vmem), errs);
        check(snn_spike = m_spike,
              "snn_spike=" & std_logic'image(snn_spike) & " model=" & std_logic'image(m_spike), errs);
        model_errors <= errs;
        model_steps  <= steps;
    end process model_proc;

    ----------------------------------------------------------------------------
    -- Stimulus + directed checks
    ----------------------------------------------------------------------------
    stim_proc : process
        variable errs   : natural := 0;
        variable lfsr   : std_logic_vector(15 downto 0) := x"ACE1";
        variable spikes : natural := 0;
        variable pat    : std_logic_vector(3 downto 0);
        variable exp_v  : natural;

        -- present one pattern for exactly one SNN timestep
        procedure step (spk : std_logic_vector(3 downto 0)) is
        begin
            gray_spike <= spk;
            wait until rising_edge(clk) and tick = '1';
            wait for 1 ns;
            gray_spike <= (others => '0');
        end procedure;

        procedure do_reset is
        begin
            rst <= '1';
            for i in 1 to 3 loop
                wait until rising_edge(clk);
            end loop;
            wait for 1 ns;
            rst <= '0';
        end procedure;

        procedure expect (vm : natural; sp : std_logic; tag : string) is
        begin
            check(to_integer(membrane_potential) = vm,
                  tag & ": Vmem=" & integer'image(to_integer(membrane_potential)) &
                  " expected " & integer'image(vm), errs);
            check(snn_spike = sp,
                  tag & ": snn_spike=" & std_logic'image(snn_spike) &
                  " expected " & std_logic'image(sp), errs);
        end procedure;

    begin
        do_reset;
        expect(0, '0', "after reset");

        -- (1) Single events: never fire (FSD 17.1)
        report "LIF: single events";
        for ch in 0 to 3 loop
            do_reset;
            pat     := (others => '0');
            pat(ch) := '1';
            step(pat);
            expect(weighted_sum(pat), '0', "single event ch" & integer'image(ch));
        end loop;

        -- (2) Two simultaneous events: never fire, max 9 (FSD 17.2)
        report "LIF: pairs";
        for a in 0 to 3 loop
            for b in a + 1 to 3 loop
                do_reset;
                pat    := (others => '0');
                pat(a) := '1';
                pat(b) := '1';
                step(pat);
                expect(weighted_sum(pat), '0', "pair " & to_str(pat));
            end loop;
        end loop;

        -- (3) Triples and all four (FSD 17.3)
        report "LIF: triples / all";
        do_reset; step("0111"); expect(9, '0', "V+T+C=9");
        do_reset; step("1011"); expect(0, '1', "V+T+M=10");
        do_reset; step("1101"); expect(0, '1', "V+C+M=12");
        do_reset; step("1110"); expect(0, '1', "T+C+M=11");
        do_reset; step("1111"); expect(0, '1', "V+T+C+M=14");
        -- spike lasts exactly one timestep
        step("0000"); expect(0, '0', "spike one timestep wide");

        -- (4) Temporal accumulation V -> idle -> C -> M (FSD 18)
        report "LIF: temporal accumulation";
        do_reset;
        step("0001"); expect(3,  '0', "t0 Voltage");
        step("0000"); expect(3,  '0', "t1 idle (leak 3>>3=0)");
        step("0100"); expect(7,  '0', "t2 Clock");
        step("1000"); expect(0,  '1', "t3 Memory -> 12 >= 10 spike, reset");
        step("0000"); expect(0,  '0', "t4 post-spike");

        -- (5) Leak decay: 9 -> 8 -> 7 -> 7
        report "LIF: leak";
        do_reset;
        step("1100"); expect(9, '0', "C+M=9");
        step("0000"); expect(8, '0', "leak 9-1");
        step("0000"); expect(7, '0', "leak 8-1");
        step("0000"); expect(7, '0', "leak 7>>3=0");

        -- (6) Repeated same parameter: 3, 6, 9, (leak to 7), 10 -> spike
        report "LIF: repeated voltage";
        do_reset;
        step("0001"); expect(3, '0', "V#1");
        step("0001"); expect(6, '0', "V#2");
        step("0001"); expect(9, '0', "V#3");
        step("0000"); step("0000"); expect(7, '0', "leak to 7");
        step("0001"); expect(0, '1', "V#4 -> 10 spike");

        -- (7) Pseudo-random stimulus, model checker compares every clock
        report "LIF: random stimulus";
        do_reset;
        for n in 1 to 400 loop
            for i in 0 to 3 loop
                pat(i) := lfsr(i) and lfsr(i + 8);   -- ~25 % event density
            end loop;
            lfsr := lfsr(14 downto 0) & (lfsr(15) xor lfsr(13) xor lfsr(12) xor lfsr(10));
            step(pat);
            if snn_spike = '1' then
                spikes := spikes + 1;
            end if;
        end loop;
        check(spikes > 0, "random test produced no spikes", errs);
        report "LIF: random test spikes = " & integer'image(spikes);

        -- Finish
        wait until rising_edge(clk);
        wait for 2 ns;
        check(model_steps > 400, "model checker did not run", errs);
        if errs + model_errors = 0 then
            report "TB_LIF_NEURON: PASS (" & integer'image(model_steps) & " timesteps checked)";
        else
            report "TB_LIF_NEURON: FAIL (" & integer'image(errs + model_errors) & " errors)"
                severity failure;
        end if;
        sim_done <= true;
        std.env.finish;
        wait;
    end process stim_proc;

end architecture sim;
