import sdl2
import ../model/[state, textbuffer]
import ../ui/[font, sdl2_utils, texture]

# titlebar.
# in penknife the titlebar's rendering depends on:
#   1.  the dirty state, the name and the full path of the current session;
#   2.  the width and grid height of the current window;
#   3.  the current global font;
# all of which requires us to depend on the globalState.


type
  TitleBar* = ref object
    parentState*: State
    dstrect*: ptr Rect
    lateral: tuple[
      dirty: bool,
      name: string,
      fullPath: string,
      windowW: cint,
      gridSizeW: cint,
      gridSizeH: cint,
      font: TVFont
    ]

proc mkTitleBar*(st: State, dstrect: ptr Rect): TitleBar =
  return TitleBar(
    parentState: st,
    dstrect: dstrect,
    lateral: (
      dirty: st.session.isDirty,
      name: st.session.name,
      fullPath: st.session.fullPath,
      windowW: st.viewport.fullGridW,
      gridSizeW: st.gridSize.w,
      gridSizeH: st.gridSize.h,
      font: st.globalFont
    )
  )

proc check(tb: TitleBar): bool =
  let st = tb.parentState
  let lt = tb.lateral
  return (
    lt.dirty == st.session.isDirty and
    lt.name == st.session.name and
    lt.fullPath == st.session.fullPath and
    lt.windowW == st.viewport.fullGridW and
    lt.gridSizeW == st.gridSize.w and
    lt.gridSizeH == st.gridSize.h and
    lt.font == st.globalFont
  )

proc sync(tb: TitleBar): void =
  let st = tb.parentState
  tb.lateral.dirty = st.session.isDirty
  tb.lateral.name = st.session.name
  tb.lateral.fullPath = st.session.fullPath
  tb.lateral.windowW = st.viewport.fullGridW
  tb.lateral.gridSizeW = st.gridSize.w
  tb.lateral.gridSizeH = st.gridSize.h
  tb.lateral.font = st.globalFont

proc render*(renderer: RendererPtr, tb: TitleBar): void =
  tb.sync()
  tb.dstrect.x = 0
  tb.dstrect.y = 0
  tb.dstrect.w = tb.lateral.windowW*tb.lateral.gridSizeW
  tb.dstrect.h = TITLE_BAR_HEIGHT*tb.lateral.gridSizeH
  renderer.setDrawColor(
    tb.parentState.fgColor.r,
    tb.parentState.fgColor.g,
    tb.parentState.fgColor.b
  )
  renderer.fillRect(tb.dstrect)
  var titleBarStr = ""
  titleBarStr &= (if tb.lateral.dirty: "[*] " else: "    ")
  titleBarStr &= tb.lateral.name
  titleBarStr &= " | "
  titleBarStr &= tb.lateral.fullPath
  if titleBarStr.len <= 0: return
  let texture = renderer.mkTextTexture(
    tb.lateral.font, titleBarStr.cstring, tb.parentState.bgColor
  )
  tb.dstrect.w = texture.w
  renderer.copyEx(texture.raw, nil, tb.dstrect, 0.cdouble, nil)
  texture.dispose()
  
proc renderWith*(tb: TitleBar, renderer: RendererPtr): void =
  renderer.render(tb)
