--------------------------------------------------------------------------------
-- SynapseGuard - penalty_gsr  (FSD 21, 22)
--
-- Counts SNN spikes and monitors extreme threshold alert (SWA Layer 1).
-- Triggers penalty (penalty_request + soft_rst + Artix-7 STARTUPE2 GSR) when:
--   1. SPIKES_FOR_PENALTY SNN spikes have been observed from SWB.
--   2. SWA extreme alert is asserted (Layer 1 threshold crossing -> direct GSR).
--
-- Self-terminating reset pulse:
--   penalty_r is stretched to RESET_PULSE_CYCLES clocks (default 32 = 320 ns)
--   to ensure all internal slices, flip-flops, and STARTUPE2 GSR complete
--   reset propagation, then deasserts automatically.
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;

entity penalty_gsr is
    generic (
        SPIKES_FOR_PENALTY : positive := 2;
        RESET_PULSE_CYCLES : positive := 32;
        USE_STARTUPE2      : boolean  := true
    );
    port (
        clk             : in  std_logic;
        rst             : in  std_logic;
        snn_spike       : in  std_logic;
        extreme_alert   : in  std_logic := '0';
        penalty_request : out std_logic;
        soft_rst        : out std_logic
    );
end entity penalty_gsr;

architecture rtl of penalty_gsr is

    -- Component declaration for STARTUPE2
    component STARTUPE2 is
        generic (
            PROG_USR : string := "FALSE"
        );
        port (
            CFGCLK    : out std_ulogic;
            CFGMCLK   : out std_ulogic;
            EOS       : out std_ulogic;
            PREQ      : out std_ulogic;
            CLK       : in  std_ulogic;
            GSR       : in  std_ulogic;
            GTS       : in  std_ulogic;
            KEYCLEARB : in  std_ulogic;
            PACK      : in  std_ulogic;
            USRCCLKO  : in  std_ulogic;
            USRCCLKTS : in  std_ulogic;
            USRDONEO  : in  std_ulogic;
            USRDONETS : in  std_ulogic
        );
    end component;

    signal spike_d    : std_logic := '0';
    signal spike_cnt  : natural range 0 to SPIKES_FOR_PENALTY - 1 := 0;
    signal pulse_cnt  : natural range 0 to RESET_PULSE_CYCLES := 0;
    signal penalty_r  : std_logic := '0';

    attribute DONT_TOUCH : string;
    attribute DONT_TOUCH of penalty_r : signal is "TRUE";

begin

    ----------------------------------------------------------------------------
    -- Spike counter & extreme alert -> penalty request (self-terminating pulse)
    ----------------------------------------------------------------------------
    count_proc : process (clk)
    begin
        if rising_edge(clk) then
            spike_d <= snn_spike;

            if extreme_alert = '1' then
                -- Direct GSR from SWA extreme tamper condition
                penalty_r <= '1';
                pulse_cnt <= RESET_PULSE_CYCLES;
                spike_cnt <= 0;
            elsif pulse_cnt > 0 then
                -- Active penalty reset pulse countdown
                pulse_cnt <= pulse_cnt - 1;
                penalty_r <= '1';
            elsif snn_spike = '1' and spike_d = '0' then
                -- Rising edge of SNN spike from SWB
                if spike_cnt = SPIKES_FOR_PENALTY - 1 then
                    penalty_r <= '1';
                    pulse_cnt <= RESET_PULSE_CYCLES;
                    spike_cnt <= 0;
                else
                    spike_cnt <= spike_cnt + 1;
                    penalty_r <= '0';
                end if;
            else
                penalty_r <= '0';
            end if;
        end if;
    end process count_proc;

    penalty_request <= penalty_r;
    soft_rst        <= penalty_r;

    ----------------------------------------------------------------------------
    -- Hardware GSR access through STARTUPE2 (never an external pin / GPIO)
    ----------------------------------------------------------------------------
    gen_startup : if USE_STARTUPE2 generate
        u_startupe2 : STARTUPE2
            generic map (
                PROG_USR => "FALSE"
            )
            port map (
                CFGCLK    => open,
                CFGMCLK   => open,
                EOS       => open,
                PREQ      => open,
                CLK       => '0',        -- no user startup clock
                GSR       => penalty_r,  -- PENALTY: global set/reset
                GTS       => '0',        -- never tri-state user I/O
                KEYCLEARB => '1',        -- do not clear the BBRAM key
                PACK      => '0',
                USRCCLKO  => '0',
                USRCCLKTS => '1',        -- CCLK not driven by user logic
                USRDONEO  => '1',        -- keep DONE high
                USRDONETS => '1'
            );
    end generate gen_startup;

end architecture rtl;
