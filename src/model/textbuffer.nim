import std/[strutils, unicode, sequtils]
import cursor

type
  TextBuffer* = ref object
    name*: string
    fullPath*: string
    dirty: bool
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

proc getLineOfRune(tb: TextBuffer, l: int): seq[Rune] =
  return tb.lineList[l]
  
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
    let origText = tb.getLineOfRune(line)
    let leftPart = origText[0..<col]
    let rightPart = origText[col..<origText.len]
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
        tb.lineList[line] = theLine[0..<c] & newLines[0] & theLine[c..<theLine.len]
        return (dline: 0, dcol: newLines[0].len)
      of 2:
        tb.lineList[line] &= newLines[0]
        if line == tb.lineCount()-1:
          tb.lineList.add(newLines[1])
        else:
          tb.lineList[line+1] &= newLines[1]
        return (dline: 1, dcol: newLines[1].len)
      else:
        tb.lineList[line] &= newLines[0]
        tb.lineList.insert(newLines[1..<newLines.len-1], line+1)
        let lastLineY = (line+1+newLines.len-2)
        tb.lineList[lastLineY] = newLines[^1] & tb.lineList[lastLineY]
        # we should be safe when the code for handling case when `newLine.len`
        # is 0 is technically wrong.
        return (dline: newLines.len-1, dcol: newLines[^1].len)
    
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
      tb.lineList.delete(startLine+1..lastLine)
    else:
      tb.lineList.delete(startLine+1..<lastLine)

proc getRange*(tb: TextBuffer, start: Cursor, last: Cursor): seq[Rune] =
  let (startLine, startCol) = tb.resolvePosition(start)
  let (lastLine, lastCol) = tb.resolvePosition(last)
  if startLine == lastLine:
    return tb.lineList[startLine][startCol..<lastCol]
  else:
    var res: seq[Rune] = @[]
    let startSeq = tb.getLineOfRune(startLine)
    if startSeq.len > 0:
      res &= startSeq[startCol..<startSeq.len]
    var i = startLine + 1
    if i < tb.lineCount() and i < lastLine:
      res.add("\n".runeAt(0))
      while i < tb.lineCount() and i < lastLine:
        res &= tb.getLineOfRune(i)
        res.add("\n".runeAt(0))
        i += 1
    if lastLine < tb.lineCount():
      res.add("\n".runeAt(0))
      if lastCol > 0:
        res &= tb.getLineOfRune(lastLine)[0..<lastCol]
    return res
    
proc getRangeString*(tb: TextBuffer, start: Cursor, last: Cursor): string =
  return $tb.getRange(start, last)
  
