type
  MinibufferView* = ref object
    parent: EditorWindow
    dstrect: Rect
    lateral: GenericWindow

proc relayout*(mv: MinibufferView, ewLateral: GenericWindow): void =
  mv.lateral.offsetX = ewLateral.offsetX
  mv.lateral.offsetY = ewLateral.offsetY + ewLateral.h - 1
  mv.lateral.w = ewLateral.w
  mv.lateral.h = 1
    
proc mkMinibufferView*(parent: EditorWindow): TitleBar =
  return TitleBar(
    parent: parent,
    dstrect: (x: 0, y: 0, w: 0, h: 0),
    lateral: mkGenericWindow()
  )

proc render*(renderer: RendererPtr, mv: MinibufferView): void =
  if mv.parent.minibufferText.len > 0:
    discard renderer.renderTextSolid(
      mv.parent.style.font, mv.parent.minibufferText.cstring,
      mv.lateral.offsetX * mv.parent.gridSizeW,
      mv.lateral.offsetY * mv.parent.gridSizeH,
      mv.parent.style.fgColor
    )
    mv.parent.minibufferText = ""
  
proc renderWith*(tb: TitleBar, renderer: RendererPtr): void =
  renderer.render(tb)
  
