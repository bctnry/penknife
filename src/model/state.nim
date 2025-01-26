import std/unicode
from sdl2 import color
import textbuffer
import cursor
import selection
import keyseq
import editsession
import ../ui/font

proc digitCount(x: int): int =
  var m = 10
  var res = 1
  while m < x:
    m *= 10
    res += 1
  return res

# the gap between the linenumber panel and the viewport. (grid)
const VIEWPORT_GAP*: cint = 2

# the height of the title bar. (grid)
const TITLE_BAR_HEIGHT*: cint = 1

const MM_NONE*: int = 0
const MM_OPEN_AND_LOAD_FILE*: int = 1
const MM_SAVE_FILE*: int = 2
const MM_PROMPT_SAVE_AND_OPEN_FILE*: int = 3
  
type
  ViewPort* = ref object
    # col offset in document (grid)
    x*: cint
    # row offset in document (grid)
    y*: cint
    # width (grid)
    w*: cint
    # height (grid)
    h*: cint
    # offset from left edge (gap included) (grid)
    offset*: cint
    # offset from top edge (grid)
    offsetY*: cint
    # width of whole window (grid)
    fullGridW*: cint
    # height of whole wiindow (grid)
    fullGridH*: cint
  GridSizeDescriptor* = ref object
    w*: cint
    h*: cint
  State* = ref object
    viewport*: ViewPort
    currentEditSession*: EditSession
    gridSize*: GridSizeDescriptor
    globalFont*: TVFont
    fgColor*: sdl2.Color
    bgColor*: sdl2.Color
    # currently minibuffer is a one-line text/textfield.
    # the problem is minibuffer and the current text buffer shares the same
    # source of events.
    minibufferText*: string
    minibufferMode*: bool
    minibufferInputCursor*: int
    minibufferInputValue*: seq[Rune]
    minibufferCommand*: int
    fkeyMap*: FKeyMap

proc session*(st: State): TextBuffer = st.currentEditSession.textBuffer
proc cursor*(st: State): Cursor = st.currentEditSession.cursor
proc selection*(st: State): LinearSelection = st.currentEditSession.selection
proc selectionInEffect*(st: State): bool = st.currentEditSession.selectionInEffect
proc `selectionInEffect=`*(st: var State, nv: bool): void =
  st.currentEditSession.selectionInEffect = nv
    
proc mkNewViewPort*(x: cint = 0, y: cint = 0, w: cint = 0, h: cint = 0,
                                                        offset: cint = 0, fullGridW: cint = 0, fullGridH: cint = 0, offsetY: cint = 0): ViewPort =
    ViewPort(x: x, y: y, w: w, h: h,
             offset: offset, offsetY: offsetY,
             fullGridW: fullGridW, fullGridH: fullGridH)
proc mkNewState*(): State =
  State(viewport: mkNewViewPort(),
        currentEditSession: mkEditSession(),
        gridSize: GridSizeDescriptor(w: 0, h: 0),
        globalFont: TVFont(raw: nil, w: 0, h: 0),
        fgColor: sdl2.color(0, 0, 0, 0),
        bgColor: sdl2.color(0, 0, 0, 0),
        minibufferText: "",
        minibufferMode: false,
        minibufferInputCursor: 0,
        minibufferInputValue: @[],
        minibufferCommand: MM_NONE,
        fkeyMap: mkFKeyMap()
  )

proc loadText*(st: State, s: string, name: string = "*unnamed*", fullPath: string = ""): void =
  st.currentEditSession.textBuffer = s.fromString
  st.currentEditSession.textBuffer.name = name
  st.currentEditSession.textBuffer.fullPath = fullPath
                              
proc relayout*(st: State): void
proc syncViewPort*(st: State): void =
  # move viewport to the place where the cursor can be seen.
  if st.cursor.x < st.viewPort.x: st.viewPort.x = st.cursor.x
  elif st.cursor.x >= st.viewPort.x + st.viewPort.w:
    st.viewPort.x = st.cursor.x - st.viewPort.w + 1
  if st.cursor.y < st.viewPort.y:
    st.viewPort.y = st.cursor.y
    st.relayout()
  elif st.cursor.y >= st.viewPort.y + st.viewPort.h:
    st.viewPort.y = st.cursor.y - st.viewPort.h + 1
    st.relayout()

proc startMinibufferInput*(st: State, prompt: string = ""): void =
  st.minibufferText = prompt
  st.minibufferMode = true
proc minibufferCursorLeft*(st: State): void =
  if st.minibufferInputCursor > 0: st.minibufferInputCursor -= 1
proc minibufferCursorRight*(st: State): void =
  if st.minibufferInputCursor < st.minibufferInputValue.len: st.minibufferInputCursor += 1

proc cursorLeft*(st: State, session: TextBuffer): void =
  if st.minibufferMode:
    st.minibufferCursorLeft()
    return
  if st.cursor.x > 0:
    st.cursor.x -= 1
    st.cursor.expectingX = st.cursor.x
  else:
    # if cursor.x = 0 and user choose to go left
    # check if there is prev line
    # if yes:
    if st.cursor.y > 0:
      # goto prev line. but we move pass 1 char so minus 1
      let prevLineLen = session.getLine(st.cursor.y-1).len
      st.cursor.x = prevLineLen.cint
      st.cursor.expectingX = st.cursor.x
      st.cursor.y -= 1
    # if no: do nothing
  st.syncViewPort()

proc cursorRight*(st: State, session: TextBuffer): void =
  if st.minibufferMode:
    st.minibufferCursorRight()
    return
  var cursor = st.cursor
  # if at end-of-document
  if cursor.y >= session.lineCount(): return
  # if at line end
  if cursor.x >= session.getLine(cursor.y).len:
    # if there is next line
    if cursor.y < session.lineCount()-1:
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

proc cursorUp*(st: State, session: TextBuffer): void =
  if st.minibufferMode: return
  var cursor = st.cursor
  # if has prev line
  if cursor.y > 0:
    # if prev line is not as long
    if session.getLine(cursor.y-1).len <= cursor.expectingX:
      # set x at end of prev line
      cursor.x = session.getLine(cursor.y-1).len.cint
    # else we set cursor x at expected x
    else:
      cursor.x = cursor.expectingX
    # update cursor y
    cursor.y -= 1
    st.syncViewPort()
  # else: do nothing.

proc cursorDown*(st: State, session: TextBuffer): void =
  if st.minibufferMode: return
  var cursor = st.cursor
  if cursor.y < session.lineCount():
    # if next line is end-of-document:
    if cursor.y+1 == session.lineCount():
      cursor.x = 0
    # else, if next line is not as long:
    elif session.getLine(cursor.y+1).len <= cursor.expectingX:
      # set x at end of next line
      cursor.x = session.getLine(cursor.y+1).len.cint
    # else we set cursor x at expected x
    else:
      cursor.x = cursor.expectingX
    # update cursor y
    cursor.y += 1
    st.syncViewPort()

proc setCursor*(st: State, line: int, col: int): void =
  var cursor = st.cursor
  cursor.x = col.cint
  cursor.y = line.cint
  st.selection.first.x = col.cint
  st.selection.first.y = line.cint
  st.syncViewPort()

proc clearSelection*(st: State): void =
  st.currentEditSession.selectionInEffect = false

proc setSelectionFirstPoint*(st: State, firstX: int, firstY: int): void =
  st.selection.first.x = firstX.cint
  st.selection.first.y = firstY.cint

proc startSelection*(st: State, firstX: int, firstY: int): void =
  st.currentEditSession.selectionInEffect = true
  st.selection.first.x = firstX.cint
  st.selection.first.y = firstY.cint
  
proc setSelectionLastPoint*(st: State, lastX: int, lastY: int): void =
  st.selection.last.x = lastX.cint
  st.selection.last.y = lastY.cint
  
proc relayout*(st: State, windowWidth: cint, windowHeight: cint): void =
  var viewPort = st.viewPort
  var w = windowWidth
  var h = windowHeight
  let fullGridW = w div st.gridSize.w
  let fullGridH = (h div st.gridSize.h) - 2
  let linenumberPanelSize = max(2, digitCount(viewPort.y+viewPort.h)+1)
  viewPort.fullGridW = fullGridW
  viewPort.fullGridH = fullGridH
  viewPort.offset = linenumberPanelSize.cint+VIEWPORT_GAP
  viewPort.offsetY = TITLE_BAR_HEIGHT
  viewPort.w = fullGridW - linenumberPanelSize.cint - VIEWPORT_GAP
  # 1 for the status line, 1 for the mini buffer.
  viewPort.h = (h div st.gridSize.h) - 2 - TITLE_BAR_HEIGHT

proc resetCurrentCursor*(tb: State): void =
  let (line, col) = tb.session.resolvePosition(tb.cursor)
  tb.cursor.y = line.cint
  tb.cursor.x = col.cint
  
proc relayout*(st: State): void =
  var viewPort = st.viewPort
  # assumes the window size didn't change.
  let linenumberPanelSize = max(2, digitCount(viewPort.y+viewPort.h)+1)
  viewPort.offset = linenumberPanelSize.cint+VIEWPORT_GAP
  viewPort.w = viewPort.fullGridW - linenumberPanelSize.cint - VIEWPORT_GAP

proc verticalScroll*(st: State, n: int): void =
  # n positive: up, n negative: down.
  let newViewPortY = max(0, min(st.viewPort.y-n, st.session.lineCount()-1))
  st.viewPort.y = newViewPortY.cint
  st.relayout()
  
proc horizontalScroll*(st: State, n: int): void =
  # n positive: right, n negative: left
  if st.cursor.y < st.session.lineCount():
    let newViewPortX = max(0, min(st.viewPort.x-n, st.session.getLineLength(st.cursor.y)-1))
    st.viewPort.x = newViewPortX.cint
    st.relayout()
  
proc gotoLineStart*(st: State): void =
  st.cursor.x = 0
  st.cursor.expectingX = 0
  st.syncViewPort()
proc gotoLineEnd*(st: State): void =
  if st.cursor.y < st.session.lineCount():
    st.cursor.x = st.session.getLineLength(st.cursor.y).cint
    st.cursor.expectingX = st.cursor.x
    st.syncViewPort()
    
proc convertMousePositionX*(st: State, x: cint): cint =
  return st.viewPort.x + ((x + st.gridSize.w div 2) div st.gridSize.w) - st.viewport.offset

proc convertMousePositionY*(st: State, y: cint): cint =
  return st.viewPort.y + (y div st.gridSize.h) - st.viewport.offsetY

# NOTE THAT cursor movement should be orthogonal with 
proc invalidateSelection*(st: State): void =
  st.currentEditSession.selectionInEffect = false
  
