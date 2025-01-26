import std/unicode
from sdl2 import color
import textbuffer
import cursor
import selection
import keyseq
import editsession
import style
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

type
  State* = ref object
    style*: Style
    currentEditorView*: EditorView
    # currently minibuffer is a one-line text/textfield.
    # the problem is minibuffer and the current text buffer shares the same
    # source of events.
    minibufferText*: string
    minibufferMode*: bool
    minibufferInputCursor*: int
    minibufferInputValue*: seq[Rune]
    fkeyMap*: FKeyMap
    lateral: GenericWindow
    
proc mkNewState*(st: Style): State =
  var st = State(
    style: st,
    currentEditorView: nil
    minibufferText: "",
    minibufferMode: false,
    minibufferInputCursor: 0,
    minibufferInputValue: @[],
    fkeyMap: mkFKeyMap(),
    lateral: mkGenericWindow()
  )
  var ev = mkEditorView(st)
  st.currentEditorView = ev
  return st

proc loadText*(st: var State, s: string, name: string = "*unnamed*", fullPath: string = ""): void =
  st.currentEditorView.session.textBuffer = s.fromString
  st.currentEditorView.session.textBuffer.name = name
  st.currentEditorView.session.textBuffer.fullPath = fullPath
  
proc relayout*(st: var State, windowWidth: cint, windowHeight: cint): void =
  var viewPort = st.viewPort
  var w = windowWidth
  var h = windowHeight
  let fullGridW = w div st.gridSize.w
  let fullGridH = (h div st.gridSize.h) - 2
  let linenumberPanelSize = max(2, digitCount(viewPort.y+viewPort.h)+1)
  st.lateral.offsetX = 0
  st.lateral.offsetY = 0
  st.lateral.w = fullGridW
  st.lateral.h = fullGridH


proc relayout*(st: var State): void =
  var viewPort = st.viewPort
  # assumes the window size didn't change.
  let linenumberPanelSize = max(2, digitCount(viewPort.y+viewPort.h)+1)
  viewPort.offset = linenumberPanelSize.cint+VIEWPORT_GAP
  viewPort.w = viewPort.fullGridW - linenumberPanelSize.cint - VIEWPORT_GAP

proc convertMousePositionX*(st: var State, x: cint): cint =
  return st.viewPort.x + ((x + st.gridSize.w div 2) div st.gridSize.w) - st.viewport.offset

proc convertMousePositionY*(st: var State, y: cint): cint =
  return st.viewPort.y + (y div st.gridSize.h) - st.viewport.offsetY
