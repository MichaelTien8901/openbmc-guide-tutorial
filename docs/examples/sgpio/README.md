# SGPIO Examples

Reference device tree fragments, a `phosphor-multi-gpio-monitor` configuration, and a
libgpiod reader for the ASPEED (and Nuvoton NPCM) serial GPIO controllers.

See the [SGPIO (Serial GPIO) guide](../../05-advanced/22-sgpio-guide.md) for the
full walkthrough.

> **Requires an OpenBMC environment + real hardware** -- the SGPIO controller registers
> a gpiochip under Linux, but meaningful input values require the physical serial link to
> the host/PCH or external shift registers. The `ast2600-evb` QEMU target does not emulate
> the SGPIO serial bus.

## Files

| File | Target | Description |
|------|--------|-------------|
| `sgpiom0-ast2600.dtsi` | AST2600 | Enables `&sgpiom0` (master 0), 128 hardware lines, with host/CPU status line names |
| `sgpio-ast2500.dtsi` | AST2500 | Enables `&sgpio`, 80 hardware lines (Intel Vegman style) |
| `sgpio-npcm.dtsi` | Nuvoton NPCM7xx/NPCM8xx | Authors an `sgpio` node (SIOX hardware) — separate input/output GPIO counts, outputs-first layout |
| `sgpio-host-status.json` | any | `phosphor-multi-gpio-monitor` config monitoring SGPIO host-status inputs |
| `read-sgpio.c` | any | Minimal libgpiod reader for a named SGPIO input line |

## The `ngpios` doubling rule (ASPEED)

ASPEED declares the number of **hardware** SGPIO lines via `ngpios`, and the driver
exposes **two** software GPIO lines per hardware line:

- **even** offset = input half (read host/PCH/CPU status)
- **odd** offset = output half (drive an LED/strobe)

So `ngpios = <80>` -> 160 software GPIOs and `ngpios = <128>` -> 256. `ngpios` must be a
**multiple of 8**. Populate input names on even indices, output names (or `""`) on odd.

Nuvoton NPCM is different: it uses **separate** `nuvoton,input-ngpios` and
`nuvoton,output-ngpios` properties, and the underlying hardware is the **SIOX**
(Serial I/O eXpansion) block — half-duplex, ~half the throughput of true SGPIO at
a given clock. See `sgpio-npcm.dtsi`.

## Usage

```bash
# Discover the SGPIO gpiochip and its named lines
gpiodetect
gpioinfo $(gpiodetect | awk '/sgpio/{print $1}') | grep -v unnamed

# Read a host-status input by name
gpioget $(gpiofind "CPU1_THERMTRIP")

# Build and run the libgpiod reader
gcc read-sgpio.c -lgpiod -o read-sgpio && ./read-sgpio
```
</content>
