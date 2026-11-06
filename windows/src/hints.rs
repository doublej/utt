//! A port of `UttCore/Text/TranscriptHints.swift`: correct a transcript against words the
//! caller knew were coming. Deliberately conservative — a hint only displaces text that is
//! already nearly it and starts with the same letter, never merely similar text.

/// How far a word may be from a hint and still be taken for it, scaled by the hint's length.
fn tolerance(length: usize) -> usize {
    match length {
        0..=2 => 0,
        3..=5 => 1,
        _ => 2,
    }
}

/// The most words one hint may be spread across ("deck hand" → "deckhand").
const MAXIMUM_WINDOW: usize = 3;

struct Word {
    text: String,
    separator: String,
}

struct Match {
    replacement: String,
    length: usize,
    distance: usize,
}

/// `text` with each near-miss replaced by the hint it was reaching for.
pub fn apply(text: &str, hints: &[String]) -> String {
    let terms: Vec<&str> = hints
        .iter()
        .map(|hint| hint.trim())
        .filter(|hint| !hint.is_empty() && normalized(hint).chars().count() >= 2)
        .collect();
    if terms.is_empty() {
        return text.to_string();
    }
    let words = split(text);
    if words.is_empty() {
        return text.to_string();
    }
    let mut result = String::new();
    let mut index = 0;
    while index < words.len() {
        if let Some(found) = best_match(&words, index, &terms) {
            result.push_str(&found.replacement);
            result.push_str(&words[index + found.length - 1].separator);
            index += found.length;
            continue;
        }
        result.push_str(&words[index].text);
        result.push_str(&words[index].separator);
        index += 1;
    }
    result
}

fn best_match(words: &[Word], index: usize, terms: &[&str]) -> Option<Match> {
    let mut best: Option<Match> = None;
    for length in 1..=MAXIMUM_WINDOW {
        if index + length > words.len() {
            break;
        }
        let window: Vec<&str> = words[index..index + length]
            .iter()
            .map(|w| w.text.as_str())
            .collect();
        let (prefix, core, suffix) = trimmed(&window.join(" "));
        let candidate = normalized(&core);
        if candidate.is_empty() {
            continue;
        }
        for term in terms {
            let target = normalized(term);
            // Already spelled the way the caller spells it: leave it, casing and all.
            if core == *term {
                return None;
            }
            if candidate.chars().next() != target.chars().next() {
                continue;
            }
            let distance = edit_distance(&candidate, &target);
            if distance > tolerance(target.chars().count()) {
                continue;
            }
            let better = match &best {
                None => true,
                Some(b) => distance < b.distance || (distance == b.distance && length > b.length),
            };
            if better {
                best = Some(Match {
                    replacement: format!("{prefix}{term}{suffix}"),
                    length,
                    distance,
                });
            }
        }
    }
    best
}

fn is_part(c: char) -> bool {
    c.is_alphanumeric()
}

/// The punctuation around a window, and the term inside it.
fn trimmed(window: &str) -> (String, String, String) {
    let chars: Vec<char> = window.chars().collect();
    let start = chars
        .iter()
        .position(|&c| is_part(c))
        .unwrap_or(chars.len());
    let end = chars
        .iter()
        .rposition(|&c| is_part(c))
        .map_or(start, |i| i + 1)
        .max(start);
    let take = |range: std::ops::Range<usize>| chars[range].iter().collect::<String>();
    (take(0..start), take(start..end), take(end..chars.len()))
}

/// Letters and digits, lowercased.
fn normalized(value: &str) -> String {
    value
        .to_lowercase()
        .chars()
        .filter(|&c| is_part(c))
        .collect()
}

/// Levenshtein, two rows rather than a matrix.
fn edit_distance(lhs: &str, rhs: &str) -> usize {
    let left: Vec<char> = lhs.chars().collect();
    let right: Vec<char> = rhs.chars().collect();
    if left.is_empty() {
        return right.len();
    }
    if right.is_empty() {
        return left.len();
    }
    let mut previous: Vec<usize> = (0..=right.len()).collect();
    let mut current = vec![0; right.len() + 1];
    for row in 1..=left.len() {
        current[0] = row;
        for column in 1..=right.len() {
            current[column] = if left[row - 1] == right[column - 1] {
                previous[column - 1]
            } else {
                previous[column - 1]
                    .min(previous[column])
                    .min(current[column - 1])
                    + 1
            };
        }
        std::mem::swap(&mut previous, &mut current);
    }
    previous[right.len()]
}

/// A word and whatever whitespace followed it, so the text can be rebuilt exactly.
fn split(text: &str) -> Vec<Word> {
    let mut words = Vec::new();
    let (mut word, mut separator) = (String::new(), String::new());
    for c in text.chars() {
        if c.is_whitespace() {
            separator.push(c);
        } else {
            if !separator.is_empty() {
                words.push(Word {
                    text: std::mem::take(&mut word),
                    separator: std::mem::take(&mut separator),
                });
            }
            word.push(c);
        }
    }
    if !word.is_empty() || !separator.is_empty() {
        words.push(Word {
            text: word,
            separator,
        });
    }
    words
}

#[cfg(test)]
mod tests {
    use super::apply;

    fn hints(list: &[&str]) -> Vec<String> {
        list.iter().map(|s| s.to_string()).collect()
    }

    #[test]
    fn a_split_compound_is_joined() {
        assert_eq!(
            apply("open deck hand now", &hints(&["deckhand"])),
            "open deckhand now"
        );
    }

    #[test]
    fn a_mishearing_with_the_same_onset_is_corrected_and_punctuation_kept() {
        assert_eq!(
            apply("the cockwheel, please", &hints(&["cogwheel"])),
            "the cogwheel, please"
        );
    }

    #[test]
    fn a_different_onset_is_left_alone() {
        assert_eq!(apply("a free tree", &hints(&["tree"])), "a free tree");
    }

    #[test]
    fn short_terms_must_match_exactly_and_casing_is_the_callers() {
        assert_eq!(apply("the tu y works", &hints(&["TUI"])), "the TUI works");
        assert_eq!(apply("TUI", &hints(&["TUI"])), "TUI");
    }
}
