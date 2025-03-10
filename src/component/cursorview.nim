import std/unicode
import sdl2
import ../model/[state, textbuffer, cursor, editsession]
import ../ui/[sdl2_ui_utils, tvfont]

# cursor.

type
  CursorView* = ref object
    parentState*: State
    dstrect*: Rect
    residingSession*: EditSession
    invert: bool
    offsetX: cint
    offsetY: cint
    cursorPX: cint
    cursorPY: cint

proc mkCursorView*(st: State): CursorView =
  return CursorView(
    parentState: st,
    dstrect: (x: 0.cint, y: 0.cint, w: 0.cint, h: 0.cint),
    invert: false,
    offsetX: 0,
    offsetY: 0
  )

proc calibrate*(cv: CursorView, x: cint, y: cint): void =
  cv.offsetX = x
  cv.offsetY = y

proc render*(renderer: RendererPtr, tb: CursorView, flat: bool = false): void =
  let st = tb.parentState
  let ss = tb.residingSession
  let cursorX = ss.cursor.x
  let cursorY = ss.cursor.y
  let viewportAGX = ss.textBuffer.canonicalXToGridX(st.globalStyle.font, ss.viewPort.x, ss.cursor.y)
  let cursorAGX = ss.textBuffer.canonicalXToGridX(st.globalStyle.font, cursorX, ss.cursor.y)
  let cursorRelativeX = (cursorAGX - viewportAGX).cint
  let cursorRelativeY = (cursorY - ss.viewPort.y).cint
  let selectionRangeStart = min(ss.selection.first, ss.selection.last)
  let selectionRangeEnd = max(ss.selection.first, ss.selection.last)
  if cursorRelativeX >= 0 and cursorRelativeY < ss.viewPort.w:
    let baselineX = (tb.offsetX*st.gridSize.w).cint
    let offsetPY = (tb.offsetY*st.gridSize.h).cint
    var shouldFgColorBeAux = (
      (flat and not (ss.selectionInEffect and
                     between(cursorRelativeX, cursorRelativeY, selectionRangeStart, selectionRangeEnd))) or
      (not flat and not tb.invert)
    )
    if st.focusOnAux: shouldFgColorBeAux = not shouldFgColorBeAux
    let bgcolor = if shouldFgColorBeAux: st.globalStyle.highlightColor
                  else: st.globalStyle.backgroundColor
    
    let cursorPX = baselineX+cursorRelativeX*st.gridSize.w
    let cursorPY = offsetPY+cursorRelativeY*st.gridSize.h
    let lineOfRune = if ss.cursor.y >= ss.textBuffer.lineCount(): @[]
                     else: ss.textBuffer.getLineOfRune(ss.cursor.y)
    if ss.cursor.x >= lineOfRune.len:
      renderer.setDrawColor(bgcolor.r, bgcolor.g, bgcolor.b)
      tb.dstrect.x = cursorPX
      tb.dstrect.y = cursorPY
      tb.dstrect.w = st.gridSize.w
      tb.dstrect.h = st.gridSize.h
      renderer.fillRect(tb.dstrect.addr)
    else:
      var s = ss.textBuffer.getLineOfRune(ss.cursor.y)[ss.cursor.x]
      renderer.setDrawColor(bgcolor.r, bgcolor.g, bgcolor.b)
      tb.dstrect.x = cursorPX
      tb.dstrect.y = cursorPY
      tb.dstrect.w = (if s.isFullWidthByFont(st.globalStyle.font): 2 else: 1) * st.gridSize.w
      tb.dstrect.h = st.gridSize.h
      renderer.fillRect(tb.dstrect.addr)
      if ss.cursor.y < ss.textBuffer.lineCount() and
         ss.cursor.x < ss.textBuffer.getLineLength(ss.cursor.y):
        discard st.globalStyle.font.renderUTF8Blended(
          $s, renderer, nil,
          cursorPX.cint, cursorPY.cint, shouldFgColorBeAux
        )
    if not flat:
      renderer.present()
      tb.invert = not tb.invert
    # update IME box position
    sdl2.setTextInputRect(tb.dstrect.addr)
    tb.cursorPX = tb.dstrect.x
    tb.cursorPY = tb.dstrect.y

proc moveIMEBoxToCursorView*(tb: CursorView): void =
  tb.dstrect.x = tb.cursorPX
  tb.dstrect.y = tb.cursorPY
  sdl2.setTextInputRect(tb.dstrect.addr)

  
proc renderWith*(tb: CursorView, renderer: RendererPtr): void =
  renderer.render(tb)
  
