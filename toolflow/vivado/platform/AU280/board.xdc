# ------------------------------------------------------------------------
set_property CONFIG_VOLTAGE 1.8 [current_design]
set_property BITSTREAM.CONFIG.CONFIGFALLBACK Enable [current_design]
set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]
set_property CONFIG_MODE SPIx4 [current_design]
set_property BITSTREAM.CONFIG.SPI_BUSWIDTH 4 [current_design]
set_property BITSTREAM.CONFIG.CONFIGRATE 85.0 [current_design]
set_property BITSTREAM.CONFIG.EXTMASTERCCLK_EN disable [current_design]
set_property BITSTREAM.CONFIG.SPI_FALL_EDGE YES [current_design]
set_property BITSTREAM.CONFIG.UNUSEDPIN Pullup [current_design]
set_property BITSTREAM.CONFIG.SPI_32BIT_ADDR Yes [current_design]
# ------------------------------------------------------------------------

set_property PACKAGE_PIN D32 [get_ports {dout_0[0]}]

set_property IOSTANDARD LVCMOS18 [get_ports {dout_0[0]}]

# Constraints for left HBM stack

set_property PACKAGE_PIN BJ43 [get_ports hbm_ref_clk_0_clk_p]
set_property PACKAGE_PIN BJ44 [get_ports hbm_ref_clk_0_clk_n]
set_property IOSTANDARD LVDS [get_ports hbm_ref_clk_0_clk_p]
set_property IOSTANDARD LVDS [get_ports hbm_ref_clk_0_clk_n]
set_property DQS_BIAS TRUE [get_ports hbm_ref_clk_0_clk_p]

create_clock -period 10 -name hbm_ref_clk_0_clk_p [get_ports hbm_ref_clk_0_clk_p]

set_clock_groups -asynchronous -group [get_clocks hbm_ref_clk_0_clk_p -include_generated_clocks]
set_clock_groups -asynchronous -group [get_clocks clk_out1_system_clk_wiz_0 -include_generated_clocks]
set_clock_groups -asynchronous -group [get_clocks clk_out2_system_clk_wiz_0 -include_generated_clocks]


set_property CLOCK_DEDICATED_ROUTE BACKBONE [get_nets system_i/memory/mig/clocking_0/ibuf/U0/IBUF_OUT[0]]