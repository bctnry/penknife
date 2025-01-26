import cursor
import textbuffer
import selection
import viewport

type
  EditSession* = ref object
    textBuffer*: TextBuffer
    viewPort*: ViewPort
    # NOTE: selection remains non-nil at all time to (try to) prevent frequent
    # small object allcation.
    selection*: LinearSelection
    selectionInEffect*: bool
    cursor*: Cursor

proc mkEditSession*(): EditSession =
  return EditSession(
    cursor: mkNewCursor(),
    viewPort: mkNewViewPort(),
    textBuffer: "".fromString,
    selection: LinearSelection(
      first: Cursor(x: 0, y: 0, expectingX: 0),
      last: Cursor(x: 0, y: 0, expectingX: 0)
    ),
    selectionInEffect: false
  )

proc syncViewPort*(es: EditSession): void =
  # move viewport to the place where the cursor can be seen.
  if es.cursor.x < es.viewPort.x:
    es.viewPort.x = es.cursor.x
  elif es.cursor.x >= es.viewPort.x + es.viewPort.w:
    es.viewPort.x = es.cursor.x - es.viewPort.w + 1
  if es.cursor.y < es.viewPort.y:
    es.viewPort.y = es.cursor.y
  elif es.cursor.y >= es.viewPort.y + es.viewPort.h:
    es.viewPort.y = es.cursor.y - es.viewPort.h + 1

proc cursorLeft*(es: EditSession): void =
  if es.cursor.x > 0:
    es.cursor.x -= 1
    es.cursor.expectingX = es.cursor.x
  else:
    # if cursor.x = 0 and user choose to go left
    # check if there is prev line
    # if yes:
    if es.cursor.y > 0:
      # goto prev line. but we move pass 1 char so minus 1
      let prevLineLen = es.textBuffer.getLine(es.cursor.y-1).len
      es.cursor.x = prevLineLen.cint
      es.cursor.expectingX = es.cursor.x
      es.cursor.y -= 1
    # if no: do nothing
  es.syncViewPort()

proc cursorRight*(es: EditSession): void =
  var cursor = es.cursor
  # if at end-of-document
  if cursor.y >= es.textBuffer.lineCount(): return
  # if at line end
  if cursor.x >= es.textBuffer.getLine(cursor.y).len:
    # if there is next line
    if cursor.y < es.textBuffer.lineCount()-1:
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
  es.syncViewPort()
  
proc cursorUp*(es: EditSession): void =
  var cursor = es.cursor
  # if has prev line
  if cursor.y > 0:
    # if prev line is not as long
    if es.textBuffer.getLine(cursor.y-1).len <= cursor.expectingX:
      # set x at end of prev line
      cursor.x = es.textBuffer.getLine(cursor.y-1).len.cint
    # else we set cursor x at expected x
    else:
      cursor.x = cursor.expectingX
    # update cursor y
    cursor.y -= 1
    es.syncViewPort()
  # else: do nothing.

proc cursorDown*(es: EditSession): void =
  var cursor = es.cursor
  if cursor.y < es.textBuffer.lineCount():
    # if next line is end-of-document:
    if cursor.y+1 == es.textBuffer.lineCount():
      cursor.x = 0
    # else, if next line is not as long:
    elif es.textBuffer.getLine(cursor.y+1).len <= cursor.expectingX:
      # set x at end of next line
      cursor.x = es.textBuffer.getLine(cursor.y+1).len.cint
    # else we set cursor x at expected x
    else:
      cursor.x = cursor.expectingX
    # update cursor y
    cursor.y += 1
    es.syncViewPort()

proc setCursor*(es: EditSession, line: int, col: int): void =
  var cursor = es.cursor
  cursor.x = col.cint
  cursor.y = line.cint
  es.selection.first.x = col.cint
  es.selection.first.y = line.cint
  es.syncViewPort()

proc clearSelection*(es: EditSession): void =
  es.selectionInEffect = false

proc setSelectionFirstPoint*(es: EditSession, firstX: int, firstY: int): void =
  es.selection.first.x = firstX.cint
  es.selection.first.y = firstY.cint

proc startSelection*(es: EditSession, firstX: int, firstY: int): void =
  es.selectionInEffect = true
  es.selection.first.x = firstX.cint
  es.selection.first.y = firstY.cint
  
proc setSelectionLastPoint*(es: EditSession, lastX: int, lastY: int): void =
  es.selection.last.x = lastX.cint
  es.selection.last.y = lastY.cint
  
proc resetCurrentCursor*(es: EditSession): void =
  let (line, col) = es.textBuffer.resolvePosition(es.cursor)
  es.cursor.y = line.cint
  es.cursor.x = col.cint

proc verticalScroll*(es: EditSession, n: int): void =
  # n positive: up, n negative: down.
  let newViewPortY = max(0, min(es.viewPort.y-n, es.textBuffer.lineCount()-1))
  es.viewPort.y = newViewPortY.cint
  
proc horizontalScroll*(es: EditSession, n: int): void =
  # n positive: right, n negative: left
  if es.cursor.y < es.textBuffer.lineCount():
    let newViewPortX = max(0, min(es.viewPort.x-n, es.textBuffer.getLineLength(es.cursor.y)-1))
    es.viewPort.x = newViewPortX.cint
  
proc gotoLineStart*(es: EditSession): void =
  es.cursor.x = 0
  es.cursor.expectingX = 0
  es.syncViewPort()
  
proc gotoLineEnd*(es: EditSession): void =
  if es.cursor.y < es.textBuffer.lineCount():
    es.cursor.x = es.textBuffer.getLineLength(es.cursor.y).cint
    es.cursor.expectingX = es.cursor.x
    es.syncViewPort()

# NOTE THAT cursor movement should be orthogonal with 
proc invalidateSelection*(es: EditSession): void =
  es.selectionInEffect = false
  
