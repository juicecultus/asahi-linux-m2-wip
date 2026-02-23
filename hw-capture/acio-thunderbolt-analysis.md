# Apple ACIO/Thunderbolt NHI Hardware Analysis — T8112 (M2)

## Hardware Components (from macOS ioreg)

### Per-Port Architecture (2 ports on M2 MacBook Air)

Each USB-C port has:
```
atc-phy{N}    — Type-C PHY (USB2/USB3/USB4/DP muxing)
acio{N}       — Thunderbolt/USB4 controller ("ACIO")
dart-acio{N}  — IOMMU for ACIO DMA
acio-cpu{N}   — IOP coprocessor running ACIO firmware
```

### ACIO0 (Port 0 — near MagSafe)
- **acio0@81F00000**: compatible = "acio"
  - MMIO base: 0x381F00000, length: 0x100000 (1MB)
  - Additional MMIO regions (from IODeviceMemory):
    - 0x381F00000 (1MB) — main registers
    - 0x381830000 (196KB) — additional regs
    - 0x381400000 (16KB)
    - 0x381404000 (16KB)
    - 0x381408000 (16KB)
    - 0x381B00000 (16KB)
  - atc-phy-parent: 0xb8 (phandle to atc-phy0)
  - link-speed-default: [8, 12, 12, 0] (Gen2/Gen3 speeds)
  - link-width-default: [1, 1, 2, 0] (x1/x1/x2 widths)
  - spec-version: 0x20 (USB4 v2.0)
  - IOPCITunnelControllerID: 0xFFFFFF9D
  - thunderbolt-drom: Contains "Apple Inc." vendor, "iOS" string
  - Has top_tunables, lbw_fabric_tunables, hi_up_tx_desc_fabric_tunables, etc.

- **dart-acio0@81A80000**: compatible = "dart,t8110"
  - MMIO: 0x381A80000 (16KB)
  - DART (IOMMU) for ACIO0 DMA
  - page-size: 0x4000 (16KB)
  - sid: [1, 15]

- **acio-cpu0@81108000**: compatible = "iop,mxwrap-acio"
  - MMIO: 0x381108000 (16KB), 0x381100000 (16KB)
  - Role: "ACIO0"
  - IOP coprocessor that runs Thunderbolt firmware
  - 4 interrupts
  - Creates iop-acio0-nub child

### ACIO1 (Port 1 — far from MagSafe)
- **acio1@1F00000**: compatible = "acio"
  - Same structure as ACIO0 but different addresses (0x5XXXXXXX range)
  - atc-phy-parent: 0xbe (phandle to atc-phy1)
  - IOPCITunnelControllerID: 0xFFFFFFA3
  - Own thunderbolt-drom

- **dart-acio1@1A80000**: compatible = "dart,t8110"
- **acio-cpu1@1108000**: compatible = "iop,mxwrap-acio"

## macOS Driver Stack
```
AppleARMIODevice (acio0@81F00000)
  └─ AppleThunderboltHALType5
       └─ AppleThunderboltNHIType5
            └─ IOThunderboltControllerType5
                 ├─ IOThunderboltPort@7
                 │    └─ IOThunderboltSwitchType5
                 │         ├─ IOThunderboltPort@3 (downstream)
                 │         └─ IOThunderboltPort@4 (downstream)
                 └─ IOThunderboltXDomainLink@0,1
```

## Key Observations

1. **IOP Coprocessor**: The ACIO uses an IOP ("I/O Processor") coprocessor
   with "iop,mxwrap-acio" compatible. Other Apple IOP drivers exist in
   Linux (e.g., apple-rtkit-helper for DCP, ISP). The ACIO IOP likely
   uses Apple's RTKit protocol for communication.

2. **DART**: Each ACIO has its own DART (IOMMU). The Linux DART driver
   already supports "dart,t8110". This is needed for DMA between ACIO
   and system memory.

3. **PCIe Tunneling**: The `IOPCITunnelControllerID` property indicates
   ACIO handles PCIe tunneling for Thunderbolt. Connected devices appear
   as PCIe endpoints tunneled through the Thunderbolt link.

4. **Thunderbolt DROM**: Device ROM containing vendor info, port capabilities.
   Standard Thunderbolt DROM format used by the Linux `thunderbolt` driver.

5. **Fabric Tunables**: Multiple sets of fabric tunables suggest complex
   internal bus architecture with separate upstream/downstream data paths.

## What Linux Needs

### Phase 1: DT + Basic ACIO Driver
- Add ACIO nodes to t8112 DTS (acio0, acio1, dart-acio, acio-cpu)
- Write basic ACIO platform driver that probes and initializes hardware
- Initialize DART for ACIO DMA
- Boot ACIO IOP coprocessor via RTKit

### Phase 2: NHI Integration
- Implement NHI (Native Host Interface) compatible with Linux `thunderbolt`
- Register with `tb_nhi_alloc()` / `tb_nhi_init()`
- Handle ring buffer setup for Thunderbolt protocol
- Process Thunderbolt control packets

### Phase 3: Tunnel Management
- Enable PCIe tunneling (for Thunderbolt devices)
- Enable DP tunneling (for Thunderbolt displays)
- USB3 tunneling (for USB over Thunderbolt)

## Existing Linux Patterns to Follow
- `drivers/thunderbolt/nhi.c` — Intel NHI reference
- `drivers/soc/apple/rtkit.c` — Apple RTKit IOP protocol
- `drivers/gpu/drm/apple/dcp*.c` — Apple DCP (similar IOP pattern)
- `drivers/iommu/apple-dart.c` — Apple DART driver
