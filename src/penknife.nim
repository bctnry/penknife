import std/[syncio, strformat, cmdline]
import std/strutils
import std/paths
import std/unicode
import sdl2
import sdl2/ttf
import model/[textbuffer, editsession, state, cursor, undoredo]
import ui/[tvfont, timer]
import component/[cursorview, editorview, editorframe]
import config
import aux

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

var shouldReload: bool = false
var globalState: State = mkNewState()
proc main(): int =
  if not init(): return QuitFailure

  # load font according to config
  var gfontFileName = getGlobalConfig(CONFIG_KEY_FONT_PATH)
  var gfontSize = getGlobalConfig(CONFIG_KEY_FONT_SIZE).parseInt
  if not loadFont(globalState.globalStyle.font, gfontFileName.cstring, gfontSize):
    logError(&"Failed to load gfont {gfontFileName.repr}.")
    return QuitFailure

  # load color according to config
  globalState.globalStyle.mainColor.loadColorFromString(getGlobalConfig(CONFIG_MAIN_COLOR))
  globalState.globalStyle.backgroundColor.loadColorFromString(getGlobalConfig(CONFIG_BACKGROUND_COLOR))
  globalState.globalStyle.auxColor.loadColorFromString(getGlobalConfig(CONFIG_AUX_COLOR))
  globalState.globalStyle.highlightColor.loadColorFromString(getGlobalConfig(CONFIG_HIGHLIGHT_COLOR))
  globalState.globalStyle.font.useNewMainColor(globalState.globalStyle.mainColor)
  globalState.globalStyle.font.useNewAuxColor(globalState.globalStyle.auxColor)

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

  # setup textbuffer
  if paramCount() <= 0:
    globalState.loadText("")
  else:
    let fn = paramStr(1)
    let f = open(fn, fmRead)
    let s = f.readAll()
    f.close()
    globalState.loadText(s, name=fn.Path.extractFilename.string, fullPath=fn.Path.absolutePath.string)
  var session = globalState.currentEditSession

  # setup grid
  var gridSize = globalState.gridSize
  gridSize.h = globalState.globalStyle.font.h
  gridSize.w = globalState.globalStyle.font.w

  var event: sdl2.Event
  var shouldQuit: bool = false
  
  var w, h: cint
  window.getSize(w, h)

  var editorFrame = mkEditorFrame(globalState)
  var cursorView = editorFrame.cursor
  var editorView = editorFrame.editorView
  editorFrame.relayout(0, 0, w div gridSize.w, h div gridSize.h)

  var cursorDrawn = false
  var shouldRefresh = false
  var selectionInitiated = false
  var selectionInitiationX = 0
  var selectionInitiationY = 0
  var cursorBlinkTimer = mkInterval((
    proc (): void =
      cursorView.renderWith(renderer)
  ), 1000)
  # cursorBlinkTimer.start()

  while not shouldQuit:
    shouldRefresh = false
    cursorDrawn = false

    if sdl2.waitEvent(event).bool:
      # handle event here.
      case event.kind:
        of sdl2.QuitEvent:
          shouldQuit = true
          break

        of sdl2.WindowEvent:
          case event.window.event:
            of sdl2.WindowEvent_Resized:
              window.getSize(w, h)
              editorFrame.relayout(0, 0, w div gridSize.w, h div gridSize.h)
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
          if not (sdl2.getModState() and KMOD_ALT).bool:
            if globalState.currentEditSession.selectionInEffect:
              let s1 = min(globalState.currentEditSession.selection.first, globalState.currentEditSession.selection.last)
              let s2 = max(globalState.currentEditSession.selection.first, globalState.currentEditSession.selection.last)
              globalState.currentEditSession.textBuffer.delete(s1, s2)
              globalState.currentEditSession.setCursor(s1.y, s1.x)
              globalState.currentEditSession.selectionInEffect = false
            var i = 0
            var l = globalState.currentEditSession.cursor.y
            var c = globalState.currentEditSession.cursor.x
            var s = ""
            while event.text.text[i] != '\x00':
              s.add(event.text.text[i])
              i += 1
            globalState.currentEditSession.recordInsertAction(mkNewCursor(c, l), s.toRunes())
            let (dline, dcol) = globalState.currentEditSession.textBuffer.insert(l, c, s)
            if dline > 0:
              globalState.currentEditSession.cursor.y += dline.cint
              globalState.currentEditSession.cursor.x = dcol.cint
            else:
              globalState.currentEditSession.cursor.x += dcol.cint
            globalState.currentEditSession.syncViewPort()
            shouldRefresh = true
            # echo "input"
              
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
            globalState.currentEditSession.horizontalScroll(step)
          else:
            globalState.currentEditSession.verticalScroll(step)
          shouldRefresh = true
          
        of sdl2.MouseButtonDown:
          globalState.currentEditSession.invalidateSelectedState()
          if sdl2.getModState().cint == sdl2.KMOD_NONE.cint:
            let relativeGridY = event.button.y div gridSize.h
            let line = max(0,
                           min(globalState.currentEditSession.viewPort.y + relativeGridY,
                               globalState.currentEditSession.textBuffer.lineCount()) - editorView.offsetY
            )
            var x = 0
            if line < globalState.currentEditSession.textBuffer.lineCount():
              let relativeGridX = (event.button.x div gridSize.w) - editorView.offsetX
              let baseGridX = session.textBuffer.canonicalXToGridX(globalState.globalStyle.font,
                                                        globalState.currentEditSession.viewPort.x, line)
              let absoluteGridX = max(0, baseGridX + relativeGridX)
              let absoluteCanonicalX = session.textBuffer.gridXToCanonicalX(globalState.globalStyle.font,
                                                                 absoluteGridX,
                                                                 line)
              x = max(0, min(globalState.currentEditSession.textBuffer.getLineLength(line), absoluteCanonicalX))
            let y = line
            x = min(x, globalState.currentEditSession.textBuffer.getLineOfRune(y).len)
            globalState.currentEditSession.setCursor(y, x)
            globalState.currentEditSession.cursor.expectingX = x.cint
            globalState.currentEditSession.syncViewPort()
            selectionInitiated = true
            selectionInitiationX = x
            selectionInitiationY = y
            globalState.currentEditSession.selection.first.x = x.cint
            globalState.currentEditSession.selection.first.y = y.cint
            shouldRefresh = true

        of sdl2.MouseButtonUp:
          let relativeGridY = event.button.y div gridSize.h
          let y = max(0, min(globalState.currentEditSession.viewPort.y + relativeGridY, globalState.currentEditSession.textBuffer.lineCount()) - editorView.offsetY)
          var x = 0
          if y < globalState.currentEditSession.textBuffer.lineCount():
            let relativeGridX = (event.button.x div gridSize.w) - editorView.offsetX
            let baseGridX = session.textBuffer.canonicalXToGridX(globalState.globalStyle.font,
                                                                 globalState.currentEditSession.viewPort.x, y)
            let absoluteGridX = max(0, baseGridX + relativeGridX)
            let absoluteCanonicalX = session.textBuffer.gridXToCanonicalX(globalState.globalStyle.font,
                                                                          absoluteGridX,
                                                                          y)
            x = max(0, min(globalState.currentEditSession.textBuffer.getLineLength(y), absoluteCanonicalX))
          x = min(x, globalState.currentEditSession.textBuffer.getLineOfRune(y).len)
          if selectionInitiated:
            if globalState.currentEditSession.selection.first.x != x or globalState.currentEditSession.selection.first.y != y:
              globalState.currentEditSession.selectionInEffect = true
            selectionInitiated = false
            
        of sdl2.MouseMotion:
          if sdl2.getModState() == KMOD_NONE:
            if not (event.motion.xrel == 0 and event.motion.yrel == 0):
              if (event.motion.state == BUTTON_LEFT).bool:
                let relativeGridY = event.motion.y div gridSize.h
                let line = max(0,
                               min(globalState.currentEditSession.viewPort.y + relativeGridY,
                                   globalState.currentEditSession.textBuffer.lineCount()) - editorView.offsetY
                )
                var x = 0
                if line < globalState.currentEditSession.textBuffer.lineCount():
                  let relativeGridX = (event.motion.x div gridSize.w) - editorView.offsetX
                  let baseGridX = session.textBuffer.canonicalXToGridX(globalState.globalStyle.font,
                                                            globalState.currentEditSession.viewPort.x, line)
                  let absoluteGridX = max(0, baseGridX + relativeGridX)
                  let absoluteCanonicalX = session.textBuffer.gridXToCanonicalX(globalState.globalStyle.font,
                                                                     absoluteGridX,
                                                                     line)
                  x = max(0, min(globalState.currentEditSession.textBuffer.getLineLength(line), absoluteCanonicalX))
                let y = line
                x = min(x, globalState.currentEditSession.textBuffer.getLineOfRune(y).len)
                if selectionInitiated:
                  globalState.currentEditSession.selectionInEffect = true
                  globalState.currentEditSession.setSelectionLastPoint(x, y)
                  globalState.currentEditSession.cursor.x = x.cint
                  globalState.currentEditSession.cursor.y = y.cint
                  globalState.currentEditSession.syncViewPort()
                shouldRefresh = true
            
        of sdl2.KeyDown:
          let shifting = (sdl2.getModState() and KMOD_SHIFT).bool
          let ctrl = (sdl2.getModState() and KMOD_CTRL).bool
          let alt = (sdl2.getModState() and KMOD_ALT).bool
          case event.key.keysym.scancode:
            of SDL_SCANCODE_HOME:
              let targetY = globalState.currentEditSession.cursor.y
              let targetX = 0
              if shifting:
                if globalState.currentEditSession.cursor.x != targetX or globalState.currentEditSession.cursor.y != targetY:
                  if not globalState.currentEditSession.selectionInEffect:
                    globalState.currentEditSession.startSelection(globalState.currentEditSession.cursor.x, globalState.currentEditSession.cursor.y)
                  globalState.currentEditSession.setSelectionLastPoint(targetX, targetY)
                  globalState.currentEditSession.cursor.x = targetX.cint
                  globalState.currentEditSession.cursor.y = targetY.cint
                  globalState.currentEditSession.syncViewPort()
                  shouldRefresh = true
              else:
                if globalState.currentEditSession.selectionInEffect:
                  globalState.currentEditSession.invalidateSelectedState()
                  shouldRefresh = true
                globalState.currentEditSession.gotoLineStart()
            of SDL_SCANCODE_END:
              let targetY = globalState.currentEditSession.cursor.y
              let targetX = if targetY >= globalState.currentEditSession.textBuffer.lineCount(): 0 else: globalState.currentEditSession.textBuffer.getLineLength(targetY)
              if shifting:
                if globalState.currentEditSession.cursor.x != targetX or globalState.currentEditSession.cursor.y != targetY:
                  if not globalState.currentEditSession.selectionInEffect:
                    globalState.currentEditSession.startSelection(globalState.currentEditSession.cursor.x, globalState.currentEditSession.cursor.y)
                  globalState.currentEditSession.setSelectionLastPoint(targetX, targetY)
                  globalState.currentEditSession.cursor.x = targetX.cint
                  globalState.currentEditSession.cursor.y = targetY.cint
                  globalState.currentEditSession.syncViewPort()
                  shouldRefresh = true
              else:
                if globalState.currentEditSession.selectionInEffect:
                  globalState.currentEditSession.invalidateSelectedState()
                  shouldRefresh = true
                globalState.currentEditSession.gotoLineEnd()
            of SDL_SCANCODE_DELETE:
              if globalState.currentEditSession.selectionInEffect:
                let start = min(globalState.currentEditSession.selection.first, globalState.currentEditSession.selection.last)
                let last = max(globalState.currentEditSession.selection.last, globalState.currentEditSession.selection.first)
                globalState.currentEditSession.textBuffer.delete(start, last)
                globalState.currentEditSession.setCursor(start.y, start.x)
              else:
                globalState.currentEditSession.textBuffer.deleteChar(globalState.currentEditSession.cursor.y, globalState.currentEditSession.cursor.x)
              globalState.currentEditSession.invalidateSelectedState()
            of SDL_SCANCODE_BACKSPACE:
              # When there's selection we delete the selection (and set the cursor
              # at the start of the selection, which we will save beforehand).
              if globalState.currentEditSession.selectionInEffect:
                let start = min(globalState.currentEditSession.selection.first, globalState.currentEditSession.selection.last)
                let last = max(globalState.currentEditSession.selection.last, globalState.currentEditSession.selection.first)
                globalState.currentEditSession.textBuffer.delete(start, last)
                globalState.currentEditSession.setCursor(start.y, start.x)
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
                var deleteY = globalState.currentEditSession.cursor.y
                var deleteX = globalState.currentEditSession.cursor.x
                if deleteY >= globalState.currentEditSession.textBuffer.lineCount():
                  deleteY -= 1
                  deleteX = globalState.currentEditSession.textBuffer.getLineLength(deleteY).cint
                  globalState.currentEditSession.cursor.y -= 1
                  globalState.currentEditSession.cursor.x = globalState.currentEditSession.textBuffer.getLineLength(deleteY).cint
                if deleteX == 0:
                  if deleteY > 0:
                    globalState.currentEditSession.cursor.y -= 1
                    globalState.currentEditSession.cursor.x = globalState.currentEditSession.textBuffer.getLineLength(globalState.currentEditSession.cursor.y).cint
                else:
                  globalState.currentEditSession.cursor.x -= 1
                globalState.currentEditSession.textBuffer.backspaceChar(deleteY, deleteX)
              globalState.currentEditSession.syncViewPort()
              globalState.currentEditSession.invalidateSelectedState()
            of SDL_SCANCODE_UP:
              # note that the behaviour is different between different editors when the
              # cursor is at the top, e.g. emacs doesn't do anything, but gedit (and
              # possibly many other editors) would start a selection from the cursor to
              # the beginning of the line. here we follow the latter.
              if shifting:
                let targetY = if globalState.currentEditSession.cursor.y > 0: globalState.currentEditSession.cursor.y-1 else: 0
                let targetX = (
                  if globalState.currentEditSession.cursor.y > 0:
                    min(globalState.currentEditSession.cursor.expectingX, globalState.currentEditSession.textBuffer.getLineLength(targetY))
                  else:
                    0
                )
                if targetX != globalState.currentEditSession.cursor.x or targetY != globalState.currentEditSession.cursor.y:
                  if not globalState.currentEditSession.selectionInEffect:
                    globalState.currentEditSession.startSelection(globalState.currentEditSession.cursor.x, globalState.currentEditSession.cursor.y)
                  globalState.currentEditSession.setSelectionLastPoint(targetX.cint, targetY.cint)
                  globalState.currentEditSession.cursor.y = targetY.cint
                  globalState.currentEditSession.cursor.x = targetX.cint
                  globalState.currentEditSession.syncViewPort()
                  shouldRefresh = true
              else:
                if globalState.currentEditSession.selectionInEffect:
                  globalState.currentEditSession.invalidateSelectedState()
                  shouldRefresh = true
                globalState.currentEditSession.cursorUp()

            of SDL_SCANCODE_DOWN:
              if not (globalState.currentEditSession.cursor.y > globalState.currentEditSession.textBuffer.lineCount()):
                if shifting:
                  let targetY = if globalState.currentEditSession.cursor.y < globalState.currentEditSession.textBuffer.lineCount(): globalState.currentEditSession.cursor.y+1 else: globalState.currentEditSession.textBuffer.lineCount().cint
                  let targetX = (
                    if targetY < globalState.currentEditSession.textBuffer.lineCount().cint:
                      min(globalState.currentEditSession.cursor.expectingX, globalState.currentEditSession.textBuffer.getLineLength(targetY))
                    else:
                      0
                  )
                  if targetX != globalState.currentEditSession.cursor.x or targetY != globalState.currentEditSession.cursor.y:
                    if not globalState.currentEditSession.selectionInEffect:
                      globalState.currentEditSession.startSelection(globalState.currentEditSession.cursor.x, globalState.currentEditSession.cursor.y)
                    globalState.currentEditSession.setSelectionLastPoint(targetX.cint, targetY.cint)
                    globalState.currentEditSession.cursor.y = targetY.cint
                    globalState.currentEditSession.cursor.x = targetX.cint
                    globalState.currentEditSession.syncViewPort()
                    shouldRefresh = true
                else:
                  if globalState.currentEditSession.selectionInEffect:
                    globalState.currentEditSession.invalidateSelectedState()
                    shouldRefresh = true
                  globalState.currentEditSession.cursorDown()

            of SDL_SCANCODE_LEFT:
              if shifting:
                let targetY = if globalState.currentEditSession.cursor.x > 0: globalState.currentEditSession.cursor.y else: max(globalState.currentEditSession.cursor.y-1, 0)
                let targetX = (
                  if globalState.currentEditSession.cursor.x > 0:
                    (globalState.currentEditSession.cursor.x-1).cint
                  else:
                    if globalState.currentEditSession.cursor.y == 0:
                        0
                    else:
                      globalState.currentEditSession.textBuffer.getLineLength(globalState.currentEditSession.cursor.y-1).cint
                )
                if targetX != globalState.currentEditSession.cursor.x or targetY != globalState.currentEditSession.cursor.y:
                  if not globalState.currentEditSession.selectionInEffect:
                    globalState.currentEditSession.startSelection(globalState.currentEditSession.cursor.x, globalState.currentEditSession.cursor.y)
                  globalState.currentEditSession.setSelectionLastPoint(targetX.cint, targetY.cint)
                  globalState.currentEditSession.cursor.y = targetY.cint
                  globalState.currentEditSession.cursor.x = targetX.cint
                  globalState.currentEditSession.syncViewPort()
                  shouldRefresh = true
              else:
                if globalState.currentEditSession.selectionInEffect:
                  globalState.currentEditSession.invalidateSelectedState()
                  shouldRefresh = true
                globalState.currentEditSession.cursorLeft()
                  
            of SDL_SCANCODE_RIGHT:
              if shifting:
                let targetY = (
                  if globalState.currentEditSession.cursor.y >= globalState.currentEditSession.textBuffer.lineCount():
                    globalState.currentEditSession.textBuffer.lineCount()
                  elif globalState.currentEditSession.cursor.x == globalState.currentEditSession.textBuffer.getLineLength(globalState.currentEditSession.cursor.y):
                    globalState.currentEditSession.cursor.y + 1
                  else:
                    globalState.currentEditSession.cursor.y
                )
                let targetX = (
                  if targetY >= globalState.currentEditSession.textBuffer.lineCount():
                    0
                  elif globalState.currentEditSession.cursor.x == globalState.currentEditSession.textBuffer.getLineLength(globalState.currentEditSession.cursor.y):
                    0
                  else:
                    globalState.currentEditSession.cursor.x + 1
                )
                if targetX != globalState.currentEditSession.cursor.x or targetY != globalState.currentEditSession.cursor.y:
                  # if no selection but has shift then create selection
                  if not globalState.currentEditSession.selectionInEffect:
                    globalState.currentEditSession.startSelection(globalState.currentEditSession.cursor.x, globalState.currentEditSession.cursor.y)
                  globalState.currentEditSession.setSelectionLastPoint(targetX.cint, targetY.cint)
                  globalState.currentEditSession.cursor.y = targetY.cint
                  globalState.currentEditSession.cursor.x = targetX.cint
                  globalState.currentEditSession.syncViewPort()
                  shouldRefresh = true
              else:
                if not globalState.currentEditSession.selectionInEffect:
                  globalState.currentEditSession.invalidateSelectedState()
                  shouldRefresh = true
                globalState.currentEditSession.cursorRight()

            else:

              let insertX = globalState.currentEditSession.cursor.x
              let insertY = globalState.currentEditSession.cursor.y
              let k = event.key.keysym.scancode.getKeyFromScancode

              if k == 13 and sdl2.getModState() == KMOD_NONE:
                discard globalState.currentEditSession.textBuffer.insert(insertY, insertX, '\n')
                globalState.currentEditSession.selectionInEffect = false
                globalState.currentEditSession.setCursor(globalState.currentEditSession.cursor.y + 1, 0)
                globalState.currentEditSession.syncViewPort()
                shouldRefresh = true
              else:

                if alt and ctrl:
                  case k:
                    of 's'.ord:
                      # save-as.
                      discard nil
                    of '/'.ord:
                      # redo.
                      globalState.currentEditSession.undoRedoStack.redo(globalState.currentEditSession.textBuffer)
                    else:
                      discard nil
                      
                elif alt and not ctrl:
                  case k:
                    of 'w'.ord:
                      # copy.
                      if globalState.currentEditSession.selectionInEffect:
                        let start = min(globalState.currentEditSession.selection.first, globalState.currentEditSession.selection.last)
                        let last = max(globalState.currentEditSession.selection.first, globalState.currentEditSession.selection.last)
                        let data = globalState.currentEditSession.textBuffer.getRangeString(start, last).cstring
                        discard sdl2.setClipboardText(data)
                        globalState.currentEditSession.invalidateSelectedState()
                    else:
                      discard

                elif ctrl and not alt:
                  case k:
                    of '/'.ord:
                      # undo.
                      globalState.currentEditSession.undoRedoStack.undo(globalState.currentEditSession.textBuffer)
                    of 'p'.ord:
                      # previous line.
                      globalState.currentEditSession.cursorUp()
                    of 'n'.ord:
                      # next line.
                      globalState.currentEditSession.cursorDown()
                    of 'a'.ord:
                      # home.
                      globalState.currentEditSession.gotoLineStart()
                    of 'e'.ord:
                      # end.
                      globalState.currentEditSession.gotoLineEnd()
                    of 'w'.ord:
                      # cut
                      if not globalState.currentEditSession.selectionInEffect:
                        discard nil
                      else:
                        let start = min(globalState.currentEditSession.selection.first, globalState.currentEditSession.selection.last)
                        let last = max(globalState.currentEditSession.selection.first, globalState.currentEditSession.selection.last)
                        let data = globalState.currentEditSession.textBuffer.getRange(start, last)
                        globalState.currentEditSession.recordDeleteAction(start, data)
                        discard sdl2.setClipboardText(($data).cstring)
                        globalState.currentEditSession.textBuffer.delete(start, last)
                        globalState.currentEditSession.invalidateSelectedState()
                        globalState.currentEditSession.resetCurrentCursor()
                        globalState.currentEditSession.syncViewPort()
                    of 'y'.ord:
                      # paste.
                      let s = $getClipboardText()
                      if globalState.currentEditSession.selectionInEffect:
                        let start = min(globalState.currentEditSession.selection.first, globalState.currentEditSession.selection.last)
                        let last = max(globalState.currentEditSession.selection.last, globalState.currentEditSession.selection.first)
                        globalState.currentEditSession.textBuffer.delete(start, last)
                        globalState.currentEditSession.setCursor(start.y, start.x)
                      let l = globalState.currentEditSession.cursor.y
                      let c = globalState.currentEditSession.cursor.x
                      let (dline, dcol) = globalState.currentEditSession.textBuffer.insert(l, c, s)
                      if dline > 0:
                        globalState.currentEditSession.cursor.y += dline.cint
                        globalState.currentEditSession.cursor.x = dcol.cint
                      else:
                        globalState.currentEditSession.cursor.x += dcol.cint
                      globalState.currentEditSession.syncViewPort()
                      shouldRefresh = true
                    of 's'.ord:
                      # save.
                      discard nil
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
                else:
                  discard nil
                        
          shouldRefresh = true
        else:
          discard

    # echo $globalState.currentEditSession.undoRedoStack
        
    cursorBlinkTimer.check()
    if not shouldRefresh: continue

    # echo "re-render"
    
    # render screen here.
    renderer.setDrawColor(globalState.globalStyle.backgroundColor.r,
                          globalState.globalStyle.backgroundColor.g,
                          globalState.globalStyle.backgroundColor.b)
    renderer.clear()

    editorFrame.render(renderer)
    
    # draw cursor.
    if cursorBlinkTimer.paused or cursorBlinkTimer.stopped:
      renderer.render(cursorView, flat=true)
    
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
  
    


