import sdl2
import ../model/[state, textbuffer, style]
import ../ui/[tvfont]
import ../aux

# line number panel.
# depends on the current session's viewpot.
# in penknife the statusbar's rendering depends on the current session, which
# can change after we implement multiple-file support so we need globalState.

const VIEWPORT_GAP = 2

type
  LineNumberPanel* = ref object
    parentState*: State
    dstrect*: Rect
    offsetX*: cint
    offsetY*: cint
    rightBorderX: cint
    dirty: bool

proc mkLineNumberPanel*(st: State): LineNumberPanel =
  return LineNumberPanel(
    parentState: st,
    dstrect: (x: 0, y: 0, w: 0, h: 0),
    offsetX: 0,
    offsetY: 0,
    rightBorderX: 0,
  )

proc relayout*(lnp: LineNumberPanel, x: cint, y: cint): void =
  lnp.offsetX = x
  lnp.offsetY = y
  
proc render*(renderer: RendererPtr, lnp: LineNumberPanel): void =
  let st = lnp.parentState
  let session = st.mainEditSession
  let renderRowBound = min(session.viewPort.y+session.viewPort.h, session.textBuffer.lineCount())
  let lnpTargetWidth = (digitCount(renderRowBound) + 1 + VIEWPORT_GAP).cint
  # left border
  let baselineX = (lnp.offsetX*st.gridSize.w).cint
  # top border
  let offsetPY = (lnp.offsetY*st.gridSize.h).cint
  # right border (start of text)
  let rightBorderX = (baselineX + lnpTargetWidth*st.gridSize.w).cint
  # right border (end of number)
  let lnRightBorder = rightBorderX - 2*st.gridSize.w
  # render line number
  for i in session.viewPort.y..<renderRowBound:
    let lnStr = ($(i+1))
    let width = st.globalStyle.font.calculateWidth(lnStr, renderer)
    lnp.dstrect.x = (lnRightBorder - width).cint
    lnp.dstrect.y = offsetPY + ((i-session.viewPort.y)*st.gridSize.h).cint
    lnp.dstrect.w = width.cint
    lnp.dstrect.h = st.globalStyle.font.h
    if session.cursor.y == i:
      let bgColor = st.globalStyle.getColor(MAIN_LINENUMBER_SELECT_BACKGROUND)
      renderer.setDrawColor(bgColor.r, bgColor.g, bgColor.b)
      renderer.fillRect(lnp.dstrect)
    discard st.globalStyle.font.renderUTF8Blended(
      lnStr, renderer, nil,
      lnp.dstrect.x, lnp.dstrect.y,
      st.globalStyle.getColor(
        if session.cursor.y == i: MAIN_LINENUMBER_SELECT_FOREGROUND
        else: MAIN_LINENUMBER_FOREGROUND
      )
    )
    # render selection marker
  if session.selectionInEffect:
    let selectionRangeStart = min(session.selection.first.y, session.selection.last.y)
    let selectionRangeEnd = max(session.selection.first.y, session.selection.last.y)
    for i in session.viewPort.y..<renderRowBound:
      if (selectionRangeStart <= i and i <= selectionRangeEnd):
        lnp.dstrect.y = offsetPY + ((i-session.viewPort.y)*st.gridSize.h).cint
        let indicator =
          if selectionRangeStart == selectionRangeEnd and i == selectionRangeStart: "*"
          elif i == selectionRangeStart: "{"
          elif i == selectionRangeEnd: "}"
          else: "|"
        discard st.globalStyle.font.renderUTF8Blended(
          indicator, renderer, nil,
          lnRightBorder, lnp.dstrect.y,
          st.globalStyle.getColor(MAIN_LINENUMBER_FOREGROUND)
        )
  
  # if the current viewport is at a position that can show the end-of-file indicator
  # we display that as well.
  if renderRowBound >= session.textBuffer.lineCount():
    discard st.globalStyle.font.renderUTF8Blended(
      "*", renderer, nil,
      lnRightBorder - 1 * st.gridSize.w,
      ((lnp.offsetY+(renderRowBound-st.currentEditSession.viewPort.y))*st.gridSize.h).cint,
      st.globalStyle.getColor(MAIN_LINENUMBER_FOREGROUND)
    )

proc renderWith*(lnp: LineNumberPanel, renderer: RendererPtr): void =
  renderer.render(lnp)
  
