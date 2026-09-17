//! Aero's minimal RISC-V 64-bit linker.
//!
//! Usage: aero-ld -T linker.ld -o kernel.elf input1.o input2.o ...

mod elf;
mod ldscript;
mod linker;

use std::env;
use std::fs;

fn main() {
    let args: Vec<String> = env::args().skip(1).collect();
    
    let mut ldscript_path: Option<String> = None;
    let mut output_path = "a.out".to_string();
    let mut input_paths: Vec<String> = Vec::new();
    
    let mut i = 0;
    while i < args.len() {
        match args[i].as_str() {
            "-T" | "--script" => {
                i += 1;
                if i < args.len() { ldscript_path = Some(args[i].clone()); }
            }
            "-o" | "--output" => {
                i += 1;
                if i < args.len() { output_path = args[i].clone(); }
            }
            "-h" | "--help" => {
                eprintln!("aero-ld: minimal RISC-V linker");
                eprintln!("Usage: aero-ld -T linker.ld -o kernel.elf input.o [...]");
                std::process::exit(0);
            }
            _ => {
                if args[i].ends_with(".o") || args[i].ends_with(".elf") {
                    input_paths.push(args[i].clone());
                } else {
                    // Might be a positional arg
                    input_paths.push(args[i].clone());
                }
            }
        }
        i += 1;
    }
    
    let script_path = match ldscript_path {
        Some(p) => p,
        None => {
            eprintln!("error: no linker script specified (use -T linker.ld)");
            std::process::exit(1);
        }
    };
    
    // Parse script
    let script_src = fs::read_to_string(&script_path).unwrap_or_else(|e| {
        eprintln!("error reading {}: {}", script_path, e);
        std::process::exit(1);
    });
    let script = ldscript::LdScript::parse(&script_src).unwrap_or_else(|e| {
        eprintln!("error parsing ldscript: {}", e);
        std::process::exit(1);
    });
    
    // Parse all input .o files
    let mut objects = Vec::new();
    for path in &input_paths {
        match elf::parse_obj(path) {
            Ok(obj) => {
                eprintln!("  parsed {}: {} sections, {} symbols, {} relocs", 
                    path, obj.sections.len(), obj.symbols.len(), obj.relocs.len());
                objects.push(obj);
            }
            Err(e) => {
                eprintln!("error parsing {}: {}", path, e);
                std::process::exit(1);
            }
        }
    }
    
    // Link
    eprintln!("linking {} objects with script {} (ENTRY={})...", 
        objects.len(), script_path, script.entry);
    let output_bytes = linker::link(objects, &script).unwrap_or_else(|e| {
        eprintln!("link error: {}", e);
        std::process::exit(1);
    });
    
    // Write
    fs::write(&output_path, &output_bytes).unwrap_or_else(|e| {
        eprintln!("error writing {}: {}", output_path, e);
        std::process::exit(1);
    });
    
    eprintln!("OK: {} bytes written to {}", output_bytes.len(), output_path);
}