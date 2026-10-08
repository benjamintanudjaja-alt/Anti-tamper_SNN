--------------------------------------------------------------------------------
-- SynapseGuard - input_conditioner
--
-- * Two-flip-flop synchronizer for all 8 asynchronous switch inputs (FSD 8).
-- * Tick-based debouncer for the 4 gray-zone switches (SWB).
--   A new level is accepted only after it has been sampled DEBOUNCE_TICKS
--   consecutive SNN ticks (default 20 ticks @ 1 kHz = 20 ms).
-- * Extreme switches (SWA) are only synchronized (they feed the
--   combinational Layer-1 threshold detector).
--
-- rst : synchronous soft reset (GSR emulation from the penalty path).
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity input_conditioner is
    generic (
        DEBOUNCE_TICKS : positive := 20
    );
    port (
        clk       : in  std_logic;
        rst       : in  std_logic;
        tick      : in  std_logic;                       -- SNN clock enable
        swa_in    : in  std_logic_vector(3 downto 0);    -- raw extreme switches
        swb_in    : in  std_logic_vector(3 downto 0);    -- raw gray-zone switches
        swa_sync  : out std_logic_vector(3 downto 0);    -- synchronized SWA
        swb_clean : out std_logic_vector(3 downto 0)     -- synchronized + debounced SWB
    );
end entity input_conditioner;

architecture rtl of input_conditioner is

    signal swa_meta : std_logic_vector(3 downto 0) := (others => '0');
    signal swa_s    : std_logic_vector(3 downto 0) := (others => '0');
    signal swb_meta : std_logic_vector(3 downto 0) := (others => '0');
    signal swb_s    : std_logic_vector(3 downto 0) := (others => '0');

    attribute ASYNC_REG : string;
    attribute ASYNC_REG of swa_meta : signal is "TRUE";
    attribute ASYNC_REG of swa_s    : signal is "TRUE";
    attribute ASYNC_REG of swb_meta : signal is "TRUE";
    attribute ASYNC_REG of swb_s    : signal is "TRUE";

    type cnt_array_t is array (0 to 3) of natural range 0 to DEBOUNCE_TICKS - 1;
    signal deb_cnt : cnt_array_t := (others => 0);
    signal stable  : std_logic_vector(3 downto 0) := (others => '0');

begin

    ----------------------------------------------------------------------------
    -- 2-FF synchronizers (free running, every 100 MHz clock)
    ----------------------------------------------------------------------------
    sync_proc : process (clk)
    begin
        if rising_edge(clk) then
            swa_meta <= swa_in;
            swa_s    <= swa_meta;
            swb_meta <= swb_in;
            swb_s    <= swb_meta;
        end if;
    end process sync_proc;

    ----------------------------------------------------------------------------
    -- Debouncer for gray-zone inputs, sampled on SNN ticks
    ----------------------------------------------------------------------------
    debounce_proc : process (clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                deb_cnt <= (others => 0);
                stable  <= (others => '0');
            elsif tick = '1' then
                for i in 0 to 3 loop
                    if swb_s(i) = stable(i) then
                        -- input agrees with accepted level: restart qualification
                        deb_cnt(i) <= 0;
                    elsif deb_cnt(i) = DEBOUNCE_TICKS - 1 then
                        -- input differed for DEBOUNCE_TICKS consecutive ticks
                        stable(i)  <= swb_s(i);
                        deb_cnt(i) <= 0;
                    else
                        deb_cnt(i) <= deb_cnt(i) + 1;
                    end if;
                end loop;
            end if;
        end if;
    end process debounce_proc;

    swa_sync  <= swa_s;
    swb_clean <= stable;

end architecture rtl;
