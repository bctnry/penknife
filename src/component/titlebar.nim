import sdl2
import ../model/[state, textbuffer, style]
import ../ui/[tvfont]

# titlebar.
# in penknife the titlebar's rendering depends on:
#   1.  the dirty state, the name and the full path of the current session;
#   2.  the width and grid height of the current window;
#   3.  the current global font;
# all of which requires us to depend on the globalState.

const TITLE_BAR_HEIGHT* = 1

type
  TitleBar* = ref object
    parentState*: State
    dstrect*: Rect
    offsetX*: cint
    offsetY*: cint
    width*: cint
    height*: cint

proc mkTitleBar*(st: State): TitleBar =
  return TitleBar(
    parentState: st,
    dstrect: (x: 0, y: 0, w: 0, h: 0),
    offsetX: 0,
    offsetY: 0,
    width: 0,
    height: 0,
  )

proc relayout*(tb: TitleBar, x: cint, y: cint, w: cint, h: cint): void =
  tb.offsetX = x
  tb.offsetY = y
  tb.width = w
  tb.height = h

proc render*(renderer: RendererPtr, tb: TitleBar): void =
  let st = tb.parentState
  let ss = st.auxEditSession
  tb.dstrect.x = tb.offsetX*st.gridSize.w
  tb.dstrect.y = tb.offsetY*st.gridSize.h
  tb.dstrect.w = tb.width*st.gridSize.w
  tb.dstrect.h = tb.height*st.gridSize.h
  let bgColor = st.globalStyle.getColor(AUX_BACKGROUND)
  renderer.setDrawColor(bgColor.r, bgColor.g, bgColor.b  )
  renderer.fillRect(tb.dstrect)
  for i in 0..<ss.textBuffer.lineCount():
    var s = ""
    s &= ss.textBuffer.getLine(i)
    discard st.globalStyle.font.renderUTF8Blended(
      s, renderer, nil,
      tb.dstrect.x, tb.dstrect.y,
      st.globalStyle.getColor(AUX_FOREGROUND)
    )
    tb.dstrect.y += st.gridSize.h
  
proc renderWith*(tb: TitleBar, renderer: RendererPtr): void =
  renderer.render(tb)
  
