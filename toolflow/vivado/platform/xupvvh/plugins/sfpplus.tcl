# Copyright (c) 2014-2020 Embedded Systems and Applications, TU Darmstadt.
#
# This file is part of TaPaSCo
# (see https://github.com/esa-tu-darmstadt/tapasco).
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU Lesser General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Lesser General Public License for more details.
#
# You should have received a copy of the GNU Lesser General Public License
# along with this program. If not, see <http://www.gnu.org/licenses/>.
#

if {[tapasco::is_feature_enabled "SFPPLUS"]} {
  proc create_custom_subsystem_network {{args {}}} {

    variable data [tapasco::get_feature "SFPPLUS"]
    variable ports [sfpplus::get_portlist $data]
    create_bd_intf_pin -mode Slave -vlnv xilinx.com:interface:aximm_rtl:1.0 S_NETWORK
    sfpplus::makeMaster "M_NETWORK"
    puts "Creating Network Interfaces for Ports: $ports"
    sfpplus::generate_cores $ports

    variable value [dict values [dict remove $data enabled]]
    foreach port $value {
      sfpplus::generate_port $port
    }
    puts "Network Connection done"
    current_bd_instance /network
      
  }
}

namespace eval sfpplus {

  variable available_ports 4
  #variable refclk_pins           {"P13" "V13" "AD13" "AJ15"}
  #variable gt_quads              {"Quad_X1Y11" "Quad_X1Y9" "Quad_X1Y6" "Quad_X1Y4"}
  #variable gt_lanes              {"X1Y44" "X1Y45" "X1Y46" "X1Y47" "X1Y36" "X1Y37" "X1Y38" "X1Y39" "X1Y24" "X1Y25" "X1Y26" "X1Y27" "X1Y16" "X1Y17" "X1Y18" "X1Y19"}
  variable refclk_pins           {"AJ15" "V13" "AD13" "P13"}
  variable gt_quads              {"Quad_X1Y4" "Quad_X1Y9" "Quad_X1Y6" "Quad_X1Y11"}
  variable gt_lanes              {"X1Y16" "X1Y17" "X1Y18" "X1Y19" "X1Y36" "X1Y37" "X1Y38" "X1Y39" "X1Y24" "X1Y25" "X1Y26" "X1Y27" "X1Y44" "X1Y45" "X1Y46" "X1Y47"}

  proc find_ID {input} {
    variable composition
    for {variable o 0} {$o < [llength $composition] -1} {incr o} {
      if {[regexp ".*:$input:.*" [dict get $composition $o vlnv]]} {
        return $o
      }
    }
    return -1
  }

  proc countKernels {kernels} {
    variable counter 0

    foreach kernel $kernels {
      variable counter [expr {$counter + [dict get $kernel Count]}]
    }
    return $counter
  }

  proc get_portlist {input} {
    variable counter [list]
    variable value [dict values [dict remove $input enabled]]
    foreach kernel $value {
      variable counter [lappend counter [dict get $kernel PORT]]
    }
    return $counter
  }

  proc makeInverter {name} {
    variable ret [create_bd_cell -type ip -vlnv xilinx.com:ip:util_vector_logic:2.0 $name]
    set_property -dict [list CONFIG.C_SIZE {1} CONFIG.C_OPERATION {not} CONFIG.LOGO_FILE {data/sym_notgate.png}] [get_bd_cells $name]
    return $ret
  }

  # Start: Validating Configuration
  proc validate_sfp_ports {{args {}}} {
    if {[tapasco::is_feature_enabled "SFPPLUS"]} {
      variable available_ports
      variable composition [tapasco::get_composition]
      set f [tapasco::get_feature "SFPPLUS"]
      variable ky [dict keys $f]
      variable used_ports [list]

      puts "Checking SFP-Network for palausability:"
      # Check if Board supports enough SFP-Ports
      if { [llength $ky]-1 > $available_ports} {
        puts "To many SFP-Ports specified (Max: $available_ports)"
        exit
      }

      #Check if Port Config is valid
      for {variable i 0} {$i < [llength $ky]} {incr i} {
        set key [lindex $ky $i]
        if {$key != "enabled"} {
          variable port [dict get $f $key]
          lappend used_ports [dict get $port PORT]
          variable mode [dict get $port mode]
          puts "Port: [dict get $port PORT]"
          puts "  Mode: $mode"
          dict set [lindex [dict get $port kernel] 0] vlnv " "
          switch $mode {
            singular   { validate_singular $port }
            broadcast  { validate_broadcast $port }
            roundrobin { validate_roundrobin $port }
            default {
              puts "Mode $mode not supported"
              exit
            }
          }
          variable unique_ports [lsort -unique $used_ports]
          if { [llength $used_ports] > [llength $unique_ports]} {
            puts "Port-specification not Unique (Ports Specified: [lsort $used_ports])"
            exit
          }
        }
      }
      puts "SFP-Config OK"

    }
    return {}
  }

  # validate Port for singular mode
  proc validate_singular {config} {
    variable kern [dict get $config kernel]
    variable composition
    if {[llength $kern] == 1} {
      puts "  Kernel:"
      variable x [lindex $kern 0]
      dict set $x "vlnv" " "
      dict with  x {
        if  {[dict exists $x "allow_reuse_PEs"]} {
          set allow_reuse_PEs [dict get $x "allow_reuse_PEs"]
        } else {
          set allow_reuse_PEs false
        }
        puts "    ID: $ID"
        puts "    Count: $Count"
        puts "    Recieve:  $interface_rx"
        puts "    Transmit: $interface_tx"
        puts "    Allow Reuse: $allow_reuse_PEs"
        variable kernelID [find_ID $ID]
        if { $kernelID != -1 } {
          variable newCount [expr {[dict get $composition $kernelID count] - $Count}]
          set vlnv [dict get $composition $kernelID vlnv]
          if { $newCount < 0} {
            puts "Not Enough Instances of Kernel $ID"
            exit
          }
          if {!$allow_reuse_PEs} {
            [dict set composition $kernelID count $newCount]
          }
        } else {
          puts "Kernel not found"
          exit
        }
      }
    } else {
      puts "Only one Kernel allowed in Singular mode"
      exit
    }
  }

  # validate Port for broadcast mode
  proc validate_broadcast {config} {
    variable composition
    variable kern [dict get $config kernel]
    for {variable c 0} {$c < [llength $kern]} {incr c} {
      puts "  Kernel_$c:"
      variable x [lindex $kern $c]
      dict set $x "vlnv" " "
      dict with  x {
        if  {[dict exists $x "allow_reuse_PEs"]} {
          set allow_reuse_PEs [dict get $x "allow_reuse_PEs"]
        } else {
          set allow_reuse_PEs false
        }
        puts "    ID: $ID"
        puts "    Count: $Count"
        puts "    Recieve:  $interface_rx"
        puts "    Transmit: $interface_tx"
        puts "    Allow Reuse: $allow_reuse_PEs"
        variable kernelID [find_ID $ID]
        if { $kernelID != -1 } {
          variable newCount [expr {[dict get $composition $kernelID count] - $Count}]
          set vlnv [dict get $composition $kernelID vlnv]
          if { $newCount < 0} {
            puts "Not Enough Instances of Kernel $ID"
            exit
          }
          if {!$allow_reuse_PEs} {
            [dict set composition $kernelID count $newCount]
          }
        } else {
          puts "Kernel not found"
          exit
        }
      }
    }
  }

  # validate Port for roundrobin mode
  proc validate_roundrobin {config} {
    variable composition
    variable kern [dict get $config kernel]
    for {variable c 0} {$c < [llength $kern]} {incr c} {
      puts "  Kernel_$c:"
      variable x [lindex $kern $c]
      dict set $x "vlnv" " "
      dict with  x {
        if  {[dict exists $x "allow_reuse_PEs"]} {
          set allow_reuse_PEs [dict get $x "allow_reuse_PEs"]
        } else {
          set allow_reuse_PEs false
        }
        puts "    ID: $ID"
        puts "    Count: $Count"
        puts "    Recieve:  $interface_rx"
        puts "    Transmit: $interface_tx"
        puts "    Allow Reuse: $allow_reuse_PEs"
        variable kernelID [find_ID $ID]
        if { $kernelID != -1 } {
          variable newCount [expr {[dict get $composition $kernelID count] - $Count}]
          set vlnv [dict get $composition $kernelID vlnv]
          puts "VLNV: $vlnv"
          if { $newCount < 0} {
            puts "Not Enough Instances of Kernel $ID"
            exit
          }

          if {!$allow_reuse_PEs} {
            [dict set composition $kernelID count $newCount]
          }
        } else {
          puts "Kernel not found"
          exit
        }
      }
    }
  }
  # END: Validating Configuration

  # Generate Network Setup
  proc generate_cores {ports} {
    variable refclk_pins
    variable gt_quads
    variable gt_lanes

    set constraints_fn "[get_property DIRECTORY [current_project]]/sfpplus.xdc"
    set constraints_file [open $constraints_fn w+]

    for {set i 0} {$i < [llength $ports]} {incr i} {
      create_bd_pin -type clk -dir O sfp_clock_${i}
      create_bd_pin -type rst -dir O sfp_resetn_${i}
      create_bd_pin -type rst -dir O sfp_reset_${i}
    }

    #Setup CLK-Ports for Ethernet-Subsystem
    set gt_refclk_0 [create_bd_intf_port -mode Slave -vlnv xilinx.com:interface:diff_clock_rtl:1.0 gt_refclk_0]
    set_property CONFIG.FREQ_HZ 322265625 $gt_refclk_0
    puts $constraints_file [format {set_property PACKAGE_PIN %s [get_ports %s]} [lindex $refclk_pins 0] gt_refclk_0_clk_p]
    #puts $constraints_file [format {create_clock -name %s -period 3.104 [get_ports %s]} gtrefclk_0 gt_refclk_0_clk_p]
    # AXI Interconnect for Configuration
    create_bd_cell -type ip -vlnv xilinx.com:ip:axi_interconnect:2.1 AXI_Config
    set_property CONFIG.NUM_SI 1 [get_bd_cells AXI_Config]
    set_property CONFIG.NUM_MI [llength $ports] [get_bd_cells AXI_Config]

    set dclk_wiz [tapasco::ip::create_clk_wiz dclk_wiz]
    set_property -dict [list CONFIG.USE_SAFE_CLOCK_STARTUP {true} CONFIG.CLKOUT1_REQUESTED_OUT_FREQ 100 CONFIG.USE_LOCKED {false} CONFIG.USE_RESET {false}] $dclk_wiz

    create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 "dclk_reset"

    connect_bd_net [get_bd_pins dclk_wiz/clk_out1] [get_bd_pins dclk_reset/slowest_sync_clk]
    connect_bd_net [get_bd_pins design_peripheral_aresetn] [get_bd_pins dclk_reset/ext_reset_in]
    connect_bd_net [get_bd_pins design_clk] [get_bd_pins $dclk_wiz/clk_in1]
    connect_bd_net [get_bd_pins AXI_Config/M*_ACLK] [get_bd_pins $dclk_wiz/clk_out1]
    connect_bd_net [get_bd_pins AXI_Config/M*_ARESETN] [get_bd_pins dclk_reset/peripheral_aresetn]

    connect_bd_intf_net [get_bd_intf_pins AXI_Config/S00_AXI] [get_bd_intf_pins S_NETWORK]
    connect_bd_net [get_bd_pins AXI_Config/S00_ACLK] [get_bd_pins design_clk]
    connect_bd_net [get_bd_pins AXI_Config/S00_ARESETN] [get_bd_pins design_interconnect_aresetn]
    connect_bd_net [get_bd_pins AXI_Config/ACLK] [get_bd_pins design_clk]
    connect_bd_net [get_bd_pins AXI_Config/ARESETN] [get_bd_pins design_interconnect_aresetn]

    set core [create_bd_cell -type ip -vlnv xilinx.com:ip:xxv_ethernet:3.1 Ethernet10G]
    set_property -dict [list \
      CONFIG.NUM_OF_CORES [llength $ports] \
      CONFIG.LINE_RATE {10} \
      CONFIG.BASE_R_KR {BASE-R} \
      CONFIG.INCLUDE_AXI4_INTERFACE {1} \
      CONFIG.INCLUDE_STATISTICS_COUNTERS {0} \
      CONFIG.GT_REF_CLK_FREQ {322.265625} \
      CONFIG.GT_GROUP_SELECT [lindex $gt_quads 0]
      ] $core
    for {set i 0} {$i < [llength $ports]} {incr i} {
      set lane_index [format %01s [expr $i + 1]]
      set_property -dict [list CONFIG.LANE${lane_index}_GT_LOC [lindex $gt_lanes $i]] $core
    }
    connect_bd_intf_net $gt_refclk_0 [get_bd_intf_pins $core/gt_ref_clk]
    connect_bd_net [get_bd_pins $core/sys_reset] [get_bd_pins dclk_reset/peripheral_reset]
    make_bd_intf_pins_external [get_bd_intf_pins $core/gt_rx]
    make_bd_intf_pins_external [get_bd_intf_pins $core/gt_tx]
    connect_bd_net [get_bd_pins $core/dclk] [get_bd_pins $dclk_wiz/clk_out1]
    set const_clksel [tapasco::ip::create_constant const_clksel 3 5]

    for {set i 0} {$i < [llength $ports]} {incr i} {
      variable port [lindex $ports $i]

      # Local Pins (Network-Hierarchie)
      create_bd_intf_pin -mode Master -vlnv xilinx.com:interface:axis_rtl:1.0 AXIS_RX_${i}
      create_bd_intf_pin -mode Slave -vlnv xilinx.com:interface:axis_rtl:1.0 AXIS_TX_${i}

      # Connect Local pins to Global Ports
      connect_bd_intf_net [get_bd_intf_pins $core/axis_rx_${i}] [get_bd_intf_pins AXIS_RX_${i}]
      connect_bd_intf_net [get_bd_intf_pins $core/axis_tx_${i}] [get_bd_intf_pins AXIS_TX_${i}]
      connect_bd_intf_net [get_bd_intf_pins $core/s_axi_${i}] [get_bd_intf_pins /Network/AXI_Config/M[format %02d $i]_AXI]
      connect_bd_net [get_bd_pins $core/s_axi_aclk_${i}] [get_bd_pins $dclk_wiz/clk_out1]
      connect_bd_net [get_bd_pins $core/s_axi_aresetn_${i}] [get_bd_pins dclk_reset/peripheral_aresetn]
      connect_bd_net [get_bd_pins $core/tx_clk_out_${i}] [get_bd_pins $core/rx_core_clk_${i}]
      #connect_bd_net [get_bd_pins $core/rx_reset_${i}] [get_bd_pins dclk_reset/peripheral_reset]
      #connect_bd_net [get_bd_pins $core/tx_reset_${i}] [get_bd_pins dclk_reset/peripheral_reset]
      connect_bd_net [get_bd_pins $core/txoutclksel_in_${i}] [get_bd_pins $const_clksel/dout]
      connect_bd_net [get_bd_pins $core/rxoutclksel_in_${i}] [get_bd_pins $const_clksel/dout]


      connect_bd_net [get_bd_pins Ethernet10G/tx_clk_out_${i}] [get_bd_pins /Network/sfp_clock_${i}]

      set out_inv [makeInverter reset_inverter_${i}]
      connect_bd_net [get_bd_pins Ethernet10G/user_tx_reset_${i}] [get_bd_pins /Network/sfp_reset_${i}]
      connect_bd_net [get_bd_pins Ethernet10G/user_tx_reset_${i}] [get_bd_pins $out_inv/Op1]
      connect_bd_net [get_bd_pins /Network/sfp_resetn_${i}] [get_bd_pins $out_inv/Res]

      #set reset [create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 sfpclk_reset_${i}]

      #connect_bd_net [get_bd_pins Ethernet10G/tx_clk_out_${i}] [get_bd_pins $reset/slowest_sync_clk]
      #connect_bd_net [get_bd_pins Ethernet10G/user_tx_reset_${i}] [get_bd_pins $reset/ext_reset_in]

      #connect_bd_net [get_bd_pins $reset/peripheral_reset] [get_bd_pins /Network/sfp_reset_${i}]
      #connect_bd_net [get_bd_pins $reset/peripheral_aresetn] [get_bd_pins /Network/sfp_resetn_${i}] 
    }

    close $constraints_file
    read_xdc $constraints_fn
    set_property PROCESSING_ORDER NORMAL [get_files $constraints_fn]
    save_bd_design
  }

  # Build A Port Mode Setups
  proc generate_port {input} {

    dict with input {
      variable kernelc [countKernels $kernel]
      puts "Creating Port $PORT"
      puts "  with mode -> $mode"
      puts "  with sync -> $sync"
      puts "  with $kernelc PEs"
      foreach k $kernel {
        puts "    [dict get $k Count] of type [dict get $k ID]"
      }
    

      current_bd_instance /arch
      create_bd_pin -type clk -dir I sfp_clock_${PORT}
      create_bd_pin -type rst -dir I sfp_reset_${PORT}
      create_bd_pin -type rst -dir I sfp_resetn_${PORT}

      create_bd_intf_pin -mode Slave  -vlnv xilinx.com:interface:axis_rtl:1.0 AXIS_RX_$PORT
      create_bd_intf_pin -mode Master -vlnv xilinx.com:interface:axis_rtl:1.0 AXIS_TX_$PORT
      # Create Hierarchie-Cell
      create_bd_cell -type hier Port_$PORT
      variable ret [current_bd_instance .]
      current_bd_instance Port_$PORT
      # Create Ports for the Hierarchie
      create_bd_pin -dir I design_clk
      create_bd_pin -dir I design_interconnect_aresetn
      create_bd_pin -dir I design_peripheral_aresetn
      create_bd_pin -dir I design_peripheral_areset
      create_bd_pin -dir I sfp_clock
      create_bd_pin -dir I sfp_reset
      create_bd_pin -dir I sfp_resetn
      create_bd_intf_pin -mode Slave  -vlnv xilinx.com:interface:axis_rtl:1.0 AXIS_RX
      create_bd_intf_pin -mode Master -vlnv xilinx.com:interface:axis_rtl:1.0 AXIS_TX
      # Connect Hierarchie to the Upper Layer
      connect_bd_net [get_bd_pins sfp_clock]  [get_bd_pins /arch/sfp_clock_${PORT}]
      connect_bd_net [get_bd_pins sfp_reset]  [get_bd_pins /arch/sfp_reset_${PORT}]
      connect_bd_net [get_bd_pins sfp_resetn] [get_bd_pins /arch/sfp_resetn_${PORT}]
      connect_bd_net [get_bd_pins design_clk] [get_bd_pins /arch/design_clk]
      connect_bd_net [get_bd_pins design_peripheral_aresetn]     [get_bd_pins /arch/design_peripheral_aresetn]
      connect_bd_net [get_bd_pins design_peripheral_areset]      [get_bd_pins /arch/design_peripheral_areset]
      connect_bd_net [get_bd_pins design_interconnect_aresetn]   [get_bd_pins /arch/design_interconnect_aresetn]
      connect_bd_intf_net [get_bd_intf_pins /arch/AXIS_TX_$PORT] [get_bd_intf_pins AXIS_TX]
      connect_bd_intf_net [get_bd_intf_pins /arch/AXIS_RX_$PORT] [get_bd_intf_pins AXIS_RX]
      # Create Port infrastructure depending on mode
      switch $mode {
        singular   {
          generate_singular [lindex $kernel 0] $PORT $sync
        }
        broadcast  {
          generate_broadcast $kernelc $sync
          connect_PEs $kernel $PORT $sync
        }
        roundrobin {
          generate_roundrobin $kernelc $sync
          connect_PEs $kernel $PORT $sync
        }
      }
      current_bd_instance $ret
    }
  }

  # Create A Broadcast-Config
  proc generate_broadcast {kernelc sync} {
  # Create Reciever Interconnect
      create_bd_cell -type ip -vlnv xilinx.com:ip:axis_broadcaster:1.1  reciever
      set_property CONFIG.NUM_MI $kernelc [get_bd_cells reciever]
      set_property -dict [list CONFIG.M_TDATA_NUM_BYTES {8} CONFIG.S_TDATA_NUM_BYTES {8}] [get_bd_cells reciever]

      for {variable i 0} {$i < $kernelc} {incr i} {
          set_property CONFIG.M[format "%02d" $i]_TDATA_REMAP tdata[63:0]  [get_bd_cells reciever]
      }

  # If not Syncronized insert Interconnect to Sync the Clocks
      if {$sync} {
        connect_bd_intf_net [get_bd_intf_pins reciever/S_AXIS] [get_bd_intf_pins AXIS_RX]
        connect_bd_net [get_bd_pins sfp_clock] [get_bd_pins reciever/aclk]
        connect_bd_net [get_bd_pins sfp_resetn] [get_bd_pins reciever/aresetn]
      } else {
        connect_bd_net [get_bd_pins design_clk] [get_bd_pins reciever/aclk]
        connect_bd_net [get_bd_pins design_interconnect_aresetn] [get_bd_pins reciever/aresetn]

        create_bd_cell -type ip -vlnv xilinx.com:ip:axis_interconnect:2.1 reciever_sync
        set_property -dict [list CONFIG.NUM_MI {1} CONFIG.NUM_SI {1} CONFIG.S00_FIFO_DEPTH {2048} CONFIG.M00_FIFO_DEPTH {2048} CONFIG.S00_FIFO_MODE {0} CONFIG.M00_FIFO_MODE {0} ] [get_bd_cells reciever_sync]
        connect_bd_net [get_bd_pins sfp_clock]  [get_bd_pins reciever_sync/ACLK]
        connect_bd_net [get_bd_pins sfp_resetn] [get_bd_pins reciever_sync/ARESETN]
        connect_bd_net [get_bd_pins sfp_clock]  [get_bd_pins reciever_sync/S*_ACLK]
        connect_bd_net [get_bd_pins sfp_resetn] [get_bd_pins reciever_sync/S*_ARESETN]
        connect_bd_net [get_bd_pins design_clk] [get_bd_pins reciever_sync/M*_ACLK]
        connect_bd_net [get_bd_pins design_peripheral_aresetn] [get_bd_pins reciever_sync/M*_ARESETN]

        connect_bd_intf_net [get_bd_intf_pins reciever/S_AXIS] [get_bd_intf_pins reciever_sync/M*_AXIS]
        connect_bd_intf_net [get_bd_intf_pins reciever_sync/S00_AXIS] [get_bd_intf_pins AXIS_RX]
      }

  # Create Transmitter Interconnect
      create_bd_cell -type ip -vlnv xilinx.com:ip:axis_interconnect:2.1 transmitter
      set_property -dict [list CONFIG.NUM_MI {1} CONFIG.ARB_ON_TLAST {1}] [get_bd_cells transmitter]
      set_property -dict [list CONFIG.M00_FIFO_MODE {1} CONFIG.M00_FIFO_DEPTH {2048}] [get_bd_cells transmitter]
      set_property CONFIG.NUM_SI $kernelc [get_bd_cells transmitter]
      set_property -dict [list CONFIG.ARB_ALGORITHM {3} CONFIG.ARB_ON_MAX_XFERS {0}] [get_bd_cells transmitter]


      for {variable i 0} {$i < $kernelc} {incr i} {
          set_property CONFIG.[format "S%02d" $i]_FIFO_DEPTH 2048 [get_bd_cells transmitter]
          set_property CONFIG.[format "S%02d" $i]_FIFO_MODE 0 [get_bd_cells transmitter]
      }

      connect_bd_intf_net [get_bd_intf_pins transmitter/M*_AXIS] [get_bd_intf_pins AXIS_TX]
      connect_bd_net [get_bd_pins sfp_clock] [get_bd_pins transmitter/M*_ACLK]
      connect_bd_net [get_bd_pins sfp_resetn] [get_bd_pins transmitter/M*_ARESETN]

      if {$sync} {
        connect_bd_net [get_bd_pins sfp_clock] [get_bd_pins transmitter/ACLK]
        connect_bd_net [get_bd_pins sfp_resetn] [get_bd_pins transmitter/ARESETN]
        connect_bd_net [get_bd_pins sfp_clock] [get_bd_pins transmitter/S*_ACLK]
        connect_bd_net [get_bd_pins sfp_resetn] [get_bd_pins transmitter/S*_ARESETN]
      } else {
        connect_bd_net [get_bd_pins design_clk] [get_bd_pins transmitter/ACLK]
        connect_bd_net [get_bd_pins design_interconnect_aresetn] [get_bd_pins transmitter/ARESETN]
        connect_bd_net [get_bd_pins design_clk] [get_bd_pins transmitter/S*_ACLK]
        connect_bd_net [get_bd_pins design_peripheral_aresetn] [get_bd_pins transmitter/S*_ARESETN]
      }
  }

  # Create A Roundrobin-Config
  proc generate_roundrobin {kernelc sync} {
    # Create Reciever Interconnect
    create_bd_cell -type ip -vlnv xilinx.com:ip:axis_interconnect:2.1 reciever
    set_property -dict [list CONFIG.NUM_SI {1} CONFIG.S00_FIFO_MODE {0} CONFIG.S00_FIFO_DEPTH {2048}] [get_bd_cells reciever]
    set_property CONFIG.NUM_MI $kernelc [get_bd_cells reciever]

    for {variable i 0} {$i < $kernelc} {incr i} {
        set_property CONFIG.[format "M%02d" $i]_FIFO_DEPTH 2048 [get_bd_cells reciever]
        set_property CONFIG.[format "M%02d" $i]_FIFO_MODE 0 [get_bd_cells reciever]
    }

    connect_bd_net [get_bd_pins sfp_clock] [get_bd_pins reciever/ACLK]
    connect_bd_net [get_bd_pins sfp_resetn] [get_bd_pins reciever/ARESETN]

    connect_bd_net [get_bd_pins sfp_clock] [get_bd_pins reciever/S*_ACLK]
    connect_bd_net [get_bd_pins sfp_resetn] [get_bd_pins reciever/S*_ARESETN]

    if {$sync} {
      connect_bd_net [get_bd_pins sfp_clock] [get_bd_pins reciever/M*_ACLK]
      connect_bd_net [get_bd_pins sfp_resetn] [get_bd_pins reciever/M*_ARESETN]
    } else {
      connect_bd_net [get_bd_pins design_clk] [get_bd_pins reciever/M*_ACLK]
      connect_bd_net [get_bd_pins design_peripheral_aresetn] [get_bd_pins reciever/M*_ARESETN]
    }

    tapasco::ip::create_axis_arbiter "arbiter"
    create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 roundrobin_turnover
    set_property CONFIG.CONST_WIDTH 5 [get_bd_cells roundrobin_turnover]
    set_property CONFIG.CONST_VAL $kernelc [get_bd_cells roundrobin_turnover]

    connect_bd_net [get_bd_pins arbiter/maxClients] [get_bd_pins roundrobin_turnover/dout]
    connect_bd_net [get_bd_pins arbiter/CLK] [get_bd_pins sfp_clock]
    connect_bd_net [get_bd_pins arbiter/RST_N] [get_bd_pins sfp_resetn]
    connect_bd_intf_net [get_bd_intf_pins arbiter/axis_S] [get_bd_intf_pins AXIS_RX]
    connect_bd_intf_net [get_bd_intf_pins arbiter/axis_M] [get_bd_intf_pins reciever/S*_AXIS]

    # Create Transmitter Interconnect
    create_bd_cell -type ip -vlnv xilinx.com:ip:axis_interconnect:2.1 transmitter
    set_property -dict [list CONFIG.NUM_MI {1} CONFIG.ARB_ON_TLAST {1}] [get_bd_cells transmitter]
    set_property -dict [list CONFIG.M00_FIFO_MODE {1} CONFIG.M00_FIFO_DEPTH {2048}] [get_bd_cells transmitter]
    set_property CONFIG.NUM_SI $kernelc [get_bd_cells transmitter]
    set_property -dict [list CONFIG.ARB_ALGORITHM {3} CONFIG.ARB_ON_MAX_XFERS {0}] [get_bd_cells transmitter]


    for {variable i 0} {$i < $kernelc} {incr i} {
      set_property CONFIG.[format "S%02d" $i]_FIFO_DEPTH 2048 [get_bd_cells transmitter]
      set_property CONFIG.[format "S%02d" $i]_FIFO_MODE 0 [get_bd_cells transmitter]
    }

    connect_bd_intf_net [get_bd_intf_pins transmitter/M*_AXIS] [get_bd_intf_pins AXIS_TX]
    connect_bd_net [get_bd_pins sfp_clock] [get_bd_pins transmitter/M*_ACLK]
    connect_bd_net [get_bd_pins sfp_resetn] [get_bd_pins transmitter/M*_ARESETN]
    if {$sync} {
      connect_bd_net [get_bd_pins sfp_clock] [get_bd_pins transmitter/ACLK]
      connect_bd_net [get_bd_pins sfp_resetn] [get_bd_pins transmitter/ARESETN]
      connect_bd_net [get_bd_pins sfp_clock] [get_bd_pins transmitter/S*_ACLK]
      connect_bd_net [get_bd_pins sfp_resetn] [get_bd_pins transmitter/S*_ARESETN]
    } else {
      connect_bd_net [get_bd_pins design_clk] [get_bd_pins transmitter/ACLK]
      connect_bd_net [get_bd_pins design_interconnect_aresetn] [get_bd_pins transmitter/ARESETN]
      connect_bd_net [get_bd_pins design_clk] [get_bd_pins transmitter/S*_ACLK]
      connect_bd_net [get_bd_pins design_peripheral_aresetn] [get_bd_pins transmitter/S*_ARESETN]
    }
  }

  # Create A Solo-Config
  proc generate_singular {kernel PORT sync} {
    dict with kernel {
      variable kern [find_ID $ID]
      variable pes [lrange [get_bd_cells /arch/target_ip_[format %02d $kern]_*] 0 $Count-1]
      #move_bd_cells [get_bd_cells Port_$PORT] $pes
      if {$sync} {
        create_bd_intf_pin -mode Master  -vlnv xilinx.com:interface:axis_rtl:1.0 AXIS_RX_OUT
        create_bd_intf_pin -mode Slave -vlnv xilinx.com:interface:axis_rtl:1.0 AXIS_TX_OUT
        connect_bd_intf_net [get_bd_intf_pins AXIS_RX] [get_bd_intf_pins AXIS_RX_OUT]
        connect_bd_intf_net [get_bd_intf_pins AXIS_TX] [get_bd_intf_pins AXIS_TX_OUT]
        puts "Connecting [get_bd_intf_pins AXIS_RX_OUT] to [get_bd_intf_pins [lindex $pes 0]/$interface_rx]"
        connect_bd_intf_net [get_bd_intf_pins AXIS_RX_OUT] [get_bd_intf_pins [lindex $pes 0]/$interface_rx]
        puts "Connecting [get_bd_intf_pins AXIS_TX_OUT] to [get_bd_intf_pins [lindex $pes 0]/$interface_tx]"
        connect_bd_intf_net [get_bd_intf_pins AXIS_TX_OUT] [get_bd_intf_pins [lindex $pes 0]/$interface_tx]

        variable clks [get_bd_pins -of_objects [lindex $pes 0] -filter {type == clk}]
        if {[llength $clks] > 1} {
          foreach clk $clks {
            variable interfaces [get_property CONFIG.ASSOCIATED_BUSIF $clk]
            if {[regexp $interface_rx $interfaces]} {
                disconnect_bd_net [get_bd_nets -of_objects $clk]    $clk
                connect_bd_net [get_bd_pins sfp_clock] $clk

                variable rst [get_bd_pins [lindex $pes 0]/[get_property CONFIG.ASSOCIATED_RESET $clk]]
                disconnect_bd_net [get_bd_nets -of_objects $rst]  $rst
                connect_bd_net [get_bd_pins /arch/sfp_resetn_${PORT}] $rst
              } elseif {[regexp $interface_tx $interfaces]} {
                disconnect_bd_net [get_bd_nets -of_objects $clk]    $clk
                connect_bd_net [get_bd_pins sfp_clock] $clk

                variable rst [get_bd_pins [lindex $pes 0]/[get_property CONFIG.ASSOCIATED_RESET $clk]]
                disconnect_bd_net [get_bd_nets -of_objects $rst]  $rst
                connect_bd_net [get_bd_pins /arch/sfp_resetn_${PORT}] $rst
              }
            }
        } else {
          variable axi [find_AXI_Connection [lindex $pes 0]]
          variable axiclk [get_bd_pins ${axi}_ACLK]
          variable axireset [get_bd_pins ${axi}_ARESETN]

          disconnect_bd_net [get_bd_nets -of_objects $axiclk]    $axiclk
          disconnect_bd_net [get_bd_nets -of_objects $axireset]  $axireset
          connect_bd_net [get_bd_pins /arch/sfp_clock_${PORT}] $axiclk
          connect_bd_net [get_bd_pins /arch/sfp_resetn_${PORT}] $axireset

          variable rst [get_bd_pins [lindex $pes 0]/[get_property CONFIG.ASSOCIATED_RESET $clks]]
          disconnect_bd_net [get_bd_nets -of_objects $clks]  $clks
          connect_bd_net [get_bd_pins /arch/sfp_clock_${PORT}] $clks
          disconnect_bd_net [get_bd_nets -of_objects $rst]  $rst
          connect_bd_net [get_bd_pins /arch/sfp_resetn_${PORT}] $rst
        }
      } else {
        create_bd_cell -type ip -vlnv xilinx.com:ip:axis_interconnect:2.1 reciever_sync
        set_property -dict [list CONFIG.NUM_MI {1} CONFIG.NUM_SI {1} CONFIG.S00_FIFO_DEPTH {2048} CONFIG.M00_FIFO_DEPTH {2048} CONFIG.S00_FIFO_MODE {0} CONFIG.M00_FIFO_MODE {0} ] [get_bd_cells reciever_sync]
        connect_bd_net [get_bd_pins sfp_clock]  [get_bd_pins reciever_sync/ACLK]
        connect_bd_net [get_bd_pins sfp_resetn] [get_bd_pins reciever_sync/ARESETN]
        connect_bd_net [get_bd_pins sfp_clock]  [get_bd_pins reciever_sync/S*_ACLK]
        connect_bd_net [get_bd_pins sfp_resetn] [get_bd_pins reciever_sync/S*_ARESETN]
        connect_bd_net [get_bd_pins design_clk] [get_bd_pins reciever_sync/M*_ACLK]
        connect_bd_net [get_bd_pins design_peripheral_aresetn] [get_bd_pins reciever_sync/M*_ARESETN]
        puts "Connecting [get_bd_intf_pins reciever_sync/M00_AXIS] to [get_bd_intf_pins [lindex $pes 0]/$interface_rx]"
        connect_bd_intf_net [get_bd_intf_pins reciever_sync/M00_AXIS] [get_bd_intf_pins [lindex $pes 0]/$interface_rx]
        connect_bd_intf_net [get_bd_intf_pins reciever_sync/S00_AXIS] [get_bd_intf_pins AXIS_RX]

        create_bd_cell -type ip -vlnv xilinx.com:ip:axis_interconnect:2.1 transmitter_sync
        set_property -dict [list CONFIG.NUM_MI {1} CONFIG.NUM_SI {1} CONFIG.S00_FIFO_DEPTH {2048} CONFIG.M00_FIFO_DEPTH {2048} CONFIG.S00_FIFO_MODE {0} CONFIG.M00_FIFO_MODE {1} ] [get_bd_cells transmitter_sync]
        connect_bd_net [get_bd_pins design_clk]  [get_bd_pins transmitter_sync/ACLK]
        connect_bd_net [get_bd_pins design_interconnect_aresetn] [get_bd_pins transmitter_sync/ARESETN]
        connect_bd_net [get_bd_pins design_clk]  [get_bd_pins transmitter_sync/S*_ACLK]
        connect_bd_net [get_bd_pins design_peripheral_aresetn] [get_bd_pins transmitter_sync/S*_ARESETN]
        connect_bd_net [get_bd_pins sfp_clock] [get_bd_pins transmitter_sync/M*_ACLK]
        connect_bd_net [get_bd_pins sfp_resetn] [get_bd_pins transmitter_sync/M*_ARESETN]
        puts "Connecting [get_bd_intf_pins transmitter_sync/S00_AXIS] to [get_bd_intf_pins [lindex $pes 0]/$interface_tx]"
        connect_bd_intf_net [get_bd_intf_pins transmitter_sync/S00_AXIS] [get_bd_intf_pins [lindex $pes 0]/$interface_tx]
        connect_bd_intf_net [get_bd_intf_pins transmitter_sync/M00_AXIS] [get_bd_intf_pins AXIS_TX]
      }
    }
  }

  # Group PEs and Connect them to transmitter and reciever
  proc connect_PEs {kernels PORT sync} {
    variable counter 0
    foreach kernel $kernels {
      dict with kernel {
        variable kern [find_ID $ID]
        variable pes [lrange [get_bd_cells /arch/target_ip_[format %02d $kern]_*] 0 $Count-1]
        move_bd_cells [get_bd_cells Port_$PORT] $pes
        for {variable i 0} {$i < $Count} {incr i} {
          puts "Using PE [lindex $pes $i] for Port $PORT"
          puts "Connecting [get_bd_intf_pins reciever/M[format %02d $counter]_AXIS] to [get_bd_intf_pins [lindex $pes $i]/$interface_rx]"
          connect_bd_intf_net [get_bd_intf_pins reciever/M[format %02d $counter]_AXIS] [get_bd_intf_pins [lindex $pes $i]/$interface_rx]
          puts "Connecting [get_bd_intf_pins transmitter/S[format %02d $counter]_AXIS] to [get_bd_intf_pins [lindex $pes $i]/$interface_tx]"
          connect_bd_intf_net [get_bd_intf_pins transmitter/S[format %02d $counter]_AXIS] [get_bd_intf_pins [lindex $pes $i]/$interface_tx]

          if {$sync} {
            variable clks [get_bd_pins -of_objects [lindex $pes $i] -filter {type == clk}]
            if {[llength $clks] > 1} {
              foreach clk $clks {
                variable interfaces [get_property CONFIG.ASSOCIATED_BUSIF $clk]
                if {[regexp $interface_rx $interfaces]} {
                  puts "Connecting $clk to SFP-Clock  for $interface_rx"
                  disconnect_bd_net [get_bd_nets -of_objects $clk] $clk
                  connect_bd_net [get_bd_pins sfp_clock] $clk
                  variable reset [get_bd_pins [lindex $pes $i]/[get_property CONFIG.ASSOCIATED_RESET $clk]]
                  disconnect_bd_net [get_bd_nets -of_objects $reset] $reset
                  connect_bd_net [get_bd_pins sfp_resetn] $reset
                } elseif {[regexp $interface_tx $interfaces]} {
                  puts "Connecting $clk to SFP-Clock for $interface_tx"
                  disconnect_bd_net [get_bd_nets -of_objects $clk] $clk
                  connect_bd_net [get_bd_pins sfp_clock] $clk
                  variable reset [get_bd_pins [lindex $pes $i]/[get_property CONFIG.ASSOCIATED_RESET $clk]]
                  disconnect_bd_net [get_bd_nets -of_objects $reset] $reset
                  connect_bd_net [get_bd_pins sfp_resetn] $reset
                }
              }
            } else {
              #Only one Clock-present
              variable axi [find_AXI_Connection [lindex $pes $i]]
              variable axiclk [get_bd_pins ${axi}_ACLK]
              variable axireset [get_bd_pins ${axi}_ARESETN]

              disconnect_bd_net [get_bd_nets -of_objects $axiclk]    $axiclk
              disconnect_bd_net [get_bd_nets -of_objects $axireset]  $axireset
              connect_bd_net [get_bd_pins /arch/sfp_clock_${PORT}] $axiclk
              connect_bd_net [get_bd_pins /arch/sfp_resetn_${PORT}] $axireset

              variable rst [get_bd_pins [lindex $pes $i]/[get_property CONFIG.ASSOCIATED_RESET $clks]]
              disconnect_bd_net [get_bd_nets -of_objects $clks]  $clks
              connect_bd_net [get_bd_pins /arch/sfp_clock_${PORT}] $clks
              disconnect_bd_net [get_bd_nets -of_objects $rst]  $rst
              connect_bd_net [get_bd_pins /arch/sfp_resetn_${PORT}] $rst
            }
          }
          variable counter [expr {$counter+1}]
        }
      }
    }
  }

  #Find the Masterinterface for a given Slaveinterface
  proc find_AXI_Connection {input} {
    variable pin [get_bd_intf_pins -of_objects $input -filter {vlnv == xilinx.com:interface:aximm_rtl:1.0}]
    variable net ""
    while {![regexp "(.*M[0-9][0-9])_AXI" $pin -> port]} {
      variable nets [get_bd_intf_nets -boundary_type both -of_objects $pin]
      variable id [lsearch $nets $net]
      variable net [lreplace $nets $id $id]

      variable pins [get_bd_intf_pins -of_objects $net]
      variable id [lsearch $pins $pin]
      variable pin [lreplace $pins $id $id]
    }
    return $port
  }

  proc makeMaster {name} {
    set m_si [create_bd_intf_pin -mode Master -vlnv xilinx.com:interface:aximm_rtl:1.0 /host/$name]
    set num_mi_old [get_property CONFIG.NUM_MI [get_bd_cells /host/out_ic]]
    set num_mi [expr "$num_mi_old + 1"]
    set_property -dict [list CONFIG.NUM_MI $num_mi] [get_bd_cells /host/out_ic]
    connect_bd_intf_net $m_si [get_bd_intf_pins /host/out_ic/[format "M%02d_AXI" $num_mi_old]]
  }

  proc write_SI5324_Constraints {} {
    variable iic_scl
    variable iic_sda
    variable iic_rst
    variable si5324_rst

    set constraints_fn  "[get_property DIRECTORY [current_project]]/si5324.xdc]"
    set constraints_file [open $constraints_fn w+]

    puts $constraints_file {# I2C Clock}
    puts $constraints_file [format {set_property PACKAGE_PIN %s [get_ports IIC_scl_io]} [lindex $iic_scl 0]]
    puts $constraints_file [format {set_property PULLUP %s [get_ports IIC_scl_io]}      [lindex $iic_scl 1]]
    puts $constraints_file [format {set_property DRIVE  %s [get_ports IIC_scl_io]}      [lindex $iic_scl 2]]
    puts $constraints_file [format {set_property SLEW   %s [get_ports IIC_scl_io]}      [lindex $iic_scl 3]]
    puts $constraints_file [format {set_property IOSTANDARD %s [get_ports IIC_scl_io]}  [lindex $iic_scl 4]]

    puts $constraints_file {# I2C Data}
    puts $constraints_file [format {set_property PACKAGE_PIN %s [get_ports IIC_sda_io]} [lindex $iic_sda 0]]
    puts $constraints_file [format {set_property PULLUP %s [get_ports IIC_sda_io]}      [lindex $iic_sda 1]]
    puts $constraints_file [format {set_property DRIVE %s [get_ports IIC_sda_io]}       [lindex $iic_sda 2]]
    puts $constraints_file [format {set_property SLEW  %s [get_ports IIC_sda_io]}       [lindex $iic_sda 3]]
    puts $constraints_file [format {set_property IOSTANDARD %s [get_ports IIC_sda_io]}  [lindex $iic_sda 4]]

    puts $constraints_file {# I2C Reset}
    puts $constraints_file [format {set_property PACKAGE_PIN %s [get_ports i2c_reset[0]]} [lindex $iic_rst 0]]
    puts $constraints_file [format {set_property DRIVE %s [get_ports i2c_reset[0]]}       [lindex $iic_rst 1]]
    puts $constraints_file [format {set_property SLEW  %s [get_ports i2c_reset[0]]}       [lindex $iic_rst 2]]
    puts $constraints_file [format {set_property IOSTANDARD %s [get_ports i2c_reset[0]]}  [lindex $iic_rst 3]]

    puts $constraints_file {# SI5324 Reset}
    puts $constraints_file [format {set_property PACKAGE_PIN %s [get_ports i2c_reset[1]]} [lindex $si5324_rst 0]]
    puts $constraints_file [format {set_property DRIVE %s [get_ports i2c_reset[1]]}       [lindex $si5324_rst 1]]
    puts $constraints_file [format {set_property SLEW  %s [get_ports i2c_reset[1]]}       [lindex $si5324_rst 2]]
    puts $constraints_file [format {set_property IOSTANDARD  %s [get_ports i2c_reset[1]]} [lindex $si5324_rst 3]]

    close $constraints_file
    read_xdc $constraints_fn
    set_property PROCESSING_ORDER EARLY [get_files $constraints_fn]
  }


  proc addressmap {{args {}}} {
    if {[tapasco::is_feature_enabled "SFPPLUS"]} {
          set args [lappend args "M_SI5324"  [list 0x22ff000 0 0 ""]]
          set args [lappend args "M_NETWORK" [list 0x2500000 0 0 ""]]
          puts $args
      }
      save_bd_design
      return $args
  }

}



tapasco::register_plugin "platform::sfpplus::validate_sfp_ports" "pre-arch"
tapasco::register_plugin "platform::sfpplus::addressmap" "post-address-map"
