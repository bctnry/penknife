import std/[syncio, strformat, cmdline]
import std/strutils
import std/paths
import std/unicode
import sdl2
import sdl2/ttf
import model/[textbuffer, editsession, state, cursor, undoredo, keyseq, style]
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

  globalState.keySession.stateInterface = StateInterface(
    currentEditSession: proc (): EditSession = return globalState.currentEditSession,
    globalStyle: proc(): Style = return globalState.globalStyle,
    keySession: proc(): FKeySession = return globalState.keySession,
    focusOnAux: proc(): bool = return globalState.focusOnAux,
    toggleFocus: proc(): void = globalState.focusOnAux = not globalState.focusOnAux
  )
  globalState.keySession.root = globalState.keyMap.nMap
  globalState.keySession.globalOverride = globalState.keyMap.globalOverrideMap

                                          

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
      editorFrame.cursor.renderWith(renderer)
      editorFrame.auxCursor.renderWith(renderer)
  ), 1000)
  # cursorBlinkTimer.start()

  let HomeCallback = (
    proc (si: StateInterface): void =
      let session = si.currentEditSession()
      if session.selectionInEffect:
        session.invalidateSelectedState()
      session.gotoLineStart()
      shouldRefresh = true
  )
  discard globalState.keyMap.registerFKeyCallback(
    @["<home>"],
    HomeCallback
  )
  discard globalState.keyMap.registerFKeyCallback(
    @["C-a"],
    HomeCallback
  )
  
  let ShiftHomeCallback = (
    proc (si: StateInterface): void =
      let session = si.currentEditSession()
      let targetY = session.cursor.y
      let targetX = 0
      if session.cursor.x != targetX or session.cursor.y != targetY:
        if not session.selectionInEffect:
          session.startSelection(session.cursor.x, session.cursor.y)
        session.setSelectionLastPoint(targetX, targetY)
        session.cursor.x = targetX.cint
        session.cursor.y = targetY.cint
        session.syncViewPort()
        shouldRefresh = true
  )
  discard globalState.keyMap.registerFKeyCallback(
    @["S-<home>"],
    ShiftHomeCallback
  )
  discard globalState.keyMap.registerFKeyCallback(
    @["CS-a"],
    ShiftHomeCallback
  )
  
  let EndCallback = (
    proc (si: StateInterface): void =
      let session = si.currentEditSession()
      let targetY = session.cursor.y
      let targetX = if targetY >= session.textBuffer.lineCount(): 0 else: session.textBuffer.getLineLength(targetY)
      if session.selectionInEffect:
        session.invalidateSelectedState()
        shouldRefresh = true
      session.gotoLineEnd()
  )
  discard globalState.keyMap.registerFKeyCallback(
    @["<end>"],
    EndCallback
  )
  discard globalState.keyMap.registerFKeyCallback(
    @["C-e"],
    EndCallback
  )

  let ShiftEndCallback = (
    proc (si: StateInterface): void =
      let session = si.currentEditSession()
      let targetY = session.cursor.y
      let targetX = if targetY >= session.textBuffer.lineCount(): 0 else: session.textBuffer.getLineLength(targetY)
      if session.cursor.x != targetX or session.cursor.y != targetY:
        if not session.selectionInEffect:
          session.startSelection(session.cursor.x, session.cursor.y)
        session.setSelectionLastPoint(targetX, targetY)
        session.cursor.x = targetX.cint
        session.cursor.y = targetY.cint
        session.syncViewPort()
        shouldRefresh = true
  )
  discard globalState.keyMap.registerFKeyCallback(
    @["S-<end>"],
    ShiftEndCallback
  )
  discard globalState.keyMap.registerFKeyCallback(
    @["CS-e"],
    ShiftEndCallback
  )
  
  discard globalState.keyMap.registerFKeyCallback(
    @["M-w"],
    proc (si: StateInterface): void =
      let session = si.currentEditSession()
      if session.selectionInEffect:
        let start = min(session.selection.first, session.selection.last)
        let last = max(session.selection.first, session.selection.last)
        let data = session.textBuffer.getRangeString(start, last).cstring
        discard sdl2.setClipboardText(data)
        session.invalidateSelectedState()
  )
  discard globalState.keyMap.registerFKeyCallback(
    @["<del>"],
    proc (si: StateInterface): void =
      let session = si.currentEditSession()
      if session.selectionInEffect:
        let start = min(session.selection.first, session.selection.last)
        let last = max(session.selection.last, session.selection.first)
        session.textBuffer.delete(start, last)
        session.setCursor(start.y, start.x)
      else:
        session.textBuffer.deleteChar(session.cursor.y, session.cursor.x)
      session.invalidateSelectedState()
  )
  discard globalState.keyMap.registerFKeyCallback(
    @["<backspace>"],
    proc (si: StateInterface): void =
      let session = si.currentEditSession()
      # When there's selection we delete the selection (and set the cursor
      # at the start of the selection, which we will save beforehand).
      if session.selectionInEffect:
        let start = min(session.selection.first, session.selection.last)
        let last = max(session.selection.last, session.selection.first)
        session.textBuffer.delete(start, last)
        session.setCursor(start.y, start.x)
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
        var deleteY = session.cursor.y
        var deleteX = session.cursor.x
        if deleteY >= session.textBuffer.lineCount():
          deleteY -= 1
          deleteX = session.textBuffer.getLineLength(deleteY).cint
          session.cursor.y -= 1
          session.cursor.x = session.textBuffer.getLineLength(deleteY).cint
        if deleteX == 0:
          if deleteY > 0:
            session.cursor.y -= 1
            session.cursor.x = session.textBuffer.getLineLength(session.cursor.y).cint
        else:
          session.cursor.x -= 1
        session.textBuffer.backspaceChar(deleteY, deleteX)
      session.syncViewPort()
      session.invalidateSelectedState()
  )
  
  let UpCallback = (
    proc (si: StateInterface): void =
      let session = si.currentEditSession()
      if session.selectionInEffect:
        session.invalidateSelectedState()
        shouldRefresh = true
      session.cursorUp()
  )
  discard globalState.keyMap.registerFKeyCallback(
    @["<up>"],
    UpCallback
  )
  discard globalState.keyMap.registerFKeyCallback(
    @["C-p"],
    UpCallback
  )
  
  # note that the behaviour is different between different editors when the
  # cursor is at the top, e.g. emacs doesn't do anything, but gedit (and
  # possibly many other editors) would start a selection from the cursor to
  # the beginning of the line. here we follow the latter.
  let ShiftUpCallback = (
    proc (si: StateInterface): void =
      let session = si.currentEditSession()
      let targetY = if session.cursor.y > 0: session.cursor.y-1 else: 0
      let targetX = (
        if session.cursor.y > 0:
          min(session.cursor.expectingX, session.textBuffer.getLineLength(targetY))
        else:
          0
      )
      if targetX != session.cursor.x or targetY != session.cursor.y:
        if not session.selectionInEffect:
          session.startSelection(session.cursor.x, session.cursor.y)
        session.setSelectionLastPoint(targetX.cint, targetY.cint)
        session.cursor.y = targetY.cint
        session.cursor.x = targetX.cint
        session.syncViewPort()
        shouldRefresh = true
  )
  discard globalState.keyMap.registerFKeyCallback(
    @["S-<up>"],
    ShiftUpCallback
  )
  discard globalState.keyMap.registerFKeyCallback(
    @["CS-p"],
    ShiftUpCallback
  )

  let DownCallback = (
    proc (si: StateInterface): void =
      let session = si.currentEditSession()
      if session.selectionInEffect:
        session.invalidateSelectedState()
        shouldRefresh = true
      session.cursorDown()
  )
  discard globalState.keyMap.registerFKeyCallback(
    @["<down>"],
    DownCallback
  )
  discard globalState.keyMap.registerFKeyCallback(
    @["C-n"],
    DownCallback
  )

  let ShiftDownCallback = (
    proc (si: StateInterface): void =
      let session = si.currentEditSession()
      if not (session.cursor.y > session.textBuffer.lineCount()):
        let targetY = (if session.cursor.y < session.textBuffer.lineCount():
                         session.cursor.y+1
                       else:
                         session.textBuffer.lineCount().cint)
        let targetX = (
          if targetY < session.textBuffer.lineCount().cint:
            min(session.cursor.expectingX, session.textBuffer.getLineLength(targetY))
          else:
            0
        )
        if targetX != session.cursor.x or targetY != session.cursor.y:
          if not session.selectionInEffect:
            session.startSelection(session.cursor.x, session.cursor.y)
          session.setSelectionLastPoint(targetX.cint, targetY.cint)
          session.cursor.y = targetY.cint
          session.cursor.x = targetX.cint
          session.syncViewPort()
          shouldRefresh = true
  )
  discard globalState.keyMap.registerFKeyCallback(
    @["S-<down>"],
    ShiftDownCallback
  )
  discard globalState.keyMap.registerFKeyCallback(
    @["CS-n"],
    ShiftDownCallback
  )

  let LeftCallback = (
    proc (si: StateInterface): void =
      let session = si.currentEditSession()
      if session.selectionInEffect:
        session.invalidateSelectedState()
      session.cursorLeft()
      shouldRefresh = true
  )
  discard globalState.keyMap.registerFKeyCallback(
    @["<left>"],
    LeftCallback
  )
  discard globalState.keyMap.registerFKeyCallback(
    @["C-b"],
    LeftCallback
  )

  let ShiftLeftCallback = (
    proc (si: StateInterface): void =
      let session = si.currentEditSession()
      let targetY = (if session.cursor.x > 0: session.cursor.y
                     else: max(session.cursor.y-1, 0))
      let targetX = (
        if session.cursor.x > 0:
          (session.cursor.x-1).cint
        else:
          if session.cursor.y == 0:
            0
          else:
            session.textBuffer.getLineLength(session.cursor.y-1).cint
      )
      if targetX != session.cursor.x or targetY != session.cursor.y:
        if not session.selectionInEffect:
          session.startSelection(session.cursor.x, session.cursor.y)
        session.setSelectionLastPoint(targetX.cint, targetY.cint)
        session.cursor.y = targetY.cint
        session.cursor.x = targetX.cint
        session.syncViewPort()
        shouldRefresh = true
  )
  discard globalState.keyMap.registerFKeyCallback(
    @["S-<left>"],
    ShiftLeftCallback
  )
  discard globalState.keyMap.registerFKeyCallback(
    @["CS-b"],
    ShiftLeftCallback
  )

  let RightCallback = (
    proc (si: StateInterface): void =
      let session = si.currentEditSession()
      if session.selectionInEffect:
        session.invalidateSelectedState()
      session.cursorRight()
      shouldRefresh = true
  )
  discard globalState.keyMap.registerFKeyCallback(
    @["<right>"],
    RightCallback
  )
  discard globalState.keyMap.registerFKeyCallback(
    @["C-f"],
    RightCallback
  )

  let ShiftRightCallback = (
    proc (si: StateInterface): void =
      let session = si.currentEditSession()
      let targetY = (
        if session.cursor.y >= session.textBuffer.lineCount():
          session.textBuffer.lineCount()
        elif session.cursor.x == session.textBuffer.getLineLength(session.cursor.y):
          session.cursor.y + 1
        else:
          session.cursor.y
      )
      let targetX = (
        if targetY >= session.textBuffer.lineCount():
          0
        elif session.cursor.x == session.textBuffer.getLineLength(session.cursor.y):
          0
        else:
          session.cursor.x + 1
      )
      if targetX != session.cursor.x or targetY != session.cursor.y:
        # if no selection but has shift then create selection
        if not session.selectionInEffect:
          session.startSelection(session.cursor.x, session.cursor.y)
        session.setSelectionLastPoint(targetX.cint, targetY.cint)
        session.cursor.y = targetY.cint
        session.cursor.x = targetX.cint
        session.syncViewPort()
        shouldRefresh = true
  )
  discard globalState.keyMap.registerFKeyCallback(
    @["S-<right>"],
    ShiftRightCallback
  )
  discard globalState.keyMap.registerFKeyCallback(
    @["CS-f"],
    ShiftRightCallback
  )

  discard globalState.keyMap.registerFKeyCallback(
    @["C-w"],
    proc (si: StateInterface): void =
      let session = si.currentEditSession()
      if not session.selectionInEffect:
        discard nil
      else:
        let start = min(session.selection.first, session.selection.last)
        let last = max(session.selection.first, session.selection.last)
        let data = session.textBuffer.getRange(start, last)
        session.recordDeleteAction(start, data)
        discard sdl2.setClipboardText(($data).cstring)
        session.textBuffer.delete(start, last)
        session.invalidateSelectedState()
        session.resetCurrentCursor()
        session.syncViewPort()
  )

  discard globalState.keyMap.registerFKeyCallback(
    @["C-k"],
    proc (si: StateInterface): void =
      let session = si.currentEditSession()
      if session.cursor.y >= session.textBuffer.lineCount(): return
      let cutStart = session.cursor.x
      let cutEnd = session.textBuffer.getLineLength(session.cursor.y)
      session.selection.first.x = cutStart.cint
      session.selection.first.y = session.cursor.y.cint
      session.selection.last.x = cutEnd.cint
      session.selection.last.y = session.cursor.y.cint
      let start = session.selection.first
      let last = session.selection.last
      let data = session.textBuffer.getRange(start, last)
      discard sdl2.setClipboardText(($data).cstring)
      session.textBuffer.delete(start, last)
      session.invalidateSelectedState()
      session.resetCurrentCursor()
      session.syncViewPort()
  )
  discard globalState.keyMap.registerFKeyCallback(
    @["C-v", "C-m"],
    proc (si: StateInterface): void =
      echo "hello!"
  )

  discard globalState.keyMap.registerFKeyCallback(
    @["C-y"],
    proc (si: StateInterface): void =
      let session = si.currentEditSession()
      let s = $getClipboardText()
      if session.selectionInEffect:
        let start = min(session.selection.first, session.selection.last)
        let last = max(session.selection.last, session.selection.first)
        session.textBuffer.delete(start, last)
        session.setCursor(start.y, start.x)
      let l = session.cursor.y
      let c = session.cursor.x
      let (dline, dcol) = session.textBuffer.insert(l, c, s)
      if dline > 0:
        session.cursor.y += dline.cint
        session.cursor.x = dcol.cint
      else:
        session.cursor.x += dcol.cint
      session.syncViewPort()
      shouldRefresh = true
  )

  discard globalState.keyMap.registerFKeyCallback(
    @["C-r"],
    proc (si: StateInterface): void =
      shouldReload = true
      shouldQuit = true
  )
  
  globalState.keyMap.registerGlobalOverrideCallback(
    "C-q",
    proc (si: StateInterface): void =
      si.keySession().cancelCurrentSequence()
  )
  
  discard globalState.keyMap.registerFKeyCallback(
    @["C-g"],
    proc (si: StateInterface): void =
      shouldReload = false
      shouldQuit = true
  )

  discard globalState.keyMap.registerFKeyCallback(
    @["M-<up>"],
    proc (si: StateInterface): void =
      if not si.focusOnAux():
        si.toggleFocus()
        editorFrame.auxCursor.moveIMEBoxToCursorView()
        shouldRefresh = true
  )
  
  discard globalState.keyMap.registerFKeyCallback(
    @["M-<down>"],
    proc (si: StateInterface): void =
      if si.focusOnAux():
        si.toggleFocus()
        editorFrame.cursor.moveIMEBoxToCursorView()
        shouldRefresh = true
  )

  var firstTime = true
  
  while not shouldQuit:
    shouldRefresh = false
    cursorDrawn = false

    if firstTime:
      firstTime = false
      shouldRefresh = true
    elif sdl2.waitEvent(event).bool:
      # handle event here.
      case event.kind:
        of sdl2.QuitEvent:
          shouldQuit = true
          break

        of sdl2.WindowEvent:
          case event.window.event:
            of sdl2.WindowEvent_Resized:
              window.getSize(w, h)
              globalState.windowWidth = w div gridSize.w
              globalState.windowHeight = h div gridSize.h
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
          var keyDescriptor = ""
          let shifting = (sdl2.getModState() and KMOD_SHIFT).bool
          let ctrl = (sdl2.getModState() and KMOD_CTRL).bool
          let alt = (sdl2.getModState() and KMOD_ALT).bool
          if ctrl: keyDescriptor &= "C"
          if alt: keyDescriptor &= "M"
          if shifting: keyDescriptor &= "S"
          if keyDescriptor.len > 0: keyDescriptor &= "-"
          case event.key.keysym.scancode:
            of SDL_SCANCODE_HOME: keyDescriptor &= "<home>"
            of SDL_SCANCODE_END: keyDescriptor &= "<end>"
            of SDL_SCANCODE_DELETE: keyDescriptor &= "<del>"
            of SDL_SCANCODE_BACKSPACE: keyDescriptor &= "<backspace>"
            of SDL_SCANCODE_UP: keyDescriptor &= "<up>"
            of SDL_SCANCODE_DOWN: keyDescriptor &= "<down>"
            of SDL_SCANCODE_LEFT: keyDescriptor &= "<left>"
            of SDL_SCANCODE_RIGHT: keyDescriptor &= "<right>"
            of SDL_SCANCODE_PAGEUP: keyDescriptor &= "<pgup>"
            of SDL_SCANCODE_PAGEDOWN: keyDescriptor &= "<pgdn>"
            of SDL_SCANCODE_F1: keyDescriptor &= "<f1>"
            of SDL_SCANCODE_F2: keyDescriptor &= "<f2>"
            of SDL_SCANCODE_F3: keyDescriptor &= "<f3>"
            of SDL_SCANCODE_F4: keyDescriptor &= "<f4>"
            of SDL_SCANCODE_F5: keyDescriptor &= "<f5>"
            of SDL_SCANCODE_F6: keyDescriptor &= "<f6>"
            of SDL_SCANCODE_F7: keyDescriptor &= "<f7>"
            of SDL_SCANCODE_F8: keyDescriptor &= "<f8>"
            of SDL_SCANCODE_F9: keyDescriptor &= "<f9>"
            of SDL_SCANCODE_F10: keyDescriptor &= "<f10>"
            of SDL_SCANCODE_F11: keyDescriptor &= "<f11>"
            of SDL_SCANCODE_F12: keyDescriptor &= "<f12>"
            else:
              let k = event.key.keysym.scancode.getKeyFromScancode
              if k == 13 and sdl2.getModState() == KMOD_NONE:
                keyDescriptor = ""
                let insertX = globalState.currentEditSession.cursor.x
                let insertY = globalState.currentEditSession.cursor.y
                discard globalState.currentEditSession.textBuffer.insert(insertY, insertX, '\n')
                globalState.currentEditSession.selectionInEffect = false
                globalState.currentEditSession.setCursor(globalState.currentEditSession.cursor.y + 1, 0)
                globalState.currentEditSession.syncViewPort()
                shouldRefresh = true
              else:
                case k:
                  of '\n'.ord: keyDescriptor &= "<return>"
                  of '\t'.ord: keyDescriptor &= "<tab>"
                  else:
                    if k in 0..255 and k.chr in PrintableChars:
                      keyDescriptor &= k.chr
          if keyDescriptor.len > 0:
            discard globalState.keySession.recordAndTryExecute(keyDescriptor)
                        
          shouldRefresh = true
        else:
          discard
          
    if shouldQuit: break

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
    renderer.render(editorFrame.cursor, flat=true)
    renderer.render(editorFrame.auxCursor, flat=true)
    
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
  
    


