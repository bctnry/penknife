import std/unicode
import cursor
import textbuffer
import selection
import viewport
import undoredo

# the gap between the linenumber panel and the viewport. (grid)
const VIEWPORT_GAP*: cint = 2

type
  EditSession* = ref object
    textBuffer*: TextBuffer
    viewPort*: ViewPort
    # NOTE: selection remains non-nil at all time to (try to) prevent frequent
    # small object allcation.
    selection*: LinearSelection
    selectionInEffect*: bool
    cursor*: Cursor
    undoRedoStack*: UndoRedoStack
    onCursorMove*: proc (oldX: cint, oldY: cint): void

proc mkEditSession*(): EditSession =
  return EditSession(
    cursor: mkNewCursor(),
    textBuffer: "".fromString,
    viewport: mkNewViewPort(),
    selection: LinearSelection(
      first: Cursor(x: 0, y: 0, expectingX: 0),
      last: Cursor(x: 0, y: 0, expectingX: 0)
    ),
    selectionInEffect: false,
    undoRedoStack: mkUndoRedoStack(),
    onCursorMove: nil
  )

proc syncViewPort*(st: EditSession): void =
  # move viewport to the place where the cursor can be seen.
  if st.cursor.x < st.viewPort.x: st.viewPort.x = st.cursor.x
  elif st.cursor.x >= st.viewPort.x + st.viewPort.w:
    st.viewPort.x = st.cursor.x - st.viewPort.w + 1
  if st.cursor.y < st.viewPort.y:
    st.viewPort.y = st.cursor.y
  elif st.cursor.y >= st.viewPort.y + st.viewPort.h:
    st.viewPort.y = st.cursor.y - st.viewPort.h + 1

proc cursorLeft*(st: EditSession): void =
  let oldX = st.cursor.x
  let oldY = st.cursor.y
  if st.cursor.x > 0:
    st.cursor.x -= 1
    st.cursor.expectingX = st.cursor.x
  else:
    # if cursor.x = 0 and user choose to go left
    # check if there is prev line
    # if yes:
    if st.cursor.y > 0:
      # goto prev line. but we move pass 1 char so minus 1
      let prevLineLen = st.textBuffer.getLineOfRune(st.cursor.y-1).len
      st.cursor.x = prevLineLen.cint
      st.cursor.expectingX = st.cursor.x
      st.cursor.y -= 1
    # if no: do nothing
  st.syncViewPort()
  if not st.onCursorMove.isNil: st.onCursorMove(oldX, oldY)

proc cursorRight*(st: EditSession): void =
  let oldX = st.cursor.x
  let oldY = st.cursor.y
  var cursor = st.cursor
  # if at end-of-document
  if cursor.y >= st.textBuffer.lineCount(): return
  # if at line end
  if cursor.x >= st.textBuffer.getLineOfRune(cursor.y).len:
    # if there is next line
    if cursor.y < st.textBuffer.lineCount()-1:
      # set x to one over the first char
      cursor.x = 0.cint
      cursor.expectingX = cursor.x
      # set y to next line
      cursor.y += 1
    # if no next line then do nothing.
  # if not at line end
  else:
    # update x
    cursor.x += 1
    cursor.expectingX = cursor.x
  st.syncViewPort()
  if not st.onCursorMove.isNil: st.onCursorMove(oldX, oldY)

proc cursorUp*(st: EditSession): void =
  let oldX = st.cursor.x
  let oldY = st.cursor.y
  var cursor = st.cursor
  # if has prev line
  if cursor.y > 0:
    # if prev line is not as long
    if st.textBuffer.getLine(cursor.y-1).len <= cursor.expectingX:
      # set x at end of prev line
      cursor.x = st.textBuffer.getLineOfRune(cursor.y-1).len.cint
    # else we set cursor x at expected x
    else:
      cursor.x = cursor.expectingX
    # update cursor y
    cursor.y -= 1
    st.syncViewPort()
    if not st.onCursorMove.isNil: st.onCursorMove(oldX, oldY)
  # else: do nothing.

proc cursorDown*(st: EditSession): void =
  let oldX = st.cursor.x
  let oldY = st.cursor.y
  var cursor = st.cursor
  if cursor.y < st.textBuffer.lineCount():
    # if next line is end-of-document:
    if cursor.y+1 == st.textBuffer.lineCount():
      cursor.x = 0
    # else, if next line is not as long:
    elif st.textBuffer.getLine(cursor.y+1).len <= cursor.expectingX:
      # set x at end of next line
      cursor.x = st.textBuffer.getLineOfRune(cursor.y+1).len.cint
    # else we set cursor x at expected x
    else:
      cursor.x = cursor.expectingX
    # update cursor y
    cursor.y += 1
    st.syncViewPort()
    if not st.onCursorMove.isNil: st.onCursorMove(oldX, oldY)

proc setCursor*(st: EditSession, line: int, col: int): void =
  let oldX = st.cursor.x
  let oldY = st.cursor.y
  var cursor = st.cursor
  cursor.x = col.cint
  cursor.y = line.cint
  st.selection.first.x = col.cint
  st.selection.first.y = line.cint
  st.syncViewPort()
  if not st.onCursorMove.isNil: st.onCursorMove(oldX, oldY)

proc invalidateSelectedState*(st: EditSession): void =
  st.selectionInEffect = false

proc setSelectionFirstPoint*(st: EditSession, firstX: int, firstY: int): void =
  st.selection.first.x = firstX.cint
  st.selection.first.y = firstY.cint

proc startSelection*(st: EditSession, firstX: int, firstY: int): void =
  st.selectionInEffect = true
  st.selection.first.x = firstX.cint
  st.selection.first.y = firstY.cint
  
proc setSelectionLastPoint*(st: EditSession, lastX: int, lastY: int): void =
  st.selection.last.x = lastX.cint
  st.selection.last.y = lastY.cint

proc getCurrentSelection*(st: EditSession): seq[Rune] =
  if not st.selectionInEffect: return @[]
  let start = min(st.selection.first, st.selection.last)
  let last = max(st.selection.first, st.selection.last)
  return st.textBuffer.getRange(start, last)

proc getExecutableSource*(st: EditSession): seq[Rune] =
  if st.selectionInEffect: return st.getCurrentSelection()
  let y = st.cursor.y
  let line = st.textBuffer.getLineOfRune(y)
  if line[st.cursor.x].isWhiteSpace(): return @[]
  var start = st.cursor.x
  while start >= 0 and (not line[start].isWhiteSpace()): start -= 1
  start += 1
  var last = st.cursor.x
  while last < line.len and (not line[last].isWhiteSpace()): last += 1
  last -= 1
  return line[start..last]
  
proc relayout*(st: EditSession, gridWidth: cint, gridHeight: cint): void =
  st.viewPort.w = gridWidth
  st.viewPort.h = gridHeight

proc resetCurrentCursor*(tb: EditSession): void =
  let oldX = tb.cursor.x
  let oldY = tb.cursor.y
  let (line, col) = tb.textBuffer.resolvePosition(tb.cursor)
  tb.cursor.y = line.cint
  tb.cursor.x = col.cint
  if not tb.onCursorMove.isNil: tb.onCursorMove(oldX, oldY)

proc verticalScroll*(st: EditSession, n: int): void =
  # n positive: up, n negative: down.
  let newViewPortY = max(0, min(st.viewPort.y-n, st.textBuffer.lineCount()-1))
  st.viewPort.y = newViewPortY.cint

proc horizontalScroll*(st: EditSession, n: int): void =
  # n positive: right, n negative: left
  if st.cursor.y < st.textBuffer.lineCount():
    let newViewPortX = max(0, st.viewPort.x-n)
    st.viewPort.x = newViewPortX.cint
  
proc gotoLineStart*(st: EditSession): void =
  let oldX = st.cursor.x
  st.cursor.x = 0
  st.cursor.expectingX = 0
  st.syncViewPort()
  if not st.onCursorMove.isNil: st.onCursorMove(oldX, st.cursor.y)
  
proc gotoLineEnd*(st: EditSession): void =
  if st.cursor.y < st.textBuffer.lineCount():
    let oldX = st.cursor.x
    st.cursor.x = st.textBuffer.getLineLength(st.cursor.y).cint
    st.cursor.expectingX = st.cursor.x
    st.syncViewPort()
    if not st.onCursorMove.isNil: st.onCursorMove(oldX, st.cursor.y)

proc undo(tb: TextBuffer, ur: UndoRedoPiece): void =
  case ur.kind:
    of UR_DELETE:
      discard tb.insert(ur.postPosition.y, ur.postPosition.x, ur.data)
    of UR_INSERT:
      let start = ur.postPosition
      let last = ur.postPosition.advanceWith(ur.data)
      tb.delete(start, last)

proc redo(tb: TextBuffer, ur: UndoRedoPiece): void =
  case ur.kind:
    of UR_DELETE:
      let start = ur.postPosition
      let last = ur.postPosition.advanceWith(ur.data)
      tb.delete(start, last)
    of UR_INSERT:
      discard tb.insert(ur.postPosition.y, ur.postPosition.x, ur.data)
    
proc undo*(stk: UndoRedoStack, tb: TextBuffer): void =
  if stk.i < 0: return
  let p = stk.pieces[stk.i]
  tb.undo(p)
  stk.i -= 1

proc redo*(stk: UndoRedoStack, tb: TextBuffer): void =
  if stk.i >= stk.pieces.len-1: return
  let p = stk.pieces[stk.i+1]
  tb.redo(p)
  stk.i += 1
    
proc recordInsertAction*(es: EditSession, position: Cursor, data: seq[Rune]): void =
  let stk = es.undoRedoStack
  if stk.i < stk.pieces.len-1:
    for _ in 0..<stk.pieces.len-1 - stk.i:
      discard stk.pieces.pop()
  stk.pieces.add(UndoRedoPiece(kind: UR_INSERT, postPosition: position.clone(), data: data))
  stk.i = stk.pieces.len-1

proc recordDeleteAction*(es: EditSession, position: Cursor, data: seq[Rune]): void =
  let stk = es.undoRedoStack
  if stk.i < stk.pieces.len-1:
    for _ in 0..<stk.pieces.len-1 - stk.i:
      discard stk.pieces.pop()
  stk.pieces.add(UndoRedoPiece(kind: UR_DELETE, postPosition: position.clone(), data: data))
  stk.i = stk.pieces.len-1
  
    
