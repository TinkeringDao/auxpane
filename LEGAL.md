# Legal, Trademark, & Interoperability Notice

## 1. Independent Interoperability Project & Non-Affiliation (Trademark Notice)

**`auxpane` — Unofficial macOS Synaptics `VMM5322` ViewXpand DisplayPort AUX Controller & Bezel-Aware Dual-Monitor Window Manager for Lenovo ThinkPad Thunderbolt 3 Dock Gen 2 (`40AN`)** is an **independent, non-commercial, community-developed free and open-source software project** created solely to enable desktop host interoperability and dual-monitor display configuration on macOS (where native DisplayPort Multi-Stream Transport is not provided by the operating system).

- **No Affiliation or Endorsement:** This project is **not affiliated with, authorized by, sponsored by, or endorsed by Lenovo Group Limited, Synaptics Incorporated, Dell Inc., Intel Corporation, or Apple Inc.**
- **Indication of Intended Purpose & Nominative Fair Use:**
  - Pursuant to **Article 14(1)(c) of Regulation (EU) 2017/1001 (EU Trade Mark Regulation — EUTMR)**, settled Court of Justice of the European Union jurisprudence (*Case C-228/03 — Gillette v. LA-Laboratories*; *Case C-63/97 — BMW v. Deenik*), and **US Nominative Fair Use (`15 U.S.C. §§ 1115(b)(4), 1125`**, *New Kids on the Block v. News America Publishing, Inc.*, 971 F.2d 302 (9th Cir. 1992)), third-party trademarks are referenced strictly as a necessary indication of intended purpose, nominative fair use, and hardware compatibility of this independent utility:
    - "Lenovo" and "ThinkPad" are registered trademarks or trademarks of **Lenovo Group Limited**.
    - "Synaptics" and "ViewXpand" are registered trademarks or trademarks of **Synaptics Incorporated**.
    - "Dell" is a registered trademark of **Dell Inc.**
    - "Thunderbolt" and "Intel" are registered trademarks of **Intel Corporation**.
    - "macOS", "Mac", "Apple", and "CoreGraphics" are registered trademarks of **Apple Inc.**
  - Zero corporate logos, icons, proprietary OEM application screenshots, or proprietary trade dress are included in this repository.

---

## 2. Statutory Interoperability, Uncopyrightable Functional Facts, & Trade Secret Law

All source code and protocol documentation in this repository were developed independently via clean-room observation of standard DisplayPort AUX / DPCD register communication with lawfully acquired hardware owned by the user, building upon publicly documented open-source protocols (`fwupd` `synaptics-mst` plugin and `kksimp/wd19-split`):

### 2.1 European Union (`Directive 2009/24/EC` & `Directive (EU) 2016/943`)
1. **Exclusion of Functional Protocols & Interfaces from Copyright (`Article 1(2) of Directive 2009/24/EC`):**
   - Under `Article 1(2) of Directive 2009/24/EC` and settled Court of Justice of the European Union precedent (*SAS Institute Inc. v. World Programming Ltd*, Case `C-406/10`, paras. 39–46), ideas, principles, functional interfaces, data formats, and hardware register layouts (`DPCD 0x4B0..0x4FF`, volatile SRAM `0x1740`, and EDID descriptors at `0x1600`) are **excluded from copyright protection**.
2. **Right to Observe, Study, and Test (`Article 5(3) of Directive 2009/24/EC`):**
   - Permits the lawful owner or user of a device or computer program to observe, study, and test its functioning without prior authorization in order to determine the underlying ideas, principles, and register transitions during normal use.
3. **Mandatory Right of Interoperability (`Article 6 of Directive 2009/24/EC`):**
   - Permits independent analysis necessary to achieve the **interoperability** of an independently created computer program (`auxpane` for macOS) with existing hardware and software where interface specifications were not previously published.
4. **Statutory Nullity of Contrary EULA Provisions (`Article 8 of Directive 2009/24/EC`):**
   - Under mandatory European Union law (`Article 8 of Directive 2009/24/EC`), any contractual or End-User License Agreement (EULA) clauses purporting to waive or restrict rights under `Article 5(3)` or `Article 6 of Directive 2009/24/EC` are **statutorily null and void**.
5. **Lawful Hardware Reverse Engineering (`Article 3(1)(b) of Directive (EU) 2016/943`):**
   - Under **Article 3(1)(b) of Directive (EU) 2016/943**, obtaining technical information by observing, studying, disassembling, or testing a product that has been made available to the public or that is lawfully in the possession of the acquirer of the information (who is free from any legally valid duty to limit the acquisition of the trade secret) is expressly declared a **lawful acquisition**.

### 2.2 United States (`17 U.S.C. §§ 102(b), 107, 1201(f)` & `18 U.S.C. §§ 1839(6)(B), 1030`)
1. **Uncopyrightable Methods of Operation & Merger (`17 U.S.C. § 102(b)`):**
   - Numeric DPCD register addresses (`0x4B0..0x4FF`, `0x500..0x50F`), SRAM offsets (`0x1600`, `0x1700`, `0x1740`, `0x1820`), and VESA EDID Detailed Timing Descriptors constitute uncopyrightable systems, methods of operation, and functional facts necessary for compatibility (*Baker v. Selden*, 101 U.S. 99 (1879); *Google LLC v. Oracle America, Inc.*, 593 U.S. 1 (2021); *Lexmark Int'l, Inc. v. Static Control Components, Inc.*, 387 F.3d 522 (6th Cir. 2004)).
2. **Interoperability Exemptions (`17 U.S.C. § 1201(f)`, `17 U.S.C. § 107`, & `37 C.F.R. § 201.40`):**
   - Developed exclusively for achieving interoperability of an independently created computer program with lawfully owned consumer hardware (*Sega Enterprises Ltd. v. Accolade, Inc.*, 977 F.2d 1510 (9th Cir. 1992); *Sony Computer Entertainment, Inc. v. Connectix Corp.*, 203 F.3d 596 (9th Cir. 2000); *The Chamberlain Group, Inc. v. Skylink Technologies, Inc.*, 381 F.3d 1178 (Fed. Cir. 2004)).
3. **Defend Trade Secrets Act Reverse-Engineering Safe Harbor (`18 U.S.C. § 1839(6)(B)`):**
   - Under the Defend Trade Secrets Act (`18 U.S.C. § 1839(6)(B)`), reverse engineering, independent derivation, and clean-room observation of a lawfully acquired product on the open market are explicitly excluded from the definition of "improper means".
4. **Authorized Local Owner Execution (`18 U.S.C. § 1030` — CFAA):**
   - Under *Van Buren v. United States*, 593 U.S. 374 (2021), this utility executes 100% locally on the hardware owner's computer and communicates over a physical Thunderbolt / DisplayPort cable with the owner's own peripheral. Zero manufacturer cloud servers, remote APIs, or restricted network endpoints are accessed.

---

## 3. Non-Circumvention of Technological Protection Measures (`Directive 2009/24/EC` & `17 U.S.C. §§ 1201(a), 1201(f)`)

Under **Directive 2009/24/EC (Articles 1(2), 5(3), 6, 8)** and **17 U.S.C. §§ 1201(a), 1201(f)**, this software **does not circumvent, bypass, decrypt, or defeat any Technological Protection Measure (TPM)** or Digital Rights Management (DRM) system:

- **Zero SPI Flash Modification or Firmware Patching:** This project **never modifies, erases, patches, or flashes** the dock's SPI flash memory. All mode changes (`0x1740 = 0x02` for ViewXpand or `0x1740 = 0x03` for pass-through) are written strictly to volatile SRAM and revert automatically whenever the dock's power is cycled.
- **Zero HDCP / Content Protection Circumvention:** This project never accesses, modifies, or interacts with HDCP keys, ESM registers, or content-protection state machines. In the optional `Two displays` (`ScreenCaptureKit`) layout, macOS content protection is fully respected (DRM-protected video streams render black by macOS design).

---

## 4. Zero Proprietary Code, Verbatim Firmware Bytes, or Binary Distribution

- **100% Open-Source Code:** Every line of C ([`Sources/DockCore/`](Sources/DockCore), [`Sources/dockctl/`](Sources/dockctl)), Objective-C ([`Sources/VirtualDisplay/`](Sources/VirtualDisplay)), Swift ([`Sources/StretchTheMac/`](Sources/StretchTheMac)), Python ([`lenovo_40an_vmm5322_split.py`](lenovo_40an_vmm5322_split.py)), and Shell ([`build.sh`](build.sh), [`build_app.sh`](build_app.sh)) in this repository is licensed under the [MIT License](LICENSE).
- **No OEM Binaries, Firmware Dumps, or Assets:** This repository does **not** host, redistribute, or link to any proprietary firmware images (`.bin`, `.dfu`, `.exe`), decompiled vendor source code, or verbatim firmware hex slices (`<REDACTED_OEM_BYTES>`).

---

## 5. Authorized Local Owner Execution Only (`18 U.S.C. § 1030` — CFAA)

In accordance with the **Computer Fraud and Abuse Act (`18 U.S.C. § 1030` — CFAA)** (*Van Buren v. United States*, 593 U.S. 374 (2021)):

- **No Access-Security Circumvention:** This software operates exclusively on DisplayPort / Thunderbolt docks physically connected to the local host computer by the hardware owner via standard macOS `IOKit` (`DCPDPDeviceProxy`) and `CoreGraphics` APIs.
- **Authorized Local Owner Execution Only:** All volatile SRAM commands sent by this utility modify only the runtime display aggregation state (`0x1740`) of hardware owned or lawfully controlled by the operator.

---

## 6. Non-Commercial Open-Source Software Notice (EU CRA `Regulation (EU) 2024/2847` & EU PLD `Directive (EU) 2024/2853` Exemption)

- **EU Cyber Resilience Act Exemption (`Regulation (EU) 2024/2847`, Recitals 15 & 18; `Art. 2(5)`):** This repository is developed, maintained, and supplied strictly as **non-commercial free and open-source software outside the course of any commercial activity**. No fee is charged, no paid support or commercial services are offered, and no personal data is collected or monetized. Accordingly, the authors are neither "manufacturers" (`Art. 3(13)`) nor "open-source software stewards" (`Art. 3(14)`), and CE-marking (`Art. 28`) and commercial manufacturer obligations under Regulation (EU) 2024/2847 do not apply.
- **EU Product Liability Directive Exemption (`Directive (EU) 2024/2853`, `Art. 2(2)` & Recitals 14, 15, 24):** Pursuant to **Article 2(2)** and **Recitals 14–15 of Directive (EU) 2024/2853**, this Directive does not apply to free and open-source software developed or supplied outside the course of a commercial activity. Any third party who integrates, bundles, or redistributes this software in the course of a commercial activity does so solely under their own legal and regulatory responsibility as a manufacturer.

---

## 7. Electromagnetic Compatibility & Hardware Safety Compliance

This software operates exclusively over standard VESA DisplayPort AUX (`DPCD`) data channels and leaves all electrical, power-delivery (`USB-PD`), and clock/PHY signal-integrity parameters unmodified.

---

## 8. AS IS Warranty Disclaimer & Hardware Risk Notice

THE SOFTWARE AND DOCUMENTATION ARE PROVIDED **"AS IS"**, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE, AND NONINFRINGEMENT (SEE [`LICENSE`](LICENSE)).

- **Owner's Sole Risk:** Communicating with hardware registers over DisplayPort AUX (`DPCD`) is performed entirely at the user's own risk. While all mode changes in volatile SRAM (`0x1740`) are reversible via `python3 lenovo_40an_vmm5322_split.py mirror`, `./dist/dockctl mst-poke 0x1740 3`, or power-cycling the dock, the authors assume no liability for hardware malfunction, unexpected display behavior, or warranty disputes.

---

## Addendum: German Statutory References (Applicable to Residents of Germany)

Where German national law applies alongside European Union regulations and directives, the following national statutory provisions govern this repository:

- **Trademark Indication of Intended Purpose (`§ 23 Abs. 1 Nr. 3 MarkenG` — *Bestimmungsangabe*):** Section 23(1) No. 3 of the German Trademark Act (*Markengesetz*, implementing `Art. 14(1)(c) EUTMR`; BGH `I ZR 6/10`) permits the use of third-party trademarks and product designations where necessary to indicate the intended purpose of accessories or interoperable software, provided such use accords with honest practices in industrial or commercial matters.
- **Software Interoperability & Uncopyrightable Interfaces (`§§ 69a Abs. 2 & 5, 69d Abs. 3, 69e, 69f Abs. 2, 69g Abs. 2, 95a UrhG`):** Under the German Copyright Act (*Urheberrechtsgesetz*, implementing `Directive 2009/24/EC`):
  - `§ 69a Abs. 2 Satz 2 UrhG` excludes ideas, principles, and functional interfaces underlying a computer program from copyright protection.
  - `§ 69d Abs. 3 UrhG` entitles the lawful user to observe, study, or test the functioning of a program to determine its underlying ideas and principles.
  - `§ 69e UrhG` authorizes independent analysis necessary to achieve the interoperability of an independently created computer program.
  - `§ 69g Abs. 2 UrhG` renders any contractual or EULA clauses contrary to `§ 69d Abs. 2, 3` or `§ 69e UrhG` statutorily null and void (*nichtig*).
  - `§ 69a Abs. 5 UrhG` (*lex specialis*) excludes computer programs from general technological protection measure rules (`§ 95a UrhG`), and this project circumvents zero technical protection mechanisms (`§ 69f Abs. 2 UrhG`).
- **Reverse Engineering of Lawfully Acquired Hardware (`§ 3 Abs. 1 Nr. 2 lit. a & b GeschGehG`):** Section 3(1) No. 2 of the German Trade Secrets Act (*Geschäftsgeheimnisgesetz*, implementing `Article 3(1)(b) of Directive (EU) 2016/943`) expressly authorizes obtaining technical information by observing, examining, disassembling, or testing a product that has been made publicly available (`lit. a`) or is in the lawful possession of the observer (`lit. b`).
- **German IT Criminal Law & Property Ownership (`§§ 202a–202c, 303a StGB`, `§ 903 BGB`):** Under the German Criminal Code (*Strafgesetzbuch*, as interpreted by the Federal Constitutional Court, *BVerfG, 2 BvR 2233/07*) and Section 903 of the German Civil Code (*Bürgerliches Gesetzbuch*):
  - No access security mechanism (*Zugangssicherung*) is bypassed (`§§ 202a, 202c StGB`) and no non-public transmission is intercepted (`§ 202b StGB`).
  - All configuration operations modify exclusively the physical owner's (`§ 903 BGB`) own local device volatile SRAM state (*eigene Daten*, `§ 303a StGB`).
- **Gratuitous Open-Source Liability Standard (`§§ 521, 523, 524, 599, 600 BGB`):** Because this free and open-source software and documentation are provided gratuitously (*unentgeltlich*) outside the course of commercial activity, statutory liability under the German Civil Code (`§§ 521, 523, 524, 599, 600 BGB`) is limited strictly to intent (*Vorsatz*) and gross negligence (*grobe Fahrlässigkeit*).
