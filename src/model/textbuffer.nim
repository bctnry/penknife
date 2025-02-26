import std/[strutils, unicode, sequtils]
import cursor
import ../ui/[tvfont, sdl2_ui_utils]
import ../aux

type
  TextBuffer* = ref object
    name*: string
    fullPath*: string
    dirty*: bool
    lineList: seq[seq[Rune]]

proc fromString*(s: string, fp: string = ""): TextBuffer =
  var r: seq[seq[Rune]] = @[]
  for k in s.split("\n"):
    r.add(k.toRunes)
  return TextBuffer(fullPath: fp, lineList: r)

proc toString*(tb: TextBuffer): string =
  var r: seq[string] = @[]
  for k in tb.lineList: r.add($k)
  return r.join("\n")

proc lineCount*(tb: TextBuffer): int =
  return tb.lineList.len

proc getLineOfRune*(tb: TextBuffer, l: int): seq[Rune] =
  return tb.lineList[l]

proc canonicalLineWidth*(tb: TextBuffer, i: int): int =
  return 0
  
proc getLine*(tb: TextBuffer, l: int): string =
  return $tb.getLineOfRune(l)

proc getLineLength*(tb: TextBuffer, l: int): int =
  return tb.getLineOfRune(l).len

proc isDirty*(tb: TextBuffer): bool =
  return tb.dirty

proc resetDirtyState*(tb: TextBuffer): void =
  tb.dirty = false

proc getName*(tb: TextBuffer): string =
  return tb.name
  
proc resolvePosition*(tb: TextBuffer, line: int, col: int): tuple[line: int, col: int]

# three kind of sizes are called as follow:
# byte size - size in bytes (in utf8). in this system 1 cjk character is of size 3.
# grid size - size in units of width. in this system half-width characters are of
#             size 1 and full-width characters are of size 2.
# canonical size - size in unicode codepoints. in this system every character is
#                  of size 1.
proc canonicalXToGridX*(tb: TextBuffer, x: int, y: int): int =
  let (line, col) = tb.resolvePosition(y, x)
  if line == tb.lineCount(): return 0
  if tb.getLineOfRune(line).len <= 0: return 0
  var r = 0
  var i = 0
  let l = tb.getLineOfRune(line)
  while i < col:
    let k = l[i]
    if k.isFullWidth: r += 2 else: r += 1
    i += 1
  return r
proc gridXToCanonicalX*(tb: TextBuffer, x: int, y: int): int =
  if y == tb.lineCount(): return 0
  if tb.getLineOfRune(y).len <= 0: return 0
  var r = 0
  var i = 0
  var j = x
  let l = tb.getLineOfRune(y)
  while j > 0 and i < tb.getLineOfRune(y).len:
    let canSize = if l[i].isFullWidth: 2 else: 1
    if j < canSize: j = canSize
    j -= canSize
    if j == 2: break
    i += 1
  return i
proc canonicalXToGridX*(tb: TextBuffer, font: TVFont, x: int, y: int): int =
  let (line, col) = tb.resolvePosition(y, x)
  if line == tb.lineCount(): return 0
  if tb.getLineOfRune(line).len <= 0: return 0
  var r = 0
  var i = 0
  let l = tb.getLineOfRune(line)
  while i < col:
    let k = l[i]
    if k.isFullWidthByFont(font): r += 2 else: r += 1
    i += 1
  return r
proc gridXToCanonicalX*(tb: TextBuffer, font: TVFont, x: int, y: int): int =
  if y == tb.lineCount(): return 0
  if tb.getLineOfRune(y).len <= 0: return 0
  var i = 0
  var j = x
  let l = tb.getLineOfRune(y)
  while j > 0 and i < tb.getLineOfRune(y).len:
    let canSize = if l[i].isFullWidthByFont(font): 2 else: 1
    if j == 1 and canSize == 2: break
    j -= canSize
    i += 1
  return i

proc insert*(tb: TextBuffer, l: int, c: int, ch: char): tuple[dline: int, dcol: int] =
  tb.dirty = true
  let (line, col) = tb.resolvePosition(l, c)
  if ch == '\n':
    if line == tb.lineCount():  # end of document
      tb.lineList.add("".toRunes)
      return
    let origText = tb.getLineOfRune(line)
    let leftPart = origText[0..<col]
    let rightPart = origText[col..<origText.len]
    tb.lineList[line] = leftPart
    tb.lineList.insert(rightPart, line+1)
    return (dline: 1, dcol: 0)
  else:
    if line == tb.lineCount():  # end of document
      # we follow emacs's behaviour here: adding a character at the end of a
      # document creates a new line.
      tb.lineList.add("".toRunes)
    tb.lineList[line].insert(ch.Rune, col)
    return (dline: 0, dcol: 1)

proc insert*(tb: TextBuffer, l: int, c: int, s: string): tuple[dline: int, dcol: int] =
  tb.dirty = true
  let (line, col) = tb.resolvePosition(l, c)
  if line >= tb.lineCount():
    let ll = s.split("\n")
    for k in ll:
      tb.lineList.add(k.toRunes)
    return (dline: ll.len, dcol: 0)
  else:
    var theLine = tb.lineList[line]
    var newLines: seq[seq[Rune]] = @[]
    for k in s.split("\n"):
      newLines.add(k.toRunes)
    case newLines.len:
      of 0:
        return (dline: 0, dcol: 0)
      of 1:
        tb.lineList[line] = theLine[0..<col] & newLines[0] & theLine[col..<theLine.len]
        return (dline: 0, dcol: newLines[0].len)
      of 2:
        tb.lineList[line] = theLine[0..<col] & newLines[0]
        if line == tb.lineCount()-1:
          tb.lineList.add(newLines[1] & theLine[col..<theLine.len])
        else:
          let oldLine = tb.lineList[line+1]
          tb.lineList[line+1] = newLines[1] & theLine[col..<theLine.len]
          tb.lineList.insert(oldLine, line+2)
        return (dline: 1, dcol: newLines[1].len)
      else:
        let dcol = newLines[^1].len
        tb.lineList[line] = theLine[0..<col] & newLines[0]
        if line+1 >= tb.lineCount():
          for k in newLines[1..^1]:
            tb.lineList.add(k)
          tb.lineList[^1] &= theLine[col..<theLine.len]
        else:
          let oldcol = newLines[newLines.len-1].len
          newLines[newLines.len-1] &= theLine[col..<theLine.len]
          tb.lineList.insert(newLines[1..<newLines.len], line+1)
          # we should be safe when the code for handling case when `newLine.len`
          # is 0 is technically wrong.
        return (dline: newLines.len-1, dcol: dcol)

proc insert*(tb: TextBuffer, l: int, c: int, s: seq[Rune]): tuple[dline: int, dcol: int] =
  # TODO: find a better way to do all of this.
  let ss = $s
  return tb.insert(l, c, ss)
    
proc resolvePosition*(tb: TextBuffer, line: int, col: int): tuple[line: int, col: int] =#
  ## Return value ranges from (0, 0) to (tb.lineCount(), 0)
  # We need to have the very end be (tb.lineCount(), 0). Consider this:
  #         "abcdef"
  #     0   abcdef$      --> last char (0, 5)
  #         *                ends at (0, 6) ~ (1, 0)
  #     ----------------------------------
  #         "abcdef\n"
  #     0   abcdef
  #     1   $            --> last char (0, 6) ~ (1, 0)
  #                          (since line 0 col range is 0 ~ 5)
  #     2   *                ends at (1, 1) ~ (2, 0)
  var targetLine = line
  var targetCol = col
  if line < 0: return (line: 0, col: 0)
  if line >= tb.lineCount(): return (line: tb.lineCount(), col: 0)
  if col < 0:
    targetLine -= 1
    if targetLine < 0: return (line: 0, col: 0)
    targetCol = -targetCol
    while targetCol > 0:
      let currentLineLength = tb.getLineLength(targetLine)
      if currentLineLength < targetCol:
        targetCol -= currentLineLength
        targetLine -= 1
        if targetLine < 0: return (line: 0, col: 0)
      else:
        return (line: targetLine, col: currentLineLength - targetCol)
  elif col > tb.getLineLength(targetLine):
    while targetCol > tb.getLineLength(targetLine):
      targetCol -= tb.getLineLength(targetLine)
      targetLine += 1
      if targetLine >= tb.lineCount(): return (line: tb.lineCount(), col: 0)
    return (line: targetLine, col: targetCol)
  else:
    return (line: line, col: col)

proc resolvePosition*(tb: TextBuffer, c: Cursor): tuple[line: int, col: int] =
  return tb.resolvePosition(c.y.cint, c.x.cint)

proc clip*(tb: TextBuffer, line: int, col: int): tuple[line: int, col: int] =
  # the difference between this and `resolvePosition` is that this function
  # just "clips" locations instead of resolving them. e.g. if in your session
  # line 23 only has 16 characters, `resolvePosition` (23, 20) would count
  # that to the next line, i.e. resulting in (24, 4) (and if line 24 has
  # less than 4 characters then it would continue onto line 25 etc..) but
  # `clip` would only returns (23, 16).
  if line < 0: return (line: 0, col: 0)
  elif line >= tb.lineCount(): return (line: tb.lineCount(), col: 0)
  elif col < 0: return (line: line, col: 0)
  elif col >= tb.getLineLength(line): return (line: line, col: tb.getLineLength(line))
  else: return (line: line, col: col)

proc clip*(tb: TextBuffer, c: Cursor): tuple[line: int, col: int] =
  return tb.clip(c.y.int, c.x.int)
  
# Backspacing and deleting a character is technically the same kind
# of operation done at different locations, with deleting being
# equivalent to backspacing from the next char and backspacing being
# equivalent to deleting from the previous char. This is written this
# way because we implement TextBuffer as a sequence of texts with with 
# backspacing and deleting has different edge cases.
proc backspaceChar*(tb: TextBuffer, l: int, c: int): void =
  tb.dirty = true
  var (line, col) = tb.resolvePosition(l, c)
  if line == 0 and col == 0: return
  if line == tb.lineCount():
    line -= 1
    col = tb.getLineLength(line)
  var ltext = tb.getLineOfRune(line)
  if col == 0:
    tb.lineList.delete(line)
    tb.lineList[line-1] = tb.lineList[line-1] & ltext
  else:
    tb.lineList[line] = ltext[0..<col-1] & ltext[col..<ltext.len]

proc deleteChar*(tb: TextBuffer, l: int, c: int): void =
  tb.dirty = true
  let (line, col) = tb.resolvePosition(l, c)
  if line > tb.lineCount(): return
  var ltext = tb.getLineOfRune(line)
  if col == ltext.len():
    if line+1 >= tb.lineCount(): return
    var nltext = tb.getLineOfRune(line+1)
    tb.lineList.delete(line+1)
    tb.lineList[line] &= nltext
  else:
    tb.lineList[line] = ltext[0..<col] & ltext[col+1..<ltext.len]
  
proc delete*(tb: TextBuffer, start: Cursor, last: Cursor): void =
  tb.dirty = true
  let (startLine, startCol) = tb.resolvePosition(start)
  let (lastLine, lastCol) = tb.resolvePosition(last)
  # requires start <= last.
  if startLine == lastLine:
    if startCol < lastCol:
      tb.lineList[startLine].delete(startCol..<lastCol)
  else:
    var startSeq = tb.getLineOfRune(startLine)
    if startCol < startSeq.len:
      tb.lineList[startLine].delete(startCol..<startSeq.len)
    if lastLine < tb.lineCount():
      # we move the last line onto the first line first.
      let lastSeqLen = tb.lineList[lastLine].len
      if lastCol < lastSeqLen:
        tb.lineList[startLine] &= tb.lineList[lastLine][lastCol..<lastSeqLen]
    if lastLine < tb.lineCount():
      # when `startLine+1 == lastLine` (i.e. the range spans over 2 lines) the
      # line below covers this case since deleting `startLine+1..lastLine` would
      # delete `startLine+1` which is the same as `lastLine`. this is different
      # in the case when `lastLine >= tb.lineCount()`, however; since we can't
      # delete the line at `lastLine` (which in this case would be the same as
      # `tb.lineCount()` which would be outside of the actual data range) we
      # have to delete `..<lastLine` which would be invalid when there is only
      # two lines (i.e. `startLine+1 == lastLine`.
      tb.lineList.delete(startLine+1..lastLine)
    else:
      if startLine+1 < lastLine:
        tb.lineList.delete(startLine+1..<lastLine)

proc getRange*(tb: TextBuffer, start: Cursor, last: Cursor): seq[Rune] =
  let (startLine, startCol) = tb.resolvePosition(start)
  let (lastLine, lastCol) = tb.resolvePosition(last)
  if startLine == lastLine:
    return tb.lineList[startLine][startCol..<lastCol]
  var res: seq[Rune] = @[]
  let startSeq = tb.getLineOfRune(startLine)
  if startSeq.len > 0:
    res &= startSeq[startCol..<startSeq.len]
  res.add("\n".runeAt(0))
  var i = startLine + 1
  if i < tb.lineCount() and i < lastLine:
    while i < tb.lineCount() and i < lastLine:
      res &= tb.getLineOfRune(i)
      res.add("\n".runeAt(0))
      i += 1
  if lastLine < tb.lineCount():
    res &= tb.getLineOfRune(lastLine)[0..<lastCol]
  else:
    discard res.pop()
  return res
    
proc getRangeString*(tb: TextBuffer, start: Cursor, last: Cursor): string =
  return $tb.getRange(start, last)
  
