import sdl2
import ../model/[state, textbuffer, cursor]
import ../ui/[sdl2_utils, sdl2_ui_utils, texture, tvfont]

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
    let lnStr = ($(i+1))
    let lnSurface = st.globalFont.renderUTF8Blended(lnStr, renderer, st.cursor.y == i)
    let lnTexture = lnSurface.makeLTextureWith(renderer)
    lnSurface.freeSurface()
    if st.cursor.y == i:
      lnp.dstrect.x = 0
      lnp.dstrect.y = offsetPY + ((i-st.viewPort.y)*st.gridSize.h).cint
      lnp.dstrect.w = baselineX-(VIEWPORT_GAP-1)*st.gridSize.w
      lnp.dstrect.h = st.gridSize.h
      renderer.setDrawColor(st.globalStyle.highlightColor.r,
                            st.globalStyle.highlightColor.g,
                            st.globalStyle.highlightColor.b)
      renderer.fillRect(lnp.dstrect)
    lnp.dstrect.x = (st.viewPort.offset-VIEWPORT_GAP)*st.gridSize.w-lnTexture.w
    lnp.dstrect.y = offsetPY + ((i-st.viewPort.y)*st.gridSize.h).cint
    lnp.dstrect.w = lnTexture.w
    lnp.dstrect.h = lnTexture.h
    renderer.copy(lnTexture.raw, nil, lnp.dstrect.addr)
    
    # render selection marker
  if st.selectionInEffect:
    let selectionRangeStart = min(st.selection.first.y, st.selection.last.y)
    let selectionRangeEnd = max(st.selection.first.y, st.selection.last.y)
    for i in st.viewPort.y..<renderRowBound:
      if (selectionRangeStart <= i and i <= selectionRangeEnd):
        lnp.dstrect.y = offsetPY + ((i-st.viewPort.y)*st.gridSize.h).cint
        let indicator =
          if selectionRangeStart == selectionRangeEnd and i == selectionRangeStart: "*"
          elif i == selectionRangeStart: "{"
          elif i == selectionRangeEnd: "}"
          else: "|"
        discard renderer.renderTextSolid(
          lnp.dstrect.addr, st.globalFont, indicator.cstring,
          baselineX-VIEWPORT_GAP*st.gridSize.w, lnp.dstrect.y,
          st.cursor.y == i
        )
            

proc renderWith*(lnp: LineNumberPanel, renderer: RendererPtr): void =
  renderer.render(lnp)
  
