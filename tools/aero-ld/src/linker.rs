//! Core linker logic: flattening, GC, layout, symbol resolution, reloc application.

use crate::elf::{InputObj, OutputPhdr, OutputSection, build_output_elf};
use crate::ldscript::{BodyElem, DotExpr, LdScript};
use std::collections::{HashMap, VecDeque};

const SHF_WRITE: u64 = 0x1;
const SHF_ALLOC: u64 = 0x2;
const SHF_EXECINSTR: u64 = 0x4;
const SHT_NOBITS: u32 = 8;

#[derive(Clone)]
struct IReloc {
    offset: u64,
    rtype: u32,
    sym: usize,
    addend: i64,
}

struct ISec {
    name: String,
    flags: u64,
    data: Vec<u8>,
    size: u64,
    align: u64,
    relocs: Vec<IReloc>,
    alive: bool,
    placed: bool,
    out_index: usize,
    out_off: u64,
    vma: u64,
}

struct ISym {
    name: String,
    sec: Option<usize>,
    value: u64,
    size: u64,
    info: u8,
    addr: u64,
    defined: bool,
    /// For synthetic script-assignment symbols: explicit 1-based output section index.
    synth_sec: Option<u16>,
}

struct OSec {
    name: String,
    sh_type: u32,
    flags: u64,
    align: u64,
    vma: u64,
    size: u64,
    noload: bool,
    data: Vec<u8>,
}

fn align_up(v: u64, a: u64) -> u64 {
    let a = a.max(1);
    (v + a - 1) & !(a - 1)
}

fn glob_match(name: &str, pat: &str) -> bool {
    let n = name.as_bytes();
    let p = pat.as_bytes();
    let (mut ni, mut pi) = (0usize, 0usize);
    let mut star_p: Option<usize> = None;
    let mut star_n: Option<usize> = None;
    while ni < n.len() {
        if pi < p.len() && p[pi] == b'*' {
            star_p = Some(pi);
            star_n = Some(ni);
            pi += 1;
        } else if pi < p.len() && (p[pi] == b'?' || p[pi] == n[ni]) {
            ni += 1;
            pi += 1;
        } else if let (Some(sp), Some(sn)) = (star_p, star_n) {
            pi = sp + 1;
            star_n = Some(sn + 1);
            ni = sn + 1;
        } else {
            return false;
        }
    }
    while pi < p.len() && p[pi] == b'*' {
        pi += 1;
    }
    pi == p.len()
}

fn resolve(syms: &[ISym], name_to_def: &HashMap<String, usize>, i: usize) -> Option<usize> {
    if syms[i].defined {
        return Some(i);
    }
    name_to_def.get(&syms[i].name).copied()
}

pub fn link(objects: Vec<InputObj>, script: &LdScript) -> Result<Vec<u8>, String> {
    // ---- Step 1: flatten sections / symbols / relocs ----------------------
    let mut secs: Vec<ISec> = Vec::new();
    let mut syms: Vec<ISym> = Vec::new();
    let mut sec_map: HashMap<(usize, usize), usize> = HashMap::new();
    let mut sym_map: HashMap<(usize, usize), usize> = HashMap::new();

    for (oi, obj) in objects.iter().enumerate() {
        for (si, s) in obj.sections.iter().enumerate() {
            let gi = secs.len();
            sec_map.insert((oi, si), gi);
            secs.push(ISec {
                name: s.name.clone(),
                flags: s.flags,
                data: s.data.clone(),
                size: s.size,
                align: s.align.max(1),
                relocs: Vec::new(),
                alive: false,
                placed: false,
                out_index: usize::MAX,
                out_off: 0,
                vma: 0,
            });
        }
    }
    for (oi, obj) in objects.iter().enumerate() {
        for (si, s) in obj.symbols.iter().enumerate() {
            let gi = syms.len();
            sym_map.insert((oi, si), gi);
            let sec = s
                .section_idx
                .and_then(|li| sec_map.get(&(oi, li)).copied());
            syms.push(ISym {
                name: s.name.clone(),
                sec,
                value: s.st_value,
                size: s.st_size,
                info: s.st_info,
                addr: 0,
                defined: s.st_shndx != 0, // SHN_UNDEF
                synth_sec: None,
            });
        }
    }
    for (oi, obj) in objects.iter().enumerate() {
        for r in &obj.relocs {
            if let Some(&gi) = sec_map.get(&(oi, r.section_shndx)) {
                let sym = sym_map.get(&(oi, r.sym_idx)).copied().unwrap_or(0);
                secs[gi].relocs.push(IReloc {
                    offset: r.offset,
                    rtype: r.rtype,
                    sym,
                    addend: r.addend,
                });
            }
        }
    }

    // Name -> defined global symbol (for cross-object resolution).
    let mut name_to_def: HashMap<String, usize> = HashMap::new();
    for (i, s) in syms.iter().enumerate() {
        if s.defined && !s.name.is_empty() && (s.info & 0xF0) >= 0x10 {
            name_to_def.entry(s.name.clone()).or_insert(i);
        }
    }

    // ---- Step 2: garbage collection from ENTRY ----------------------------
    let entry_sym = syms
        .iter()
        .enumerate()
        .find(|(_, s)| s.name == script.entry && s.defined)
        .map(|(i, _)| i)
        .ok_or_else(|| format!("entry symbol '{}' not found", script.entry))?;
    let entry_sec = syms[entry_sym]
        .sec
        .ok_or_else(|| format!("entry symbol '{}' has no section", script.entry))?;

    let mut alive = vec![false; secs.len()];
    let mut queue: VecDeque<usize> = VecDeque::new();
    alive[entry_sec] = true;
    queue.push_back(entry_sec);
    while let Some(gi) = queue.pop_front() {
        for r in &secs[gi].relocs {
            if r.rtype == 51 || r.sym == 0 {
                continue;
            }
            let Some(tgt) = resolve(&syms, &name_to_def, r.sym) else {
                continue;
            };
            if let Some(ts) = syms[tgt].sec {
                if !alive[ts] {
                    alive[ts] = true;
                    queue.push_back(ts);
                }
            }
        }
    }
    for (i, a) in alive.iter().enumerate() {
        secs[i].alive = *a;
    }

    let mut warnings: Vec<String> = Vec::new();

    // ---- Step 3: layout ---------------------------------------------------
    // /DISCARD/ first: mark matching input sections as placed but not emitted.
    for ld in &script.sections {
        if ld.name == "/DISCARD/" {
            for e in &ld.body {
                if let BodyElem::Wildcard(pat) = e {
                    for s in secs.iter_mut() {
                        if !s.placed && glob_match(&s.name, pat) {
                            s.placed = true;
                        }
                    }
                }
            }
        }
    }

    let mut out_sections: Vec<OSec> = Vec::new();
    let mut synth: Vec<(String, u64, u16)> = Vec::new();
    let mut dot: u64 = script.initial_dot.unwrap_or(0);

    for ld in &script.sections {
        if ld.name == "/DISCARD/" {
            continue;
        }

        // Which input sections match this output section (in body/wildcard order)?
        let mut matched: Vec<usize> = Vec::new();
        for e in &ld.body {
            if let BodyElem::Wildcard(pat) = e {
                for (gi, s) in secs.iter().enumerate() {
                    if s.alive && !s.placed && glob_match(&s.name, pat) && !matched.contains(&gi) {
                        matched.push(gi);
                    }
                }
            }
        }

        let keep_empty = ld.noload || ld.name == ".bss" || ld.name == ".stack";
        if matched.is_empty() && !keep_empty {
            continue;
        }

        let mut align = 1u64;
        for &gi in &matched {
            align = align.max(secs[gi].align);
        }
        dot = align_up(dot, align);
        let sec_vma = dot;
        let out_idx = out_sections.len();

        let mut cur = sec_vma;
        let mut odata: Vec<u8> = Vec::new();
        let mut oflags: u64 = 0;

        for e in &ld.body {
            match e {
                BodyElem::Wildcard(pat) => {
                    for gi in 0..secs.len() {
                        if !(secs[gi].alive && !secs[gi].placed && glob_match(&secs[gi].name, pat)) {
                            continue;
                        }
                        let a = secs[gi].align.max(1);
                        let at = align_up(cur, a);
                        // pad the output data up to this section's offset
                        let want = (at - sec_vma) as usize;
                        if !ld.noload && odata.len() < want {
                            odata.resize(want, 0);
                        }
                        let s = &mut secs[gi];
                        s.out_index = out_idx;
                        s.out_off = at - sec_vma;
                        s.vma = at;
                        s.placed = true;
                        oflags |= s.flags;
                        if !ld.noload {
                            odata.extend_from_slice(&s.data);
                        }
                        cur = at + s.size;
                    }
                }
                BodyElem::Assign(name, expr) => {
                    let val = match expr {
                        DotExpr::Dot => cur,
                        DotExpr::Align(n) => {
                            cur = align_up(cur, *n);
                            cur
                        }
                        DotExpr::Value(v) => *v,
                    };
                    if name != "." {
                        synth.push((name.clone(), val, (out_idx + 1) as u16));
                    }
                }
            }
        }

        let sec_size = cur - sec_vma;
        if oflags == 0 {
            oflags = if ld.noload {
                SHF_ALLOC | SHF_WRITE
            } else {
                SHF_ALLOC
            };
        }
        out_sections.push(OSec {
            name: ld.name.clone(),
            sh_type: if ld.noload { SHT_NOBITS } else { 1 },
            flags: oflags,
            align,
            vma: sec_vma,
            size: sec_size,
            noload: ld.noload,
            data: if ld.noload { Vec::new() } else { odata },
        });
        dot = sec_vma + sec_size;
    }

    // Fallback: alive, alloc, still-unplaced sections must not be silently dropped.
    for gi in 0..secs.len() {
        if !(secs[gi].alive && !secs[gi].placed && (secs[gi].flags & SHF_ALLOC != 0)) {
            continue;
        }
        let target = if secs[gi].flags & SHF_EXECINSTR != 0 {
            ".text"
        } else if secs[gi].flags & SHF_WRITE != 0 {
            ".data"
        } else {
            ".rodata"
        };
        warnings.push(format!(
            "section '{}' not matched by script; appended to {}",
            secs[gi].name, target
        ));
        let Some(oi) = out_sections.iter().position(|o| o.name == target) else {
            warnings.push(format!("  (output section {} absent; dropping)", target));
            continue;
        };
        let base = out_sections[oi].vma;
        let a = secs[gi].align.max(1);
        let at = align_up(base + out_sections[oi].size, a);
        let want = (at - base) as usize;
        if out_sections[oi].data.len() < want {
            out_sections[oi].data.resize(want, 0);
        }
        let s = &mut secs[gi];
        s.out_index = oi;
        s.out_off = at - base;
        s.vma = at;
        s.placed = true;
        let extra = s.data.clone();
        out_sections[oi].data.extend_from_slice(&extra);
        out_sections[oi].size = at - base + s.size;
    }

    // Merged `.riscv.attributes` (non-alloc) — pick the largest input blob.
    if let Some(gi) = secs
        .iter()
        .enumerate()
        .filter(|(_, s)| s.name == ".riscv.attributes")
        .max_by_key(|(_, s)| s.size)
        .map(|(i, _)| i)
    {
        out_sections.push(OSec {
            name: ".riscv.attributes".into(),
            sh_type: 0x7000_0003,
            flags: 0,
            align: 1,
            vma: 0,
            size: secs[gi].size,
            noload: false,
            data: secs[gi].data.clone(),
        });
    }

    // ---- Step 4: resolve symbol addresses ---------------------------------
    for s in syms.iter_mut() {
        if let Some(gi) = s.sec {
            if secs[gi].alive && secs[gi].placed {
                s.addr = secs[gi].vma + s.value;
            } else {
                s.defined = false; // lives in a discarded / dropped section
            }
        } else if s.defined {
            // SHN_ABS and friends
            s.addr = s.value;
        }
    }
    // Inject synthetic dot-assignment symbols.
    for (name, addr, shndx) in &synth {
        let idx = syms.len();
        syms.push(ISym {
            name: name.clone(),
            sec: None,
            value: *addr,
            size: 0,
            info: 0x10, // STB_GLOBAL | STT_NOTYPE
            addr: *addr,
            defined: true,
            synth_sec: Some(*shndx),
        });
        name_to_def.entry(name.clone()).or_insert(idx);
    }

    // ---- Step 5: relocations ---------------------------------------------
    // First pass: PCREL_HI20 delta map keyed by resolved auipc address P.
    let mut auipc_delta: HashMap<u64, i64> = HashMap::new();
    for gi in 0..secs.len() {
        if !secs[gi].placed {
            continue;
        }
        for r in &secs[gi].relocs {
            if r.rtype != 23 || r.sym == 0 {
                continue;
            }
            let Some(tgt) = resolve(&syms, &name_to_def, r.sym) else {
                continue;
            };
            if !syms[tgt].defined {
                continue;
            }
            let p = (secs[gi].vma + r.offset) as i64;
            let v = syms[tgt].addr as i64 + r.addend;
            auipc_delta.insert(p as u64, v - p);
        }
    }

    let mut undefined_count = 0usize;
    for gi in 0..secs.len() {
        if !secs[gi].placed {
            continue;
        }
        let out_index = secs[gi].out_index;
        let out_off = secs[gi].out_off;
        let sec_vma = secs[gi].vma;
        let sec_name = secs[gi].name.clone();
        let relocs = secs[gi].relocs.clone();
        for r in &relocs {
            if r.rtype == 51 || r.rtype == 43 || r.sym == 0 {
                continue;
            }
            let Some(tgt) = resolve(&syms, &name_to_def, r.sym) else {
                warnings.push(format!(
                    "undefined sym '{}' referenced in '{}'",
                    "<unknown>", sec_name
                ));
                undefined_count += 1;
                continue;
            };
            if !syms[tgt].defined {
                warnings.push(format!(
                    "undefined sym '{}' referenced in '{}'",
                    syms[tgt].name, sec_name
                ));
                undefined_count += 1;
                continue;
            }
            let v = syms[tgt].addr as i64 + r.addend;
            let p = (sec_vma + r.offset) as i64;
            let pos = (out_off + r.offset) as usize;
            let sym_addr = syms[tgt].addr;
            let buf = &mut out_sections[out_index].data;
            apply_reloc(r.rtype, buf, pos, v, p, sym_addr, &auipc_delta);
        }
    }
    if undefined_count > 0 {
        warnings.push(format!("{undefined_count} undefined-symbol relocations skipped"));
    }

    // ---- Step 6: build output ---------------------------------------------
    let entry_addr = syms
        .iter()
        .find(|s| s.name == script.entry && s.defined)
        .map(|s| s.addr)
        .unwrap_or(0);

    let out_secs: Vec<OutputSection> = out_sections
        .iter()
        .map(|o| OutputSection {
            name: o.name.clone(),
            sh_type: o.sh_type,
            vma: o.vma,
            size: if o.noload { o.size } else { o.data.len() as u64 },
            align: o.align,
            flags: o.flags,
            data: o.data.clone(),
        })
        .collect();

    let mut phdrs: Vec<OutputPhdr> = Vec::new();
    {
        let mut i = 0usize;
        while i < out_secs.len() {
            if out_secs[i].flags & SHF_ALLOC == 0 {
                i += 1;
                continue;
            }
            let pf = pf_flags(out_secs[i].flags);
            let start = i;
            while i < out_secs.len()
                && out_secs[i].flags & SHF_ALLOC != 0
                && pf_flags(out_secs[i].flags) == pf
            {
                i += 1;
            }
            phdrs.push(OutputPhdr {
                p_type: 1, // PT_LOAD
                p_flags: pf,
                p_offset: 0,
                p_vaddr: out_secs[start].vma,
                p_paddr: out_secs[start].vma,
                p_filesz: 0,
                p_memsz: 0,
                p_align: 0x1000,
            });
        }
        phdrs.push(OutputPhdr {
            p_type: 0x6474_e551, // PT_GNU_STACK
            p_flags: 6,
            p_offset: 0,
            p_vaddr: 0,
            p_paddr: 0,
            p_filesz: 0,
            p_memsz: 0,
            p_align: 0,
        });
    }

    // Symbol table: locals first, then globals.
    let mut locals: Vec<(String, u64, u64, u8, u16)> = Vec::new();
    let mut globals: Vec<(String, u64, u64, u8, u16)> = Vec::new();
    for s in &syms {
        if !s.defined || s.info & 0xF == 3 {
            continue; // skip UNDEFINED and STT_SECTION
        }
        let shndx: u16 = if let Some(sx) = s.synth_sec {
            sx
        } else if let Some(gi) = s.sec {
            if !(secs[gi].alive && secs[gi].placed) {
                continue;
            }
            (1 + secs[gi].out_index) as u16
        } else {
            0xFFF1 // SHN_ABS
        };
        let e = (s.name.clone(), s.addr, s.size, s.info, shndx);
        if s.info & 0xF0 == 0 {
            locals.push(e);
        } else {
            globals.push(e);
        }
    }
    locals.extend(globals);

    for w in &warnings {
        eprintln!("WARN: {w}");
    }

    Ok(build_output_elf(entry_addr, &out_secs, &phdrs, &locals))
}

fn pf_flags(sh_flags: u64) -> u32 {
    let mut f = 0u32;
    if sh_flags & SHF_ALLOC != 0 {
        f |= 4; // PF_R
    }
    if sh_flags & SHF_WRITE != 0 {
        f |= 2; // PF_W
    }
    if sh_flags & SHF_EXECINSTR != 0 {
        f |= 1; // PF_X
    }
    f
}

// -------------------------- reloc helpers ---------------------------------

fn rd32(b: &[u8], o: usize) -> u32 {
    u32::from_le_bytes([b[o], b[o + 1], b[o + 2], b[o + 3]])
}
fn wr32(b: &mut [u8], o: usize, v: u32) {
    b[o..o + 4].copy_from_slice(&v.to_le_bytes());
}
fn rd16(b: &[u8], o: usize) -> u16 {
    u16::from_le_bytes([b[o], b[o + 1]])
}
fn wr16(b: &mut [u8], o: usize, v: u16) {
    b[o..o + 2].copy_from_slice(&v.to_le_bytes());
}

fn apply_reloc(
    rtype: u32,
    b: &mut [u8],
    pos: usize,
    v: i64,
    p: i64,
    sym_addr: u64,
    auipc_delta: &HashMap<u64, i64>,
) {
    let off = v - p;
    match rtype {
        1 => {
            // R_RISCV_32
            if pos + 4 <= b.len() {
                wr32(b, pos, v as u32);
            }
        }
        2 => {
            // R_RISCV_64
            if pos + 8 <= b.len() {
                b[pos..pos + 8].copy_from_slice(&(v as u64).to_le_bytes());
            }
        }
        16 => {
            // R_RISCV_BRANCH
            if pos + 4 > b.len() {
                return;
            }
            let mut inst = rd32(b, pos) & 0x01FF_F07F;
            inst |= (((off >> 12) & 1) as u32) << 31;
            inst |= (((off >> 5) & 0x3F) as u32) << 25;
            inst |= (((off >> 1) & 0xF) as u32) << 8;
            inst |= (((off >> 11) & 1) as u32) << 7;
            wr32(b, pos, inst);
        }
        17 => {
            // R_RISCV_JAL
            if pos + 4 > b.len() {
                return;
            }
            let mut inst = rd32(b, pos) & 0x0000_0FFF;
            inst |= (((off >> 20) & 1) as u32) << 31;
            inst |= (((off >> 1) & 0x3FF) as u32) << 21;
            inst |= (((off >> 11) & 1) as u32) << 20;
            inst |= (((off >> 12) & 0xFF) as u32) << 12;
            wr32(b, pos, inst);
        }
        18 | 19 => {
            // R_RISCV_CALL / R_RISCV_CALL_PLT
            if pos + 8 > b.len() {
                return;
            }
            let imm20 = ((off + 0x800) >> 12) & 0xFFFFF;
            let inst1 = (rd32(b, pos) & 0xFFF) | ((imm20 as u32) << 12);
            wr32(b, pos, inst1);
            let imm12 = (off & 0xFFF) as u32;
            let inst2 = (rd32(b, pos + 4) & 0x000F_FFFF) | ((imm12 & 0xFFF) << 20);
            wr32(b, pos + 4, inst2);
        }
        23 => {
            // R_RISCV_PCREL_HI20
            if pos + 4 > b.len() {
                return;
            }
            let val = auipc_delta.get(&(p as u64)).copied().unwrap_or(0);
            let hi20 = (((val + 0x800) >> 12) & 0xFFFFF) as u32;
            let inst = (rd32(b, pos) & 0xFFF) | (hi20 << 12);
            wr32(b, pos, inst);
        }
        24 => {
            // R_RISCV_PCREL_LO12_I (sym_addr is the auipc address P_hi)
            if pos + 4 > b.len() {
                return;
            }
            let delta = auipc_delta.get(&sym_addr).copied().unwrap_or(0);
            let imm12 = (delta & 0xFFF) as u32;
            let inst = (rd32(b, pos) & 0x000F_FFFF) | ((imm12 & 0xFFF) << 20);
            wr32(b, pos, inst);
        }
        25 => {
            // R_RISCV_PCREL_LO12_S
            if pos + 4 > b.len() {
                return;
            }
            let delta = auipc_delta.get(&sym_addr).copied().unwrap_or(0);
            let mut inst = rd32(b, pos) & 0x01FF_F07F;
            inst |= ((((delta >> 5) & 0x7F) as u32) << 25) | (((delta & 0x1F) as u32) << 7);
            wr32(b, pos, inst);
        }
        26 => {
            // R_RISCV_HI20
            if pos + 4 > b.len() {
                return;
            }
            let imm20 = ((v + 0x800) >> 12) & 0xFFFFF;
            let inst = (rd32(b, pos) & 0xFFF) | ((imm20 as u32) << 12);
            wr32(b, pos, inst);
        }
        27 => {
            // R_RISCV_LO12_I
            if pos + 4 > b.len() {
                return;
            }
            let imm12 = (v & 0xFFF) as u32;
            let inst = (rd32(b, pos) & 0x000F_FFFF) | ((imm12 & 0xFFF) << 20);
            wr32(b, pos, inst);
        }
        28 => {
            // R_RISCV_LO12_S
            if pos + 4 > b.len() {
                return;
            }
            let mut inst = rd32(b, pos) & 0x01FF_F07F;
            inst |= ((((v >> 5) & 0x7F) as u32) << 25) | (((v & 0x1F) as u32) << 7);
            wr32(b, pos, inst);
        }
        33..=40 => {
            // R_RISCV_ADD8/16/32/64 (33..36), SUB8/16/32/64 (37..40)
            let add = rtype <= 36;
            let width = match (rtype - 33) % 4 {
                0 => 1,
                1 => 2,
                2 => 4,
                _ => 8,
            };
            if pos + width > b.len() {
                return;
            }
            let mut cur: u64 = 0;
            for k in 0..width {
                cur |= (b[pos + k] as u64) << (8 * k);
            }
            let nv = if add {
                cur.wrapping_add(v as u64)
            } else {
                cur.wrapping_sub(v as u64)
            };
            for k in 0..width {
                b[pos + k] = ((nv >> (8 * k)) & 0xFF) as u8;
            }
        }
        44 => {
            // R_RISCV_RVC_BRANCH
            if pos + 2 > b.len() {
                return;
            }
            let mut inst = rd16(b, pos) & 0xE383;
            inst |= (((off >> 8) & 1) as u16) << 12;
            inst |= (((off >> 3) & 3) as u16) << 10;
            inst |= (((off >> 6) & 3) as u16) << 5;
            inst |= (((off >> 1) & 3) as u16) << 3;
            inst |= (((off >> 5) & 1) as u16) << 2;
            wr16(b, pos, inst);
        }
        45 => {
            // R_RISCV_RVC_JUMP
            if pos + 2 > b.len() {
                return;
            }
            let mut inst = rd16(b, pos) & 0xE003;
            inst |= (((off >> 11) & 1) as u16) << 12;
            inst |= (((off >> 4) & 1) as u16) << 11;
            inst |= (((off >> 8) & 3) as u16) << 9;
            inst |= (((off >> 10) & 1) as u16) << 8;
            inst |= (((off >> 6) & 1) as u16) << 7;
            inst |= (((off >> 7) & 1) as u16) << 6;
            inst |= (((off >> 1) & 7) as u16) << 3;
            inst |= (((off >> 5) & 1) as u16) << 2;
            wr16(b, pos, inst);
        }
        57 => {
            // R_RISCV_32_PCREL
            if pos + 4 <= b.len() {
                wr32(b, pos, off as u32);
            }
        }
        // 43 = ALIGN (padding present), 51 = RELAX, 52..=56 = SET6/SUB6/... : no-op
        _ => {}
    }
}
