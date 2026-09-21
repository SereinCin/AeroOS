> **[中文版本 →](zh-CN/VERSIONING.md)**

# Versioning — AeroOS Naming Convention v1.1

Team-internal specification. Applied to all release names, file names, URL paths, package identifiers, and patch numbering.

---

## Core principles

- **Two parallel lineages, not sequential.** The **26-line** (birth / stable) and **27+ line** (evolution / generation) run side-by-side. `AeroOS 26R10` and `AeroOS 27H1` are not comparable by any simple "which is newer" rule.
- 26-line has **no PRO** variant. 27+ line **has PRO**.
- T-patches apply only to **OS-level code changes** (bug fixes, feature updates, kernel behavior). Hardware-related work is **not** a T-patch — it is EVT (Engineering Verification Test).
- Birth year = release line anchor. 26 = 2026, 27 = 2027, etc.

## 26-line — Birth / stable

```
AeroOS 26R1
│      │  │
│      │  └── R1 = 1st Release of the 26-line
│      └───── 26 = birth year 2026 (fixed, never changes)
└──────────── AeroOS = system name
```

Support suffixes (add to the above):

```
AeroOS 26R1 LTS    5-year long-term support
AeroOS 26R1 STS    2-year short-term support
```

Serial rule: `R1 → R2 → R3 → ...` Long-term serial, no reset.

## 27+ line — Evolution / generation

```
AeroOS 27H1
│      │  │
│      │  └── H1 = first half of 2027 (H2 = second half)
│      └───── 27 = generation year 2027
└──────────── AeroOS = system name
```

PRO suffix:
```
AeroOS 27H1 PRO     2027 H1 professional edition
AeroOS 27H2 PRO     2027 H2 professional edition
```

H1/H2 per-generation cadence — still TBD whether 28+ continues this.

## Complete naming inventory

```
26-line (birth / stable):
  AeroOS 26R1              ← current Release
  AeroOS 26R2
  AeroOS 26R3
  AeroOS 26R1 LTS          (5 years)
  AeroOS 26R1 STS          (2 years)
  T-26R1 00000             ← T-patch

27-line (evolution / generation):
  AeroOS 27H1
  AeroOS 27H2
  AeroOS 27H1 PRO
  AeroOS 27H2 PRO
  T-27H1 00000

28+ line:
  AeroOS 28H1 / H2 / PRO
  (whether H1/H2 continues after 27 is TBD)
```

## Display name vs technical name vs file name

| Type | Rule | Example |
|---|---|---|
| Display name | Allows spaces, mixed case, readable | `AeroOS 26R1 LTS` |
| Technical name | All lowercase + hyphens | `aeroos-26r1-lts` |
| File name | Technical name + suffix | `aeroos-26r1-riscv64-qemu.zip` |
| URL path | Technical name | `https://aeroos.dev/releases/aeroos-26r1/` |

**Hard rule**: technical names drive file names and URLs. Display names are for READMEs, docs, and end-user-facing UI only.

## T-patch specification

### What qualifies as a T-patch

A T-patch applies **only** to OS-level changes:
- Code bug fixes (kernel panic, scheduler deadlock, syscall ABI break, etc.)
- Feature additions to the OS itself (new syscalls, new scheduler policies, PMP support, etc.)
- Kernel behavior changes

### What does NOT qualify

- **Hardware bring-up** (new board support, SD card boot, EVT prototype testing) → this is EVT, not T-patch
- **User program updates** (new demo app, better README example)
- **Build system refactors** (unless they change the resulting kernel binary)
- **Documentation-only changes**

### Numbering

```
Display: T-26R1 00000
Tech   : T-26R1-00000
File   : aeroos-26r1-patch-T-26R1-00000.zip
```

| Part | Meaning |
|---|---|
| T | Patch marker |
| 26 / 27 | Year (last two digits) |
| R1 / H1 | Release segment |
| 00000 | 5-digit serial, starts at 00000 |

27-line:
```
Display: T-27H1 00000
Tech   : T-27H1-00000
File   : aeroos-27h1-patch-T-27H1-00000.zip
```

## 26R1 alignment check

| Item | Actual value | Aligned? |
|---|---|---|
| Display name | `AeroOS 26R1` | ✅ |
| Technical name | `aeroos-26r1` | ✅ (zip, directory, URL) |
| Kernel image | `AeroOS-26R1-riscv64.elf` / `.bin` | ✅ |
| Aero.toml version | `"26R1"` | ✅ |
| LTS / STS suffix | Not applied | OK — optional suffix |
| T-patch | Not yet published | Wait for first OS-level fix |
| EVT status | Real hardware = DEFERRED | ✅ Correctly not labeled as T-patch |

---

> Versioning spec v1.1 · Team-internal finalization · Applied to all AeroOS 26R series and 27+ series releases, patches, package names, and URLs
