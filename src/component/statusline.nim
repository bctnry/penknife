import std/strformat
import sdl2
import ../model/[state]
import ../ui/[sdl2_utils]

# status bar.

type
  StatusLine* = ref object
    parentState*: State
    dstrect*: Rect

proc mkStatusLine*(st: State): StatusLine =
  return StatusLine(
    parentState: st,
    dstrect: (x: 0, y: 0, w: 0, h: 0)
  )

proc render*(renderer: RendererPtr, tb: StatusLine): void =
  let st = tb.parentState
  tb.dstrect.x = 0
  tb.dstrect.y = ((st.viewPort.offsetY+st.viewPort.h)*st.gridSize.h).cint
  tb.dstrect.w = st.viewPort.fullGridW*st.gridSize.w
  tb.dstrect.h = st.gridSize.h
  renderer.setDrawColor(st.fgColor.r, st.fgColor.g, st.fgColor.b)
  renderer.fillRect(tb.dstrect)
  let cursorLocationStr = (
    if st.selectionInEffect:
       &"({st.selection.first.y+1},{st.selection.first.x+1})-({st.selection.last.y+1},{st.selection.last.x+1})"
    else:
       &"({st.cursor.y+1},{st.cursor.x+1})"
  )
  discard renderer.renderTextSolid(
    tb.dstrect.addr, st.globalFont, cursorLocationStr.cstring,
    0, ((st.viewPort.offsetY+st.viewPort.h) * st.gridSize.h).cint,
    st.bgColor
  )
  
proc renderWith*(tb: StatusLine, renderer: RendererPtr): void =
  renderer.render(tb)
  
