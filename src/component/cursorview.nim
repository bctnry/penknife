import std/unicode
import sdl2
import ../model/[state, textbuffer, cursor]
import ../ui/[sdl2_ui_utils]

# cursor.

type
  CursorView* = ref object
    parentState*: State
    dstrect*: Rect
    lateral: tuple[
      invert: bool,
    ]

proc mkCursorView*(st: State): CursorView =
  return CursorView(
    parentState: st,
    dstrect: (x: 0.cint, y: 0.cint, w: 0.cint, h: 0.cint),
    lateral: (invert: false)
  )

proc render*(renderer: RendererPtr, tb: CursorView, flat: bool = false): void =
  let st = tb.parentState
  let ss = st.currentEditSession
  let viewportAGX = ss.textBuffer.canonicalXToGridX(st.globalFont, st.viewPort.x, st.cursor.y)
  let cursorAGX = ss.textBuffer.canonicalXToGridX(st.globalFont, st.cursor.x, st.cursor.y)
  let cursorRelativeX = (cursorAGX - viewportAGX).cint
  let cursorRelativeY = st.cursor.y - st.viewPort.y
  let selectionRangeStart = min(st.selection.first, st.selection.last)
  let selectionRangeEnd = max(st.selection.first, st.selection.last)
    
  if cursorRelativeX >= 0 and cursorRelativeY < st.viewPort.w:
    let baselineX = (st.viewPort.offset*st.gridSize.w).cint
    let offsetPY = (st.viewPort.offsetY*st.gridSize.h).cint
    let bgcolor = (
      if flat:
        if st.selectionInEffect and
           between(cursorRelativeX, cursorRelativeY, selectionRangeStart, selectionRangeEnd):
          st.globalStyle.backgroundColor
        else:
          st.globalStyle.highlightColor
      else:
        if tb.lateral.invert: st.globalStyle.backgroundColor
        else: st.globalStyle.highlightColor
    )
    let shouldFgColorBeAux = (
      (flat and not (st.selectionInEffect and
                     between(cursorRelativeX, cursorRelativeY, selectionRangeStart, selectionRangeEnd))) or
      (not flat and not tb.lateral.invert)
    )
    
    let cursorPX = baselineX+cursorRelativeX*st.gridSize.w
    let cursorPY = offsetPY+cursorRelativeY*st.gridSize.h
    let lineOfRune = st.session.getLineOfRune(st.cursor.y)
    if st.cursor.x >= lineOfRune.len:
      renderer.setDrawColor(bgcolor.r, bgcolor.g, bgcolor.b)
      tb.dstrect.x = cursorPX
      tb.dstrect.y = cursorPY
      tb.dstrect.w = st.gridSize.w
      tb.dstrect.h = st.gridSize.h
      renderer.fillRect(tb.dstrect.addr)
    else:
      var s = st.session.getLineOfRune(st.cursor.y)[st.cursor.x]
      renderer.setDrawColor(bgcolor.r, bgcolor.g, bgcolor.b)
      tb.dstrect.x = cursorPX
      tb.dstrect.y = cursorPY
      tb.dstrect.w = (if s.isFullWidthByFont(st.globalFont): 2 else: 1) * st.gridSize.w
      tb.dstrect.h = st.gridSize.h
      renderer.fillRect(tb.dstrect.addr)
      if st.cursor.y < st.session.lineCount() and
         st.cursor.x < st.session.getLineLength(st.cursor.y):
        discard renderer.renderTextSolid(
          tb.dstrect.addr, st.globalFont, ($s).cstring, cursorPX, cursorPY,
          shouldFgColorBeAux
        )
    if not flat:
      renderer.present()
      tb.lateral.invert = not tb.lateral.invert
    # update IME box position
    sdl2.setTextInputRect(tb.dstrect.addr)
  
proc renderWith*(tb: CursorView, renderer: RendererPtr): void =
  renderer.render(tb)
  
