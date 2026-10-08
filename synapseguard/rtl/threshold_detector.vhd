--------------------------------------------------------------------------------
-- SynapseGuard - threshold_detector  (Layer 1, FSD 10)
--
-- threshold_alert = SWA(0) OR SWA(1) OR SWA(2) OR SWA(3)
--
-- Registered output (initial value 0, FSD 23). Independent of the SNN.
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;

entity threshold_detector is
    port (
        clk             : in  std_logic;
        rst             : in  std_logic;
        swa             : in  std_logic_vector(3 downto 0);  -- synchronized extreme inputs
        threshold_alert : out std_logic
    );
end entity threshold_detector;

architecture rtl of threshold_detector is
    signal alert_r : std_logic := '0';
begin

    alert_proc : process (clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                alert_r <= '0';
            else
                alert_r <= swa(0) or swa(1) or swa(2) or swa(3);
            end if;
        end if;
    end process alert_proc;

    threshold_alert <= alert_r;

end architecture rtl;
