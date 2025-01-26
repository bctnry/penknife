import sdl2
import ../model/[state, textbuffer]
import ../ui/[sdl2_utils, texture]

# line number panel.
# depends on the current session's viewpot.
# in penknife the statusbar's rendering depends on the current session, which
# can change after we implement multiple-file support so we need globalState.

type
  LineNumberPanel* = ref object
    parentState*: State
    dstrect*: Rect

proc mkLineNumberPanel*(st: State): LineNumberPanel =
  return LineNumberPanel(
    parentState: st,
    dstrect: (x: 0, y: 0, w: 0, h: 0)
  )
  
proc render*(renderer: RendererPtr, lnp: LineNumberPanel): void =
  let st = lnp.parentState
  let renderRowBound = min(st.viewPort.y+st.viewPort.h, st.session.lineCount())
  let baselineX = (st.viewPort.offset*st.gridSize.w).cint
  let offsetPY = (st.viewPort.offsetY*st.gridSize.h).cint
  # render line number
  for i in st.viewPort.y..<renderRowBound:
    let lnStr = ($(i+1)).cstring
    let lnColor = if st.cursor.y == i: st.bgColor else: st.fgColor
    let lnTexture = renderer.mkTextTexture(st.globalFont, lnStr, lnColor)
    if st.cursor.y == i:
      lnp.dstrect.x = 0
      lnp.dstrect.y = offsetPY + ((i-st.viewPort.y)*st.gridSize.h).cint
      lnp.dstrect.w = baselineX-(VIEWPORT_GAP-1)*st.gridSize.w
      lnp.dstrect.h = st.gridSize.h
      renderer.setDrawColor(st.fgColor.r, st.fgColor.g, st.fgColor.b)
      renderer.fillRect(lnp.dstrect)
    lnp.dstrect.x = (st.viewPort.offset-VIEWPORT_GAP)*st.gridSize.w-lnTexture.w
    lnp.dstrect.y = offsetPY + ((i-st.viewPort.y)*st.gridSize.h).cint
    lnp.dstrect.w = lnTexture.w
    lnp.dstrect.h = lnTexture.h
    renderer.copyEx(lnTexture.raw, nil, lnp.dstrect.addr, 0.cdouble, nil)
    
    # render selection marker
  if st.selectionInEffect:
    let selectionRangeStart = min(st.selection.first, st.selection.last)
    let selectionRangeEnd = max(st.selection.first, st.selection.last)
    for i in st.viewPort.y..<renderRowBound:
      if (selectionRangeStart.y <= i and i <= selectionRangeEnd.y):
        lnp.dstrect.y = offsetPY + ((i-st.viewPort.y)*st.gridSize.h).cint
        let indicator = if i == selectionRangeStart.y: "{" elif i == selectionRangeEnd.y: "}" else: "|"
        discard renderer.renderTextSolid(
          lnp.dstrect.addr, st.globalFont, indicator.cstring,
          baselineX-VIEWPORT_GAP*st.gridSize.w, lnp.dstrect.y,
          (if st.cursor.y == i: st.bgColor else: st.fgColor)
        )
            

proc renderWith*(lnp: LineNumberPanel, renderer: RendererPtr): void =
  renderer.render(lnp)
  
