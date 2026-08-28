.pragma library

// Row building and matching for the cheatsheet overlay.
//
// The overlay renders one flat ListView rather than a nested section/entry
// structure, because a flat model is what makes "j/k moves to the next entry,
// skipping headers" and "scroll position survives a filter change" simple. So
// everything here returns rows of either { type: "section" } or
// { type: "entry" }, and the view just draws whatever it is handed.

function normalize(text) {
  return String(text === undefined || text === null ? "" : text).toLowerCase()
}

// Tokens are matched independently and in any order, so "next tab", "tab next"
// and "tb nxt" all find "Next tab". Order-independence matters more than it
// sounds: you rarely remember a description in the words its author chose.
function tokenize(query) {
  var parts = normalize(query).split(/\s+/)
  var out = []
  for (var i = 0; i < parts.length; i++) {
    if (parts[i].length > 0) out.push(parts[i])
  }
  return out
}

// Subsequence match — "dckr" matches "docker". Only used when the plain
// substring test fails, so exact typing is never penalised by fuzzy noise.
function subsequence(needle, haystack) {
  var n = 0
  for (var h = 0; h < haystack.length && n < needle.length; h++) {
    if (haystack[h] === needle[n]) n++
  }
  return n === needle.length
}

// Returns a score, or -1 for no match. Higher is better.
// A hit in the key chord beats a hit in the description, and an early hit beats
// a late one, so searching "stash" puts `git stash` above a line that merely
// mentions stashing.
function scoreEntry(entry, tokens, sectionTitle, sheetName) {
  if (tokens.length === 0) return 0

  var keys = normalize(entry.keys)
  var desc = normalize(entry.desc)
  var section = normalize(sectionTitle)
  var sheet = normalize(sheetName)
  var total = 0

  for (var i = 0; i < tokens.length; i++) {
    var token = tokens[i]
    var best = -1

    var atKeys = keys.indexOf(token)
    if (atKeys !== -1) best = 100 - Math.min(atKeys, 40)

    var atDesc = desc.indexOf(token)
    if (atDesc !== -1) best = Math.max(best, 70 - Math.min(atDesc, 40))

    if (section.indexOf(token) !== -1) best = Math.max(best, 25)
    if (sheet.indexOf(token) !== -1) best = Math.max(best, 20)

    if (best === -1) {
      if (subsequence(token, keys)) best = 12
      else if (subsequence(token, desc)) best = 8
      else return -1
    }

    total += best
  }

  // Whole-query hits on a short key chord are almost always what was wanted.
  var whole = tokens.join(" ")
  if (keys === whole) total += 200
  else if (keys.indexOf(whole) === 0) total += 60
  else if (desc.indexOf(whole) === 0) total += 30

  return total
}

// Unfiltered view of one sheet: every section, every entry, original order.
function sheetRows(sheet) {
  var rows = []
  if (!sheet || !sheet.sections) return rows

  for (var s = 0; s < sheet.sections.length; s++) {
    var section = sheet.sections[s]
    rows.push({ type: "section", title: section.title, sheet: "" })
    for (var e = 0; e < section.entries.length; e++) {
      rows.push({
        type: "entry",
        keys: section.entries[e].keys,
        desc: section.entries[e].desc,
        sheet: sheet.name,
        section: section.title
      })
    }
  }
  return rows
}

// Filtered view across every sheet. Results are grouped by sheet, the active
// one first, so a search never hides what you were already looking at — while
// still surfacing the answer when it turns out to live under another tool.
function searchRows(sheets, query, activeId, limit) {
  var tokens = tokenize(query)
  var rows = []
  if (!sheets || sheets.length === 0 || tokens.length === 0) return rows

  var groups = []
  var kept = 0

  for (var i = 0; i < sheets.length; i++) {
    var sheet = sheets[i]
    var hits = []

    for (var s = 0; s < sheet.sections.length; s++) {
      var section = sheet.sections[s]
      for (var e = 0; e < section.entries.length; e++) {
        var entry = section.entries[e]
        var score = scoreEntry(entry, tokens, section.title, sheet.name)
        if (score < 0) continue
        hits.push({
          type: "entry",
          keys: entry.keys,
          desc: entry.desc,
          sheet: sheet.name,
          section: section.title,
          score: score
        })
      }
    }

    if (hits.length === 0) continue
    hits.sort(function(a, b) { return b.score - a.score })
    groups.push({ id: sheet.id, name: sheet.name, icon: sheet.icon, hits: hits })
  }

  groups.sort(function(a, b) {
    if (a.id === activeId) return -1
    if (b.id === activeId) return 1
    return b.hits[0].score - a.hits[0].score
  })

  var cap = limit || 400
  for (var g = 0; g < groups.length && kept < cap; g++) {
    var group = groups[g]
    rows.push({
      type: "section",
      title: group.name + "  ·  " + group.hits.length
             + (group.hits.length === 1 ? " match" : " matches"),
      sheet: group.name
    })
    for (var h = 0; h < group.hits.length && kept < cap; h++) {
      rows.push(group.hits[h])
      kept++
    }
  }

  return rows
}

// Index of the first selectable row, i.e. the first thing that isn't a header.
function firstEntry(rows) {
  for (var i = 0; i < rows.length; i++) {
    if (rows[i].type === "entry") return i
  }
  return -1
}

// Move `delta` entries from `from`, stepping over section headers and stopping
// at the ends rather than wrapping — wrapping in a long list loses your place.
function step(rows, from, delta) {
  if (rows.length === 0) return -1
  var direction = delta > 0 ? 1 : -1
  var remaining = Math.abs(delta)
  var index = from
  var last = index

  while (remaining > 0) {
    index += direction
    while (index >= 0 && index < rows.length && rows[index].type !== "entry") {
      index += direction
    }
    if (index < 0 || index >= rows.length) return last
    last = index
    remaining--
  }
  return last
}
