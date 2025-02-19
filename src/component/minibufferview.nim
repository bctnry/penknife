import std/[unicode, paths]
import sdl2
import ../model/[state, textbuffer]
import ../ui/[sdl2_ui_utils, texture, tvfont]

# status bar.

type
  MinibufferView* = ref object
    parentState*: State
    dstrect*: Rect

proc mkMinibufferView*(st: State): MinibufferView =
  return MinibufferView(
    parentState: st,
    dstrect: (x: 0, y: 0, w: 0, h: 0)
  )

proc render*(renderer: RendererPtr, mv: MinibufferView): void =
  let st = mv.parentState
  let offsetPY = (st.viewPort.offsetY*st.gridSize.h).cint
  var text = st.minibufferText
  if st.minibufferMode:
    text &= $(st.minibufferInputValue)
    text &= "_"
  if text.len > 0:
    discard st.globalFont.renderUTF8Blended(
      text, renderer, nil,
      0, offsetPY+((st.viewPort.h + 1)*st.gridSize.h).cint,
      false
    )
  
proc renderWith*(tb: MinibufferView, renderer: RendererPtr): void =
  renderer.render(tb)

proc resolveCommand(mv: MinibufferView): void
proc handleEvent*(mv: MinibufferView, event: sdl2.Event, shouldRefresh: var bool, shouldQuit: var bool): void =
  let st = mv.parentState
  case event.kind:
    of sdl2.QuitEvent:
      shouldQuit = true
    of sdl2.WindowEvent:
      case event.window.event:
        of sdl2.WindowEvent_Resized:
          var w: cint
          var h: cint
          getWindowFromId(event.window.windowID).getSize(w, h)
          st.relayout(w, h)
          shouldRefresh = true
        of sdl2.WindowEvent_FocusGained:
          sdl2.startTextInput()
        of sdl2.WindowEvent_FocusLost:
          sdl2.stopTextInput()
        else:
          discard
    of sdl2.TextInput:
      if (sdl2.getModState() and KMOD_ALT).bool: return
      var i = 0
      var l = st.cursor.y
      var c = st.cursor.x
      var s = ""
      while event.text.text[i] != '\x00':
        s.add(event.text.text[i])
        i += 1
      st.minibufferInputValue = st.minibufferInputValue &  s.toRunes
      shouldRefresh = true

    of sdl2.KeyDown:
      let modState = sdl2.getModState()
      let ctrl = (modState and KMOD_CTRL).bool
      let alt = (modState and KMOD_ALT).bool
      let none = modState == KMOD_NONE
      case event.key.keysym.scancode:
        of SDL_SCANCODE_BACKSPACE:
          discard st.minibufferInputValue.pop()
          shouldRefresh = true
        else:
          let k = event.key.keysym.scancode.getKeyFromScancode
          if ctrl:
            case k:
              of 'g'.ord:
                st.minibufferCommand = MM_NONE
                st.minibufferText = ""
                st.minibufferInputValue = @[]
                st.minibufferMode = false
                shouldRefresh = true
              else:
                discard nil
          elif none:
            if k == 13:
              st.minibufferMode = false
              st.minibufferText = ""
              mv.resolveCommand()
            shouldRefresh = true

    else:
      discard nil

proc resolveCommand(mv: MinibufferView): void =
  let globalState = mv.parentState
  block minibufferCommandHandling:
    if globalState.minibufferCommand != MM_NONE:
      case globalState.minibufferCommand:
        of MM_PROMPT_SAVE_AND_OPEN_FILE:
          let answer = $(globalState.minibufferInputValue)
          if answer != "y" and answer != "n":
            globalState.minibufferText = "Please enter \"y\" or \"n\". "
            globalState.minibufferCommand = MM_PROMPT_SAVE_AND_OPEN_FILE
            globalState.minibufferInputValue = @[]
            globalState.minibufferMode = true
            break minibufferCommandHandling
          if answer == "y":
             let data = globalState.session.toString
             let f = open(globalState.session.fullPath, fmWrite)
             f.write(data)
             f.close()
             globalState.session.resetDirtyState()
          globalState.minibufferText = "Open: "
          globalState.minibufferCommand = MM_OPEN_AND_LOAD_FILE
          globalState.minibufferInputValue = @[]
          globalState.minibufferMode = true
          break minibufferCommandHandling

        of MM_OPEN_AND_LOAD_FILE:
          let ps = $(globalState.minibufferInputValue)
          let f = open(ps, fmRead)
          let s = f.readAll()
          f.close()
          let p = ps.Path
          globalState.loadText(s, name=p.extractFilename.string, fullPath=p.absolutePath.string)
        of MM_SAVE_FILE:
          let p = ($(globalState.minibufferInputValue)).Path
          globalState.session.name = p.extractFilename.string
          globalState.session.fullPath = p.absolutePath.string
          let data = globalState.session.toString
          let f = open(globalState.session.fullPath, fmWrite)
          f.write(data)
          f.close()
          globalState.session.resetDirtyState()
        else:
          discard nil
      globalState.minibufferCommand = MM_NONE
      globalState.minibufferInputValue = @[]
