import std/[syncio, strformat, cmdline]
import std/strutils
import std/paths
import sdl2
import sdl2/ttf
import model/[textbuffer, state, cursor]
import ui/[font, texture, timer, sdl2_utils]
import component/[titlebar, linenumberpanel, statusline, cursorview, editorview]
import component/[maineventhandler]
import config

const SCREEN_WIDTH: cint = 1280.cint
const SCREEN_HEIGHT: cint = 768.cint

proc logError(x: string): void =
  stderr.writeLine(x)

proc init(): bool =
  if not loadGlobalConfig(): return false
  if sdl2.init(sdl2.INIT_TIMER or sdl2.INIT_AUDIO or sdl2.INIT_VIDEO or sdl2.INIT_EVENTS) == SdlError:
    logError(&"Failed to initialie SDL2: {sdl2.getError()}")
    return false
  if ttf.ttfInit() == SdlError:
    logError(&"Failed to initialize SDL_TTF: {sdl2.getError()}")
    return false
  if not sdl2.setHint("SDL_IME_SHOW_UI".cstring, "1".cstring):
    logError(&"Failed to set hint. You might not be able to input texts through an IME.")
  return true

var window: WindowPtr
var renderer: RendererPtr
var dstrect: Rect = (x: 0.cint, y: 0.cint, w: 0.cint, h: 0.cint)

proc mkTextTexture*(renderer: RendererPtr, gfont: TVFont, str: cstring, color: sdl2.Color): LTexture =
  if str.len == 0: return nil
  let surface = gfont.raw.renderUtf8Blended(str, color)
  if surface.isNil: return nil
  let w = surface.w
  let h = surface.h
  let texture = renderer.createTextureFromSurface(surface)
  if texture.isNil:
    surface.freeSurface()
    return nil
  surface.freeSurface()
  return LTexture(raw: texture, w: w, h: h)

  
proc renderTextSolid*(renderer: RendererPtr, gfont: TVFont,
                      str: cstring,
                      x: cint, y: cint,
                      color: sdl2.Color): cint =
    # if str is empty surface would be nil, so we have to
    # do it here to separate it from the case where there's
    # a surface creation error.
    if str.len == 0: return 0
    let texture = renderer.mkTextTexture(gfont, str, color)
    let w = texture.w
    dstrect.x = x
    dstrect.y = y
    dstrect.w = texture.w
    dstrect.h = texture.h
    renderer.copyEx(texture.raw, nil, dstrect.addr, 0.cdouble, nil)
    texture.dispose()
    return w

proc renderTextSolidAtBaseline*(renderer: RendererPtr, gfont: TVFont,
                      str: cstring,
                      x: cint, y: cint,
                      color: sdl2.Color): cint =
    if str.len == 0: return 0
    let texture = renderer.mkTextTexture(gfont, str, color)
    let w = texture.w
    dstrect.x = x
    dstrect.y = y-texture.h
    dstrect.w = texture.w
    dstrect.h = texture.h
    renderer.copyEx(texture.raw, nil, dstrect.addr, 0.cdouble, nil)
    texture.dispose()
    return w

var shouldReload: bool = false
var globalState: State = mkNewState()
var foregroundColor: sdl2.Color = sdl2.color(0x00, 0x00, 0x00, 0x00)
var backgroundColor: sdl2.Color = sdl2.color(0xef, 0xef, 0xef, 0x00)
var displaySelectionRangeIndicator: bool = true
proc main(): int =
  if not init(): return QuitFailure

  # load font according to config
  var gfontFileName = getGlobalConfig(CONFIG_KEY_FONT_PATH)
  var gfontSize = getGlobalConfig(CONFIG_KEY_FONT_SIZE).parseInt
  if not loadFont(gfontFileName, globalState.globalFont, gfontSize):
    logError(&"Failed to load gfont {gfontFileName.repr}.")
    return QuitFailure

  # load color according to config
  globalState.fgColor.loadColorFromString(getGlobalConfig(CONFIG_FOREGROUND_COLOR))
  globalState.bgColor.loadColorFromString(getGlobalConfig(CONFIG_BACKGROUND_COLOR))

  # create 
  window = sdl2.createWindow("penknife".cstring,
                             sdl2.SDL_WINDOWPOS_UNDEFINED,
                             sdl2.SDL_WINDOWPOS_UNDEFINED,
                             SCREEN_WIDTH,
                             SCREEN_HEIGHT,
                             sdl2.SDL_WINDOW_RESIZABLE
  )
  if window.isNil:
    logError(&"Failed to create window: {sdl2.getError()}")
    return QuitFailure
  renderer = sdl2.createRenderer(window, -1, Renderer_Accelerated)
  if renderer.isNil:
    logError(&"Failed to create renderer: {sdl2.getError()}")
    return QuitFailure
  let screenSurface = window.getSurface()

  # setup textbuffer
  if paramCount() <= 0:
    globalState.loadText("")
  else:
    let fn = paramStr(1)
    let f = open(fn, fmRead)
    let s = f.readAll()
    f.close()
    globalState.loadText(s, name=fn.Path.extractFilename.string, fullPath=fn.Path.absolutePath.string)
  var session = globalState.session

  # setup grid
  var gridSize = globalState.gridSize
  gridSize.h = globalState.globalFont.h
  gridSize.w = globalState.globalFont.w

  var event: sdl2.Event
  var shouldQuit: bool = false
  var ctrl: bool = false
  proc setCtrl(): void =
    ctrl = true
  proc unsetCtrl(): void =
    ctrl = false
  var alt: bool = false
  proc setAlt(): void =
    alt = true
  proc unsetAlt(): void =
    alt = false
    
  var w, h: cint
  window.getSize(w, h)
  globalState.relayout(w, h)

  var titlebar = mkTitleBar(globalState, dstrect.addr)
  var lineNumberPanel = mkLineNumberPanel(globalState, dstrect.addr)
  var statusLine = mkStatusLine(globalState, dstrect.addr)
  var cursorView = mkCursorView(globalState, dstrect.addr)
  var editorView = mkEditorView(globalState)
  var mainEventHandler = mkMainEventHandler(globalState, window, renderer, dstrect.addr)

  let backgroundColor = globalState.bgColor
  let foregroundColor = globalState.fgColor
  
  var shouldRefresh = false
  var selectionInitiated = false
  var selectionInitiationX: cint = 0
  var selectionInitiationY: cint = 0
  var cursorColor: int = 1
  var cursorBlinkTimer = mkInterval((
    proc (): void =
      cursorView.renderWith(renderer)
  ), 500)
  cursorBlinkTimer.start()
  
  while not shouldQuit:
    shouldRefresh = false
    while sdl2.pollEvent(event):
      mainEventHandler.handleEvent(event, shouldQuit, shouldRefresh, shouldReload)
      
    cursorBlinkTimer.check()
    if not shouldRefresh: continue

    echo "re-render"
    
    # render screen here.
    renderer.setDrawColor(backgroundColor.r, backgroundColor.g, backgroundColor.b)
    renderer.clear()

    let baselineX = (globalState.viewPort.offset*gridSize.w).cint
    let offsetPY = (globalState.viewPort.offsetY*gridSize.h).cint
    # render edit viewport
    let renderRowBound = min(globalState.viewPort.y+globalState.viewPort.h, globalState.session.lineCount())
    let selectionRangeStart = min(globalState.selection.first, globalState.selection.last)
    let selectionRangeEnd = max(globalState.selection.first, globalState.selection.last)
    
    # render line number
    lineNumberPanel.renderWith(renderer)

    # render line.
    editorView.renderWith(renderer)
    
    # draw cursor.
    if cursorBlinkTimer.paused or cursorBlinkTimer.stopped:
      renderer.render(cursorView, flat=true)
    
    # if the current viewport is at a position that can show the end-of-file indicator
    # we display that as well.
    if renderRowBound >= session.lineCount():
      discard renderer.renderTextSolid(
        globalState.globalFont, "*".cstring,
        (baselineX - (1+VIEWPORT_GAP)*gridSize.w).cint, TITLE_BAR_HEIGHT*gridSize.h+((renderRowBound-globalState.viewPort.y)*gridSize.h).cint,
        foregroundColor
      )

    # render title bar
    titlebar.renderWith(renderer)
    
    # render status line
    statusLine.renderWith(renderer)

    # render minibuffer
    if globalState.minibufferText.len > 0:
      discard renderer.renderTextSolid(
        globalState.globalFont, globalState.minibufferText.cstring,
        0, offsetPY+((globalState.viewPort.h + 1)*gridSize.h).cint,
        foregroundColor
      )
      globalState.minibufferText = ""

    renderer.present()
  
  renderer.destroy()
  window.destroyWindow()
  sdl2.quit()
  ttf.ttfQuit()
  return QuitSuccess

when isMainModule:
  while true:
    let res = main()
    if res != QuitSuccess or not shouldReload:
      quit(res)
    shouldReload = false
  
    


