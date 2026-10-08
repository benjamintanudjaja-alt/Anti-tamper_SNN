--------------------------------------------------------------------------------
-- SynapseGuard - tb_synapseguard_top
--
-- Self-checking system testbench for synapseguard_top (FSD 29, 30, 34).
--
-- * Drives a real 100 MHz clock. The DUT is told CLK_FREQ_HZ = 100 kHz, so one
--   SNN timestep = 100 clocks (1 us). Debounce stays at 20 SNN ticks.
-- * GSR is simulated with USE_STARTUPE2 = false: the penalty path then works
--   as a synchronous internal soft reset (the same reset the hardware also
--   gets), so the simulator never resets or stops itself.
-- * Internal signals are monitored with VHDL-2008 external names.
-- * Memory demo: BTN_MEM sets LED_MEM, cleared by GSR / soft_rst.
-- * Accumulation bargraph: LED_VMEM expands towards H17.
-- * 1-Second Step Leak: holds at 4 LEDs, then 1 LED turns off every 1 second
--   (LEAK_TICKS ticks) down to 0.
-- * Direct GSR from SWA extreme inputs.
--
-- Prints "TB_SYNAPSEGUARD_TOP: PASS" or "...: FAIL" and stops automatically.
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.tb_pkg.all;

entity tb_synapseguard_top is
end entity tb_synapseguard_top;

architecture sim of tb_synapseguard_top is

    type nat_array_t is array (0 to 3) of natural;

    signal clk       : std_logic := '0';
    signal swa       : std_logic_vector(3 downto 0) := (others => '0');
    signal swb       : std_logic_vector(3 downto 0) := (others => '0');
    signal btn_mem   : std_logic := '0';
    signal led0      : std_logic;
    signal led_mem   : std_logic;
    signal led_vmem  : std_logic_vector(7 downto 0);
    signal led0_base : std_logic;
    signal sim_done  : boolean := false;

    -- monitor results
    signal gray_evt_cnt   : nat_array_t := (others => 0);
    signal last_syn       : natural := 0;
    signal model_errors   : natural := 0;
    signal model_steps    : natural := 0;
    signal spike_cnt      : natural := 0;
    signal penalty_cnt    : natural := 0;
    signal base_pen_cnt   : natural := 0;

begin

    ----------------------------------------------------------------------------
    -- 100 MHz clock
    ----------------------------------------------------------------------------
    clk <= not clk after CLK_PERIOD / 2 when not sim_done else '0';

    ----------------------------------------------------------------------------
    -- DUT: SNN mode, simulation-safe GSR
    ----------------------------------------------------------------------------
    dut : entity work.synapseguard_top
        generic map (
            CLK_FREQ_HZ        => TB_CLK_FREQ_HZ,
            SNN_TICK_HZ        => TB_SNN_TICK_HZ,
            DEBOUNCE_MS        => TB_DEBOUNCE_MS,
            MEMBRANE_WIDTH     => C_MEMBRANE_WIDTH,
            WEIGHT_VOLTAGE     => C_WEIGHT_VOLTAGE,
            WEIGHT_TEMP        => C_WEIGHT_TEMP,
            WEIGHT_CLOCK       => C_WEIGHT_CLOCK,
            WEIGHT_MEMORY      => C_WEIGHT_MEMORY,
            SPIKE_THRESHOLD    => C_SPIKE_THRESHOLD,
            RESET_POTENTIAL    => C_RESET_POTENTIAL,
            LEAK_TICKS         => C_LEAK_TICKS,
            USE_SNN            => true,
            SPIKES_FOR_PENALTY => 2,
            RESET_PULSE_CYCLES => 32,
            USE_STARTUPE2      => false
        )
        port map (
            CLK100MHZ => clk,
            SWA       => swa,
            SWB       => swb,
            BTN_MEM   => btn_mem,
            LED0      => led0,
            LED_MEM   => led_mem,
            LED_VMEM  => led_vmem
        );

    ----------------------------------------------------------------------------
    -- DUT: baseline mode (threshold detector only, FSD 28)
    ----------------------------------------------------------------------------
    dut_base : entity work.synapseguard_top
        generic map (
            CLK_FREQ_HZ        => TB_CLK_FREQ_HZ,
            SNN_TICK_HZ        => TB_SNN_TICK_HZ,
            DEBOUNCE_MS        => TB_DEBOUNCE_MS,
            USE_SNN            => false,
            USE_STARTUPE2      => false
        )
        port map (
            CLK100MHZ => clk,
            SWA       => swa,
            SWB       => swb,
            BTN_MEM   => btn_mem,
            LED0      => led0_base,
            LED_MEM   => open,
            LED_VMEM  => open
        );

    ----------------------------------------------------------------------------
    -- Monitors / checkers / stimulus
    ----------------------------------------------------------------------------
    verif : block
        alias snn_tick           is << signal .tb_synapseguard_top.dut.snn_tick           : std_logic >>;
        alias soft_rst           is << signal .tb_synapseguard_top.dut.soft_rst           : std_logic >>;
        alias threshold_alert    is << signal .tb_synapseguard_top.dut.threshold_alert    : std_logic >>;
        alias gray_spike         is << signal .tb_synapseguard_top.dut.gray_spike         : std_logic_vector(3 downto 0) >>;
        alias synaptic_input     is << signal .tb_synapseguard_top.dut.synaptic_input     : unsigned(7 downto 0) >>;
        alias membrane_potential is << signal .tb_synapseguard_top.dut.membrane_potential : unsigned(7 downto 0) >>;
        alias snn_spike          is << signal .tb_synapseguard_top.dut.snn_spike          : std_logic >>;
        alias warning_latched    is << signal .tb_synapseguard_top.dut.warning_latched    : std_logic >>;
        alias penalty_request    is << signal .tb_synapseguard_top.dut.penalty_request    : std_logic >>;

        alias base_alert         is << signal .tb_synapseguard_top.dut_base.threshold_alert    : std_logic >>;
        alias base_vmem          is << signal .tb_synapseguard_top.dut_base.membrane_potential : unsigned(7 downto 0) >>;
        alias base_penalty       is << signal .tb_synapseguard_top.dut_base.penalty_request    : std_logic >>;
    begin

        ------------------------------------------------------------------------
        -- LIF reference model + gray event monitor (every clock)
        ------------------------------------------------------------------------
        model_proc : process
            variable m_vmem  : natural := 0;
            variable m_spike : std_logic := '0';
            variable v_next  : natural;
            variable s       : natural;
            variable l_timer : natural := 0;
        begin
            wait until rising_edge(clk);

            if soft_rst = '1' then
                m_vmem  := 0;
                m_spike := '0';
                l_timer := 0;
            elsif snn_tick = '1' then
                model_steps <= model_steps + 1;

                s := 0;
                if gray_spike(0) = '1' then s := s + C_WEIGHT_VOLTAGE; end if;
                if gray_spike(1) = '1' then s := s + C_WEIGHT_TEMP;    end if;
                if gray_spike(2) = '1' then s := s + C_WEIGHT_CLOCK;   end if;
                if gray_spike(3) = '1' then s := s + C_WEIGHT_MEMORY;  end if;

                if to_integer(synaptic_input) /= s then
                    report "FAIL [ref model] synaptic_input mismatch at " & time'image(now) &
                           ": got " & integer'image(to_integer(synaptic_input)) & ", expected " & integer'image(s)
                        severity error;
                    model_errors <= model_errors + 1;
                end if;

                if s > 0 then
                    l_timer := 0;
                    v_next  := m_vmem + s;
                    if v_next > 255 then v_next := 255; end if;
                    if v_next >= C_SPIKE_THRESHOLD then
                        m_spike := '1';
                        m_vmem  := C_RESET_POTENTIAL;
                    else
                        m_spike := '0';
                        m_vmem  := v_next;
                    end if;
                else
                    m_spike := '0';
                    if m_vmem = 0 then
                        l_timer := 0;
                    elsif l_timer = C_LEAK_TICKS - 1 then
                        l_timer := 0;
                        m_vmem  := leak_step(m_vmem);
                    else
                        l_timer := l_timer + 1;
                    end if;
                end if;

                if snn_spike /= m_spike then
                    report "FAIL [ref model] snn_spike mismatch at " & time'image(now) &
                           ": got " & std_logic'image(snn_spike) & ", expected " & std_logic'image(m_spike)
                        severity error;
                    model_errors <= model_errors + 1;
                end if;

                if to_integer(membrane_potential) /= m_vmem then
                    report "FAIL [ref model] membrane_potential mismatch at " & time'image(now) &
                           ": got " & integer'image(to_integer(membrane_potential)) & ", expected " & integer'image(m_vmem)
                        severity error;
                    model_errors <= model_errors + 1;
                end if;
            end if;

            if snn_tick = '1' then
                for ch in 0 to 3 loop
                    if gray_spike(ch) = '1' then
                        gray_evt_cnt(ch) <= gray_evt_cnt(ch) + 1;
                    end if;
                end loop;
                if to_integer(synaptic_input) > 0 then
                    last_syn <= to_integer(synaptic_input);
                end if;
            end if;
        end process model_proc;

        spike_mon : process
        begin
            wait until rising_edge(snn_spike);
            spike_cnt <= spike_cnt + 1;
            report "  [mon] snn_spike #" & integer'image(spike_cnt + 1) & " at " & time'image(now);
        end process spike_mon;

        penalty_mon : process
        begin
            wait until rising_edge(penalty_request);
            penalty_cnt <= penalty_cnt + 1;
            report "  [mon] penalty_request (GSR) #" & integer'image(penalty_cnt + 1) & " at " & time'image(now);
        end process penalty_mon;

        base_pen_mon : process
        begin
            wait until rising_edge(base_penalty);
            base_pen_cnt <= base_pen_cnt + 1;
        end process base_pen_mon;

        ------------------------------------------------------------------------
        -- Stimulus and directed checks
        ------------------------------------------------------------------------
        stim_proc : process
            variable errs : natural := 0;

            procedure wait_ticks (n : natural) is
            begin
                for i in 1 to n loop
                    wait until rising_edge(clk) and snn_tick = '1';
                end loop;
                wait for 1 ns;
            end procedure;

            procedure wait_clks (n : natural) is
            begin
                for i in 1 to n loop
                    wait until rising_edge(clk);
                end loop;
                wait for 1 ns;
            end procedure;

            procedure drive_swb (new_val : std_logic_vector(3 downto 0); bounce : boolean) is
                variable old_val : std_logic_vector(3 downto 0);
            begin
                old_val := swb;
                if bounce then
                    for b in 1 to 4 loop
                        swb <= new_val;
                        wait for 2 * TB_TICK_PERIOD + 130 ns;
                        swb <= old_val;
                        wait for TB_TICK_PERIOD + 370 ns;
                    end loop;
                end if;
                swb <= new_val;
                wait_ticks(TB_DEBOUNCE_TICKS + 4);
            end procedure;

            procedure chk_int (actual, expected : natural; tag : string) is
            begin
                check(actual = expected,
                      tag & ": got " & integer'image(actual) & ", expected " & integer'image(expected), errs);
            end procedure;

            procedure chk_sl (actual, expected : std_logic; tag : string) is
            begin
                check(actual = expected,
                      tag & ": got " & std_logic'image(actual) & ", expected " & std_logic'image(expected), errs);
            end procedure;

            procedure chk_vmem (expected : natural; tag : string) is
            begin
                chk_int(to_integer(membrane_potential), expected, tag & " membrane_potential");
            end procedure;

            procedure chk_base_idle (tag : string) is
            begin
                chk_sl(led0_base, '0', tag & " baseline LED0");
                chk_int(to_integer(base_vmem), 0, tag & " baseline Vmem");
            end procedure;

        begin
            report "==== SynapseGuard system testbench start ====";
            wait_ticks(5);

            --------------------------------------------------------------------
            -- TB-01 Normal operation & Memory Demo initial state
            --------------------------------------------------------------------
            report "TB-01 normal operation";
            wait_ticks(30);
            chk_sl(threshold_alert, '0', "TB-01 threshold_alert");
            chk_sl(snn_spike,       '0', "TB-01 snn_spike");
            chk_sl(led0,            '0', "TB-01 LED0");
            chk_sl(warning_latched, '0', "TB-01 warning_latched");
            chk_sl(led_mem,         '0', "TB-01 initial led_mem");
            chk_sl(led_vmem(7),     '0', "TB-01 initial led_vmem(7)");
            chk_sl(led_vmem(0),     '0', "TB-01 initial led_vmem(0)");
            chk_int(spike_cnt,   0, "TB-01 spike count");
            chk_int(penalty_cnt, 0, "TB-01 GSR/penalty count");
            chk_vmem(0, "TB-01");
            chk_base_idle("TB-01");

            -- Test memory button N17 setting LED_MEM
            report "TB-01b Memory latch demonstration (BTN_MEM -> LED_MEM)";
            btn_mem <= '1';
            wait_clks(6);
            btn_mem <= '0';
            wait_clks(6);
            chk_sl(led_mem, '1', "TB-01b memory latch set to 1");

            --------------------------------------------------------------------
            -- TB-02..05 Extreme inputs SWA -> DIRECT GSR (no warning LED)
            --------------------------------------------------------------------
            for i in 0 to 3 loop
                report "TB-0" & integer'image(i + 2) & " extreme input SWA(" & integer'image(i) & ") -> direct GSR";
                swa    <= (others => '0');
                swa(i) <= '1';
                wait_clks(6);
                chk_sl(threshold_alert, '1', "TB-0" & integer'image(i + 2) & " threshold_alert");
                chk_sl(led0,            '0', "TB-0" & integer'image(i + 2) & " no warning LED on SWA");
                chk_sl(led_mem,         '0', "TB-0" & integer'image(i + 2) & " memory erased by SWA GSR");

                swa <= (others => '0');
                wait_clks(40); -- wait for reset pulse to complete
                chk_sl(threshold_alert, '0', "TB-0" & integer'image(i + 2) & " threshold_alert release");
                chk_sl(penalty_request, '0', "TB-0" & integer'image(i + 2) & " GSR deasserted after release");

                -- Re-arm memory latch for the next test
                btn_mem <= '1';
                wait_clks(6);
                btn_mem <= '0';
                wait_clks(6);
                chk_sl(led_mem, '1', "TB-0" & integer'image(i + 2) & " memory latch re-armed");
            end loop;

            swa <= "1111";
            wait_clks(6);
            chk_sl(threshold_alert, '1', "TB-02..05 all extremes");
            chk_sl(led_mem,         '0', "TB-02..05 memory cleared by all extremes");
            swa <= "0000";
            wait_clks(40);
            chk_sl(threshold_alert, '0', "TB-02..05 all released");
            chk_sl(penalty_request, '0', "TB-02..05 GSR self-terminated");
            chk_vmem(0, "TB-02..05 SNN untouched");

            -- Re-arm memory latch before gray-zone SWB tests
            btn_mem <= '1';
            wait_clks(6);
            btn_mem <= '0';
            wait_clks(6);
            chk_sl(led_mem, '1', "Memory latch armed for SWB tests");

            --------------------------------------------------------------------
            -- TB-06 Single gray event (with bounce) + Bargraph check
            --------------------------------------------------------------------
            report "TB-06 single gray event (Voltage, bouncing switch)";
            drive_swb("0001", true);
            chk_int(gray_evt_cnt(CH_VOLTAGE), 1, "TB-06 bouncing press -> exactly one event");
            chk_int(last_syn, C_WEIGHT_VOLTAGE,  "TB-06 synaptic_input");
            chk_vmem(3, "TB-06");
            chk_int(spike_cnt, 0, "TB-06 single event must not fire");
            chk_sl(led0, '0', "TB-06 LED0");
            chk_sl(led_vmem(7), '1', "TB-06 LED_VMEM(7) U16 lit");
            chk_sl(led_vmem(6), '1', "TB-06 LED_VMEM(6) U17 lit");
            chk_sl(led_vmem(5), '1', "TB-06 LED_VMEM(5) V17 lit");
            chk_sl(led_vmem(0), '0', "TB-06 LED_VMEM(0) H17 off");

            report "TB-06b persistent HIGH";
            wait_ticks(3 * TB_DEBOUNCE_TICKS);
            chk_int(gray_evt_cnt(CH_VOLTAGE), 1, "TB-06b persistent HIGH -> no repeated events");
            chk_vmem(3, "TB-06b residual potential retained");

            drive_swb("0000", true);
            chk_int(gray_evt_cnt(CH_VOLTAGE), 1, "TB-06c release (1->0) -> no event");
            chk_base_idle("TB-06");

            --------------------------------------------------------------------
            -- TB-10 / TB-11 Temporal pattern Voltage -> Clock -> Memory
            --------------------------------------------------------------------
            report "TB-10 temporal pattern Voltage -> Clock -> Memory";
            drive_swb("0100", true);
            chk_int(gray_evt_cnt(CH_CLOCK), 1, "TB-10 clock event");
            chk_int(last_syn, C_WEIGHT_CLOCK, "TB-10 synaptic_input (clock)");
            chk_vmem(7, "TB-10 accumulated 3+4");
            chk_int(spike_cnt, 0, "TB-10 no spike yet");
            chk_sl(led_vmem(2), '1', "TB-10 LED_VMEM(2) J13 lit");
            drive_swb("0000", true);
            wait_ticks(5);
            chk_vmem(7, "TB-10 residual potential across timesteps");

            drive_swb("1000", true);
            chk_int(gray_evt_cnt(CH_MEMORY), 1, "TB-10 memory event");
            chk_int(last_syn, C_WEIGHT_MEMORY, "TB-10 synaptic_input (memory)");
            chk_int(spike_cnt, 1, "TB-10 7+5=12 >= 10 -> spike");
            report "TB-11 post-spike reset";
            chk_vmem(C_RESET_POTENTIAL, "TB-11 reset to RESET_POTENTIAL");
            chk_sl(warning_latched, '1', "TB-10 warning_latched");
            chk_sl(led0, '1', "TB-10 LED0 ON (Warning)");
            chk_sl(led_mem, '1', "TB-10 first spike: memory intact, no GSR yet");
            drive_swb("0000", true);
            wait_ticks(10);
            chk_sl(led0, '1', "TB-10 LED0 stays latched");
            chk_base_idle("TB-10");

            --------------------------------------------------------------------
            -- TB-07 Two simultaneous gray events (V + C = 7)
            --------------------------------------------------------------------
            report "TB-07 two simultaneous gray events (Voltage + Clock)";
            drive_swb("0101", false);
            chk_int(gray_evt_cnt(CH_VOLTAGE), 2, "TB-07 voltage event");
            chk_int(gray_evt_cnt(CH_CLOCK),   2, "TB-07 clock event");
            chk_int(last_syn, 7, "TB-07 synaptic_input 3+4");
            chk_vmem(7, "TB-07");
            chk_int(spike_cnt, 1, "TB-07 two events must not fire");
            drive_swb("0000", false);

            --------------------------------------------------------------------
            -- TB-12 Penalty: residual 7 + Memory 5 -> 2nd spike -> GSR
            --------------------------------------------------------------------
            report "TB-12 penalty (2nd spike -> STARTUPE2 GSR / soft reset)";
            drive_swb("1000", true);
            chk_int(spike_cnt,   2, "TB-12 second spike");
            chk_sl(penalty_request, '0', "TB-12 GSR pulse self-terminated");
            chk_sl(warning_latched, '0', "TB-12 GSR cleared warning latch");
            chk_sl(led0, '0', "TB-12 LED0 cleared by GSR");
            chk_sl(led_mem, '0', "TB-12 memory erased by SWB GSR");
            chk_sl(led_vmem(7), '0', "TB-12 bargraph cleared by GSR");
            chk_vmem(0, "TB-12 SNN back to initial state");

            report "TB-12b switch held HIGH after GSR -> no reset loop";
            wait_ticks(3 * TB_DEBOUNCE_TICKS);
            chk_int(gray_evt_cnt(CH_MEMORY), 2, "TB-12b held switch does not re-trigger");
            chk_int(spike_cnt,   2, "TB-12b no new spike");
            drive_swb("0000", true);
            chk_base_idle("TB-12");

            --------------------------------------------------------------------
            -- TB-13 1-Second Step Leak: Hold at 4 LEDs -> 1 LED/s down to 0
            --------------------------------------------------------------------
            report "TB-13 1-second step leak demonstration (Memory -> 4 LEDs -> 1 LED/s to 0)";
            drive_swb("1000", true); -- Memory event: weight = 5 -> 4 LEDs (level 5)
            chk_vmem(5, "TB-13 Memory event reaches 4 LEDs");
            chk_sl(led_vmem(4), '1', "TB-13 4th LED (R18) is ON");
            drive_swb("0000", true);

            -- After 1 second (C_LEAK_TICKS): 4th LED turns off (5 -> 3, 3 LEDs)
            wait_ticks(C_LEAK_TICKS);
            chk_vmem(3, "TB-13 after 1s: 3 LEDs");
            chk_sl(led_vmem(4), '0', "TB-13 4th LED turned off");
            chk_sl(led_vmem(5), '1', "TB-13 3rd LED (V17) still ON");

            -- After 2nd second: 3rd LED turns off (3 -> 2, 2 LEDs)
            wait_ticks(C_LEAK_TICKS);
            chk_vmem(2, "TB-13 after 2s: 2 LEDs");
            chk_sl(led_vmem(5), '0', "TB-13 3rd LED turned off");
            chk_sl(led_vmem(6), '1', "TB-13 2nd LED (U17) still ON");

            -- After 3rd second: 2nd LED turns off (2 -> 1, 1 LED)
            wait_ticks(C_LEAK_TICKS);
            chk_vmem(1, "TB-13 after 3s: 1 LED");
            chk_sl(led_vmem(6), '0', "TB-13 2nd LED turned off");
            chk_sl(led_vmem(7), '1', "TB-13 1st LED (U16) still ON");

            -- After 4th second: 1st LED turns off (1 -> 0, all OFF)
            wait_ticks(C_LEAK_TICKS);
            chk_vmem(0, "TB-13 after 4s: completely extinguished to 0");
            chk_sl(led_vmem(7), '0', "TB-13 all LEDs extinguished");

            --------------------------------------------------------------------
            -- Summary
            --------------------------------------------------------------------
            wait_ticks(5);
            check(model_steps > 300, "reference model checked too few timesteps", errs);

            report "==== Summary ====";
            report "  SNN timesteps checked : " & integer'image(model_steps);
            report "  SNN spikes            : " & integer'image(spike_cnt);
            report "  GSR penalties         : " & integer'image(penalty_cnt);
            report "  model errors          : " & integer'image(model_errors);
            report "  directed errors       : " & integer'image(errs);

            if errs + model_errors = 0 then
                report "TB_SYNAPSEGUARD_TOP: PASS";
            else
                report "TB_SYNAPSEGUARD_TOP: FAIL" severity failure;
            end if;
            sim_done <= true;
            std.env.finish;
            wait;
        end process stim_proc;

        ------------------------------------------------------------------------
        -- Watchdog
        ------------------------------------------------------------------------
        watchdog : process
        begin
            wait for 50 ms;
            report "TB_SYNAPSEGUARD_TOP: FAIL (watchdog timeout)" severity failure;
            wait;
        end process watchdog;

    end block verif;

end architecture sim;
