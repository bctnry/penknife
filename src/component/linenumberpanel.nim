import sdl2
import ../model/[state, textbuffer]
import ../ui/[sdl2_utils, texture]

# line number panel.
# depends on the current session's viewpot.
# in penknife the statusbar's rendering depends on the current session, which
# can change after we implement multiple-file support so we need globalState.

type
  LineNumberPanel* = ref object
    parent: EditorView
    dstrect: Rect
    lateral: GenericWindow

proc getWidth(lnp: LineNumberPanel): int =
  let vp = lnp.parent.session.viewPort
  let bound = min(vp.y + vp.h, lnp.parent.session.textBuffer.lineCount())
  var res = 1
  while bound > 0:
    res += 1
    bound = bound div 10
  return res + VIEWPORT_GAP

proc relayout*(lnp: LineNumberPanel, evLateral: GenericWindow): void =
  tb.lateral.offsetX = evLateral.offsetX
  tb.lateral.offsetY = evLateral.offsetY + 1
  tb.lateral.w = lnp.getWidth()
  tb.lateral.h = evLateral.h - 2

proc mkLineNumberPanel*(parent: EditorView): LineNumberPanel =
  return LineNumberPanel(
    parent: parent,
    dstrect: (x: 0, y: 0, w: 0, h: 0),
    lateral: mkGenericWindow()
  )
  
proc render*(renderer: RendererPtr, lnp: LineNumberPanel): void =
  let session = lnp.parent.session
  let viewPort = lnp.parent.session.viewPort
  let fgColor = lnp.parent.style.fgColor
  let bgColor = lnp.parent.style.bgColor
  let font = lnp.parent.style.font
  let renderRowBound = min(viewPort.y+viewPort.h, session.textBuffer.lineCount())
  let offsetPY = lnp.lateral.offsetY * lnp.parent.gridSizeH
  let baselinePX = lnp.lateral.w * lnp.parent.gridSizeW
  let parentOffsetPX = lnp.lateral.offsetX * lnp.parent.gridSizeW
  
  # render line number
  for i in viewPort.y..<renderRowBound:
    let lnStr = ($(i+1)).cstring
    let lnColor = if session.cursor.y == i: bgColor else: fgColor
    let lnTexture = renderer.mkTextTexture(font, lnStr, lnColor)
    if session.cursor.y == i:
      lnp.dstrect.x = parentOffsetPX
      lnp.dstrect.y = offsetPY + ((i-viewPort.y)*lnp.parent.gridSizeH).cint
      lnp.dstrect.w = baselinePX-(VIEWPORT_GAP-1)*lnp.parent.gridSizeW
      lnp.dstrect.h = lnp.parent.gridSizeH
      renderer.setDrawColor(fgColor)
      renderer.fillRect(lnp.dstrect.addr)
    lnp.dstrect.x = baselinePX - lnTexture.w
    lnp.dstrect.y = offsetPY + ((i-viewPort.y)*lnp.parent.gridSizeH).cint
    lnp.dstrect.w = lnTexture.w
    lnp.dstrect.h = lnTexture.h
    renderer.copyEx(lnTexture.raw, nil, lnp.dstrect.addr, 0.cdouble, nil)
    
    # render selection marker
  if session.selectionInEffect:
    let selectionRangeStart = min(session.selection.first, session.selection.last)
    let selectionRangeEnd = max(session.selection.first, session.selection.last)
    for i in viewPort.y..<renderRowBound:
      if (selectionRangeStart.y <= i and i <= selectionRangeEnd.y):
        lnp.dstrect.y = offsetPY + ((i-viewPort.y)*lnp.parent.gridSizeH).cint
        let indicator = if i == selectionRangeStart.y: "{" elif i == selectionRangeEnd.y: "}" else: "|"
        discard renderer.renderTextSolid(
          lnp.dstrect.addr, lnp.parent.style.font, indicator.cstring,
          baselineX-VIEWPORT_GAP*lnp.parent.gridSizeW, lnp.dstrect.y,
          (if st.cursor.y == i: bgColor else: fgColor)
        )
            
proc renderWith*(lnp: LineNumberPanel, renderer: RendererPtr): void =
  renderer.render(lnp)
  
