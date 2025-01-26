import sdl2
import ../model/[state, textbuffer]
import ../ui/[font, sdl2_utils, texture]

# titlebar.

type
  TitleBar* = ref object
    parent: EditorView
    dstrect: Rect
    lateral: GenericWindow

proc relayout*(tb: TitleBar, evLateral: GenericWindow): void =
  tb.lateral.offsetX = evLateral.offsetX
  tb.lateral.offsetY = evLateral.offsetY
  tb.lateral.w = evLateral.w
  tb.lateral.h = TITLE_BAR_HEIGHT
    
proc mkTitleBar*(parent: EditorView): TitleBar =
  return TitleBar(
    parent: parent,
    dstrect: (x: 0, y: 0, w: 0, h: 0),
    lateral: mkGenericWindow()
  )

proc render*(renderer: RendererPtr, tb: TitleBar): void =
  tb.dstrect.x = tb.lateral.offsetX * tb.parent.gridSizeW
  tb.dstrect.y = tb.lateral.offsetY * tb.parent.gridSizeH
  tb.dstrect.w = tb.lateral.w * tb.parent.gridSizeW
  tb.dstrect.h = tb.lateral.h * tb.parent.gridSizeH
  renderer.setDrawColor(
    tb.style.fgColor.r,
    tb.style.fgColor.g,
    tb.style.fgColor.b
  )
  renderer.fillRect(tb.dstrect.addr)
  var titleBarStr = ""
  titleBarStr &= (if tb.parent.session.textBuffer.isDirty: "[*] " else: "[ ] ")
  titleBarStr &= tb.parent.session.name
  titleBarStr &= " | "
  titleBarStr &= tb.parent.session.fullPath
  if titleBarStr.len <= 0: return
  let texture = renderer.mkTextTexture(
    tb.parent.style.font, titleBarStr.cstring, tb.parent.style.bgColor
  )
  tb.dstrect.w = texture.w
  renderer.copyEx(texture.raw, nil, tb.dstrect.addr, 0.cdouble, nil)
  texture.dispose()
  
proc renderWith*(tb: TitleBar, renderer: RendererPtr): void =
  renderer.render(tb)
  
