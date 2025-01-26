import sdl2
import ../model/[state, textbuffer]

type
  MainEventHandler* = ref object
    parentState*: State
    window*: WindowPtr
    renderer*: RendererPtr
    dstrect*: ptr Rect
    innerState: tuple[
      selectionInitiated: bool
    ]

proc mkMainEventHandler*(st: State, window: WindowPtr, renderer: RendererPtr, dstrect: ptr Rect): MainEventHandler =
  return MainEventHandler(
    parentState: st,
    window: window,
    renderer: renderer,
    dstrect: dstrect,
    innerState: (selectionInitiated: false)
  )

proc handleEvent*(eh: MainEventHandler, event: sdl2.Event, shouldQuit: var bool, shouldRefresh: var bool, shouldReload: var bool): void =
  let window = eh.window
  var st = eh.parentState
  # handle event here.
  case event.kind:
    of sdl2.QuitEvent:
      shouldQuit = true
      return

    of sdl2.WindowEvent:
      case event.window.event:
        of sdl2.WindowEvent_Resized:
          var w: cint
          var h: cint
          window.getSize(w, h)
          st.relayout(w, h)
          shouldRefresh = true
        of sdl2.WindowEvent_FocusGained:
          sdl2.startTextInput()
        of sdl2.WindowEvent_FocusLost:
          sdl2.stopTextInput()
        else:
          discard

    of sdl2.TextInput:
      # NOTE THAT when alt is activated this event is still fired when you type things
      # we bypass this by doing this thing:
      if (sdl2.getModState() and KMOD_ALT).bool: return
      if st.currentEditSession.selectionInEffect:
        let s1 = min(st.selection.first, st.selection.last)
        let s2 = max(st.selection.first, st.selection.last)
        st.currentEditSession.textBuffer.delete(s1, s2)
        st.currentEditSession.setCursor(s1.y.cint, s1.x.cint)
        st.currentEditSession.selectionInEffect = false
      var i = 0
      var l = st.currentEditSession.cursor.y
      var c = st.currentEditSession.cursor.x
      # event.text.text is not a cstring but an array[cchar]
      # that's why this is necessary.
      var s = ""
      while event.text.text[i] != '\x00':
        s.add(event.text.text[i])
        i += 1
      let (dline, dcol) = st.currentEditSession.textBuffer.insert(l, c, s)
      if dline > 0:
        st.currentEditSession.cursor.y += dline.cint
        st.currentEditSession.cursor.x = dcol.cint
      else:
        st.currentEditSession.cursor.x += dcol.cint
      st.syncViewPort()
      shouldRefresh = true
              
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
        st.horizontalScroll(step)
      else:
        st.verticalScroll(step)
      shouldRefresh = true
          
    of sdl2.MouseButtonDown:
      st.clearSelection()
      if sdl2.getModState().cint == sdl2.KMOD_NONE.cint:
        let y = max(0, min(st.convertMousePositionY(event.button.y), st.session.lineCount()))
        var x = (
          if y == st.session.lineCount():
            0
          else:
            max(0, min(st.session.getLineLength(y), st.convertMousePositionX(event.button.x)))
        )
        st.setCursor(y, x)
        st.cursor.expectingX = x.cint
        st.syncViewPort()
        eh.innerState.selectionInitiated = true
        st.selection.first.x = x.cint
        st.selection.first.y = y.cint
        shouldRefresh = true

    of sdl2.MouseButtonUp:
      let y = max(0, min(st.convertMousePositionY(event.button.y), st.session.lineCount()))
      var x = (
        if y == st.session.lineCount():
          0
        else:
          max(0, min(st.session.getLineLength(y), st.convertMousePositionX(event.button.x)))
      )
      if eh.innerState.selectionInitiated:
        if st.selection.first.x != x or st.selection.first.y != y:
          st.selectionInEffect = true
        eh.innerState.selectionInitiated = false
            
    of sdl2.MouseMotion:
      # This comparison here is to prevent re-render when the window is being dragged
      # around. normally this probably wouldn't be a problem when it's used with a
      # window manager / desktop environment under which windows would have title bars,
      # but I use xmonad and if you remove the window from the tiling layout and drag
      # it around it *would* register as sdl2.MouseMotion events. this probably would
      # break on other similar (but different from mine) setup...
      if sdl2.getModState() == KMOD_NONE:
        if not (event.motion.xrel == 0 and event.motion.yrel == 0):
          # check if it's left mouse button press...
          if (event.motion.state and 1).bool:
            let y = max(0, min(st.convertMousePositionY(event.motion.y), st.session.lineCount()))
            var x = (
              if y == st.session.lineCount():
                0
              else:
                max(0, min(st.session.getLineLength(y), st.convertMousePositionX(event.motion.x)))
            )
            if eh.innerState.selectionInitiated:
              st.selectionInEffect = true
              st.setSelectionLastPoint(x, y)
              st.cursor.x = x.cint
              st.cursor.y = y.cint
              st.syncViewPort()
            shouldRefresh = true
            
    of sdl2.KeyDown:
      let modState = sdl2.getModState()
      let ctrl = (modState and KMOD_CTRL).bool
      let alt = (modState and KMOD_ALT).bool
      let shifting = (sdl2.getModState() and KMOD_SHIFT).bool
      case event.key.keysym.scancode:
        of SDL_SCANCODE_HOME:
          let targetY = st.cursor.y
          let targetX = 0
          if shifting:
            if st.cursor.x != targetX or st.cursor.y != targetY:
              if not st.selectionInEffect:
                st.startSelection(st.cursor.x, st.cursor.y)
              st.setSelectionLastPoint(targetX, targetY)
              st.cursor.x = targetX.cint
              st.cursor.y = targetY.cint
              st.syncViewPort()
              shouldRefresh = true
            else:
              if st.selectionInEffect:
                st.invalidateSelection()
                shouldRefresh = true
              st.gotoLineStart()
        of SDL_SCANCODE_END:
          let targetY = st.cursor.y
          let targetX = if targetY >= st.session.lineCount(): 0 else: st.session.getLineLength(targetY)
          if shifting:
            if st.cursor.x != targetX or st.cursor.y != targetY:
              if not st.selectionInEffect:
                st.startSelection(st.cursor.x, st.cursor.y)
              st.setSelectionLastPoint(targetX, targetY)
              st.cursor.x = targetX.cint
              st.cursor.y = targetY.cint
              st.syncViewPort()
              shouldRefresh = true
          else:
            if st.selectionInEffect:
              st.invalidateSelection()
              shouldRefresh = true
            st.gotoLineEnd()
        of SDL_SCANCODE_DELETE:
          if st.selectionInEffect:
            let start = min(st.selection.first, st.selection.last)
            let last = max(st.selection.last, st.selection.first)
            st.session.delete(start, last)
            st.setCursor(start.y, start.x)
          else:
            st.session.deleteChar(st.cursor.y, st.cursor.x)
          st.invalidateSelection()
        of SDL_SCANCODE_BACKSPACE:
          # When there's selection we delete the selection (and set the cursor
          # at the start of the selection, which we will save beforehand).
          if st.selectionInEffect:
            let start = min(st.selection.first, st.selection.last)
            let last = max(st.selection.last, st.selection.first)
            st.session.delete(start, last)
            st.setCursor(start.y, start.x)
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
            var deleteY = st.cursor.y
            var deleteX = st.cursor.x
            # when cursor is at (lineCount(), 0) theoretically it should really be
            # (lineCount()-1, lineLength(lineCount()-1)).
            if deleteY >= st.session.lineCount():
              deleteY -= 1
              deleteX = st.session.getLineLength(deleteY).cint
              st.cursor.y -= 1
              st.cursor.x = st.session.getLineLength(deleteY).cint
            if deleteX == 0:
              if deleteY > 0:
                st.cursor.y -= 1
                st.cursor.x = st.session.getLineLength(st.cursor.y).cint
            else:
              st.cursor.x -= 1
            st.session.backspaceChar(deleteY, deleteX)
          st.syncViewPort()
          st.invalidateSelection()
        of SDL_SCANCODE_UP:
          # note that the behaviour is different between different editors when the
          # cursor is at the top, e.g. emacs doesn't do anything, but gedit (and
          # possibly many other editors) would start a selection from the cursor to
          # the beginning of the line. here we follow the latter.
          if shifting:
            let targetY = if st.cursor.y > 0: st.cursor.y-1 else: 0
            let targetX = (
              if st.cursor.y > 0:
                min(st.cursor.expectingX, st.session.getLineLength(targetY))
              else:
                0
            )
            if targetX != st.cursor.x or targetY != st.cursor.y:
              if not st.selectionInEffect:
                st.startSelection(st.cursor.x, st.cursor.y)
              st.setSelectionLastPoint(targetX.cint, targetY.cint)
              st.cursor.y = targetY.cint
              st.cursor.x = targetX.cint
              st.syncViewPort()
              shouldRefresh = true
          else:
            if st.selectionInEffect:
              st.invalidateSelection()
              shouldRefresh = true
            st.cursorUp(st.session)

        of SDL_SCANCODE_DOWN:
          if st.cursor.y == st.session.lineCount(): return
          if shifting:
            let targetY = if st.cursor.y < st.session.lineCount(): st.cursor.y+1 else: st.session.lineCount().cint
            let targetX = (
              if targetY < st.session.lineCount().cint:
                min(st.cursor.expectingX, st.session.getLineLength(targetY))
              else:
                0
            )
            if targetX != st.cursor.x or targetY != st.cursor.y:
              if not st.selectionInEffect:
                st.startSelection(st.cursor.x, st.cursor.y)
              st.setSelectionLastPoint(targetX.cint, targetY.cint)
              st.cursor.y = targetY.cint
              st.cursor.x = targetX.cint
              st.syncViewPort()
              shouldRefresh = true
          else:
            if st.selectionInEffect:
              st.invalidateSelection()
              shouldRefresh = true
            st.cursorDown(st.session)

        of SDL_SCANCODE_LEFT:
          if shifting:
            let targetY = if st.cursor.x > 0: st.cursor.y else: max(st.cursor.y-1, 0)
            let targetX = (
              if st.cursor.x > 0:
                (st.cursor.x-1).cint
              else:
                if st.cursor.y == 0:
                    0
                else:
                  st.session.getLineLength(st.cursor.y-1).cint
            )
            if targetX != st.cursor.x or targetY != st.cursor.y:
              if not st.selectionInEffect:
                st.startSelection(st.cursor.x, st.cursor.y)
              st.setSelectionLastPoint(targetX.cint, targetY.cint)
              st.cursor.y = targetY.cint
              st.cursor.x = targetX.cint
              st.syncViewPort()
              shouldRefresh = true
          else:
            if st.selectionInEffect:
              st.invalidateSelection()
              shouldRefresh = true
            st.cursorLeft(st.session)
                  
        of SDL_SCANCODE_RIGHT:
          if shifting:
            let targetY = (
              if st.cursor.y >= st.session.lineCount():
                st.session.lineCount()
              elif st.cursor.x == st.session.getLineLength(st.cursor.y):
                st.cursor.y + 1
              else:
                st.cursor.y
            )
            let targetX = (
              if targetY >= st.session.lineCount():
                0
              elif st.cursor.x == st.session.getLineLength(st.cursor.y):
                0
              else:
                st.cursor.x + 1
            )
            if targetX != st.cursor.x or targetY != st.cursor.y:
              # if no selection but has shift then create selection
              if not st.selectionInEffect:
                st.startSelection(st.cursor.x, st.cursor.y)
              st.setSelectionLastPoint(targetX.cint, targetY.cint)
              st.cursor.y = targetY.cint
              st.cursor.x = targetX.cint
              st.syncViewPort()
              shouldRefresh = true
          else:
            if not st.selectionInEffect:
              st.invalidateSelection()
              shouldRefresh = true
            st.cursorRight(st.session)

        else:
          let insertX = st.cursor.x
          let insertY = st.cursor.y
          let k = event.key.keysym.scancode.getKeyFromScancode
          if k == 13 and sdl2.getModState() == KMOD_NONE:
            discard st.session.insert(insertY, insertX, '\n')
            st.selectionInEffect = false
            st.setCursor(st.cursor.y + 1, 0)
            st.syncViewPort()
            shouldRefresh = true
          else:
            let alt = (modState and KMOD_ALT).bool
            if alt and not ctrl:
              case k:
                of 'w'.ord:
                  # copy.
                  echo "ssss"
                  if not st.selectionInEffect:
                    st.minibufferText = "No selection for cutting."
                  else:
                    let start = min(st.selection.first, st.selection.last)
                    let last = max(st.selection.first, st.selection.last)
                    let data = st.session.getRangeString(start, last).cstring
                    discard sdl2.setClipboardText(data)
                    st.minibufferText = "Copied."
                    st.invalidateSelection()
                else:
                  discard nil 
            elif ctrl and not alt:
              case k:
                of 'p'.ord:
                  # previous line.
                  st.cursorUp(st.session)
                of 'n'.ord:
                  # next line.
                  st.cursorDown(st.session)
                of 'a'.ord:
                  # home.
                  st.gotoLineStart()
                of 'e'.ord:
                  # end.
                  st.gotoLineEnd()
                of 'w'.ord:
                  # cut
                  if not st.selectionInEffect:
                    st.minibufferText = "No selection for cutting."
                  else:
                    let start = min(st.selection.first, st.selection.last)
                    let last = max(st.selection.first, st.selection.last)
                    let data = st.session.getRangeString(start, last).cstring
                    discard sdl2.setClipboardText(data)
                    st.session.delete(start, last)
                    st.invalidateSelection()
                    st.resetCurrentCursor()
                    st.syncViewPort()
                    st.minibufferText = "Cut."
                of 'y'.ord:
                  # paste.
                  let s = $getClipboardText()
                  if st.selectionInEffect:
                    let start = min(st.selection.first, st.selection.last)
                    let last = max(st.selection.last, st.selection.first)
                    st.session.delete(start, last)
                    st.setCursor(start.y, start.x)
                  let l = st.cursor.y
                  let c = st.cursor.x
                  let (dline, dcol) = st.session.insert(l, c, s)
                  if dline > 0:
                    st.cursor.y += dline.cint
                    st.cursor.x = dcol.cint
                  else:
                    st.cursor.x += dcol.cint
                  st.syncViewPort()
                  shouldRefresh = true
                  st.minibufferText = "Pasted."
                of 's'.ord:
                  # save.
                  if st.session.fullPath.len > 0:
                    let data = st.session.toString
                    let f = open(st.session.fullPath, fmWrite)
                    f.write(data)
                    f.close()
                    st.session.resetDirtyState()
                  else:
                    st.minibufferText = "Not implemented."
                of 'o'.ord:
                  # open.
                  discard nil
                of 'r'.ord:
                  # reload.
                  shouldReload = true
                  shouldQuit = true
                of 'g'.ord:
                  # exit.
                  shouldReload = false
                  shouldQuit = true
                else:
                  discard nil

      shouldRefresh = true
      
    else:
      discard
