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

namespace eval platform {
  set platform_dirname "AU280"
  set pcie_width "x16"
  set device_type "US+"

  source $::env(TAPASCO_HOME_TCL)/platform/pcie/pcie_base.tcl

  proc get_ignored_segments { } {
    set ignored [list]
    for {set i 0} {$i < 32} {incr i} {
      set region [format %02s $i]
      assign_bd_address [get_bd_addr_segs memory/mig/hbm_0/SAXI_00/HBM_MEM${region} ]
      lappend ignored "/memory/mig/hbm_0/SAXI_00/HBM_MEM${region}"
    }
    return $ignored
  }

  # Creates input ports for reference clock(s)
  proc create_refclk_ports {} {
      set hbm_ref_clk_0 [ create_bd_intf_port -mode Slave -vlnv xilinx.com:interface:diff_clock_rtl:1.0 hbm_ref_clk_0 ]
      set_property CONFIG.FREQ_HZ 100000000 $hbm_ref_clk_0
  }

  # Creates HBM configuration for given number of active HBM ports
  proc create_hbm_properties {} {
    # disable APB debug port
    # disable AXI crossbar (global addressing)
    # configure AXI clock freq
    set hbm_properties [list \
      CONFIG.USER_APB_EN {false} \
      CONFIG.USER_SWITCH_ENABLE_00 {true} \
      CONFIG.USER_SWITCH_ENABLE_01 {true} \
      CONFIG.USER_AXI_INPUT_CLK_FREQ {450} \
      CONFIG.USER_AXI_INPUT_CLK_NS {2.222} \
      CONFIG.USER_AXI_INPUT_CLK_PS {2222} \
      CONFIG.USER_AXI_INPUT_CLK_XDC {2.222} \
      CONFIG.HBM_MMCM_FBOUT_MULT0 {51} \
      CONFIG.USER_XSDB_INTF_EN {FALSE}
    ]
    set maxSlaves 32
    lappend hbm_properties CONFIG.USER_HBM_DENSITY {8GB}

    # enable HBM ports and memory controllers as required (two ports per mc)
    for {set i 1} {$i < $maxSlaves} {incr i} {
      set saxi [format %02s $i]
      lappend hbm_properties CONFIG.USER_SAXI_${saxi} {false}
    }

    # configure memory controllers
    for {set i 0} {$i < $maxSlaves} {incr i} {
      if ([even $i]) {
        set mc [format %s [expr {$i / 2}]]
        lappend hbm_properties CONFIG.USER_MC${mc}_ECC_BYPASS false
        lappend hbm_properties CONFIG.USER_MC${mc}_ECC_CORRECTION false
        lappend hbm_properties CONFIG.USER_MC${mc}_EN_DATA_MASK true
        lappend hbm_properties CONFIG.USER_MC${mc}_TRAFFIC_OPTION {Linear}
        lappend hbm_properties CONFIG.USER_MC${mc}_BG_INTERLEAVE_EN true
      }
    }

    return $hbm_properties
  }

  # Creates HBM clocking infrastructure for a single stack
  proc create_clocking {} {
    set group [create_bd_cell -type hier clocking_0]
    set instance [current_bd_instance .]
    current_bd_instance $group

    set hbm_ref_clk [create_bd_pin -type "clk" -dir "O" "hbm_ref_clk"]
    set hbm_ref_clk2 [create_bd_pin -type "clk" -dir "O" "hbm_ref_clk2"]
    set axi_clk_0 [create_bd_pin -type "clk" -dir "O" "axi_clk_0"]
    set mem_clk [create_bd_pin -type clk -dir O mem_clk]
    set axi_reset [create_bd_pin -type "rst" -dir "O" "axi_reset"]
    set mem_peripheral_aresetn [create_bd_pin -type "rst" -dir "I" "mem_peripheral_aresetn"]

    set ibuf [tapasco::ip::create_util_buf ibuf]
    set_property -dict [ list CONFIG.C_BUF_TYPE {IBUFDS}  ] $ibuf

    connect_bd_intf_net [get_bd_intf_ports /hbm_ref_clk_0] [get_bd_intf_pins $ibuf/CLK_IN_D]

    set clk_wiz [tapasco::ip::create_clk_wiz clk_wiz]
    set_property -dict [list CONFIG.PRIM_SOURCE {No_buffer} CONFIG.CLKOUT1_REQUESTED_OUT_FREQ {450} CONFIG.CLKOUT2_REQUESTED_OUT_FREQ {300} CONFIG.CLKOUT2_USED {true} CONFIG.RESET_TYPE {ACTIVE_LOW} CONFIG.NUM_OUT_CLKS {2} CONFIG.RESET_PORT {resetn}] $clk_wiz

    connect_bd_net [get_bd_pins $ibuf/IBUF_OUT] $hbm_ref_clk
    connect_bd_net [get_bd_pins $ibuf/IBUF_OUT] $hbm_ref_clk2
    connect_bd_net [get_bd_pins $ibuf/IBUF_OUT] [get_bd_pins $clk_wiz/clk_in1]

    connect_bd_net $mem_peripheral_aresetn [get_bd_pins $clk_wiz/resetn]

    set reset_generator [tapasco::ip::create_logic_vector reset_generator]
    set_property -dict [list CONFIG.C_SIZE {1} CONFIG.C_OPERATION {and} CONFIG.LOGO_FILE {data/sym_andgate.png}] $reset_generator

    connect_bd_net $mem_peripheral_aresetn [get_bd_pins $reset_generator/Op1]
    connect_bd_net [get_bd_pins $clk_wiz/locked] [get_bd_pins $reset_generator/Op2]

    connect_bd_net [get_bd_pins axi_clk_0] [get_bd_pins $clk_wiz/clk_out1]
    connect_bd_net $mem_clk [get_bd_pins $clk_wiz/clk_out2]
    

    connect_bd_net $axi_reset [get_bd_pins $reset_generator/Res]

    current_bd_instance $instance
    return $group
  }

  # Connects a range of HBM AXI clocks with the outputs of a clocking infrastructure
  proc connect_clocking {clocking hbm startInterface numInterfaces} {
    for {set i 0} {$i < $numInterfaces} {incr i} {
        set hbm_index [format %02s [expr $i + $startInterface]]
        set block_index [expr $i < 16 ? 0 : 1]
        set clk_index [expr ($i % 16) / 2]
        set clk_index [expr $clk_index < 7 ? $clk_index : 6]
        connect_bd_net [get_bd_pins $clocking/axi_reset] [get_bd_pins $hbm/AXI_${hbm_index}_ARESET_N]
        connect_bd_net [get_bd_pins $clocking/axi_clk_${clk_index}] [get_bd_pins $hbm/AXI_${hbm_index}_ACLK]
      }
  }

  proc even x {expr {($x % 2) == 0}}

  proc create_mig_core {name} {
    puts "Creating MIG core for HBM ..."

    set inst [current_bd_instance .]
    puts $inst
    
    set mig [create_bd_cell -type hier $name]
    current_bd_instance -quiet $mig
    set c0_ddr4_aresetn [create_bd_pin -type rst -dir I c0_ddr4_aresetn]
    set c0_init_calib_complete [create_bd_pin -dir O c0_init_calib_complete]
    set c0_ddr4_ui_clk [create_bd_pin -dir O -type clk c0_ddr4_ui_clk]
    set c0_ddr4_ui_clk_sync_rst [create_bd_pin -dir O -type rst c0_ddr4_ui_clk_sync_rst]
    set C0_DDR4_S_AXI [create_bd_intf_pin -mode Slave -vlnv xilinx.com:interface:aximm_rtl:1.0 C0_DDR4_S_AXI]

    create_refclk_ports

    set hbm_properties [create_hbm_properties]

    # create and configure HBM IP
    set hbm [ create_bd_cell -type ip -vlnv xilinx.com:ip:hbm:1.0 "hbm_0" ]
    set_property -dict $hbm_properties $hbm

    # create and connect clocking infrastructure for left stack
    set clocking [create_clocking]
    connect_clocking $clocking $hbm 0 1
    connect_bd_net [get_bd_pins $clocking/hbm_ref_clk] [get_bd_pins $hbm/HBM_REF_CLK_0]
    connect_bd_net [get_bd_pins $clocking/hbm_ref_clk2] [get_bd_pins $hbm/HBM_REF_CLK_1]

    connect_bd_net [get_bd_pins $clocking/hbm_ref_clk] [get_bd_pins $hbm/APB_0_PCLK]
    connect_bd_net [get_bd_pins $clocking/hbm_ref_clk2] [get_bd_pins $hbm/APB_1_PCLK]
    connect_bd_net [get_bd_pins /host/axi_pcie3_0/user_lnk_up] [get_bd_pins $hbm/APB_0_PRESET_N] [get_bd_pins $clocking/mem_peripheral_aresetn]

    connect_bd_net $c0_ddr4_ui_clk_sync_rst [get_bd_pins $clocking/axi_reset]
    connect_bd_net $c0_init_calib_complete [get_bd_pins $clocking/axi_reset]
    connect_bd_net $c0_ddr4_ui_clk [get_bd_pins $clocking/mem_clk]

    set converter [create_bd_cell -type ip -vlnv xilinx.com:ip:smartconnect:1.0 smartconnect_0]
    set_property -dict [list CONFIG.NUM_SI {1} CONFIG.NUM_CLKS {2} CONFIG.HAS_ARESETN {0}] $converter
    save_bd_design
    connect_bd_net [get_bd_pins $clocking/mem_clk] [get_bd_pins $converter/aclk]
    connect_bd_net [get_bd_pins $hbm/AXI_00_ACLK] [get_bd_pins $converter/aclk1]
    connect_bd_intf_net [get_bd_intf_pins $converter/M00_AXI] [get_bd_intf_pins $hbm/SAXI_00]
    connect_bd_intf_net [get_bd_intf_pins $converter/S00_AXI] $C0_DDR4_S_AXI

    current_bd_instance -quiet $inst
    
    set const [tapasco::ip::create_constant constz 1 0]
    make_bd_pins_external $const

    
    return $mig
  }
  

  proc create_pcie_core {} {
    puts "Creating AXI PCIe Gen3 bridge ..."

    set pcie_core [tapasco::ip::create_axi_pcie3_0_usp axi_pcie3_0]

    apply_bd_automation -rule xilinx.com:bd_rule:board -config { Board_Interface {pci_express_x16 ( PCI Express ) } Manual_Source {Auto}}  [get_bd_intf_pins $pcie_core/pcie_mgt]
    apply_bd_automation -rule xilinx.com:bd_rule:board -config { Board_Interface {pcie_perstn ( PCI Express ) } Manual_Source {New External Port (ACTIVE_LOW)}}  [get_bd_pins $pcie_core/sys_rst_n]

    apply_bd_automation -rule xilinx.com:bd_rule:xdma -config { accel {1} auto_level {IP Level} axi_clk {Maximum Data Width} axi_intf {AXI Memory Mapped} bar_size {Disable} bypass_size {Disable} c2h {4} cache_size {32k} h2c {4} lane_width {X16} link_speed {8.0 GT/s (PCIe Gen 3)}}  [get_bd_cells $pcie_core]

    set pcie_properties [list \
      CONFIG.functional_mode {AXI_Bridge} \
      CONFIG.mode_selection {Advanced} \
      CONFIG.pcie_blk_locn {PCIE4C_X1Y0} \
      CONFIG.pl_link_cap_max_link_width {X16} \
      CONFIG.pl_link_cap_max_link_speed {8.0_GT/s} \
      CONFIG.axi_addr_width {64} \
      CONFIG.pipe_sim {true} \
      CONFIG.pf0_revision_id {01} \
      CONFIG.pf0_base_class_menu {Memory_controller} \
      CONFIG.pf0_sub_class_interface_menu {Other_memory_controller} \
      CONFIG.pf0_interrupt_pin {NONE} \
      CONFIG.pf0_msi_enabled {false} \
      CONFIG.SYS_RST_N_BOARD_INTERFACE {pcie_perstn} \
      CONFIG.PCIE_BOARD_INTERFACE {pci_express_x16} \
      CONFIG.pf0_msix_enabled {true} \
      CONFIG.c_m_axi_num_write {32} \
      CONFIG.pf0_msix_impl_locn {External} \
      CONFIG.pf0_bar0_size {64} \
      CONFIG.pf0_bar0_scale {Megabytes} \
      CONFIG.pf0_bar0_64bit {true} \
      CONFIG.axi_data_width {512_bit} \
      CONFIG.pf0_device_id {7038} \
      CONFIG.pf0_class_code_base {05} \
      CONFIG.pf0_class_code_sub {80} \
      CONFIG.pf0_class_code_interface {00} \
      CONFIG.xdma_axilite_slave {true} \
      CONFIG.coreclk_freq {500} \
      CONFIG.plltype {QPLL1} \
      CONFIG.pf0_msix_cap_table_size {83} \
      CONFIG.pf0_msix_cap_table_offset {20000} \
      CONFIG.pf0_msix_cap_table_bir {BAR_1:0} \
      CONFIG.pf0_msix_cap_pba_offset {28000} \
      CONFIG.pf0_msix_cap_pba_bir {BAR_1:0} \
      CONFIG.bar_indicator {BAR_1:0} \
      CONFIG.bar0_indicator {0}
      ]
    if {[catch {set_property -dict $pcie_properties $pcie_core}]} {
      error "ERROR: Failed to configure PCIe bridge. This may be related to the format settings of your OS for numbers. Please check that it is set to 'United States' (see AR# 51331)"
    }
    set_property -dict $pcie_properties $pcie_core


    tapasco::ip::create_msixusptrans "MSIxTranslator" $pcie_core

    set constraints_fn "$::env(TAPASCO_HOME_TCL)/platform/AU280/board.xdc"
    read_xdc $constraints_fn
    set_property PROCESSING_ORDER EARLY [get_files $constraints_fn]

    return $pcie_core
  }

  # Checks if the optional register slice given by the name is enabled (based on regslice feature and default value)
  proc is_regslice_enabled {name default} {
    if {[tapasco::is_feature_enabled "Regslice"]} {
      set regslices [tapasco::get_feature "Regslice"]
      if  {[dict exists $regslices $name]} {
          return [dict get $regslices $name]
        } else {
          return $default
        }
    } else {
      return $default
    }
  }

  # Inserts a new register slice between given master and slave (for SLR crossing)
  proc insert_regslice {name default master slave clock reset subsystem} {
    if {[is_regslice_enabled $name $default]} {
      set regslice [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_register_slice:2.1 $subsystem/regslice_${name}]
      set_property -dict [list CONFIG.REG_AW {15} CONFIG.REG_AR {15} CONFIG.REG_W {15} CONFIG.REG_R {15} CONFIG.REG_B {15} CONFIG.USE_AUTOPIPELINING {1}] $regslice
      delete_bd_objs [get_bd_intf_nets -of_objects [get_bd_intf_pins $master]]
      connect_bd_intf_net [get_bd_intf_pins $master] [get_bd_intf_pins $regslice/S_AXI]
      connect_bd_intf_net [get_bd_intf_pins $regslice/M_AXI] [get_bd_intf_pins $slave]
      connect_bd_net [get_bd_pins $clock] [get_bd_pins $regslice/aclk]
      connect_bd_net [get_bd_pins $reset] [get_bd_pins $regslice/aresetn]
    }
  }

  # Insert optional register slices
  proc insert_regslices {} {
    insert_regslice "dma_migic" false "/memory/dma/m32_axi" "/memory/mig_ic/S00_AXI" "/memory/mem_clk" "/memory/mem_peripheral_aresetn" "/memory"
    #insert_regslice "host_memctrl" true "/host/M_MEM_CTRL" "/memory/S_MEM_CTRL" "/clocks_and_resets/mem_clk" "/clocks_and_resets/mem_interconnect_aresetn" ""
    insert_regslice "arch_mem" false "/arch/M_MEM_0" "/memory/S_MEM_0" "/clocks_and_resets/design_clk" "/clocks_and_resets/design_interconnect_aresetn" ""
    insert_regslice "host_dma" true "/host/M_DMA" "/memory/S_DMA" "/clocks_and_resets/host_clk" "/clocks_and_resets/host_interconnect_aresetn" ""
    insert_regslice "dma_host" true "/memory/M_HOST" "/host/S_HOST" "/clocks_and_resets/host_clk" "/clocks_and_resets/host_interconnect_aresetn" ""
    insert_regslice "host_arch" true "/host/M_ARCH" "/arch/S_ARCH" "/clocks_and_resets/design_clk" "/clocks_and_resets/design_interconnect_aresetn" ""

    if {[is_regslice_enabled "pe" false]} {
      set ips [get_bd_cells /arch/target_ip_*]
      foreach ip $ips {
        set masters [tapasco::get_aximm_interfaces $ip]
        foreach master $masters {
          set slave [get_bd_intf_pins -filter {MODE == Slave} -of_objects [get_bd_intf_nets -of_objects $master]]
          insert_regslice [get_property NAME $ip] true $master $slave "/arch/design_clk" "/arch/design_interconnect_aresetn" "/arch"
        }
      }
    }
  }

  namespace eval AU280 {
        namespace export addressmap

        proc addressmap {args} {
            # add ECC config to platform address map
            set args [lappend args "M_MEM_CTRL" [list 0x40000 0x10000 0 "PLATFORM_COMPONENT_ECC"]]
            return $args
        }
    }


  tapasco::register_plugin "platform::AU280::addressmap" "post-address-map"

  tapasco::register_plugin "platform::insert_regslices" "post-platform"

  proc write_ltx {args} {
    global bitstreamname
    puts "Writing debug probes into file ${bitstreamname}.ltx ..."
    write_debug_probes -force -verbose "${bitstreamname}.ltx"
    return $args
  }

  #tapasco::register_plugin "platform::write_ltx" "post-impl"

}
