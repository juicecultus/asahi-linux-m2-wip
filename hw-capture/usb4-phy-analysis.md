# USB4 PHY Mode Analysis — M2 MacBook Air (T8112)

## Data Sources
- HV trace run 1: `hv_trace_run1.log` (1960 lines, macOS 13.5 dev kernel under m1n1 HV)
- HV console run 1: `hv_console_run1.log` (4621 lines)
- macOS ioreg device tree: `ioreg-devicetree.txt`
- Linux fairydust atcphy driver: `drivers/phy/apple/atc.c`

## Observed macOS PHY Transition Sequence (HV Traces)

### Phase 1: USB2 PHY Init on Port 1 (Host Mode)
```
USB2PHY_SIG: MODE_HOST=0x10 → 0x17 (configure host mode)
USB2PHY_SIG: VBUSDET_FORCE_VAL/EN set (force VBUS detection)
USB2PHY_SIG: VBUSVLDEXT_FORCE_EN=1 (force VBUS valid)
USB2PHY_CTL: SIDDQ=0, RESET deasserted, APB_RESETN=1
USB2PHY_MISCTUNE: Clock gates opened (APBCLK_GATE_OFF=0, REFCLK_GATE_OFF=0)
USB2PHY_USBCTL: MODE_HOST=1, MODE_ISOLATION=0
```

### Phase 2: DWC3 Controller Config (Host Mode)
```
GCTL: PRTCAP=2(device) → PRTCAP=1(host)
GUSB2PHYCFG: SUSPHY configured
GUSB3PIPECTL: SUSPHY configured
PIPEHANDLER_NONSELECTED_OVERRIDE: DUMMY_PHY_EN=1, NATIVE_RESET=1, NATIVE_POWER_DOWN=2
PIPEHANDLER_MUX_CTRL: MUX_MODE=DUMMY_PHY, CLK_SELECT=DUMMY_PHY
```

### Phase 3: USB2 PHY Teardown (Transition to USB4/TBT)
```
PIPEHANDLER_AON_GEN: DWC3_RESET_N=1 → 0 (reset DWC3)
PIPEHANDLER_AON_GEN: DWC3_FORCE_CLAMP_EN=1 (force clamp)
USB2PHY_USBCTL: MODE_HOST=1 → MODE_ISOLATION=1 (isolate USB2)
USB2PHY_CTL: SIDDQ=1 (power down analog)
USB2PHY_CTL: PORT_RESET=1, RESET=1 (full reset)
USB2PHY_CTL: APB_RESETN=0 (APB reset)
USB2PHY_MISCTUNE: APBCLK_GATE_OFF=1, REFCLK_GATE_OFF=1 (gate clocks)
```

### Phase 4: USB4/TBT PHY Setup (NOT CAPTURED — USB link dropped)
Expected based on code analysis:
1. CIO tunables applied (lane_usb4 tunables from ADT)
2. Lane modes set to USB4
3. Crossbar protocol set to USB4
4. Pipehandler MUX switched to USB4 (CLK=2, DATA=1)
5. BIST sequence (same as USB3)
6. Link detection overrides removed
7. DWC3 clamp released, reset deasserted

## Key Register Defines (from Linux driver)
```c
PIPEHANDLER_MUX_CTRL_CLK_USB4  = 2  // vs USB3 = 1
PIPEHANDLER_MUX_CTRL_DATA_USB4 = 1  // vs USB3 = 0
```

## CIO Tunables (from ioreg, both ports identical structure)
The ADT provides per-port tunables via:
- `apple,tunable-lane0-cio` → `atcphy->tunables.lane_usb4[0]`
- `apple,tunable-lane1-cio` → `atcphy->tunables.lane_usb4[1]`

These are already loaded by the Linux driver. The tunables contain
(offset, mask, value) triplets for CIO PHY register blocks including:
- CIO_LN{0,1}_AUSPMA_RX_SHM
- CIO_LN{0,1}_AUSPMA_RX_TOP
- CIO_LN{0,1}_AUSPMA_RX_EQ
- CIO_LN{0,1}_AUSPMA_TX_TOP
- CIO_ACIOPHY_TOP
- CIO3PLL_TOP / CIO3PLL_CORE

## Missing Implementation
File: `drivers/phy/apple/atc.c`, line 1136-1140

The `ATCPHY_PIPEHANDLER_STATE_USB4` case falls back to dummy PHY.
Needs: `atcphy_configure_pipehandler_usb4()` — same structure as
`atcphy_configure_pipehandler_usb3()` but with USB4 MUX values.

## Note on DP Tunneling
USB4 PHY mode alone enables the physical link. DisplayPort tunneling
over USB4/Thunderbolt additionally requires:
- Thunderbolt NHI (Native Host Interface) driver
- USB4 router/tunnel management
- DP IN adapter protocol
These are higher-layer protocols handled by the `thunderbolt` kernel subsystem.
