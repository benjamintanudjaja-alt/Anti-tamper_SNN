--------------------------------------------------------------------------------
-- SynapseGuard - tb_pkg
--
-- Shared testbench constants, LIF reference model and check helpers.
-- Simulation only (not synthesizable).
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package tb_pkg is

    ----------------------------------------------------------------------------
    -- Timing
    --   The testbench runs a real 100 MHz clock, but tells the DUT that the
    --   clock is TB_CLK_FREQ_HZ. This compresses the SNN timestep from
    --   100_000 cycles to 100 cycles (1 us) so that the full test runs in a
    --   few ms of simulated time. All behavior in SNN ticks is unchanged
    --   (debounce = 20 ticks, etc.).
    ----------------------------------------------------------------------------
    constant CLK_PERIOD        : time     := 10 ns;
    constant TB_CLK_FREQ_HZ    : positive := 100_000;
    constant TB_SNN_TICK_HZ    : positive := 1000;
    constant TB_DEBOUNCE_MS    : positive := 20;
    constant TB_TICK_DIV       : positive := TB_CLK_FREQ_HZ / TB_SNN_TICK_HZ;
    constant TB_TICK_PERIOD    : time     := CLK_PERIOD * TB_TICK_DIV;
    constant TB_DEBOUNCE_TICKS : positive := (TB_DEBOUNCE_MS * TB_SNN_TICK_HZ) / 1000;

    ----------------------------------------------------------------------------
    -- Default LIF parameters (FSD 27)
    ----------------------------------------------------------------------------
    constant C_MEMBRANE_WIDTH  : positive := 8;
    constant C_WEIGHT_VOLTAGE  : natural  := 3;
    constant C_WEIGHT_TEMP     : natural  := 2;
    constant C_WEIGHT_CLOCK    : natural  := 4;
    constant C_WEIGHT_MEMORY   : natural  := 5;
    constant C_SPIKE_THRESHOLD : natural  := 10;
    constant C_RESET_POTENTIAL : natural  := 0;
    constant C_LEAK_TICKS      : positive := 1000; -- 1000 ticks @ 1 kHz = 1.0 s
    constant C_VMAX            : natural  := 2 ** C_MEMBRANE_WIDTH - 1;

    -- gray channel indices
    constant CH_VOLTAGE : natural := 0;
    constant CH_TEMP    : natural := 1;
    constant CH_CLOCK   : natural := 2;
    constant CH_MEMORY  : natural := 3;

    ----------------------------------------------------------------------------
    -- Reference model helpers
    ----------------------------------------------------------------------------
    function weighted_sum (spk : std_logic_vector(3 downto 0)) return natural;
    function leak_step (v : natural) return natural;

    procedure check (
        constant cond : in    boolean;
        constant msg  : in    string;
        variable errs : inout natural
    );

    function to_str (v : std_logic_vector) return string;

end package tb_pkg;

package body tb_pkg is

    function weighted_sum (spk : std_logic_vector(3 downto 0)) return natural is
        variable s : natural := 0;
    begin
        if spk(CH_VOLTAGE) = '1' then s := s + C_WEIGHT_VOLTAGE; end if;
        if spk(CH_TEMP)    = '1' then s := s + C_WEIGHT_TEMP;    end if;
        if spk(CH_CLOCK)   = '1' then s := s + C_WEIGHT_CLOCK;   end if;
        if spk(CH_MEMORY)  = '1' then s := s + C_WEIGHT_MEMORY;  end if;
        return s;
    end function;

    function leak_step (v : natural) return natural is
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

    procedure check (
        constant cond : in    boolean;
        constant msg  : in    string;
        variable errs : inout natural
    ) is
    begin
        if not cond then
            errs := errs + 1;
            report "CHECK FAILED: " & msg severity error;
        end if;
    end procedure;

    function to_str (v : std_logic_vector) return string is
        variable s : string(1 to v'length);
        variable k : positive := 1;
    begin
        for i in v'range loop
            s(k) := std_logic'image(v(i))(2);
            k    := k + 1;
        end loop;
        return s;
    end function;

end package body tb_pkg;
