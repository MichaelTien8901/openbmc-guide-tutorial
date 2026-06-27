---
layout: default
title: SGPIO (Serial GPIO)
parent: Advanced Topics
nav_order: 22
difficulty: advanced
prerequisites:
  - gpio-management-guide
  - linux-kernel-driver-development-guide
  - device-tree
last_modified_date: 2026-06-27
---

# SGPIO (Serial GPIO)
{: .no_toc }

Expand BMC signal count over a few shared pins using the ASPEED serial GPIO master — define it in the device tree, enable the kernel driver, and use it from userspace exactly like parallel GPIO.
{: .fs-6 .fw-300 }

## Table of Contents
{: .no_toc .text-delta }

1. TOC
{:toc}

---

## Overview

**SGPIO (Serial GPIO)** is a hardware feature on ASPEED BMC SoCs that shifts many GPIO signals in and out over a small, fixed set of pins instead of dedicating one SoC pin per signal. A server platform often needs to read dozens of host-side status signals — CPU presence, THERMTRIP, VRHOT, FIVR fault, DIMM status — and drive backplane LEDs. Wiring each of those to its own BMC pin would exhaust the pinmux. SGPIO solves this by serializing the signals onto a clocked bus.

The ASPEED SGPIO controller is a **master**: it generates a shift clock and a load/latch strobe, shifts BMC output bits out, and shifts external input bits in. The other end is typically the host PCH (acting as an SGPIO source) or a chain of shift registers on a backplane. From Linux's point of view, the controller registers as an ordinary **gpiochip**, so every userspace tool you already know — `gpioinfo`, `gpioget`, `gpioset`, `gpiomon`, libgpiod, and `phosphor-multi-gpio-monitor` — works on SGPIO lines with **no API changes**.

This guide shows you how to declare the SGPIO controller in the device tree, enable and understand the `gpio-aspeed-sgpio` kernel driver, and use the resulting lines from userspace — contrasting each step with ordinary parallel GPIO so you know when to reach for SGPIO and what changes when you do. ASPEED (AST2500/AST2600) is the primary worked example; a dedicated [Nuvoton NPCM SGPIO](#nuvoton-npcm-sgpio-siox-hardware) section covers the NPCM7xx/NPCM8xx controller — whose underlying silicon is actually the **SIOX** (Serial I/O eXpansion) block with a *different, half-duplex* signaling scheme, even though its Linux driver is named `sgpio`.

**Key concepts covered:**
- What serial GPIO is and the 4-wire master protocol (clock, load, data-out, data-in)
- How SGPIO differs from parallel GPIO — pins, latency, direction model, use cases
- Declaring the SGPIO controller in the device tree (`compatible`, `ngpios`, `bus-frequency`, pinctrl)
- The `ngpios` doubling rule and the even-input / odd-output line layout
- Enabling and understanding the `gpio-aspeed-sgpio` kernel driver
- Using SGPIO lines from userspace and `phosphor-multi-gpio-monitor` — identical to GPIO
- Porting to Nuvoton NPCM, whose `nuvoton,input-ngpios`/`nuvoton,output-ngpios` model differs from ASPEED

{: .note }
SGPIO is **hardware-dependent**. The controller and its gpiochip register under Linux regardless, so you can discover lines with `gpioinfo`, but meaningful *input values* require the physical serial link to the host or shift registers. The `ast2600-evb` QEMU target does not emulate the SGPIO serial bus, so this guide is verified only as far as line discovery in QEMU; live signal values require real hardware.

---

## SGPIO vs Parallel GPIO

If you have read the [GPIO Management Guide]({% link docs/03-core-services/14-gpio-management-guide.md %}), SGPIO will feel familiar once it is up — the difference is almost entirely in *how the lines reach the SoC*, not in how you use them. Use this table to decide which one a given signal belongs on.

| Aspect | Parallel GPIO | SGPIO (Serial GPIO) |
|--------|---------------|---------------------|
| **Wiring** | One dedicated SoC pin per signal | 3–4 shared pins (clock, load, data-out, data-in) carry *all* signals |
| **Signal count** | Limited by free pins on the package | Up to **80** lines (AST2400/AST2500) or **128** lines (AST2600 master 1) per controller |
| **Transport** | Direct electrical level on the pin | State serially shifted on a clocked bus at `bus-frequency` |
| **Direction** | Each pin independently input *or* output | Each hardware line is **fixed**: one input **and** one output (see the [doubling rule](#the-ngpios-doubling-rule)) |
| **Latency** | Immediate — the register reflects the pin now | Bounded by the shift period; state refreshes once per frame |
| **Edge events** | Hardware-accurate, low-latency IRQ | Edge/level IRQ **is** supported, but timestamp granularity is bounded by the shift clock |
| **Typical use** | Buttons, resets, presence local to the BMC board | Host/PCH/CPU status *into* the BMC; backplane LED/presence fan-out |
| **Device tree** | Controller already in the SoC `.dtsi`; you just name lines | Dedicated `sgpio`/`sgpiom` node you must enable, size (`ngpios`), and clock (`bus-frequency`) |
| **Userspace API** | libgpiod / gpiochip | **Identical** — same gpiochip, same libgpiod, same tools |

{: .tip }
**Rule of thumb:** reach for SGPIO when you have many low-rate *status* signals (presence, fault, LEDs) that originate off the BMC board — especially host/PCH status. Keep latency-critical or BMC-local signals (power button, reset, watchdog strobes) on parallel GPIO.

{: .note }
The "bounded latency / no precise edge timing" characteristic follows from the serial, divided-clock design: a signal is only sampled when its bit is shifted through. The driver *does* deliver edge interrupts, so event-driven monitoring works — but do not rely on SGPIO for sub-microsecond edge timestamps the way you might with a parallel GPIO IRQ.

---

## Architecture

### The Serial Master Protocol

The ASPEED SGPIO master drives a small fixed pin group and clocks signal state through it. On the AST2600, master 1 (`SGPM1`) uses four balls:

| Signal | AST2600 ball | Pad (GPIO) | Role |
|--------|--------------|-----------|------|
| `SGPM1CLK` | A18 | GPIOH0 | Shift clock — generated by the BMC master |
| `SGPM1LD` | B18 | GPIOH1 | Load / latch strobe — frames each shift cycle |
| `SGPM1O` | C18 | GPIOH2 | Serial data **out** (BMC → external, e.g. LEDs) |
| `SGPM1I` | A17 | GPIOH3 | Serial data **in** (external → BMC, e.g. CPU status) |

The shift clock is derived from the APB bus clock divided by a programmable value set from the `bus-frequency` property. Each load/shift cycle moves the full bank of input bits into the controller's input register and the full bank of output bits out to the external shift register or device.

```
        BMC (SGPIO master)                         External (host PCH / shift registers)
  ┌──────────────────────────┐                    ┌──────────────────────────────────┐
  │  ASPEED SGPIO controller │   SGPM1CLK ───────▶│  shift clock                      │
  │  (gpio-aspeed-sgpio)     │   SGPM1LD  ───────▶│  load / latch                     │
  │                          │   SGPM1O   ───────▶│  serial data in  (LED/presence)   │
  │                          │   SGPM1I   ◀───────│  serial data out (CPU/DIMM status)│
  └──────────────────────────┘                    └──────────────────────────────────┘
            │
            ▼  registers as a standard Linux gpiochip
  /dev/gpiochipN  ──▶  libgpiod / gpioinfo / phosphor-multi-gpio-monitor
```

{: .note }
The ASPEED SoC also exposes **slave** pin groups (`SGPS1`/`SGPS2`) for the case where the BMC is an SGPIO *slave* to an external master. The mainline `gpio-aspeed-sgpio` driver implements the **master** side only. This guide covers the master path, which is the common OpenBMC use case.

### The `ngpios` Doubling Rule

This is the single most important thing to understand about ASPEED SGPIO, and the biggest difference from parallel GPIO.

The `ngpios` property declares the number of **hardware** SGPIO lines. The driver then exposes **two software GPIO lines per hardware line** — one input and one output — so the registered gpiochip has `2 × ngpios` lines. The two lines are **interleaved**, not split into halves:

- **Even** offset (0, 2, 4, …) = the **input** half of a hardware line (read host/PCH/CPU status here)
- **Odd** offset (1, 3, 5, …) = the **output** half of a hardware line (drive an LED/strobe here)

So `ngpios = <80>` produces **160** userspace GPIO lines, and `ngpios = <128>` produces **256**.

```
 hardware line:     0           1           2          ...
 software offset:  0   1       2   3       4   5
                   │   │       │   │       │   │
                  in  out     in  out     in  out
              (even)(odd)  (even)(odd)  (even)(odd)
```

{: .warning }
Because direction is fixed by this even/odd model, you cannot freely flip an SGPIO line between input and output the way you can a parallel GPIO. Each hardware line is *permanently* one input GPIO plus one output GPIO. Real platforms that only consume host status populate the **even** (input) `gpio-line-names` and leave the **odd** (output) names as empty strings `""`.

---

## Defining SGPIO in the Device Tree

There are two parts: the **SoC controller node** (already present, but disabled, in the ASPEED `.dtsi`) and your **board-level enablement** that sizes it, clocks it, and names its lines.

### Compatible Strings

| SoC | Compatible string | Notes |
|-----|-------------------|-------|
| AST2400 | `aspeed,ast2400-sgpio` | Single controller, up to 80 lines |
| AST2500 | `aspeed,ast2500-sgpio` | Single controller, up to 80 lines (shares driver data with AST2400) |
| AST2600 | `aspeed,ast2600-sgpiom` | **Two** controllers (`sgpiom0`/`sgpiom1`); note the `-sgpiom` suffix |
| AST2700 | `aspeed,ast2700-sgpiom` | Present in current mainline |

{: .warning }
Watch the suffix: AST2400/AST2500 use `-sgpio`, while AST2600/AST2700 use `-sgpio**m**` (master). A proposed patch once added `aspeed,ast2600-sgpiom1`/`-sgpiom2` compatibles, but **mainline does not use these** — both AST2600 nodes share the single `aspeed,ast2600-sgpiom` string. Do not invent per-instance compatibles.

### Properties

| Property | Required | Description |
|----------|----------|-------------|
| `compatible` | yes | One of the strings above |
| `reg` | yes | Controller register window |
| `gpio-controller` | yes | Marks this node as a GPIO provider |
| `#gpio-cells` | yes | Always `<2>` (line offset + flags) |
| `interrupts` | yes | Controller interrupt line |
| `interrupt-controller` | yes | The chip is also an IRQ provider (edge/level events) |
| `#interrupt-cells` | yes | Always `<2>` |
| `ngpios` | yes | Number of **hardware** lines — see the [doubling rule](#the-ngpios-doubling-rule). **Must be a multiple of 8.** |
| `clocks` | yes | Source clock for the shift-clock divider (APB / APB2) |
| `bus-frequency` | yes | SGPM shift-clock frequency in Hz |
| `pinctrl-0` / `pinctrl-names` | in practice | Routes the SGPM pins (not in the binding's *required* list, but needed to actually drive the bus) |

{: .warning }
`ngpios` **must be a multiple of 8** — the driver rejects any other value with `-EINVAL` ("Number of GPIOs not multiple of 8"). It is *not* enough for it to be even. Also note the driver does **not** enforce the per-controller hardware maximum (80 or 128); choosing a value that exceeds your SoC's capability is your responsibility in the board DTS.

### The SoC Controller Nodes (already in the `.dtsi`)

You normally do **not** write these — they live in the ASPEED SoC include files with `status = "disabled"`. They are shown here so you know what you are enabling.

**AST2600** (`aspeed-g6.dtsi`) — two masters:

```dts
sgpiom0: sgpiom@1e780500 {
    #gpio-cells = <2>;
    gpio-controller;
    compatible = "aspeed,ast2600-sgpiom";
    reg = <0x1e780500 0x100>;
    interrupts = <GIC_SPI 51 IRQ_TYPE_LEVEL_HIGH>;
    clocks = <&syscon ASPEED_CLK_APB2>;
    #interrupt-cells = <2>;
    interrupt-controller;
    bus-frequency = <12000000>;
    pinctrl-names = "default";
    pinctrl-0 = <&pinctrl_sgpm1_default>;
    status = "disabled";          /* you enable this in the board DTS */
};

/* sgpiom1 @ 0x1e780600 is identical except:
 *   interrupts = <GIC_SPI 70 IRQ_TYPE_LEVEL_HIGH>;
 *   pinctrl-0  = <&pinctrl_sgpm2_default>;
 */
```

**AST2500** (`aspeed-g5.dtsi`) — single controller:

```dts
sgpio: sgpio@1e780200 {
    #gpio-cells = <2>;
    compatible = "aspeed,ast2500-sgpio";
    gpio-controller;
    interrupts = <40>;
    reg = <0x1e780200 0x0100>;
    clocks = <&syscon ASPEED_CLK_APB>;
    #interrupt-cells = <2>;
    interrupt-controller;
    bus-frequency = <12000000>;
    pinctrl-names = "default";
    pinctrl-0 = <&pinctrl_sgpm_default>;
    status = "disabled";
};
```

### Enabling and Naming Lines in Your Board DTS

This is the part **you** write. Reference the SoC node by phandle, set `status = "okay"`, size it with `ngpios`, set the `bus-frequency` your hardware can carry, and assign `gpio-line-names`. Remember the even/odd layout: input names on even indices, output names (or `""`) on odd.

**AST2600 example — host/CPU status into the BMC:**

```dts
&sgpiom0 {
    status = "okay";
    ngpios = <128>;               /* 128 hardware lines -> 256 software GPIOs */
    bus-frequency = <1000000>;    /* 1 MHz shift clock; lower it for long backplane runs */

    gpio-line-names =
        /* hw line 0 */ "CPU1_PRESENCE",      "",   /* even=in, odd=out(unused) */
        /* hw line 1 */ "CPU1_THERMTRIP",     "",
        /* hw line 2 */ "CPU1_VRHOT",         "",
        /* hw line 3 */ "CPU1_FIVR_FAULT",    "",
        /* hw line 4 */ "CPU1_MEM_ABCD_VRHOT","",
        /* hw line 5 */ "CPU1_MEM_EFGH_VRHOT","",
        /* hw line 6 */ "",                   "FAULT_LED_DRIVE";  /* output example */
        /* ... continue for all 128 hardware lines (256 names) ... */
};
```

{: .warning }
The `gpio-line-names` array must list **two** names per hardware line and cover the full `2 × ngpios` count (160 for `ngpios=80`, 256 for `ngpios=128`). A short array silently leaves the trailing lines unnamed. Keep the input name on the even index and either an output name or `""` on the following odd index.

**Lowering `bus-frequency` for real boards:** the `.dtsi` default of 12 MHz is rarely used on production hardware. Long backplane cable runs and signal integrity push the clock down — mainline boards run anywhere from 2 MHz (Intel Vegman) to 500 kHz (IBM System1). The constraint is purely that the computed divider fits a 16-bit field; the exact floor depends on your APB clock.

---

## The Kernel Driver

### Driver and Kconfig

| Item | Value |
|------|-------|
| Source file | `drivers/gpio/gpio-aspeed-sgpio.c` |
| Kconfig symbol | `CONFIG_GPIO_ASPEED_SGPIO` |
| Binds via | `compatible` strings in its `of_match_table` (see [above](#compatible-strings)) |

Enable it in your kernel config fragment (see the [Kernel Driver Development Guide]({% link docs/05-advanced/12-linux-kernel-driver-development-guide.md %}) for how fragments are layered in OpenBMC):

```text
# meta-<vendor>/recipes-kernel/linux/linux-aspeed/sgpio.cfg
CONFIG_GPIO_ASPEED_SGPIO=y
```

```bitbake
# linux-aspeed_%.bbappend
FILESEXTRAPATHS:prepend := "${THISDIR}/${PN}:"
SRC_URI += "file://sgpio.cfg"
```

Verify it is built and bound after boot:

```bash
# Driver present?
zcat /proc/config.gz | grep GPIO_ASPEED_SGPIO     # CONFIG_GPIO_ASPEED_SGPIO=y

# Controller bound? (look for the sgpiom register address)
ls /sys/bus/platform/drivers/aspeed-sgpio/
dmesg | grep -i sgpio
```

### What the Driver Does

Understanding a few driver behaviors explains the userspace experience:

- **Registers a standard gpiochip.** It reads `ngpios`, sets `chip.ngpio = ngpios * 2`, and registers an ordinary `gpio_chip` plus an irqchip. That is *why* every libgpiod tool works unchanged.
- **Even = input, odd = output.** The direction of each software line is decided by `offset % 2` (`aspeed_sgpio_is_input()` returns true for even offsets). You cannot change it.
- **On-demand register access.** `get`/`set` perform direct `ioread32`/`iowrite32` against the controller's data registers — there is **no polling kernel timer**. An input read returns the value last shifted into the input register.
- **Edge and level interrupts.** The driver provides an irqchip supporting `IRQ_TYPE_EDGE_RISING`, `IRQ_TYPE_EDGE_FALLING`, `IRQ_TYPE_EDGE_BOTH`, and the level types, dispatched through `handle_edge_irq`/`handle_level_irq`. This is what makes `gpiomon` and `phosphor-multi-gpio-monitor` event-driven monitoring work on SGPIO lines. The irqchip is flagged `IRQCHIP_IMMUTABLE`.
- **Clock divider.** From `bus-frequency` it computes `div = apb_freq / (sgpio_freq * 2) - 1` (so the shift frequency is `PCLK / (2 × (div + 1))`) and rejects a divider that overflows the 16-bit field with `-EINVAL` — the practical reason a too-low `bus-frequency` fails to probe.

{: .note }
There is no SGPIO-specific character device or sysfs interface. The driver's whole job is to make a serial bus *look like a parallel gpiochip*. Once probed, forget it is serial — until you are debugging timing.

---

## Using SGPIO from Userspace

Here is the payoff: **using SGPIO is identical to using parallel GPIO.** The only thing you must keep in mind is the even-input / odd-output line layout.

### Discover Lines

```bash
# List every gpiochip; the SGPIO controller appears alongside the parallel ones
gpiodetect
# gpiochip0 [1e780000.gpio]    (232 lines)   <- parallel GPIO
# gpiochip1 [1e780500.sgpio]   (256 lines)   <- SGPIO master 0 (ngpios=128 -> 256)

# Show SGPIO lines with their names and current state
gpioinfo gpiochip1 | grep -v unnamed
#   line   0:  "CPU1_PRESENCE"   input  active-high
#   line   2:  "CPU1_THERMTRIP"  input  active-high
#   line   4:  "CPU1_VRHOT"      input  active-high
```

{: .tip }
Prefer **named-line** access over raw chip+offset. Because OpenBMC tools resolve a line by its `gpio-line-names` string across all chips, you never have to hard-code which `gpiochipN` the SGPIO controller landed on — and that number can shift when other GPIO providers probe.

### Read Inputs and Drive Outputs

```bash
# Read a host-status input by NAME (resolves to the even line, whichever chip it is on)
gpioget $(gpiofind "CPU1_THERMTRIP")
# 0   -> not asserted

# ...or by explicit chip + EVEN offset (input half of hardware line 1)
gpioget gpiochip1 2

# Drive an output by name (an ODD line — the output half of a hardware line)
gpioset $(gpiofind "FAULT_LED_DRIVE")=1

# Watch an SGPIO input for edges, exactly like a parallel GPIO
gpiomon --num-events=1 --falling-edge $(gpiofind "CPU1_THERMTRIP")
```

{: .warning }
Trying to `gpioset` an **even** (input) offset, or `gpioget`-and-expect-to-drive an **odd** (output) offset, will not do what you want. Even = input, odd = output is fixed by the hardware. If `gpioset` on a name fails, you almost certainly named the input half; the drivable line is the next (odd) offset.

### Monitoring with phosphor-multi-gpio-monitor

Because SGPIO lines are ordinary named gpiochip lines, `phosphor-multi-gpio-monitor` configures them with the **same JSON** described in the [GPIO Management Guide]({% link docs/03-core-services/14-gpio-management-guide.md %}) — just point `LineName` at an SGPIO input name. Here a host THERMTRIP arriving over SGPIO triggers a logging target:

```json
{
    "GpioConfigs": [
        {
            "Name": "Cpu1Thermtrip",
            "LineName": "CPU1_THERMTRIP",
            "GpioNum": 0,
            "ChipId": "",
            "EventMon": "FALLING",
            "Targets": {
                "0": ["log-cpu-thermtrip@0.target"]
            },
            "Continue": true
        }
    ]
}
```

{: .note }
The monitor neither knows nor cares that `CPU1_THERMTRIP` is an SGPIO line rather than a parallel one — it requests the line by name through the same libgpiod chardev path. This is the central practical takeaway of this guide.

---

## Nuvoton NPCM SGPIO (SIOX Hardware)

Nuvoton NPCM7xx and NPCM8xx BMCs expose a serial GPIO expander too, and Linux drives it through a gpiochip — so everything *above* the device tree (the gpiochip abstraction, libgpiod, `phosphor-multi-gpio-monitor`) works the same way. But there are **two** important differences from ASPEED: the device-tree model is different enough that you cannot copy the node, **and the underlying hardware is not the same kind of serial GPIO at all.**

### Hardware: SIOX, Not True SGPIO

The NPCM peripheral is the **SIOX (Serial I/O eXpansion)** block, not an SFF-8485-style SGPIO master like ASPEED's. The Linux driver and binding are *named* `sgpio` (`gpio-npcm-sgpio.c`, `nuvoton,...-sgpio`), but the silicon is SIOX. The giveaway is everywhere in the pinmux: the pin groups are `iox1`/`iox2`/`ioxh` — **IOX = I/O eXpansion** — and the interface is designed to clock external `74HC595` (output, serial-in/parallel-out) and `74HC165` (input, parallel-in/serial-out) shift-register chains.

The signaling difference matters for performance:

| | True SGPIO (ASPEED) | SIOX (Nuvoton NPCM) |
|--|---------------------|---------------------|
| **Duplex** | Full-duplex | Half-duplex |
| **How bits move** | Input and output bits are clocked on **opposite edges of the same shift clock** — one clock period moves an input bit *and* an output bit concurrently | Shifts a full **8 bits in one direction, then 8 bits in the other** direction in separate phases |
| **Throughput at a given clock** | Both directions per clock | **~half** — refreshing both the input byte and the output byte takes roughly twice the clocks |

{: .warning }
Do not assume Nuvoton SGPIO has the same refresh latency as ASPEED SGPIO at the same clock rate. Because SIOX is half-duplex (one direction at a time), the effective update rate for a given shift clock is **about half** that of a full-duplex SGPIO master. Size your timing budget for status signals accordingly, and keep genuinely fast signals on parallel GPIO. The same "[edge events may be missed/delayed](#issue-edge-events-missed-or-delayed)" caveat applies, more so.

{: .note }
Why call it "SGPIO" at all, then? Because from Linux's point of view both are just serial gpiochips, and the upstream driver/binding adopted the `sgpio` name. This guide groups them together for that reason — but when you reason about *signal timing or schematic design*, treat the Nuvoton part as SIOX with HC595/HC165 expanders, not as an SFF-8485 SGPIO.

### Where the Driver and Binding Live

| Item | Value |
|------|-------|
| Driver source | `drivers/gpio/gpio-npcm-sgpio.c` |
| Kconfig symbol | `CONFIG_GPIO_NPCM_SGPIO` |
| Mainline Linux | Present since **v6.8** |
| OpenBMC kernel | In-tree on `openbmc/linux` since **`dev-6.6`** (current `dev-6.18` has it) |
| meta-nuvoton | Enabled via defconfig — `CONFIG_GPIO_NPCM_SGPIO=y` in `npcm8xx_defconfig` (not the generic `defconfig`); **no out-of-tree kernel patch** |
| Device tree binding | `Documentation/devicetree/bindings/gpio/nuvoton,sgpio.yaml` |

{: .note }
You were right to expect a patch: in an **early (v4) submission**, the Nuvoton SGPIO DTS node carried a `bus-frequency` property and a `pinctrl-0 = <&iox1_pins>`. **Both were dropped before merge.** The shipping upstream driver and binding have neither — so do not copy a `bus-frequency`/`pinctrl-0` from an old patch onto a modern NPCM SGPIO node; it will not match the binding. The driver and binding are now fully upstream.

{: .warning }
**No in-tree device-tree node exists** for NPCM SGPIO — not in mainline, `openbmc/linux`, or U-Boot. Unlike ASPEED (where the `sgpio`/`sgpiom` node ships disabled in the SoC `.dtsi` and you just enable it), on Nuvoton you must **author the entire `sgpio` node yourself** from the binding example. Enable the controller's clock and add it under the SoC's APB3 bus.

### Compatible Strings

| SoC | Compatible string |
|-----|-------------------|
| NPCM7xx | `nuvoton,npcm750-sgpio` |
| NPCM8xx | `nuvoton,npcm845-sgpio` |

### How Nuvoton Differs from ASPEED

This is the part that trips people up. The Nuvoton controller does **not** use a single `ngpios` with the even/odd doubling rule. Instead it declares input and output counts separately, and lays the lines out as two contiguous ranges with **outputs first**.

| Aspect | ASPEED (`gpio-aspeed-sgpio`) | Nuvoton (`gpio-npcm-sgpio`) |
|--------|------------------------------|-----------------------------|
| Hardware block | SGPIO master (SFF-8485 style), full-duplex | **SIOX** (Serial I/O eXpansion), half-duplex — see [above](#hardware-siox-not-true-sgpio) |
| Line-count property | Single `ngpios` (hardware lines) | **Two**: `nuvoton,input-ngpios` and `nuvoton,output-ngpios` (each **≤ 64**) |
| Total gpiochip lines | `2 × ngpios` | `input-ngpios + output-ngpios` |
| Direction layout | **Interleaved**: even = input, odd = output | **Contiguous**: offsets `0 … nout-1` = **outputs**, then `nout … nout+nin-1` = **inputs** |
| Direction | Fixed (each hw line is 1 in + 1 out) | Fixed (each line is input-*only* or output-*only*) |
| Shift clock | `bus-frequency` property (you set it) | **No property** — auto-derived from APB3, kept **< 8 MHz** |
| pinctrl on the node | `pinctrl-0 = <&pinctrl_sgpm1_default>` | Not on the node — mux via the `iox1`/`iox2` pin groups separately |
| Max lines / controller | 80 (AST2400/2500) or 128 (AST2600 master 0) hardware | 64 input + 64 output = 128 total |
| Controllers per SoC | 1 (AST2500) / 2 (AST2600) | 2 (both NPCM7xx and NPCM8xx) |

{: .warning }
**Outputs occupy the low offsets, inputs the high offsets** — the opposite mental model from "inputs first". With `output-ngpios = <64>` and `input-ngpios = <64>`, lines `0–63` are outputs and lines `64–127` are inputs. Only the input range is interrupt-capable. Get this backwards and `gpioset`/`gpioget` will silently target the wrong half.

### Device Tree Node

This is the **merged, authoritative** NPCM7xx example from the upstream binding — note there is no `bus-frequency` and no `pinctrl-0`:

```dts
/* Add under the APB3 bus in your board DTS. NPCM7xx (nuvoton,npcm750-sgpio). */
sgpio1: gpio@101000 {
    compatible = "nuvoton,npcm750-sgpio";
    reg = <0x101000 0x200>;
    clocks = <&clk NPCM7XX_CLK_APB3>;
    interrupts = <GIC_SPI 19 IRQ_TYPE_LEVEL_HIGH>;
    gpio-controller;
    #gpio-cells = <2>;
    nuvoton,input-ngpios = <64>;     /* lines 64..127 -> inputs  */
    nuvoton,output-ngpios = <64>;    /* lines 0..63    -> outputs */
};
```

For **NPCM8xx**, swap the compatible string and the clock macro:

```dts
sgpio1: gpio@<base> {
    compatible = "nuvoton,npcm845-sgpio";
    reg = <0x<base> 0x200>;          /* confirm the NPCM8xx base from your SoC datasheet/reference DTS */
    clocks = <&clk NPCM8XX_CLK_APB3>;
    interrupts = <GIC_SPI 19 IRQ_TYPE_LEVEL_HIGH>;
    gpio-controller;
    #gpio-cells = <2>;
    nuvoton,input-ngpios = <64>;
    nuvoton,output-ngpios = <64>;
};
```

{: .warning }
The NPCM8xx register base is intentionally left as `<base>` above: no public in-tree NPCM8xx SGPIO node exists to copy a verified address from. Take the base (and the second module's address) from the NPCM8xx datasheet or your platform's reference device tree. The NPCM7xx module 1 base `0x101000` (size `0x200`) is the only address confirmed from upstream.

Both fragments, with the outputs-first `gpio-line-names` layout filled in, are in [`examples/sgpio/sgpio-npcm.dtsi`]({{ site.baseurl }}/examples/sgpio/sgpio-npcm.dtsi).

### Pinmux

The SIOX interface uses four pins (data-out, data-in, shift-clock, load/latch), muxed through the **IOX** (I/O eXpansion) pin groups — the naming that reveals this is the SIOX block. On both NPCM7xx and NPCM8xx (`pinctrl-npcm7xx` / `pinctrl-npcm8xx`):

| Group | Pins | Use |
|-------|------|-----|
| `iox1` | 0, 1, 2, 3 | Serial I/O eXpansion 1 (SIOX module 1) |
| `iox2` | 4, 5, 6, 7 | Serial I/O eXpansion 2 (SIOX module 2) |

Select the matching group in your pinctrl configuration (e.g. reference `iox1` from the board's `pinctrl` node) so the SIOX pins leave the package.

### Enabling and Using It

```text
# meta-<vendor>/recipes-kernel/linux/linux-nuvoton/<machine>.cfg  (or rely on npcm8xx_defconfig)
CONFIG_GPIO_NPCM_SGPIO=y
```

From userspace it is the same gpiochip story as ASPEED — just remember the outputs-first / inputs-second layout when you read `gpioinfo`:

```bash
gpiodetect | grep -i sgpio
gpioinfo $(gpiodetect | awk '/sgpio/{print $1}')
#   line   0:  unnamed  output      <- outputs occupy the LOW offsets
#   ...
#   line  64:  "CPU1_THERMTRIP"  input   <- inputs occupy the HIGH offsets

# Read an input (high offset), drive an output (low offset)
gpioget $(gpiofind "CPU1_THERMTRIP")
gpioset gpiochipN 5=1
```

{: .note }
The clock cannot be set from the device tree on Nuvoton — the driver derives the SGPIO shift clock from APB3 and keeps it under 8 MHz automatically. There is nothing to tune in DT; if you need a slower shift for a long backplane, that is a hardware/board concern, not a `bus-frequency` knob.

---

## Porting Guide

Follow these steps to bring up SGPIO on your platform:

1. **Confirm the use case.** SGPIO is for many off-board status/LED signals — most often host/PCH/CPU status into the BMC. Latency-critical or BMC-local signals stay on parallel GPIO.
2. **Enable the kernel driver.** Add `CONFIG_GPIO_ASPEED_SGPIO=y` via a `.cfg` fragment and `.bbappend` (see [The Kernel Driver](#the-kernel-driver)).
3. **Enable the controller in your board DTS.** Reference `&sgpiom0` (AST2600) or `&sgpio` (AST2500), set `status = "okay"`, choose `ngpios` (multiple of 8, within the hardware max), and pick a `bus-frequency` your wiring supports.
4. **Route the pins.** Make sure the SGPM pinctrl group (`pinctrl_sgpm1_default` etc.) is selected so the clock/load/data balls leave the package.
5. **Name the lines.** Fill `gpio-line-names` with input names on even indices and output names (or `""`) on odd indices, covering all `2 × ngpios` entries.
6. **Build, flash, and verify:**

```bash
bitbake obmc-phosphor-image

# After boot, confirm the chip and lines:
gpiodetect | grep sgpio
gpioinfo $(gpiodetect | awk '/sgpio/{print $1}') | grep -v unnamed

# Drive the bus and read a known signal (needs the physical serial link):
gpioget $(gpiofind "CPU1_PRESENCE")
```

{: .warning }
If `gpioinfo` lists the SGPIO lines but every input reads a stuck value, the gpiochip registered but the **serial bus is not actually shifting** — check the pinmux routing, the `bus-frequency` divider (too low → probe fails; too high → the far end cannot keep up), and that the external device/shift-register chain is powered and clocked.

---

## Code Examples

### Example 1: Minimal AST2500 Enablement (Intel Vegman style)

A real-board pattern: an AST2500 reading CPU/PCH status, 80 hardware lines at 2 MHz, only input names populated.

```dts
&sgpio {
    status = "okay";
    ngpios = <80>;                /* -> 160 software GPIOs */
    bus-frequency = <2000000>;
    gpio-line-names =
        "CPU1_PRESENCE",       "",
        "CPU1_THERMTRIP",      "",
        "CPU1_VRHOT",          "",
        "CPU1_FIVR_FAULT",     "",
        "CPU1_MEM_ABCD_VRHOT", "",
        "CPU1_MEM_EFGH_VRHOT", "";
        /* ...pad to 160 names total... */
};
```

### Example 2: Minimal AST2600 Enablement

The shortest possible bring-up — enable, size, and clock master 0. Line names can be added later; `gpioinfo` will show 256 lines immediately.

```dts
&sgpiom0 {
    status = "okay";
    ngpios = <128>;               /* -> 256 software GPIOs */
    bus-frequency = <500000>;     /* 500 kHz, conservative for long runs */
};
```

### Example 3: Reading an SGPIO Input with libgpiod (C)

SGPIO needs no special libgpiod calls — this is the ordinary named-line read pattern. See the [Kernel Driver Development Guide]({% link docs/05-advanced/12-linux-kernel-driver-development-guide.md %}#libgpiod--gpio-access) for the full libgpiod walkthrough.

```c
#include <gpiod.h>
#include <stdio.h>

int main(void)
{
    /* Resolve the line by name across all chips — works regardless of
     * which gpiochip the SGPIO controller happens to be. */
    struct gpiod_line *line = gpiod_line_find("CPU1_THERMTRIP");
    if (!line) {
        fprintf(stderr, "CPU1_THERMTRIP not found (check gpio-line-names)\n");
        return 1;
    }

    if (gpiod_line_request_input(line, "sgpio-reader") < 0) {
        perror("request_input");
        return 1;
    }

    int value = gpiod_line_get_value(line);   /* even/input line: read-only */
    printf("CPU1_THERMTRIP = %d\n", value);

    gpiod_line_release(line);
    return 0;
}
```

### Example 4: phosphor-multi-gpio-monitor for Host Status

See the inline [monitoring example](#monitoring-with-phosphor-multi-gpio-monitor) above and the working configs in the [examples/sgpio/]({{ site.baseurl }}/examples/sgpio/) directory.

---

## Troubleshooting

### Issue: Controller Fails to Probe

**Symptom**: `dmesg | grep sgpio` shows an error and no `gpiochip` for the SGPIO controller.

**Cause**: Most often an invalid `ngpios` or an out-of-range `bus-frequency`.

**Solution**:
1. Confirm `ngpios` is a **multiple of 8**. The driver rejects anything else with "Number of GPIOs not multiple of 8".
2. Confirm `bus-frequency` is not so low that the divider overflows 16 bits (`apb / (2 × freq) − 1 > 0xFFFF` → `-EINVAL`). Raise it.
3. Confirm `clocks` points at the right APB source (`ASPEED_CLK_APB2` on AST2600, `ASPEED_CLK_APB` on AST2500).

### Issue: Lines Appear but Inputs Are Stuck

**Symptom**: `gpioinfo` lists the named SGPIO lines, but every input reads the same value and never changes.

**Cause**: The gpiochip registered, but the serial bus is not actually shifting valid data — pinmux not routed, far end unpowered, or clock mismatch.

**Solution**:
1. Verify the SGPM pinctrl group is selected so the clock/load/data balls leave the package:
   ```bash
   cat /sys/kernel/debug/pinctrl/*/pinmux-pins | grep -i sgpm
   ```
2. Confirm the external device or shift-register chain is powered and its clock expectations match your `bus-frequency`. Lower the clock for long cable runs.
3. Scope `SGPM1CLK` and `SGPM1LD` — no clock means no shifting.

### Issue: `gpioset` on an SGPIO Line Has No Effect

**Symptom**: `gpioset` returns success but the output never changes; or it errors on a name you expected to drive.

**Cause**: You targeted an **even** (input) line. Only **odd** offsets are outputs.

**Solution**: Drive the **odd** line — the output half of the hardware line. If you named the signal on the even index, the drivable line is the next offset (even `N` → output `N+1`). Confirm with:
```bash
gpioinfo gpiochip1 | sed -n '1,8p'   # even=input, odd=output
```

### Issue: Edge Events Missed or Delayed

**Symptom**: `gpiomon` / `phosphor-multi-gpio-monitor` reacts late or misses brief pulses on an SGPIO input.

**Cause**: SGPIO state refreshes only once per shift frame; sub-shift-period pulses can be missed, and edge timestamps are coarse.

**Solution**: Raise `bus-frequency` if signal integrity allows, or move genuinely fast/latency-critical signals to a parallel GPIO. SGPIO is best for level-ish status, not high-rate pulse trains.

### Debug Commands

```bash
# Is the driver built and the controller bound?
zcat /proc/config.gz | grep GPIO_ASPEED_SGPIO
ls /sys/bus/platform/drivers/aspeed-sgpio/
dmesg | grep -i sgpio

# Enumerate chips and lines
gpiodetect
gpioinfo $(gpiodetect | awk '/sgpio/{print $1}')

# Pinmux routing for the SGPM group
cat /sys/kernel/debug/pinctrl/*/pinmux-pins | grep -i sgpm

# Read / watch a named SGPIO line
gpioget  $(gpiofind "CPU1_PRESENCE")
gpiomon  $(gpiofind "CPU1_THERMTRIP")
```

---

## References

### Official Resources
- [Linux `gpio-aspeed-sgpio.c` driver](https://github.com/torvalds/linux/blob/master/drivers/gpio/gpio-aspeed-sgpio.c)
- [Device tree binding: `aspeed,sgpio.yaml`](https://www.kernel.org/doc/Documentation/devicetree/bindings/gpio/aspeed,sgpio.yaml)
- [Legacy binding text: `sgpio-aspeed.txt`](https://www.kernel.org/doc/Documentation/devicetree/bindings/gpio/sgpio-aspeed.txt)
- [ASPEED AST2600 dtsi (`sgpiom0`/`sgpiom1`)](https://github.com/torvalds/linux/blob/master/arch/arm/boot/dts/aspeed/aspeed-g6.dtsi)
- [ASPEED AST2500 dtsi (`sgpio`)](https://github.com/torvalds/linux/blob/master/arch/arm/boot/dts/aspeed/aspeed-g5.dtsi)
- [Nuvoton `gpio-npcm-sgpio.c` driver (mainline ≥ v6.8)](https://github.com/torvalds/linux/blob/master/drivers/gpio/gpio-npcm-sgpio.c)
- [Nuvoton device tree binding: `nuvoton,sgpio.yaml`](https://github.com/torvalds/linux/blob/master/Documentation/devicetree/bindings/gpio/nuvoton,sgpio.yaml)
- [OpenBMC `gpio-npcm-sgpio.c` (in-tree, `dev-6.6`)](https://github.com/openbmc/linux/blob/dev-6.6/drivers/gpio/gpio-npcm-sgpio.c)
- [meta-nuvoton `npcm8xx_defconfig` (enables `CONFIG_GPIO_NPCM_SGPIO`)](https://github.com/openbmc/openbmc/blob/master/meta-nuvoton/recipes-kernel/linux/linux-nuvoton/npcm8xx_defconfig)

### Real-Board Examples
- [Intel Vegman N110 (AST2500, host status SGPIO)](https://github.com/torvalds/linux/blob/master/arch/arm/boot/dts/aspeed/aspeed-bmc-vegman-n110.dts)
- [IBM System1 (AST2600, 128-line master)](https://github.com/torvalds/linux/blob/master/arch/arm/boot/dts/aspeed/aspeed-bmc-ibm-system1.dts)

### Related Guides
- [GPIO Management Guide]({% link docs/03-core-services/14-gpio-management-guide.md %}) — phosphor-multi-gpio-monitor, line-name discovery, the JSON config SGPIO reuses
- [Linux Kernel Driver Development]({% link docs/05-advanced/12-linux-kernel-driver-development-guide.md %}) — kernel config fragments, device tree patching, libgpiod
- [Buttons Guide]({% link docs/03-core-services/13-buttons-guide.md %}) — parallel-GPIO buttons and presence

### External Documentation
- [libgpiod Documentation](https://git.kernel.org/pub/scm/libs/libgpiod/libgpiod.git/about/)
- [Linux GPIO Subsystem](https://www.kernel.org/doc/html/latest/driver-api/gpio/index.html)

---

{: .note }
**Tested on**: Line discovery verified against the ASPEED and Nuvoton SGPIO drivers and bindings; SGPIO serial signaling requires physical hardware (host/PCH or shift registers) and is **not** emulated by the `ast2600-evb` QEMU target. Facts are drawn from upstream Linux — ASPEED: `gpio-aspeed-sgpio.c`, `aspeed,sgpio.yaml`, AST2500/AST2600 dtsi, Vegman/System1 board DTS; Nuvoton: `gpio-npcm-sgpio.c` (mainline ≥ v6.8, `openbmc/linux` ≥ `dev-6.6`), `nuvoton,sgpio.yaml`, and `npcm8xx_defconfig`.
Last updated: 2026-06-27
</content>
</invoke>
