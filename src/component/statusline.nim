import std/strformat
import sdl2
import ../model/[state]
import ../ui/[sdl2_utils]

# status bar.

type
  StatusLine* = ref object
    parent: EditorView
    dstrect: Rect
    lateral: GenericWindow
    
proc relayout*(sl: StatusLine, evLateral): void =
  tb.lateral.offsetX = evLateral.offsetX
  tb.lateral.offsetY = evLateral.offsetY + evLateral.h - 1
  tb.lateral.w = evLateral.w
  tb.lateral.h = 1

proc mkStatusLine*(parent: EditorView): StatusLine =
  return StatusLine(
    parent: parent,
    dstrect: (x: 0, y: 0, w: 0, h: 0),
    lateral: mkGenericWindow()
  )

proc render*(renderer: RendererPtr, tb: StatusLine): void =
  tb.dstrect.x = tb.lateral.offsetX * tb.parent.gridSizeW
  tb.dstrect.y = tb.lateral.offsetY * tb.parent.gridSizeH
  tb.dstrect.w = tb.lateral.w * tb.parent.gridSizeW
  tb.dstrect.h = tb.lateral.h * tb.parent.gridSizeH
  renderer.setDrawColor(tb.parent.style.fgColor)
  renderer.fillRect(tb.dstrect.addr)
  let s = tb.parent.session
  let cursorLocationStr = (
    if st.selectionInEffect:
       &"({s.selection.first.y+1},{s.selection.first.x+1})-({s.selection.last.y+1},{s.selection.last.x+1})"
    else:
       &"({s.cursor.y+1},{s.cursor.x+1})"
  )
  discard renderer.renderTextSolid(
    tb.dstrect.addr, tb.parent.style.font, cursorLocationStr.cstring,
    tb.dstrect.x, tb.dstrect.y,
    tb.parent.style.bgColor
  )
  
proc renderWith*(tb: StatusLine, renderer: RendererPtr): void =
  renderer.render(tb)
  
