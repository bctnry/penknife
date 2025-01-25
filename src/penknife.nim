import std/[syncio, strformat, cmdline]
import std/strutils
import std/paths
import sdl2
import sdl2/ttf
import model/[textbuffer, state, cursor]
import ui/[font, texture, timer, sdl2_utils]
import component/[titlebar, linenumberpanel, statusline, cursorview, editorview]
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

  let backgroundColor = globalState.bgColor
  let foregroundColor = globalState.fgColor
  
  var cursorDrawn = false
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
    cursorDrawn = false
    while sdl2.pollEvent(event):
      # handle event here.
      case event.kind:
        of sdl2.QuitEvent:
          shouldQuit = true
          break

        of sdl2.WindowEvent:
          case event.window.event:
            of sdl2.WindowEvent_Resized:
              window.getSize(w, h)
              globalState.relayout(w, h)
              shouldRefresh = true
            of sdl2.WindowEvent_FocusGained:
              sdl2.startTextInput()
            of sdl2.WindowEvent_FocusLost:
              sdl2.stopTextInput()
            else:
              discard

        of sdl2.TextInput:
          # NOTE THAT when alt is activated this event is still fired
          # we bypass this by doing this thing:
          if (sdl2.getModState() and KMOD_ALT).bool: break
          if globalState.selectionInEffect:
            let s1 = min(globalState.selection.first, globalState.selection.last)
            let s2 = max(globalState.selection.first, globalState.selection.last)
            globalState.session.delete(s1, s2)
            globalState.setCursor(s1.y, s1.x)
            globalState.selectionInEffect = false
          var i = 0
          var l = globalState.cursor.y
          var c = globalState.cursor.x
          var s = ""
          while event.text.text[i] != '\x00':
            s.add(event.text.text[i])
            i += 1
          let (dline, dcol) = globalState.session.insert(l, c, s)
          if dline > 0:
            globalState.cursor.y += dline.cint
            globalState.cursor.x = dcol.cint
          else:
            globalState.cursor.x += dcol.cint
          globalState.syncViewPort()
          shouldRefresh = true
          echo "input"
              
        of sdl2.MouseWheel:
          # NOTE: even if we do it this way this is still way too slow. it's easy to
          # trigger double-wheel or triple-wheel in emacs but it's not easy here.
          # TODO: fix this.
          var rawStep = 1
          var ev: sdl2.Event
          while sdl2.peepEvents(ev.addr, 1, SDL_PEEKEVENT, sdl2.MouseWheel.uint32, sdl2.MouseWheel.uint32).bool:
            discard sdl2.pollEvent(ev)
            rawStep += 1
                
          let horizontal = (sdl2.getModState().cint and sdl2.KMOD_SHIFT.cint).bool
          let factor = if (sdl2.getModState().cint and sdl2.KMOD_CTRL.cint).bool: 5 else: 1
          let step = event.wheel.y * rawStep * factor
          if horizontal:
            globalState.horizontalScroll(step)
          else:
            globalState.verticalScroll(step)
          shouldRefresh = true
          
        of sdl2.MouseButtonDown:
          globalState.clearSelection()
          if sdl2.getModState().cint == sdl2.KMOD_NONE.cint:
            let y = min(globalState.viewPort.y + event.button.y div gridSize.h, globalState.session.lineCount())
            var x = (
              if y == globalState.session.lineCount():
                0
              else:
                max(0, min(globalState.session.getLineLength(y),
                    globalState.viewPort.x + ((event.button.x + gridSize.w div 2) div gridSize.w) - globalState.viewport.offset
                ))
            )
            globalState.setCursor(y, x)
            globalState.cursor.expectingX = x.cint
            globalState.syncViewPort()
            selectionInitiated = true
            globalState.selection.first.x = x.cint
            globalState.selection.first.y = y.cint
            shouldRefresh = true

        of sdl2.MouseButtonUp:
          let y = max(0, min(globalState.viewPort.y + event.button.y div gridSize.h, globalState.session.lineCount()))
          var x = (
            if y == globalState.session.lineCount():
              0
            else:
              max(0, min(globalState.session.getLineLength(y),
                         globalState.viewPort.x + ((event.button.x + gridSize.w div 2) div gridSize.w) - globalState.viewport.offset
              ))
          )
          if selectionInitiated:
            if globalState.selection.first.x != x or globalState.selection.first.y != y:
              globalState.selectionInEffect = true
            selectionInitiated = false
            
        of sdl2.MouseMotion:
          if sdl2.getModState() == KMOD_NONE:
            if not (event.motion.xrel == 0 and event.motion.yrel == 0):
              if (event.motion.state and 1).bool:
                let y = max(0, min(globalState.convertMousePositionY(event.motion.y), globalState.session.lineCount()))
                var x = (
                  if y == globalState.session.lineCount():
                    0
                  else:
                    max(0, min(globalState.session.getLineLength(y), globalState.convertMousePositionX(event.motion.x)))
                )
                if selectionInitiated:
                  globalState.selectionInEffect = true
                  globalState.setSelectionLastPoint(x, y)
                  globalState.cursor.x = x.cint
                  globalState.cursor.y = y.cint
                  globalState.syncViewPort()
                shouldRefresh = true
            
        of sdl2.KeyDown:
          let modState = sdl2.getModState()
          if (modState and KMOD_CTRL).bool: setCtrl()
          if (modState and KMOD_ALT).bool: setAlt()
          let shifting = (sdl2.getModState() and KMOD_SHIFT).bool
          case event.key.keysym.scancode:
            of SDL_SCANCODE_HOME:
              let targetY = globalState.cursor.y
              let targetX = 0
              if shifting:
                if globalState.cursor.x != targetX or globalState.cursor.y != targetY:
                  if not globalState.selectionInEffect:
                    globalState.startSelection(globalState.cursor.x, globalState.cursor.y)
                  globalState.setSelectionLastPoint(targetX, targetY)
                  globalState.cursor.x = targetX.cint
                  globalState.cursor.y = targetY.cint
                  globalState.syncViewPort()
                  shouldRefresh = true
              else:
                if globalState.selectionInEffect:
                  globalState.invalidateSelection()
                  shouldRefresh = true
                globalState.gotoLineStart()
            of SDL_SCANCODE_END:
              let targetY = globalState.cursor.y
              let targetX = if targetY >= globalState.session.lineCount(): 0 else: globalState.session.getLineLength(targetY)
              if shifting:
                if globalState.cursor.x != targetX or globalState.cursor.y != targetY:
                  if not globalState.selectionInEffect:
                    globalState.startSelection(globalState.cursor.x, globalState.cursor.y)
                  globalState.setSelectionLastPoint(targetX, targetY)
                  globalState.cursor.x = targetX.cint
                  globalState.cursor.y = targetY.cint
                  globalState.syncViewPort()
                  shouldRefresh = true
              else:
                if globalState.selectionInEffect:
                  globalState.invalidateSelection()
                  shouldRefresh = true
                globalState.gotoLineEnd()
            of SDL_SCANCODE_DELETE:
              if globalState.selectionInEffect:
                let start = min(globalState.selection.first, globalState.selection.last)
                let last = max(globalState.selection.last, globalState.selection.first)
                globalState.session.delete(start, last)
                globalState.setCursor(start.y, start.x)
              else:
                globalState.session.deleteChar(globalState.cursor.y, globalState.cursor.x)
              globalState.invalidateSelection()
            of SDL_SCANCODE_BACKSPACE:
              # When there's selection we delete the selection (and set the cursor
              # at the start of the selection, which we will save beforehand).
              if globalState.selectionInEffect:
                let start = min(globalState.selection.first, globalState.selection.last)
                let last = max(globalState.selection.last, globalState.selection.first)
                globalState.session.delete(start, last)
                globalState.setCursor(start.y, start.x)
              else:
                # When there's no selection:
                #   We back up current cursor position for backspacing
                #   Then we update cursor
                #   And then we backspace at the saved position
                # This is written this way because it's easy to consider
                # text buffer and cursor as two independent thing and
                # update them separately.
                # When there's selection we just delete the selection.
                # NOTE: (lineCount, 0) is treated as the same as (lineCount-1,
                #   session[lineCount-1].len).
                var deleteY = globalState.cursor.y
                var deleteX = globalState.cursor.x
                if deleteY >= globalState.session.lineCount():
                  deleteY -= 1
                  deleteX = globalState.session.getLineLength(deleteY).cint
                  globalState.cursor.y -= 1
                  globalState.cursor.x = globalState.session.getLineLength(deleteY).cint
                if deleteX == 0:
                  if deleteY > 0:
                    globalState.cursor.y -= 1
                    globalState.cursor.x = globalState.session.getLineLength(globalState.cursor.y).cint
                else:
                  globalState.cursor.x -= 1
                globalState.session.backspaceChar(deleteY, deleteX)
              globalState.syncViewPort()
              globalState.invalidateSelection()
            of SDL_SCANCODE_UP:
              # note that the behaviour is different between different editors when the
              # cursor is at the top, e.g. emacs doesn't do anything, but gedit (and
              # possibly many other editors) would start a selection from the cursor to
              # the beginning of the line. here we follow the latter.
              if shifting:
                let targetY = if globalState.cursor.y > 0: globalState.cursor.y-1 else: 0
                let targetX = (
                  if globalState.cursor.y > 0:
                    min(globalState.cursor.expectingX, globalState.session.getLineLength(targetY))
                  else:
                    0
                )
                if targetX != globalState.cursor.x or targetY != globalState.cursor.y:
                  if not globalState.selectionInEffect:
                    globalState.startSelection(globalState.cursor.x, globalState.cursor.y)
                  globalState.setSelectionLastPoint(targetX.cint, targetY.cint)
                  globalState.cursor.y = targetY.cint
                  globalState.cursor.x = targetX.cint
                  globalState.syncViewPort()
                  shouldRefresh = true
              else:
                if globalState.selectionInEffect:
                  globalState.invalidateSelection()
                  shouldRefresh = true
                globalState.cursorUp(globalState.session)

            of SDL_SCANCODE_DOWN:
              if globalState.cursor.y == globalState.session.lineCount(): break
              if shifting:
                let targetY = if globalState.cursor.y < globalState.session.lineCount(): globalState.cursor.y+1 else: globalState.session.lineCount().cint
                let targetX = (
                  if targetY < globalState.session.lineCount().cint:
                    min(globalState.cursor.expectingX, globalState.session.getLineLength(targetY))
                  else:
                    0
                )
                if targetX != globalState.cursor.x or targetY != globalState.cursor.y:
                  if not globalState.selectionInEffect:
                    globalState.startSelection(globalState.cursor.x, globalState.cursor.y)
                  globalState.setSelectionLastPoint(targetX.cint, targetY.cint)
                  globalState.cursor.y = targetY.cint
                  globalState.cursor.x = targetX.cint
                  globalState.syncViewPort()
                  shouldRefresh = true
              else:
                if globalState.selectionInEffect:
                  globalState.invalidateSelection()
                  shouldRefresh = true
                globalState.cursorDown(globalState.session)

            of SDL_SCANCODE_LEFT:
              if shifting:
                let targetY = if globalState.cursor.x > 0: globalState.cursor.y else: max(globalState.cursor.y-1, 0)
                let targetX = (
                  if globalState.cursor.x > 0:
                    (globalState.cursor.x-1).cint
                  else:
                    if globalState.cursor.y == 0:
                        0
                    else:
                      globalState.session.getLineLength(globalState.cursor.y-1).cint
                )
                if targetX != globalState.cursor.x or targetY != globalState.cursor.y:
                  if not globalState.selectionInEffect:
                    globalState.startSelection(globalState.cursor.x, globalState.cursor.y)
                  globalState.setSelectionLastPoint(targetX.cint, targetY.cint)
                  globalState.cursor.y = targetY.cint
                  globalState.cursor.x = targetX.cint
                  globalState.syncViewPort()
                  shouldRefresh = true
              else:
                if globalState.selectionInEffect:
                  globalState.invalidateSelection()
                  shouldRefresh = true
                globalState.cursorLeft(session)
                  
            of SDL_SCANCODE_RIGHT:
              if shifting:
                let targetY = (
                  if globalState.cursor.y >= globalState.session.lineCount():
                    globalState.session.lineCount()
                  elif globalState.cursor.x == globalState.session.getLineLength(globalState.cursor.y):
                    globalState.cursor.y + 1
                  else:
                    globalState.cursor.y
                )
                let targetX = (
                  if targetY >= globalState.session.lineCount():
                    0
                  elif globalState.cursor.x == globalState.session.getLineLength(globalState.cursor.y):
                    0
                  else:
                    globalState.cursor.x + 1
                )
                if targetX != globalState.cursor.x or targetY != globalState.cursor.y:
                  # if no selection but has shift then create selection
                  if not globalState.selectionInEffect:
                    globalState.startSelection(globalState.cursor.x, globalState.cursor.y)
                  globalState.setSelectionLastPoint(targetX.cint, targetY.cint)
                  globalState.cursor.y = targetY.cint
                  globalState.cursor.x = targetX.cint
                  globalState.syncViewPort()
                  shouldRefresh = true
              else:
                if not globalState.selectionInEffect:
                  globalState.invalidateSelection()
                  shouldRefresh = true
                globalState.cursorRight(session)

            else:

              let insertX = globalState.cursor.x
              let insertY = globalState.cursor.y
              let k = event.key.keysym.scancode.getKeyFromScancode

              if k == 13 and sdl2.getModState() == KMOD_NONE:
                discard globalState.session.insert(insertY, insertX, '\n')
                globalState.selectionInEffect = false
                globalState.setCursor(globalState.cursor.y + 1, 0)
                globalState.syncViewPort()
                shouldRefresh = true
              else:
                let alt = (modState and KMOD_ALT).bool
                if alt and not ctrl:
                  case k:
                    of 'w'.ord:
                      # copy.
                      echo "ssss"
                      if not globalState.selectionInEffect:
                        globalState.minibufferText = "No selection for cutting."
                        break
                      let start = min(globalState.selection.first, globalState.selection.last)
                      let last = max(globalState.selection.first, globalState.selection.last)
                      let data = globalState.session.getRangeString(start, last).cstring
                      discard sdl2.setClipboardText(data)
                      globalState.minibufferText = "Copied."
                      globalState.invalidateSelection()
                    else:
                      discard nil 
                elif ctrl and not alt:
                  case k:
                    of 'p'.ord:
                      # previous line.
                      globalState.cursorUp(globalState.session)
                    of 'n'.ord:
                      # next line.
                      globalState.cursorDown(globalState.session)
                    of 'a'.ord:
                      # home.
                      globalState.gotoLineStart()
                    of 'e'.ord:
                      # end.
                      globalState.gotoLineEnd()
                    of 'w'.ord:
                      # cut
                      if not globalState.selectionInEffect:
                        globalState.minibufferText = "No selection for cutting."
                        break
                      let start = min(globalState.selection.first, globalState.selection.last)
                      let last = max(globalState.selection.first, globalState.selection.last)
                      let data = globalState.session.getRangeString(start, last).cstring
                      discard sdl2.setClipboardText(data)
                      globalState.session.delete(start, last)
                      globalState.invalidateSelection()
                      globalState.resetCurrentCursor()
                      globalState.syncViewPort()
                      globalState.minibufferText = "Cut."
                    of 'y'.ord:
                      # paste.
                      let s = $getClipboardText()
                      if globalState.selectionInEffect:
                        let start = min(globalState.selection.first, globalState.selection.last)
                        let last = max(globalState.selection.last, globalState.selection.first)
                        globalState.session.delete(start, last)
                        globalState.setCursor(start.y, start.x)
                      let l = globalState.cursor.y
                      let c = globalState.cursor.x
                      let (dline, dcol) = globalState.session.insert(l, c, s)
                      if dline > 0:
                        globalState.cursor.y += dline.cint
                        globalState.cursor.x = dcol.cint
                      else:
                        globalState.cursor.x += dcol.cint
                      globalState.syncViewPort()
                      shouldRefresh = true
                      globalState.minibufferText = "Pasted."
                    of 's'.ord:
                      # save.
                      if globalState.session.fullPath.len > 0:
                        let data = globalState.session.toString
                        let f = open(globalState.session.fullPath, fmWrite)
                        f.write(data)
                        f.close()
                        globalState.session.resetDirtyState()
                      else:
                        globalState.minibufferText = "Not implemented."
                    of 'o'.ord:
                      # open.
                      discard nil
                    of 'r'.ord:
                      # reload.
                      shouldReload = true
                      shouldQuit = true
                      break
                    of 'g'.ord:
                      # exit.
                      shouldReload = false
                      shouldQuit = true
                      break
                    else:
                      discard nil

          shouldRefresh = true
        of sdl2.KeyUp:
          if not (sdl2.getModState() and sdl2.KMOD_CTRL).bool:
            unsetCtrl()
            shouldRefresh = true
          if not (sdl2.getModState() and sdl2.KMOD_ALT).bool:
            unsetAlt()
            shouldRefresh = true
          
        else:
          discard

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
  
    


