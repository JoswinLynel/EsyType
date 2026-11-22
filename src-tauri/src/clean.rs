//! Clean mode (English): tidies a transcript with rules. No language model, no network.
//! Every rule leaves the text alone when it is unsure: a missed tidy-up is better than a changed meaning.
//! Order: voice commands, fillers, numbers, writing style, capitalisation. The engine's own spacing is kept wherever text is kept.

#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Options {
    /// Also remove "you know", "I mean", "like", "sort of", "kind of" when set off by a comma.
    pub extended_fillers: bool,
    /// Plain counts from zero to nine as words ("three apples"), as UK style guides do.
    pub small_numbers_as_words: bool,
}

impl Default for Options {
    fn default() -> Self {
        Options { extended_fillers: false, small_numbers_as_words: true }
    }
}

#[derive(Clone, Debug, PartialEq)]
enum Kind {
    Word,
    Punct,
    /// Line breaks: 1 = new line, 2 = new paragraph.
    Break(u8),
}

#[derive(Clone, Debug)]
struct Tok {
    text: String,
    kind: Kind,
    /// Preceded by a space in the engine's text.
    space: bool,
}

impl Tok {
    fn word(text: impl Into<String>, space: bool) -> Tok {
        Tok { text: text.into(), kind: Kind::Word, space }
    }
    fn punct(text: &str, space: bool) -> Tok {
        Tok { text: text.into(), kind: Kind::Punct, space }
    }
    fn is_word(&self) -> bool {
        self.kind == Kind::Word
    }
    fn lower(&self) -> String {
        self.text.to_lowercase().replace('’', "'")
    }
    fn is(&self, p: &str) -> bool {
        self.kind == Kind::Punct && self.text == p
    }
    fn ends_sentence(&self) -> bool {
        matches!(self.kind, Kind::Break(_)) || (self.kind == Kind::Punct && matches!(self.text.as_str(), "." | "!" | "?" | "…"))
    }
}

#[cfg(test)]
pub fn apply(text: &str, o: &Options) -> String {
    apply_styled(text, o, None)
}

/// Clean, then the writing style (if any) before capitals are fixed.
pub fn apply_styled(text: &str, o: &Options, s: Option<&Style>) -> String {
    let t = tokenize(text);
    let t = commands(t);
    let t = fillers(t, o);
    let t = numbers(t, o);
    let t = match s {
        Some(s) => style(t, s),
        None => t,
    };
    let t = capitalise(t);
    render(&t)
}

// ---------- tokens ----------

fn tokenize(s: &str) -> Vec<Tok> {
    let c: Vec<char> = s.chars().collect();
    let mut out = vec![];
    let mut space = false;
    let mut i = 0;
    let alnum = |k: usize| c.get(k).is_some_and(|x| x.is_alphanumeric());
    let digit = |k: usize| c.get(k).is_some_and(|x| x.is_ascii_digit());
    while i < c.len() {
        let ch = c[i];
        if ch == '\n' {
            let n = if c.get(i + 1) == Some(&'\n') { 2 } else { 1 };
            out.push(Tok { text: String::new(), kind: Kind::Break(n), space: false });
            i += n as usize;
            space = false;
        } else if ch.is_whitespace() {
            space = true;
            i += 1;
        } else if ch.is_alphanumeric() || crate::dictionary::is_placeholder(ch) || crate::snippets::is_placeholder(ch) {
            let start = i;
            while i < c.len() {
                let x = c[i];
                let joins = match x {
                    // don't, twenty-five, p.m, e.g, 3.5, 3:30, 1,000
                    '\'' | '’' | '-' => alnum(i - 1) && alnum(i + 1),
                    '.' => alnum(i - 1) && alnum(i + 1),
                    ':' | ',' => digit(i - 1) && digit(i + 1),
                    _ => x.is_alphanumeric() || crate::dictionary::is_placeholder(x) || crate::snippets::is_placeholder(x),
                };
                if !joins {
                    break;
                }
                i += 1;
            }
            out.push(Tok::word(c[start..i].iter().collect::<String>(), space));
            space = false;
        } else {
            out.push(Tok::punct(&ch.to_string(), space));
            space = false;
            i += 1;
        }
    }
    out
}

fn render(t: &[Tok]) -> String {
    let mut s = String::new();
    for (k, x) in t.iter().enumerate() {
        match x.kind {
            Kind::Break(n) => {
                s.truncate(s.trim_end_matches(' ').len());
                s.push_str(if n == 2 { "\n\n" } else { "\n" });
            }
            _ => {
                let after_break = k > 0 && matches!(t[k - 1].kind, Kind::Break(_));
                if x.space && !s.is_empty() && !after_break {
                    s.push(' ');
                }
                s.push_str(&x.text);
            }
        }
    }
    s.trim().to_string()
}

fn eq(t: &[Tok], i: usize, words: &[&str]) -> bool {
    words.iter().enumerate().all(|(k, w)| t.get(i + k).is_some_and(|x| x.is_word() && x.lower() == *w))
}

// ---------- 1. voice commands ----------

fn commands(t: Vec<Tok>) -> Vec<Tok> {
    let mut out: Vec<Tok> = vec![];
    let mut i = 0;
    let boundary = |x: Option<&Tok>| x.is_none_or(|x| !x.is_word());
    while i < t.len() {
        // "new line" / "new paragraph", spoken as a phrase of its own (between punctuation or at either end)
        let br = if eq(&t, i, &["new", "paragraph"]) { Some(2) } else if eq(&t, i, &["new", "line"]) { Some(1) } else { None };
        if let Some(n) = br {
            if boundary(out.last()) && boundary(t.get(i + 2)) {
                while out.last().is_some_and(|x| x.is(",") || x.is(";")) {
                    out.pop();
                }
                out.push(Tok { text: String::new(), kind: Kind::Break(n), space: false });
                i += 2;
                while t.get(i).is_some_and(|x| x.kind == Kind::Punct && matches!(x.text.as_str(), "." | "," | ";" | ":")) {
                    i += 1;
                }
                continue;
            }
        }
        // "scratch that": removes the sentence (or clause after the last sentence end) before it. Only when the
        // phrase stands alone: "scratch that idea" is content.
        if eq(&t, i, &["scratch", "that"]) && t.get(i + 2).is_none_or(|x| x.kind == Kind::Punct && matches!(x.text.as_str(), "." | "," | "!" | ";" | ":")) {
            while out.last().is_some_and(|x| x.kind == Kind::Punct && matches!(x.text.as_str(), "," | ";" | ":" | "-" | "—")) {
                out.pop();
            }
            if out.last().is_some_and(|x| x.kind == Kind::Punct && matches!(x.text.as_str(), "." | "!" | "?")) {
                out.pop();
            }
            while out.last().is_some_and(|x| !x.ends_sentence()) {
                out.pop();
            }
            i += 2;
            while t.get(i).is_some_and(|x| x.kind == Kind::Punct && matches!(x.text.as_str(), "." | "," | "!" | ";" | ":")) {
                i += 1;
            }
            continue;
        }
        out.push(t[i].clone());
        i += 1;
    }
    out
}

// ---------- 2. fillers and stutters ----------

pub(crate) const FILLERS: &[&str] = &["um", "umm", "uh", "uhh", "uhm", "er", "erm", "hmm", "hm", "mm", "mmm"];
const EXTENDED: &[&[&str]] = &[&["you", "know"], &["i", "mean"], &["like"], &["sort", "of"], &["kind", "of"]];
/// Words people stumble on; other repeats ("very very", "had had", "that that") are left alone.
const STUTTER: &[&str] = &["the", "a", "an", "i", "to", "and", "we", "it", "in", "of", "you", "my", "they", "he", "she", "but", "is", "for", "with", "on"];

fn fillers(t: Vec<Tok>, o: &Options) -> Vec<Tok> {
    let mut out: Vec<Tok> = vec![];
    let mut i = 0;
    while i < t.len() {
        let x = &t[i];
        let len = if x.is_word() && FILLERS.contains(&x.lower().as_str()) {
            1
        } else if o.extended_fillers {
            // only when set off by a comma: "it was, like, huge" but not "I like it"
            EXTENDED.iter().find(|p| eq(&t, i, p) && t.get(i + p.len()).is_some_and(|n| n.is(","))).map_or(0, |p| p.len())
        } else {
            0
        };
        if len > 0 {
            i += len;
            let at_start = out.last().is_none_or(|l| l.ends_sentence());
            if t.get(i).is_some_and(|n| n.is(",")) {
                i += 1; // "Um, so" -> "So"
            } else if at_start {
                while t.get(i).is_some_and(|n| n.is(".") || n.is("…")) {
                    i += 1; // "Um... So"
                }
            } else if out.last().is_some_and(|l| l.is(",")) && t.get(i).is_none_or(|n| n.ends_sentence()) {
                out.pop(); // "We went, um." -> "We went."
            }
            continue; // the next word keeps its own spacing; a leading space is never rendered
        }
        if x.is_word() && STUTTER.contains(&x.lower().as_str()) && t.get(i + 1).is_some_and(|n| n.is_word() && n.lower() == x.lower()) {
            i += 1; // "the the" -> "the"
            continue;
        }
        out.push(x.clone());
        i += 1;
    }
    out
}

// ---------- 3. numbers ----------

const SMALL: &[&str] = &[
    "zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten", "eleven", "twelve", "thirteen", "fourteen", "fifteen", "sixteen", "seventeen",
    "eighteen", "nineteen",
];
const TENS: &[&str] = &["", "", "twenty", "thirty", "forty", "fifty", "sixty", "seventy", "eighty", "ninety"];
const ORD_SMALL: &[&str] = &[
    "zeroth", "first", "second", "third", "fourth", "fifth", "sixth", "seventh", "eighth", "ninth", "tenth", "eleventh", "twelfth", "thirteenth", "fourteenth",
    "fifteenth", "sixteenth", "seventeenth", "eighteenth", "nineteenth",
];
const ORD_TENS: &[&str] = &["", "", "twentieth", "thirtieth", "fortieth", "fiftieth", "sixtieth", "seventieth", "eightieth", "ninetieth"];
const MONTHS: &[&str] = &["january", "february", "march", "april", "may", "june", "july", "august", "september", "october", "november", "december"];
/// Measurements and data sizes: always digits ("5 kilometres"). Durations count as plain counts ("three days").
const UNITS: &[&str] = &[
    "km", "kilometre", "kilometres", "kilometer", "kilometers", "metre", "metres", "meter", "meters", "cm", "centimetre", "centimetres", "mm", "millimetre", "millimetres",
    "mile", "miles", "mph", "kph", "inch", "inches", "foot", "feet", "yard", "yards", "kg", "kilo", "kilos", "kilogram", "kilograms", "gram", "grams", "pound-weight",
    "stone", "litre", "litres", "liter", "liters", "ml", "millilitre", "millilitres", "degree", "degrees", "celsius", "fahrenheit", "kb", "mb", "gb", "tb", "kilobytes",
    "megabytes", "gigabytes", "terabytes", "bytes", "megapixels", "volts", "watts", "kw", "kwh", "hz", "mhz", "ghz", "x",
];

fn small(w: &str) -> Option<u64> {
    SMALL.iter().position(|x| *x == w).map(|v| v as u64)
}
fn tens(w: &str) -> Option<u64> {
    TENS.iter().position(|x| !x.is_empty() && *x == w).map(|v| v as u64 * 10)
}
fn ordinal(w: &str) -> Option<u64> {
    ORD_SMALL.iter().position(|x| *x == w).map(|v| v as u64).or_else(|| ORD_TENS.iter().position(|x| !x.is_empty() && *x == w).map(|v| v as u64 * 10))
}
fn digit_word(w: &str) -> Option<u64> {
    if w == "oh" { Some(0) } else { small(w).filter(|v| *v < 10) }
}
fn number_word(w: &str) -> bool {
    small(w).is_some() || tens(w).is_some() || matches!(w, "hundred" | "thousand" | "million" | "billion")
}
fn suffix(n: u64) -> &'static str {
    match (n % 10, n % 100) {
        (_, 11..=13) => "th",
        (1, _) => "st",
        (2, _) => "nd",
        (3, _) => "rd",
        _ => "th",
    }
}
fn group(n: u64) -> String {
    let s = n.to_string();
    if n < 10_000 {
        return s;
    }
    let mut out = String::new();
    for (k, ch) in s.chars().enumerate() {
        if k > 0 && (s.len() - k) % 3 == 0 {
            out.push(',');
        }
        out.push(ch);
    }
    out
}

/// A spoken number starting at word `i`: (value, decimal digits, ordinal, words used). Hyphenated words
/// ("twenty-five") are split. Only whole words are used; anything unexpected ends the number.
fn parse(t: &[Tok], i: usize) -> Option<(u64, String, bool, usize)> {
    // words with hyphen parts, remembering which token each part came from
    let mut parts: Vec<(String, usize)> = vec![];
    let mut k = i;
    while let Some(x) = t.get(k) {
        if !x.is_word() {
            break;
        }
        let ws: Vec<String> = x.lower().split('-').map(String::from).collect();
        if !ws.iter().all(|w| number_word(w) || ordinal(w).is_some() || matches!(w.as_str(), "and" | "a" | "point" | "oh")) {
            break;
        }
        for w in ws {
            parts.push((w, k));
        }
        k += 1;
    }
    let (mut total, mut cur, mut ord, mut dec) = (0u64, 0u64, false, String::new());
    let mut last = "";
    let mut j = 0;
    while j < parts.len() {
        let w = parts[j].0.as_str();
        let next = parts.get(j + 1).map(|p| p.0.as_str()).unwrap_or("");
        if w == "a" {
            if j == 0 && matches!(next, "hundred" | "thousand" | "million") {
                cur = 1;
                last = "a";
                j += 1;
                continue;
            }
            break;
        }
        if let Some(v) = small(w) {
            let ok = matches!(last, "" | "hundred" | "thousand" | "million" | "billion" | "and") || (TENS.contains(&last) && v < 10 && v > 0);
            if !ok {
                break;
            }
            cur += v;
        } else if let Some(v) = tens(w) {
            if !matches!(last, "" | "hundred" | "thousand" | "million" | "billion" | "and") {
                break;
            }
            cur += v;
        } else if w == "hundred" {
            if !(cur < 100 && (cur > 0 || last == "a")) || last == "hundred" {
                break;
            }
            cur = cur.max(1) * 100;
        } else if let Some(m) = match w {
            "thousand" => Some(1_000),
            "million" => Some(1_000_000),
            "billion" => Some(1_000_000_000),
            _ => None,
        } {
            if cur == 0 && last != "a" {
                break;
            }
            total += cur.max(1) * m;
            cur = 0;
        } else if w == "and" {
            // "two hundred and five", never "three and four"
            if !(matches!(last, "hundred" | "thousand" | "million" | "billion") && (small(next).is_some() || tens(next).is_some())) {
                break;
            }
        } else if let Some(v) = ordinal(w) {
            let ok = matches!(last, "" | "hundred" | "thousand" | "million" | "and") || (TENS.contains(&last) && v < 10 && v > 0);
            if !ok {
                break;
            }
            cur += v;
            ord = true;
            last = w;
            j += 1;
            break;
        } else if w == "point" {
            if last == "" || last == "and" {
                break;
            }
            let mut d = String::new();
            let mut m = j + 1;
            while let Some(v) = parts.get(m).and_then(|p| digit_word(&p.0)) {
                d.push_str(&v.to_string());
                m += 1;
            }
            if d.is_empty() {
                break;
            }
            dec = d;
            j = m;
            last = "point";
            break;
        } else {
            break; // "oh" outside a decimal or time
        }
        last = w;
        j += 1;
    }
    if last == "" || last == "a" || last == "and" {
        return None;
    }
    // trailing "and" is not part of the number
    while j > 0 && parts[j - 1].0 == "and" {
        j -= 1;
    }
    // a number must end on a whole token
    if j < parts.len() && j > 0 && parts[j].1 == parts[j - 1].1 {
        return None;
    }
    let used = if j == 0 { 0 } else { parts[j - 1].1 + 1 - i };
    Some((total + cur, dec, ord, used))
}

/// "twenty twenty six", "nineteen ninety nine", "twenty oh five": a year, as (year, words used).
fn year(t: &[Tok], i: usize) -> Option<(u64, usize)> {
    let (a, _, ord_a, la) = parse(t, i)?;
    if ord_a || !(a == 19 || a == 20) || la != 1 {
        return None;
    }
    if eq(t, i + 1, &["oh"]) {
        let (b, _, ord_b, lb) = parse(t, i + 2)?;
        return (!ord_b && b < 10).then_some((a * 100 + b, 2 + lb));
    }
    let (b, dec, ord_b, lb) = parse(t, i + 1)?;
    (!ord_b && dec.is_empty() && (10..100).contains(&b)).then_some((a * 100 + b, 1 + lb))
}

fn numbers(t: Vec<Tok>, o: &Options) -> Vec<Tok> {
    let mut out: Vec<Tok> = vec![];
    let mut i = 0;
    let low = |k: usize| t.get(k).filter(|x| x.is_word()).map(|x| x.lower()).unwrap_or_default();
    let month = |k: usize| MONTHS.iter().position(|m| *m == low(k));
    let cap = |s: &str| s[..1].to_uppercase() + &s[1..];
    // A year or day number after a month, spoken or as digits: (text, tokens used).
    let year_at = |k: usize| -> Option<(String, usize)> {
        let k2 = if t.get(k).is_some_and(|x| x.is(",")) { k + 1 } else { k };
        if let Some((y, l)) = year(&t, k2) {
            return Some((y.to_string(), k2 - k + l));
        }
        if let Some((v, d, false, l)) = parse(&t, k2) {
            if d.is_empty() && (1000..2100).contains(&v) {
                return Some((v.to_string(), k2 - k + l));
            }
        }
        t.get(k2).filter(|x| x.is_word() && x.text.len() == 4 && x.text.chars().all(|c| c.is_ascii_digit())).map(|x| (x.text.clone(), k2 - k + 1))
    };
    let day_at = |k: usize| -> Option<(u64, usize)> {
        if let Some((v, d, _, l)) = parse(&t, k) {
            return (d.is_empty() && (1..=31).contains(&v)).then_some((v, l));
        }
        // "5th" or "5"
        let w = t.get(k).filter(|x| x.is_word())?.lower();
        let digits: String = w.chars().take_while(|c| c.is_ascii_digit()).collect();
        let rest = &w[digits.len()..];
        let v: u64 = digits.parse().ok()?;
        ((1..=31).contains(&v) && matches!(rest, "" | "st" | "nd" | "rd" | "th")).then_some((v, 1))
    };
    while i < t.len() {
        let x = &t[i];
        if !x.is_word() {
            out.push(x.clone());
            i += 1;
            continue;
        }
        // Dates: "the fifth of March [twenty twenty six]" / "March fifth [, 2026]" -> "5 March 2026"
        let the = eq(&t, i, &["the"]) as usize;
        if let Some((d, l)) = day_at(i + the).filter(|_| the == 1 || ordinal(&low(i + the)).is_some() || low(i + the).ends_with(|c: char| c.is_alphabetic())) {
            let of = eq(&t, i + the + l, &["of"]) as usize;
            if let Some(m) = month(i + the + l + of) {
                let mut text = format!("{d} {}", cap(MONTHS[m]));
                let mut used = the + l + of + 1;
                if let Some((y, ly)) = year_at(i + used) {
                    text = format!("{text} {y}");
                    used += ly;
                }
                out.push(Tok::word(text, x.space));
                i += used;
                continue;
            }
        }
        if let Some(m) = month(i) {
            if let Some((d, l)) = day_at(i + 1) {
                let mut text = format!("{d} {}", cap(MONTHS[m]));
                let mut used = 1 + l;
                if let Some((y, ly)) = year_at(i + used) {
                    text = format!("{text} {y}");
                    used += ly;
                }
                out.push(Tok::word(text, x.space));
                i += used;
                continue;
            }
        }
        // Years: "in twenty twenty six"
        if let Some((y, l)) = year(&t, i) {
            out.push(Tok::word(y.to_string(), x.space));
            i += l;
            continue;
        }
        let Some((v, dec, ord, l)) = parse(&t, i) else {
            out.push(x.clone());
            i += 1;
            continue;
        };
        let after = i + l;
        let num = if dec.is_empty() { group(v) } else { format!("{v}.{dec}") };
        let n1 = low(after);
        // Times: "three thirty pm", "ten pm"
        let marker = |w: &str| matches!(w, "am" | "pm" | "a.m" | "p.m");
        if !ord && dec.is_empty() && (1..=12).contains(&v) {
            if marker(&n1) {
                out.push(Tok::word(v.to_string(), x.space));
                i = after;
                continue;
            }
            let (mins, lm) = if eq(&t, after, &["oh"]) {
                parse(&t, after + 1).filter(|m| !m.2 && m.1.is_empty() && m.0 < 10).map_or((None, 0), |m| (Some(m.0), m.3 + 1))
            } else {
                parse(&t, after).filter(|m| !m.2 && m.1.is_empty() && (10..60).contains(&m.0)).map_or((None, 0), |m| (Some(m.0), m.3))
            };
            if let Some(m) = mins.filter(|_| marker(&low(after + lm))) {
                out.push(Tok::word(format!("{v}:{m:02}"), x.space));
                i = after + lm;
                continue;
            }
        }
        if !ord {
            // Percent
            if n1 == "percent" || (n1 == "per" && low(after + 1) == "cent") {
                out.push(Tok::word(num, x.space));
                out.push(Tok::punct("%", false));
                i = after + if n1 == "per" { 2 } else { 1 };
                continue;
            }
            // Money: "five pounds [fifty]", "twenty dollars", "fifty pence"
            let sym = match n1.as_str() {
                "pound" | "pounds" | "quid" => Some("£"),
                "dollar" | "dollars" => Some("$"),
                "euro" | "euros" => Some("€"),
                _ => None,
            };
            if let Some(sym) = sym {
                let (cents, lc) = match parse(&t, after + 1) {
                    Some((c, d, false, lc)) if d.is_empty() && c < 100 && dec.is_empty() => (Some(c), lc),
                    _ => (None, 0),
                };
                out.push(Tok::punct(sym, x.space));
                out.push(Tok::word(match cents { Some(c) => format!("{num}.{c:02}"), None => num }, false));
                i = after + 1 + lc;
                continue;
            }
            if matches!(n1.as_str(), "pence" | "p") && dec.is_empty() && v < 100 {
                out.push(Tok::word(format!("{v}p"), x.space));
                i = after + 1;
                continue;
            }
            // Measurements: always digits, unit as spoken
            if UNITS.contains(&n1.as_str()) {
                out.push(Tok::word(num, x.space));
                i = after;
                continue;
            }
        }
        // Two numbers in a row ("three thirty", "one two three") without a context above: leave them as spoken
        if parse(&t, after).is_some() {
            let mut end = after;
            while let Some((_, _, _, l2)) = parse(&t, end) {
                end += l2;
            }
            out.extend(t[i..end].iter().cloned());
            i = end;
            continue;
        }
        // Ordinals: first to ninth stay words; 10th and above become digits
        if ord {
            if v < 10 {
                out.extend(t[i..after].iter().cloned());
            } else {
                out.push(Tok::word(format!("{v}{}", suffix(v)), x.space));
            }
            i = after;
            continue;
        }
        // Plain counts
        let keep_words = dec.is_empty() && v < 10 && (o.small_numbers_as_words || v < 2);
        if keep_words {
            out.extend(t[i..after].iter().cloned());
        } else {
            out.push(Tok::word(num, x.space));
        }
        i = after;
    }
    out
}

// ---------- 4. capitalisation ----------

/// A full stop after these does not end a sentence.
const ABBREV: &[&str] = &["a.m", "p.m", "e.g", "i.e", "mr", "mrs", "ms", "dr", "vs"];

fn capitalise(mut t: Vec<Tok>) -> Vec<Tok> {
    let mut start = true;
    let mut prev = String::new();
    for x in t.iter_mut() {
        if x.is_word() {
            let l = x.lower();
            if l == "i" || l.starts_with("i'") {
                x.text.replace_range(..1, "I");
            }
            if start {
                let mut c = x.text.chars();
                if let Some(f) = c.next() {
                    x.text = f.to_uppercase().chain(c).collect();
                }
            }
            start = false;
            prev = x.lower();
        } else if x.ends_sentence() && !(x.is(".") && ABBREV.contains(&prev.as_str())) {
            start = true;
        }
    }
    t
}

// ---------- 5. writing style (Clean mode only) ----------

#[derive(Clone, Copy, Debug, PartialEq, Default, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum FinalStop {
    /// Leave the engine's punctuation as it is.
    #[default]
    Keep,
    /// End with a full stop.
    Always,
    /// No full stop at the end of a one-sentence message.
    Never,
}

/// What a writing style changes. The presets are Professional, Formal, Casual and Concise; Custom is any mix.
#[derive(Clone, Copy, Debug, PartialEq, Default, serde::Serialize, serde::Deserialize)]
#[serde(default)]
pub struct Style {
    /// "gonna" -> "going to", "yeah" -> "yes" and similar spoken forms.
    pub written_forms: bool,
    /// "don't" -> "do not", "I'm" -> "I am"; only contractions with one meaning ("it's" and "I'd" are left alone).
    pub expand_contractions: bool,
    /// "in order to" -> "to", "due to the fact that" -> "because".
    pub shorten_phrases: bool,
    /// "basically,", "actually," and similar hedges set off by commas.
    pub drop_hedges: bool,
    pub final_stop: FinalStop,
}

impl Style {
    /// None for "standard" (no changes beyond Clean) and unknown names.
    pub fn preset(name: &str) -> Option<Style> {
        let d = Style::default();
        match name {
            "professional" => Some(Style { written_forms: true, final_stop: FinalStop::Always, ..d }),
            "formal" => Some(Style { written_forms: true, expand_contractions: true, final_stop: FinalStop::Always, ..d }),
            "casual" => Some(Style { final_stop: FinalStop::Never, ..d }),
            "concise" => Some(Style { shorten_phrases: true, drop_hedges: true, ..d }),
            _ => None,
        }
    }
}

const WRITTEN: &[(&str, &str)] = &[
    ("gonna", "going to"), ("wanna", "want to"), ("kinda", "kind of"), ("sorta", "sort of"), ("dunno", "don't know"),
    ("lemme", "let me"), ("gimme", "give me"), ("yeah", "yes"), ("yep", "yes"), ("yup", "yes"), ("nope", "no"), ("nah", "no"),
];
const CONTRACTIONS: &[(&str, &str)] = &[
    ("don't", "do not"), ("doesn't", "does not"), ("didn't", "did not"), ("can't", "cannot"), ("won't", "will not"),
    ("isn't", "is not"), ("aren't", "are not"), ("wasn't", "was not"), ("weren't", "were not"), ("haven't", "have not"),
    ("hasn't", "has not"), ("hadn't", "had not"), ("couldn't", "could not"), ("shouldn't", "should not"),
    ("wouldn't", "would not"), ("mustn't", "must not"), ("needn't", "need not"), ("shan't", "shall not"),
    ("i'm", "I am"), ("you're", "you are"), ("we're", "we are"), ("they're", "they are"),
    ("i've", "I have"), ("you've", "you have"), ("we've", "we have"), ("they've", "they have"),
    ("i'll", "I will"), ("you'll", "you will"), ("we'll", "we will"), ("they'll", "they will"), ("he'll", "he will"),
    ("she'll", "she will"),
];
const PHRASES: &[(&[&str], &str)] = &[
    (&["due", "to", "the", "fact", "that"], "because"),
    (&["in", "spite", "of", "the", "fact", "that"], "although"),
    (&["at", "this", "point", "in", "time"], "now"),
    (&["at", "the", "present", "time"], "now"),
    (&["in", "the", "near", "future"], "soon"),
    (&["in", "the", "event", "that"], "if"),
    (&["for", "the", "purpose", "of"], "for"),
    (&["a", "large", "number", "of"], "many"),
    (&["with", "regard", "to"], "about"),
    (&["in", "order", "to"], "to"),
    (&["prior", "to"], "before"),
    (&["subsequent", "to"], "after"),
];
const HEDGES: &[&[&str]] = &[&["basically"], &["actually"], &["literally"], &["honestly"], &["to", "be", "honest"]];

/// Keeps a capital first letter when the replaced word had one ("Gonna" -> "Going to").
fn like_case(original: &str, replacement: &str) -> String {
    if original.chars().next().is_some_and(|c| c.is_uppercase()) {
        let mut c = replacement.chars();
        c.next().map(|f| f.to_uppercase().chain(c).collect()).unwrap_or_default()
    } else {
        replacement.to_string()
    }
}

fn style(t: Vec<Tok>, s: &Style) -> Vec<Tok> {
    let mut out: Vec<Tok> = vec![];
    let mut i = 0;
    while i < t.len() {
        let x = &t[i];
        if !x.is_word() {
            out.push(x.clone());
            i += 1;
            continue;
        }
        let l = x.lower();
        let at_start = out.last().is_none_or(|p| p.ends_sentence());
        if s.drop_hedges {
            if let Some(h) = HEDGES.iter().find(|h| eq(&t, i, h)) {
                let next = t.get(i + h.len());
                if next.is_some_and(|n| n.is(",")) {
                    i += h.len() + 1; // "Basically, it works" -> "it works" (capitalised later)
                    continue;
                }
                if out.last().is_some_and(|p| p.is(",")) && next.is_none_or(|n| n.ends_sentence()) {
                    out.pop(); // "It works, basically." -> "It works."
                    i += h.len();
                    continue;
                }
            }
        }
        if s.shorten_phrases {
            if let Some((p, r)) = PHRASES.iter().find(|(p, _)| eq(&t, i, p)) {
                out.push(Tok::word(like_case(&x.text, r), x.space));
                i += p.len();
                continue;
            }
        }
        if s.expand_contractions {
            if let Some((_, r)) = CONTRACTIONS.iter().find(|(c, _)| *c == l) {
                out.push(Tok::word(like_case(&x.text, r), x.space));
                i += 1;
                continue;
            }
        }
        if s.written_forms {
            if l == "gotta" {
                // "I've gotta go" -> "I've got to go"; "I gotta go" -> "I have to go"
                let after_have = out.last().is_some_and(|p| p.is_word() && (p.lower().ends_with("'ve") || matches!(p.lower().as_str(), "have" | "has")));
                out.push(Tok::word(like_case(&x.text, if after_have { "got to" } else { "have to" }), x.space));
                i += 1;
                continue;
            }
            if let Some((_, r)) = WRITTEN.iter().find(|(w, _)| *w == l) {
                out.push(Tok::word(like_case(&x.text, r), x.space));
                // "Yeah I'm in" -> "Yes, I'm in"
                if *r == "yes" && at_start && t.get(i + 1).is_some_and(|n| n.is_word()) {
                    out.push(Tok::punct(",", false));
                }
                i += 1;
                continue;
            }
        }
        out.push(x.clone());
        i += 1;
    }
    final_stop(out, s.final_stop)
}

fn final_stop(mut t: Vec<Tok>, f: FinalStop) -> Vec<Tok> {
    let Some(last) = t.iter().rposition(|x| !matches!(x.kind, Kind::Break(_))) else { return t };
    match f {
        FinalStop::Keep => {}
        FinalStop::Always => {
            let x = &t[last];
            // Snippet text goes in exactly as written, so nothing is added after it.
            let snippet = x.text.chars().any(crate::snippets::is_placeholder);
            if x.is_word() && !snippet {
                t.insert(last + 1, Tok::punct(".", false));
            } else if x.is(",") || x.is(";") || x.is(":") {
                t[last] = Tok::punct(".", false);
            }
        }
        FinalStop::Never => {
            // Only a one-sentence message on one line, ending in a plain full stop (not "etc." or "p.m.").
            let ends = t.iter().enumerate().filter(|(k, x)| x.ends_sentence() && !(x.is(".") && *k > 0 && ABBREV_END.contains(&t[k - 1].lower().as_str()))).count();
            let abbrev_before = last > 0 && ABBREV_END.contains(&t[last - 1].lower().as_str());
            if ends == 1 && t[last].is(".") && !abbrev_before {
                t.remove(last);
            }
        }
    }
    t
}

/// A full stop after these belongs to the word.
const ABBREV_END: &[&str] = &["a.m", "p.m", "e.g", "i.e", "mr", "mrs", "ms", "dr", "vs", "etc"];

#[cfg(test)]
mod tests {
    use super::*;

    fn c(s: &str) -> String {
        apply(s, &Options::default())
    }

    /// (spoken / engine text, Clean result)
    const CASES: &[(&str, &str)] = &[
        // untouched
        ("Hello, how are you?", "Hello, how are you?"),
        ("Let's meet at the station.", "Let's meet at the station."),
        ("I don't think so.", "I don't think so."),
        ("It's a well-known fact.", "It's a well-known fact."),
        ("No one came.", "No one came."),
        ("One of the best.", "One of the best."),
        ("At once, please.", "At once, please."),
        ("He said \"hello\" to me.", "He said \"hello\" to me."),
        ("Email me at jo@example.com today.", "Email me at jo@example.com today."),
        ("The meeting is at 3:30 p.m. tomorrow.", "The meeting is at 3:30 p.m. tomorrow."),
        ("We sold 1,200 units.", "We sold 1,200 units."),
        ("Version 2 is out.", "Version 2 is out."),
        ("That that is, is.", "That that is, is."),
        ("It was very very good.", "It was very very good."),
        ("He had had enough.", "He had had enough."),
        ("I like it.", "I like it."),
        ("You know the answer.", "You know the answer."),
        ("May I come in?", "May I come in?"),
        ("Second, we need a plan.", "Second, we need a plan."),
        ("I'll be there in a second.", "I'll be there in a second."),
        ("He came first.", "He came first."),
        ("Formula One is fast.", "Formula One is fast."),
        ("Three and four make seven.", "Three and four make seven."),
        ("Can you scratch that itch?", "Can you scratch that itch?"),
        ("Please scratch that idea from the list.", "Please scratch that idea from the list."),
        ("Start a new line of products.", "Start a new line of products."),
        ("The new paragraph style is nice.", "The new paragraph style is nice."),
        ("Ah, I see.", "Ah, I see."),
        // fillers
        ("Um, so we went home.", "So we went home."),
        ("So, um, we went home.", "So, we went home."),
        ("We went, uh, home.", "We went, home."),
        ("We went home, um.", "We went home."),
        ("Uh... I think so.", "I think so."),
        ("I think, er, it works.", "I think, it works."),
        ("Hmm, let me check.", "Let me check."),
        ("The the cat sat.", "The cat sat."),
        ("I I think so.", "I think so."),
        ("Um um, yes.", "Yes."),
        ("It was, like, huge.", "It was, like, huge."),
        // voice commands
        ("I want tea. Scratch that. I want coffee.", "I want coffee."),
        ("Hello there. I want tea, scratch that, I want coffee.", "Hello there. I want coffee."),
        ("Scratch that.", ""),
        ("Send it Friday, scratch that.", ""),
        ("Dear Sam. New paragraph. Thanks for the call.", "Dear Sam.\n\nThanks for the call."),
        ("First item, new line, second item.", "First item\nSecond item."),
        ("Hello new line world", "Hello new line world"),
        ("Line one. New line. Line two.", "Line one.\nLine two."),
        // numbers: plain counts
        ("I have three apples.", "I have three apples."),
        ("I have twenty five apples.", "I have 25 apples."),
        ("I have twenty-five apples.", "I have 25 apples."),
        ("About a hundred people came.", "About 100 people came."),
        ("Two hundred and five pages.", "205 pages."),
        ("It costs three thousand.", "It costs 3000."),
        ("Twelve thousand five hundred fans.", "12,500 fans."),
        ("Two million people.", "2,000,000 people."),
        ("It weighs three point five.", "It weighs 3.5."),
        ("Ten days later.", "10 days later."),
        ("Nine days later.", "Nine days later."),
        ("Hundreds of people.", "Hundreds of people."),
        ("It was the twenty first time.", "It was the 21st time."),
        ("The twelfth floor.", "The 12th floor."),
        ("The third floor.", "The third floor."),
        // percent and money
        ("Prices rose ten percent.", "Prices rose 10%."),
        ("Prices rose five per cent.", "Prices rose 5%."),
        ("Growth was three point two percent.", "Growth was 3.2%."),
        ("It costs five pounds.", "It costs £5."),
        ("It costs five pounds fifty.", "It costs £5.50."),
        ("It costs twenty dollars.", "It costs $20."),
        ("It costs fifty pence.", "It costs 50p."),
        ("Ten euros each.", "€10 each."),
        ("A thousand pounds.", "£1000."),
        // measurements
        ("I ran five kilometres.", "I ran 5 kilometres."),
        ("It has two gigabytes.", "It has 2 gigabytes."),
        ("Twenty degrees today.", "20 degrees today."),
        // times
        ("Meet at three thirty pm.", "Meet at 3:30 pm."),
        ("Meet at three pm.", "Meet at 3 pm."),
        ("Meet at ten fifteen a.m. tomorrow.", "Meet at 10:15 a.m. tomorrow."),
        ("Call at nine oh five am.", "Call at 9:05 am."),
        ("Three thirty works.", "Three thirty works."),
        // dates and years
        ("On the fifth of March.", "On 5 March."),
        ("On the fifth of March twenty twenty six.", "On 5 March 2026."),
        ("March fifth, 2026.", "5 March 2026."),
        ("On March 5th we start.", "On 5 March we start."),
        ("The 21st of June.", "21 June."),
        ("In twenty twenty six.", "In 2026."),
        ("Back in nineteen ninety nine.", "Back in 1999."),
        ("In two thousand and twenty six.", "In 2026."),
        ("In May we start.", "In May we start."),
        ("May the force be with you.", "May the force be with you."),
        // capitalisation and spacing
        ("i think i'm right.", "I think I'm right."),
        ("um, i'll go.", "I'll go."),
    ];

    #[test]
    fn rule_table() {
        let mut bad = vec![];
        for (input, want) in CASES {
            let got = c(input);
            if got != *want {
                bad.push(format!("{input:?}\n   want {want:?}\n   got  {got:?}"));
            }
        }
        assert!(bad.is_empty(), "{} of {} cases wrong:\n{}", bad.len(), CASES.len(), bad.join("\n"));
    }

    #[test]
    fn options() {
        let ext = Options { extended_fillers: true, ..Options::default() };
        assert_eq!(apply("It was, like, huge.", &ext), "It was, huge.");
        assert_eq!(apply("You know, it works.", &ext), "It works.");
        assert_eq!(apply("I like it.", &ext), "I like it.");
        assert_eq!(apply("I mean what I say.", &ext), "I mean what I say.");
        let digits = Options { small_numbers_as_words: false, ..Options::default() };
        assert_eq!(apply("I have three apples.", &digits), "I have 3 apples.");
        assert_eq!(apply("No one came.", &digits), "No one came.");
    }

    #[test]
    fn verbatim_text_without_rules_is_unchanged_by_tokenising() {
        for (input, _) in CASES {
            let t = tokenize(input);
            assert_eq!(render(&t), input.trim(), "tokenise/render must round-trip");
        }
    }

    /// Clean must not hurt accuracy: word error rate on the benchmark clips (Base Q5_1 transcripts saved by the
    /// benchmark) with and without Clean. Needs the benchmark kit on D:, so it is run by hand:
    /// cargo test --release clean_keeps_accuracy -- --ignored --nocapture
    #[test]
    #[ignore]
    fn clean_keeps_accuracy() {
        let kit = std::path::Path::new(r"D:\AI Projects\Tools\bench");
        let clips: serde_json::Value = serde_json::from_slice(&std::fs::read(kit.join(r"audio\clips.json")).unwrap()).unwrap();
        let words = |s: &str| -> Vec<String> {
            s.to_lowercase().chars().map(|c| if c.is_alphanumeric() || c == '\'' { c } else { ' ' }).collect::<String>().split_whitespace().map(String::from).collect()
        };
        let errors = |r: &[String], h: &[String]| -> usize {
            let mut d: Vec<usize> = (0..=h.len()).collect();
            for i in 1..=r.len() {
                let mut prev = d[0];
                d[0] = i;
                for j in 1..=h.len() {
                    let cur = d[j];
                    d[j] = (d[j] + 1).min(d[j - 1] + 1).min(prev + (r[i - 1] != h[j - 1]) as usize);
                    prev = cur;
                }
            }
            d[h.len()]
        };
        let (mut n, mut e_raw, mut e_clean, mut changed) = (0, 0, 0, vec![]);
        for line in std::fs::read_to_string(kit.join(r"results\whisper.jsonl")).unwrap().lines() {
            let r: serde_json::Value = serde_json::from_str(line).unwrap();
            if !r["model"].as_str().unwrap().ends_with("ggml-base.en-q5_1.bin") || r["run"] != 0 || r["short_ctx"] != false || r["threads"] != 4 {
                continue;
            }
            let clip = clips.as_array().unwrap().iter().find(|c| c["file"].as_str().unwrap().replace(".wav", ".f32") == r["clip"].as_str().unwrap()).unwrap();
            let reference = words(clip["reference"].as_str().unwrap());
            let raw = r["text"].as_str().unwrap();
            let clean = c(raw);
            n += reference.len();
            e_raw += errors(&reference, &words(raw));
            e_clean += errors(&reference, &words(&clean));
            if clean != raw {
                changed.push(format!("  {raw}\n  -> {clean}"));
            }
        }
        println!("{n} words: raw {e_raw} errors, Clean {e_clean} errors; Clean changed {} transcripts:\n{}", changed.len(), changed.join("\n"));
        assert!(n > 0);
        assert!(e_clean <= e_raw, "Clean added errors");
    }

    #[test]
    fn fast_enough() {
        // about 60 seconds of speech (150 words), the plan's budget
        let long = "Um, so I think we should, er, meet at three thirty pm on the fifth of March twenty twenty six and spend about twenty five pounds. ".repeat(6);
        // best of three: one run can be slowed by other tests running in parallel or by battery power saving
        let best = (0..3)
            .map(|_| {
                let t = std::time::Instant::now();
                let _ = c(&long);
                t.elapsed()
            })
            .min()
            .unwrap();
        assert!(best.as_millis() < 5, "{best:?}");
    }
}

#[cfg(test)]
mod style_tests {
    use super::*;

    fn run(style_name: &str, s: &str) -> String {
        apply_styled(s, &Options::default(), Style::preset(style_name).as_ref())
    }

    /// (style, engine text, result)
    const CASES: &[(&str, &str, &str)] = &[
        // standard: Clean only
        ("standard", "yeah I'm gonna send it tomorrow", "Yeah I'm gonna send it tomorrow"),
        ("standard", "I don't know.", "I don't know."),
        // professional
        ("professional", "yeah I'm gonna send it tomorrow", "Yes, I'm going to send it tomorrow."),
        ("professional", "Yeah, that works.", "Yes, that works."),
        ("professional", "I wanna help.", "I want to help."),
        ("professional", "I gotta go.", "I have to go."),
        ("professional", "I've gotta go.", "I've got to go."),
        ("professional", "It's kinda late.", "It's kind of late."),
        ("professional", "It's sorta done.", "It's sort of done."),
        ("professional", "I dunno.", "I don't know."),
        ("professional", "Lemme check.", "Let me check."),
        ("professional", "Gimme a minute.", "Give me a minute."),
        ("professional", "Nope, not yet.", "No, not yet."),
        ("professional", "Yep.", "Yes."),
        ("professional", "Gonna be late.", "Going to be late."),
        ("professional", "Thanks for the update", "Thanks for the update."),
        ("professional", "Thanks for the update!", "Thanks for the update!"),
        ("professional", "Is it ready?", "Is it ready?"),
        ("professional", "See you at 3 p.m.", "See you at 3 p.m."),
        ("professional", "Thanks,", "Thanks."),
        ("professional", "I don't know.", "I don't know."),
        ("professional", "The Gonna Show is on.", "The Going to Show is on."),
        ("professional", "Okay, sounds good.", "Okay, sounds good."),
        // formal
        ("formal", "yeah I'm gonna send it tomorrow", "Yes, I am going to send it tomorrow."),
        ("formal", "I don't know.", "I do not know."),
        ("formal", "Don't worry.", "Do not worry."),
        ("formal", "We can't attend.", "We cannot attend."),
        ("formal", "It won't work.", "It will not work."),
        ("formal", "They're here and we've started.", "They are here and we have started."),
        ("formal", "I'll call, you'll see.", "I will call, you will see."),
        ("formal", "She'll know and he'll agree.", "She will know and he will agree."),
        ("formal", "It isn't, it wasn't, they weren't.", "It is not, it was not, they were not."),
        ("formal", "I haven't, it hasn't, we hadn't.", "I have not, it has not, we had not."),
        ("formal", "You couldn't, shouldn't or wouldn't.", "You could not, should not or would not."),
        ("formal", "It's done.", "It's done."),
        ("formal", "I'd like that.", "I'd like that."),
        ("formal", "Let's go.", "Let's go."),
        ("formal", "That's Jo's car.", "That's Jo's car."),
        ("formal", "I\u{2019}m here.", "I am here."),
        ("formal", "You\u{2019}re right", "You are right."),
        // casual
        ("casual", "Sounds good.", "Sounds good"),
        ("casual", "See you soon.", "See you soon"),
        ("casual", "Are you coming?", "Are you coming?"),
        ("casual", "That's great!", "That's great!"),
        ("casual", "Yes. See you soon.", "Yes. See you soon."),
        ("casual", "Bring snacks, drinks, etc.", "Bring snacks, drinks, etc."),
        ("casual", "Meet at 3 p.m.", "Meet at 3 p.m."),
        ("casual", "Sounds good", "Sounds good"),
        ("casual", "yeah I'm gonna send it tomorrow.", "Yeah I'm gonna send it tomorrow"),
        // concise
        ("concise", "We left early in order to catch the train.", "We left early to catch the train."),
        ("concise", "Due to the fact that it rained, we stayed.", "Because it rained, we stayed."),
        ("concise", "At this point in time we wait.", "Now we wait."),
        ("concise", "In the event that it fails, call me.", "If it fails, call me."),
        ("concise", "We will hire in the near future.", "We will hire soon."),
        ("concise", "A large number of people came.", "Many people came."),
        ("concise", "I wrote with regard to the invoice.", "I wrote about the invoice."),
        ("concise", "Check prior to sending.", "Check before sending."),
        ("concise", "Basically, it works.", "It works."),
        ("concise", "It works, basically.", "It works."),
        ("concise", "Actually, I agree.", "I agree."),
        ("concise", "To be honest, it's fine.", "It's fine."),
        ("concise", "It actually works.", "It actually works."),
        ("concise", "Literally nothing changed.", "Literally nothing changed."),
        ("concise", "The order to proceed came.", "The order to proceed came."),
        // styles never touch Clean's own work or protected text
        ("formal", "um I don't have twenty five pounds", "I do not have £25."),
        ("casual", "Scratch that. Sounds good.", "Sounds good"),
    ];

    #[test]
    fn style_table() {
        let bad: Vec<String> = CASES
            .iter()
            .filter(|(st, i, w)| run(st, i) != *w)
            .map(|(st, i, w)| format!("[{st}] {i:?}\n   want {w:?}\n   got  {:?}", run(st, i)))
            .collect();
        assert!(bad.is_empty(), "{} of {} wrong:\n{}", bad.len(), CASES.len(), bad.join("\n"));
    }

    #[test]
    fn protected_text_is_left_alone() {
        // a dictionary term and a snippet placeholder survive every style
        let d = crate::dictionary::Matcher::new(&[crate::dictionary::Entry { id: 1, kind: "word".into(), term: "Gonna Labs".into(), replacement: None, uses: 0 }]);
        let (t, w, _) = d.apply("i work at gonna labs, don't i", true);
        let out = crate::dictionary::restore(&apply_styled(&t, &Options::default(), Style::preset("formal").as_ref()), &w);
        assert_eq!(out, "I work at Gonna Labs, do not I.");
        let snip = crate::snippets::Matcher::new(&[crate::snippets::Snippet { id: 1, trigger: "my address".into(), body: "1 High St\nLondon".into(), mode: "whole".into(), uses: 0 }]);
        let clock = crate::snippets::Clock { year: 2026, month: 11, day: 20, weekday: 5, hour: 9, minute: 0 };
        let (t, b, _) = snip.apply("My address.", &clock);
        let out = crate::snippets::restore(&apply_styled(&t, &Options::default(), Style::preset("professional").as_ref()), &b);
        assert_eq!(out, "1 High St\nLondon", "no full stop added after snippet text");
    }

    #[test]
    fn standard_and_unknown_change_nothing_beyond_clean() {
        for s in ["Yeah I'm gonna go.", "um it works, basically", "Don't."] {
            assert_eq!(run("standard", s), apply(s, &Options::default()));
            assert_eq!(apply_styled(s, &Options::default(), Style::preset("nonsense").as_ref()), apply(s, &Options::default()));
        }
    }

    #[test]
    fn style_is_fast() {
        let long = "Yeah I'm gonna say that due to the fact that we can't, basically, we won't in order to save time. ".repeat(7);
        let all = Style { written_forms: true, expand_contractions: true, shorten_phrases: true, drop_hedges: true, final_stop: FinalStop::Always };
        // Clean and the style together stay within Clean's 5 ms budget for a minute of speech (measured 2.4-3.9 ms on
        // battery power on the development PC); best of three, so a cold first run does not fail it
        let best = (0..3)
            .map(|_| {
                let t = std::time::Instant::now();
                let _ = apply_styled(&long, &Options::default(), Some(&all));
                t.elapsed()
            })
            .min()
            .unwrap();
        assert!(best.as_millis() < 5, "{best:?}");
    }
}
