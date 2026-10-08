--------------------------------------------------------------------------------
-- SynapseGuard - gray_event_encoder  (FSD 9)
--
-- Converts debounced gray-zone levels into one-timestep events:
--   0 -> 1      : exactly one event (gray_spike(i) = '1' for one SNN timestep)
--   1 -> 1      : no event
--   1 -> 0 -> 1 : required before the next event
--
-- Reset-loop protection (FSD 22): an input must be observed LOW at least once
-- after configuration / GSR ("armed") before it can produce an event. A switch
-- that is still HIGH when the penalty reset releases therefore does NOT
-- re-trigger the neuron and cannot create a permanent GSR loop.
--
-- gray_spike(0)=Voltage, (1)=Temperature, (2)=Clock, (3)=Memory Integrity
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;

entity gray_event_encoder is
    port (
        clk        : in  std_logic;
        rst        : in  std_logic;
        tick       : in  std_logic;                     -- SNN clock enable
        gray_in    : in  std_logic_vector(3 downto 0);  -- debounced SWB levels
        gray_spike : out std_logic_vector(3 downto 0)   -- one-timestep events
    );
end entity gray_event_encoder;

architecture rtl of gray_event_encoder is
    signal previous_gray : std_logic_vector(3 downto 0) := (others => '0');
    signal armed         : std_logic_vector(3 downto 0) := (others => '0');
    signal spike_r       : std_logic_vector(3 downto 0) := (others => '0');
begin

    encode_proc : process (clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                previous_gray <= (others => '0');
                armed         <= (others => '0');
                spike_r       <= (others => '0');
            elsif tick = '1' then
                -- rising-edge detection, held for exactly one SNN timestep
                spike_r       <= gray_in and (not previous_gray) and armed;
                previous_gray <= gray_in;
                -- arm each channel once a LOW level has been observed
                armed         <= armed or (not gray_in);
            end if;
        end if;
    end process encode_proc;

    gray_spike <= spike_r;

end architecture rtl;
