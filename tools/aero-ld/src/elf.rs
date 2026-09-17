//! ELF input parsing (via goblin) + output construction.
//!
//! Input: RISC-V 64-bit .o files (ET_REL).
//! Output: RISC-V 64-bit executable (ET_EXEC) with resolved relocs.

use goblin::elf::{Elf, section_header};
use std::fs;

/// Parsed input object file with all metadata we need.
#[derive(Debug, Clone)]
pub struct InputObj {
    pub sections: Vec<InputSection>,
    pub symbols: Vec<InputSymbol>,
    pub relocs: Vec<InputReloc>,  // indexed by section
}

#[derive(Debug, Clone)]
pub struct InputSection {
    pub name: String,
    pub flags: u64,
    pub size: u64,
    pub align: u64,
    pub data: Vec<u8>,    // raw bytes
}

#[derive(Debug, Clone)]
pub struct InputSymbol {
    pub name: String,
    pub st_value: u64,
    pub st_size: u64,
    pub st_info: u8,      // type + bind
    pub st_shndx: u16,    // SHN_UNDEF if undefined
    pub section_idx: Option<usize>,  // resolved to which InputSection
}

#[derive(Debug, Clone)]
pub struct InputReloc {
    pub section_shndx: usize,  // which InputSection
    pub offset: u64,
    pub rtype: u32,            // reloc type (R_RISCV_*)
    pub sym_idx: usize,        // index into InputObj.symbols
    pub addend: i64,
}

/// Parse one .o file.
pub fn parse_obj(path: &str) -> Result<InputObj, String> {
    let data = fs::read(path).map_err(|e| format!("read {}: {}", path, e))?;
    let elf = Elf::parse(&data).map_err(|e| format!("parse {}: {}", path, e))?;
    
    // Verify it's RISC-V 64-bit ET_REL
    let header = &elf.header;
    if header.e_type != 1 { // ET_REL
        return Err(format!("{}: not ET_REL (type={})", path, header.e_type));
    }
    // RISC-V e_machine = 0xF3 (243)
    if header.e_machine != 0xF3 {
        return Err(format!("{}: not RISC-V (machine=0x{:x})", path, header.e_machine));
    }
    // Verify 64-bit little-endian
    let container = header.container().map_err(|e| format!("container: {}", e))?;
    let endian = header.endianness().map_err(|e| format!("endianness: {}", e))?;
    if container != goblin::container::Container::Big || endian != goblin::container::Endian::Little {
        return Err(format!("{}: expected 64-bit LE", path));
    }

    let strtab = &elf.strtab;
    let shstrtab = &elf.shdr_strtab;

    let mut obj = InputObj {
        sections: vec![],
        symbols: vec![],
        relocs: vec![],
    };

    // Parse sections
    let section_headers = &elf.section_headers;
    for sh in section_headers.iter() {
        let name = shstrtab.get_at(sh.sh_name).unwrap_or("").to_string();
        let sec_data = if sh.sh_type != section_header::SHT_NOBITS {
            let start = sh.sh_offset as usize;
            let end = start + sh.sh_size as usize;
            if end > data.len() { vec![] } else { data[start..end].to_vec() }
        } else {
            vec![0u8; sh.sh_size as usize]
        };
        obj.sections.push(InputSection {
            name,
            flags: sh.sh_flags,
            size: sh.sh_size,
            align: sh.sh_addralign,
            data: sec_data,
        });
    }

    // Parse symbols
    let syms_iter = elf.syms.iter();
    let symstrtab = strtab;
    for sym in syms_iter {
        let name = symstrtab.get_at(sym.st_name).unwrap_or("").to_string();
        let section_idx = if sym.st_shndx == 0 || sym.st_shndx >= 0xFF00 {
            None
        } else {
            Some(sym.st_shndx as usize)
        };
        obj.symbols.push(InputSymbol {
            name,
            st_value: sym.st_value,
            st_size: sym.st_size,
            st_info: sym.st_info,
            st_shndx: sym.st_shndx as u16,
            section_idx,
        });
    }

    // Parse relocations using elf.shdr_relocs (Vec<(ShdrIdx, RelocSection)>)
    for (shdr_idx, reloc_sec) in &elf.shdr_relocs {
        // Get the section header to find the section name
        let sh = section_headers.get(*shdr_idx).ok_or("bad shdr idx")
            .map_err(|e| format!("reloc shdr: {}", e))?;
        let name = shstrtab.get_at(sh.sh_name).unwrap_or("");
        // .rela.XXX → target is .XXX (need leading dot back!)
        let target_name = match name.strip_prefix(".rela.").or_else(|| name.strip_prefix(".rel.")) {
            Some(t) if !t.is_empty() && !t.starts_with('.') => format!(".{}", t),
            Some(t) => t.to_string(),
            None => String::new(),
        };
        
        for r in reloc_sec.iter() {
            // Reloc is now a plain struct: r_offset, r_addend, r_sym, r_type
            let off = r.r_offset;
            let rtype = r.r_type;
            let sym_idx = r.r_sym;
            let addend = r.r_addend.unwrap_or(0);
            // Find target section index
            let target_idx = obj.sections.iter()
                .position(|s| s.name == target_name)
                .unwrap_or_else(|| {
                    eprintln!("WARN: reloc {}: target '{}' not found", name, target_name);
                    0
                });
            obj.relocs.push(InputReloc {
                section_shndx: target_idx,
                offset: off,
                rtype,
                sym_idx,
                addend: addend as i64,
            });
        }
    }

    // Validate: cross-reference symbol section_idx → InputSection
    for sym in &mut obj.symbols {
        if let Some(idx) = sym.section_idx {
            if idx >= obj.sections.len() {
                sym.section_idx = None;
            }
        }
    }

    Ok(obj)
}

// ==================== OUTPUT ELF ====================

/// Final assembled section ready to write.
#[derive(Debug, Clone)]
pub struct OutputSection {
    pub name: String,
    pub sh_type: u32,
    pub vma: u64,
    pub size: u64,
    pub align: u64,
    pub flags: u64,
    pub data: Vec<u8>,  // resolved bytes
}

/// EType program header.
#[derive(Debug, Clone)]
pub struct OutputPhdr {
    pub p_type: u32,
    pub p_flags: u32,
    pub p_offset: u64,
    pub p_vaddr: u64,
    pub p_paddr: u64,
    pub p_filesz: u64,
    pub p_memsz: u64,
    pub p_align: u64,
}

/// Build output ELF binary.
pub fn build_output_elf(
    entry: u64,
    sections: &[OutputSection],
    phdrs: &[OutputPhdr],
    // Final symbol table: name, value, size, st_info, section index
    symtab_entries: &[(String, u64, u64, u8, u16)],
) -> Vec<u8> {
    /// A fully described section header (named fields — no positional tuples).
    #[derive(Clone)]
    struct Sh {
        name: String,
        sh_type: u32,
        flags: u64,
        addr: u64,
        offset: u64,
        size: u64,
        link: u32,
        info: u32,
        addralign: u64,
        entsize: u64,
        data: Vec<u8>,
        nobits: bool,
    }

    fn pf(flags: u64) -> u32 {
        let mut f = 0u32;
        if flags & 0x2 != 0 {
            f |= 4; // PF_R
        }
        if flags & 0x1 != 0 {
            f |= 2; // PF_W
        }
        if flags & 0x4 != 0 {
            f |= 1; // PF_X
        }
        f
    }

    fn push_name(buf: &mut Vec<u8>, s: &str) -> u32 {
        let o = buf.len() as u32;
        buf.extend_from_slice(s.as_bytes());
        buf.push(0);
        o
    }

    let base_vma = sections
        .iter()
        .find(|s| s.flags & 0x2 != 0)
        .map(|s| s.vma)
        .unwrap_or(0);

    // -- Content section headers (in caller order) --
    let mut content: Vec<Sh> = Vec::new();
    for s in sections {
        let alloc = s.flags & 0x2 != 0;
        let nobits = s.sh_type == section_header::SHT_NOBITS;
        content.push(Sh {
            name: s.name.clone(),
            sh_type: s.sh_type,
            flags: s.flags,
            addr: s.vma,
            offset: if alloc { 0x1000 + (s.vma - base_vma) } else { 0 },
            size: s.size,
            link: 0,
            info: 0,
            addralign: s.align.max(1),
            entsize: 0,
            data: if nobits { Vec::new() } else { s.data.clone() },
            nobits,
        });
    }

    // -- File offsets: alloc sections derive from vma; others follow sequentially --
    let mut loaded_end: u64 = 0x1000;
    for sh in &content {
        if sh.flags & 0x2 != 0 && !sh.nobits {
            loaded_end = loaded_end.max(sh.offset + sh.data.len() as u64);
        }
    }
    let mut next = loaded_end;
    for sh in content.iter_mut() {
        if sh.flags & 0x2 != 0 {
            continue;
        }
        let a = sh.addralign.max(1);
        next = (next + a - 1) & !(a - 1);
        sh.offset = next;
        next += sh.data.len() as u64;
    }

    // -- .strtab --
    let mut strtab: Vec<u8> = vec![0u8];
    let mut name_off: Vec<u32> = Vec::with_capacity(symtab_entries.len());
    for (n, _, _, _, _) in symtab_entries {
        name_off.push(push_name(&mut strtab, n));
    }

    // -- .symtab (NULL symbol + entries), sh_info = first GLOBAL symbol index --
    let mut symdata: Vec<u8> = Vec::new();
    symdata.extend_from_slice(&[0u8; 24]); // NULL symbol
    let mut first_global = symtab_entries.len() + 1;
    for (i, (_, value, size, info, shndx)) in symtab_entries.iter().enumerate() {
        if info & 0xF0 != 0 && first_global == symtab_entries.len() + 1 {
            first_global = i + 1;
        }
        symdata.extend_from_slice(&name_off[i].to_le_bytes()); // st_name
        symdata.push(*info); // st_info
        symdata.push(0); // st_other
        symdata.extend_from_slice(&shndx.to_le_bytes()); // st_shndx
        symdata.extend_from_slice(&value.to_le_bytes()); // st_value
        symdata.extend_from_slice(&size.to_le_bytes()); // st_size
    }

    let n_content = content.len();
    let strtab_idx = n_content + 1;
    let shstrtab_idx = n_content + 3;

    let mut strtab_sh = Sh {
        name: ".strtab".into(),
        sh_type: 3, // STRTAB
        flags: 0,
        addr: 0,
        offset: 0,
        size: strtab.len() as u64,
        link: 0,
        info: 0,
        addralign: 1,
        entsize: 0,
        data: strtab,
        nobits: false,
    };
    let a = strtab_sh.addralign.max(1);
    next = (next + a - 1) & !(a - 1);
    strtab_sh.offset = next;
    next += strtab_sh.data.len() as u64;

    let symtab_sh = Sh {
        name: ".symtab".into(),
        sh_type: 2, // SYMTAB
        flags: 0,
        addr: 0,
        offset: 0, // assigned below
        size: symdata.len() as u64,
        link: strtab_idx as u32,
        info: first_global as u32,
        addralign: 8,
        entsize: 24,
        data: symdata,
        nobits: false,
    };
    let mut symtab_sh = symtab_sh;
    next = (next + 7) & !7u64;
    symtab_sh.offset = next;
    next += symtab_sh.data.len() as u64;

    // -- .shstrtab (built after all names are known) --
    let mut shstr: Vec<u8> = vec![0u8];
    let mut name_offsets: Vec<u32> = Vec::with_capacity(n_content + 4);
    name_offsets.push(0); // NULL section: empty name
    for sh in &content {
        name_offsets.push(push_name(&mut shstr, &sh.name));
    }
    name_offsets.push(push_name(&mut shstr, ".strtab"));
    name_offsets.push(push_name(&mut shstr, ".symtab"));
    name_offsets.push(push_name(&mut shstr, ".shstrtab"));

    let mut shstrtab_sh = Sh {
        name: ".shstrtab".into(),
        sh_type: 3, // STRTAB
        flags: 0,
        addr: 0,
        offset: 0,
        size: shstr.len() as u64,
        link: 0,
        info: 0,
        addralign: 1,
        entsize: 0,
        data: shstr,
        nobits: false,
    };
    let a = shstrtab_sh.addralign.max(1);
    next = (next + a - 1) & !(a - 1);
    shstrtab_sh.offset = next;

    // -- Assemble the final section table --
    let mut all: Vec<Sh> = Vec::new();
    all.push(Sh {
        name: String::new(),
        sh_type: 0,
        flags: 0,
        addr: 0,
        offset: 0,
        size: 0,
        link: 0,
        info: 0,
        addralign: 0,
        entsize: 0,
        data: Vec::new(),
        nobits: false,
    });
    all.extend(content);
    all.push(strtab_sh);
    all.push(symtab_sh);
    all.push(shstrtab_sh);
    debug_assert_eq!(all.len(), n_content + 4);

    // -- Recompute LOAD program headers from the actual section placement --
    let mut groups: Vec<Vec<usize>> = Vec::new();
    for (i, sh) in all.iter().enumerate().skip(1) {
        if sh.flags & 0x2 == 0 {
            continue;
        }
        let my = pf(sh.flags);
        match groups.last_mut() {
            Some(g) if pf(all[g[0]].flags) == my => g.push(i),
            _ => groups.push(vec![i]),
        }
    }
    let mut new_phdrs: Vec<OutputPhdr> = Vec::new();
    for g in &groups {
        let first = &all[g[0]];
        let mut filesz = 0u64;
        let mut memsz = 0u64;
        for &i in g {
            let sh = &all[i];
            memsz = memsz.max(sh.offset + sh.size);
            if !sh.nobits {
                filesz = filesz.max(sh.offset + sh.data.len() as u64);
            }
        }
        new_phdrs.push(OutputPhdr {
            p_type: 1, // PT_LOAD
            p_flags: pf(first.flags),
            p_offset: first.offset,
            p_vaddr: first.addr,
            p_paddr: first.addr,
            p_filesz: filesz.saturating_sub(first.offset),
            p_memsz: memsz.saturating_sub(first.offset),
            p_align: 0x1000,
        });
    }
    for ph in phdrs {
        if ph.p_type != 1 {
            new_phdrs.push(ph.clone());
        }
    }

    // -- Write the file --
    let phoff = 64u64;
    let phnum = new_phdrs.len();

    let mut out: Vec<u8> = Vec::new();
    out.extend_from_slice(&[0x7f, b'E', b'L', b'F', 2, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0]);
    out.extend_from_slice(&2u16.to_le_bytes()); // e_type = ET_EXEC
    out.extend_from_slice(&0xF3u16.to_le_bytes()); // e_machine = EM_RISCV
    out.extend_from_slice(&1u32.to_le_bytes()); // e_version
    out.extend_from_slice(&entry.to_le_bytes()); // e_entry
    out.extend_from_slice(&phoff.to_le_bytes()); // e_phoff
    let shoff_pos = out.len();
    out.extend_from_slice(&0u64.to_le_bytes()); // e_shoff (patched later)
    out.extend_from_slice(&5u32.to_le_bytes()); // e_flags = RVC | double-float ABI
    out.extend_from_slice(&64u16.to_le_bytes()); // e_ehsize
    out.extend_from_slice(&56u16.to_le_bytes()); // e_phentsize
    out.extend_from_slice(&(phnum as u16).to_le_bytes()); // e_phnum
    out.extend_from_slice(&64u16.to_le_bytes()); // e_shentsize
    out.extend_from_slice(&(all.len() as u16).to_le_bytes()); // e_shnum
    out.extend_from_slice(&(shstrtab_idx as u16).to_le_bytes()); // e_shstrndx

    for ph in &new_phdrs {
        out.extend_from_slice(&ph.p_type.to_le_bytes());
        out.extend_from_slice(&ph.p_flags.to_le_bytes());
        out.extend_from_slice(&ph.p_offset.to_le_bytes());
        out.extend_from_slice(&ph.p_vaddr.to_le_bytes());
        out.extend_from_slice(&ph.p_paddr.to_le_bytes());
        out.extend_from_slice(&ph.p_filesz.to_le_bytes());
        out.extend_from_slice(&ph.p_memsz.to_le_bytes());
        out.extend_from_slice(&ph.p_align.to_le_bytes());
    }

    // Pad from end-of-headers to the first loadable byte.
    if (out.len() as u64) < 0x1000 {
        out.resize(0x1000, 0);
    }
    for sh in all.iter().skip(1) {
        if sh.nobits || sh.data.is_empty() {
            continue;
        }
        if (out.len() as u64) < sh.offset {
            out.resize(sh.offset as usize, 0);
        }
        out.extend_from_slice(&sh.data);
    }

    let shoff = ((out.len() as u64) + 7) & !7u64;
    if (out.len() as u64) < shoff {
        out.resize(shoff as usize, 0);
    }
    for (i, sh) in all.iter().enumerate() {
        out.extend_from_slice(&name_offsets[i].to_le_bytes()); // sh_name
        out.extend_from_slice(&sh.sh_type.to_le_bytes()); // sh_type
        out.extend_from_slice(&sh.flags.to_le_bytes()); // sh_flags
        out.extend_from_slice(&sh.addr.to_le_bytes()); // sh_addr
        out.extend_from_slice(&sh.offset.to_le_bytes()); // sh_offset
        out.extend_from_slice(&sh.size.to_le_bytes()); // sh_size
        out.extend_from_slice(&sh.link.to_le_bytes()); // sh_link
        out.extend_from_slice(&sh.info.to_le_bytes()); // sh_info
        out.extend_from_slice(&sh.addralign.to_le_bytes()); // sh_addralign
        out.extend_from_slice(&sh.entsize.to_le_bytes()); // sh_entsize
    }

    out[shoff_pos..shoff_pos + 8].copy_from_slice(&shoff.to_le_bytes());
    out
}
