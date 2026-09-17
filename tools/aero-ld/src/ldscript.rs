//! Minimal GNU linker script parser for Aero-ld.
//!
//! Handles the subset of the linker script grammar that AeroOS uses:
//!   ENTRY(_start)
//!   SECTIONS {
//!       . = 0x80200000;
//!       .text.boot : { *(.text.boot) }
//!       .bss (NOLOAD) : { _bss_start = .; *(.bss*) . = ALIGN(8); _bss_end = .; }
//!       /DISCARD/ : { *(.comment) }
//!   }

pub struct LdScript {
    pub entry: String,
    pub initial_dot: Option<u64>,
    pub sections: Vec<LdSection>,
}

pub struct LdSection {
    pub name: String,
    pub noload: bool,
    pub body: Vec<BodyElem>,
}

pub enum BodyElem {
    Wildcard(String),
    Assign(String, DotExpr),
}

#[derive(Clone, Debug)]
pub enum DotExpr {
    /// Pure number, e.g. `0x80200000`.
    Value(u64),
    /// Just `.`.
    Dot,
    /// `ALIGN(n)` where `n` is a pure number.
    Align(u64),
}

impl LdScript {
    pub fn parse(src: &str) -> Result<LdScript, String> {
        let tokens = tokenize(src)?;
        let mut p = Parser::new(&tokens);

        let mut entry = String::new();
        let mut initial_dot: Option<u64> = None;
        let mut sections: Vec<LdSection> = Vec::new();

        while !p.is_empty() {
            if p.peek_keyword("ENTRY") {
                p.advance();
                p.expect_op("(")?;
                entry = p.expect_ident()?;
                p.expect_op(")")?;
                continue;
            }
            if p.peek_keyword("SECTIONS") {
                p.advance();
                p.expect_op("{")?;
                loop {
                    while p.peek_op(";") {
                        p.advance();
                    }
                    if p.peek_op("}") {
                        p.advance();
                        break;
                    }
                    if p.is_empty() {
                        return Err("unterminated SECTIONS block".into());
                    }
                    // Top-level dot assignment: `. = 0x80200000;`
                    if p.peek_op(".") && p.peek_at_op(1, "=") {
                        p.advance(); // "."
                        p.advance(); // "="
                        let expr = parse_expr(&mut p)?;
                        p.expect_op(";")?;
                        if initial_dot.is_none() {
                            if let DotExpr::Value(v) = expr {
                                initial_dot = Some(v);
                            }
                        }
                        continue;
                    }
                    let section = parse_section(&mut p)?;
                    sections.push(section);
                }
                continue;
            }
            p.advance();
        }

        if entry.is_empty() {
            return Err("Linker script missing ENTRY(symbol)".into());
        }

        Ok(LdScript {
            entry,
            initial_dot,
            sections,
        })
    }
}

// ---------------------------------------------------------------------------
// Tokenizer
// ---------------------------------------------------------------------------

#[derive(Clone, Debug)]
enum Token {
    Ident(String),
    Number(u64),
    Op(String),
}

impl Token {
    fn text(&self) -> String {
        match self {
            Token::Ident(s) => s.clone(),
            Token::Number(n) => n.to_string(),
            Token::Op(s) => s.clone(),
        }
    }
}

fn tokenize(src: &str) -> Result<Vec<Token>, String> {
    let b = src.as_bytes();
    let mut i = 0usize;
    let mut out: Vec<Token> = Vec::new();

    while i < b.len() {
        let c = b[i] as char;

        if c.is_whitespace() {
            i += 1;
            continue;
        }
        // `// ...`
        if c == '/' && i + 1 < b.len() && b[i + 1] == b'/' {
            while i < b.len() && b[i] != b'\n' {
                i += 1;
            }
            continue;
        }
        // `/* ... */`
        if c == '/' && i + 1 < b.len() && b[i + 1] == b'*' {
            i += 2;
            while i + 1 < b.len() && !(b[i] == b'*' && b[i + 1] == b'/') {
                i += 1;
            }
            i = (i + 2).min(b.len());
            continue;
        }

        // Number: 0x... / decimal
        if c.is_ascii_digit() {
            let start = i;
            if c == '0' && i + 1 < b.len() && (b[i + 1] == b'x' || b[i + 1] == b'X') {
                i += 2;
                while i < b.len() && (b[i] as char).is_ascii_hexdigit() {
                    i += 1;
                }
            } else {
                while i < b.len() && (b[i] as char).is_ascii_digit() {
                    i += 1;
                }
            }
            let txt = &src[start..i];
            let (digits, radix) = if let Some(rest) = txt.strip_prefix("0x").or_else(|| txt.strip_prefix("0X")) {
                (rest, 16u32)
            } else {
                (txt, 10u32)
            };
            let n = u64::from_str_radix(digits, radix).map_err(|_| format!("Bad number: {txt}"))?;
            out.push(Token::Number(n));
            continue;
        }

        // `.`-led identifier (section/symbol names like `.text.boot`), otherwise `.` op.
        if c == '.' {
            if i + 1 < b.len() {
                let n = b[i + 1] as char;
                if n.is_ascii_alphabetic() || n == '_' {
                    let start = i;
                    i += 1;
                    while i < b.len() {
                        let ch = b[i] as char;
                        if ch.is_ascii_alphanumeric() || ch == '_' || ch == '.' {
                            i += 1;
                        } else {
                            break;
                        }
                    }
                    out.push(Token::Ident(src[start..i].to_string()));
                    continue;
                }
            }
            i += 1;
            out.push(Token::Op(".".into()));
            continue;
        }

        // Identifier / keyword
        if c.is_ascii_alphabetic() || c == '_' {
            let start = i;
            while i < b.len() {
                let ch = b[i] as char;
                if ch.is_ascii_alphanumeric() || ch == '_' || ch == '.' {
                    i += 1;
                } else {
                    break;
                }
            }
            out.push(Token::Ident(src[start..i].to_string()));
            continue;
        }

        // Single punctuation: ( ) { } * ; = / , :
        i += 1;
        out.push(Token::Op(c.to_string()));
    }

    Ok(out)
}

// ---------------------------------------------------------------------------
// Parser
// ---------------------------------------------------------------------------

struct Parser<'a> {
    t: &'a [Token],
    i: usize,
}

impl<'a> Parser<'a> {
    fn new(t: &'a [Token]) -> Self {
        Self { t, i: 0 }
    }

    fn is_empty(&self) -> bool {
        self.i >= self.t.len()
    }

    fn peek_op(&self, s: &str) -> bool {
        matches!(self.t.get(self.i), Some(Token::Op(x)) if x == s)
    }

    fn peek_at_op(&self, off: usize, s: &str) -> bool {
        matches!(self.t.get(self.i + off), Some(Token::Op(x)) if x == s)
    }

    fn peek_ident(&self) -> bool {
        matches!(self.t.get(self.i), Some(Token::Ident(_)))
    }

    fn peek_keyword(&self, kw: &str) -> bool {
        matches!(self.t.get(self.i), Some(Token::Ident(x)) if x == kw)
    }

    fn advance(&mut self) {
        self.i += 1;
    }

    fn expect_op(&mut self, s: &str) -> Result<(), String> {
        if self.peek_op(s) {
            self.i += 1;
            Ok(())
        } else {
            Err(format!("Expected token '{s}' at pos {}", self.i))
        }
    }

    fn expect_ident(&mut self) -> Result<String, String> {
        if let Some(Token::Ident(x)) = self.t.get(self.i) {
            let x = x.clone();
            self.i += 1;
            Ok(x)
        } else {
            Err(format!("Expected identifier at pos {}", self.i))
        }
    }

    fn expect_number(&mut self) -> Result<u64, String> {
        if let Some(Token::Number(n)) = self.t.get(self.i) {
            let n = *n;
            self.i += 1;
            Ok(n)
        } else {
            Err(format!("Expected number at pos {}", self.i))
        }
    }
}

fn parse_section(p: &mut Parser) -> Result<LdSection, String> {
    let name = if p.peek_op("/") {
        p.advance(); // "/"
        let d = p.expect_ident()?; // "DISCARD"
        p.expect_op("/")?;
        format!("/{d}/")
    } else {
        p.expect_ident()?
    };

    let mut noload = false;
    if p.peek_op("(") {
        p.advance();
        let attr = p.expect_ident()?;
        if attr == "NOLOAD" {
            noload = true;
        }
        p.expect_op(")")?;
    }

    p.expect_op(":")?;
    p.expect_op("{")?;

    let mut body: Vec<BodyElem> = Vec::new();
    loop {
        while p.peek_op(";") {
            p.advance();
        }
        if p.peek_op("}") {
            p.advance();
            break;
        }
        if p.is_empty() {
            return Err(format!("unterminated section body '{name}'"));
        }

        // Wildcard: `*( PATTERN )` — reconstruct pattern from ALL tokens.
        if p.peek_op("*") {
            p.advance();
            p.expect_op("(")?;
            let mut pat = String::new();
            while !p.peek_op(")") {
                if p.is_empty() {
                    return Err("unterminated wildcard".into());
                }
                pat.push_str(&p.t[p.i].text());
                p.advance();
            }
            p.expect_op(")")?;
            body.push(BodyElem::Wildcard(pat));
            continue;
        }

        // `. = EXPR ;`
        if p.peek_op(".") && p.peek_at_op(1, "=") {
            p.advance();
            p.advance();
            let e = parse_expr(p)?;
            p.expect_op(";")?;
            body.push(BodyElem::Assign(".".into(), e));
            continue;
        }

        // `IDENT = EXPR ;`
        if p.peek_ident() {
            let id = p.expect_ident()?;
            p.expect_op("=")?;
            let e = parse_expr(p)?;
            p.expect_op(";")?;
            body.push(BodyElem::Assign(id, e));
            continue;
        }

        // Unknown token — skip one.
        p.advance();
    }

    Ok(LdSection { name, noload, body })
}

fn parse_expr(p: &mut Parser) -> Result<DotExpr, String> {
    if p.peek_keyword("ALIGN") {
        p.advance();
        p.expect_op("(")?;
        let n = p.expect_number()?;
        p.expect_op(")")?;
        return Ok(DotExpr::Align(n));
    }
    if p.peek_op(".") {
        p.advance();
        return Ok(DotExpr::Dot);
    }
    if let Some(Token::Number(n)) = p.t.get(p.i) {
        let n = *n;
        p.advance();
        return Ok(DotExpr::Value(n));
    }
    Err(format!("Expected expression at pos {}", p.i))
}
