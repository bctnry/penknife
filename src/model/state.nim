import textbuffer
import editsession
import style
import keyseq
import ../ui/tvfont

  
type
  GridSizeDescriptor* = ref object
    w*: cint
    h*: cint
  State* = ref object
    mainEditSession*: EditSession
    gridSize*: GridSizeDescriptor
    globalStyle*: Style
    keyMap*: FKeyMap
    keySession*: FKeySession
    auxEditSession*: EditSession
    focusOnAux*: bool
    windowWidth*: cint
    windowHeight*: cint

proc globalFont*(s: State): TVFont {.inline.} =
  return s.globalStyle.font

proc mkNewState*(): State =
  State(mainEditSession: mkEditSession(),
        gridSize: GridSizeDescriptor(w: 0, h: 0),
        globalStyle: mkStyle(),
        keyMap: mkFKeyMap(),
        keySession: mkFKeySession(),
        auxEditSession: mkEditSession(),
        focusOnAux: false,
        windowWidth: 0,
        windowHeight: 0
  )

proc currentEditSession*(s: State): EditSession =
  if s.focusOnAux: return s.auxEditSession
  else: return s.mainEditSession

proc loadText*(st: State, s: string, name: string = "*unnamed*", fullPath: string = ""): void =
  st.mainEditSession.textBuffer = s.fromString
  st.mainEditSession.textBuffer.name = name
  st.mainEditSession.textBuffer.fullPath = fullPath
  st.auxEditSession.textBuffer = (name & " | " & fullPath).fromString
  st.auxEditSession.textBuffer.name = "*aux*"
  st.auxEditSession.textBuffer.fullPath = ""
  
                              
