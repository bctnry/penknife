import std/strutils
import sdl2
import ../model/[state, textbuffer, style, cursor]
import ../ui/[tvfont]

const STATUS_BAR_HEIGHT*: cint = 1

type
  StatusBar* = ref object
    parentState*: State
    dstrect*: Rect
    offsetX*: cint
    offsetY*: cint
    width*: cint
    height*: cint

proc mkStatusBar*(st: State): StatusBar =
  return StatusBar(
    parentState: st,
    dstrect: (x: 0, y: 0, w: 0, h: 0),
    offsetX: 0,
    offsetY: 0,
    width: 0,
    height: 0,
  )

proc relayout*(tb: StatusBar, x: cint, y: cint, w: cint, h: cint): void =
  tb.offsetX = x
  tb.offsetY = y
  tb.width = w
  tb.height = h

proc render*(renderer: RendererPtr, tb: StatusBar): void =
  let st = tb.parentState
  let ss = st.currentEditSession
  tb.dstrect.x = tb.offsetX*st.gridSize.w
  tb.dstrect.y = tb.offsetY*st.gridSize.h
  tb.dstrect.w = tb.width*st.gridSize.w
  tb.dstrect.h = tb.height*st.gridSize.h
  let bgColor = st.globalStyle.getColor(STATUSBAR_BACKGROUND)
  renderer.setDrawColor(bgColor.r, bgColor.g, bgColor.b)
  renderer.fillRect(tb.dstrect)
  var s = "[" & (if st.mainEditSession.textBuffer.dirty: "*" else: " ") & "] "
  s &= (if st.focusOnAux: "^" else: "v")
  s &= " "
  if st.mainEditSession.selectionInEffect:
    s &= "(" & $st.mainEditSession.selection.first.y & "," &
               $st.mainEditSession.selection.first.x & ")-(" &
               $st.mainEditSession.selection.last.y & "," &
               $st.mainEditSession.selection.last.x & ")"
  else:
    s &= $st.mainEditSession.cursor
  s &= " " & st.keySession.keyBuffer.join(" ")
  discard st.globalStyle.font.renderUTF8Blended(
    s, renderer, nil,
    tb.dstrect.x, tb.dstrect.y,
    st.globalStyle.getColor(STATUSBAR_FOREGROUND)
  )
  
proc renderWith*(tb: StatusBar, renderer: RendererPtr): void =
  renderer.render(tb)
  
