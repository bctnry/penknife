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
    currentEditSession*: EditSession
    gridSize*: GridSizeDescriptor
    globalStyle*: Style
    keyMap*: FKeyMap
    keySession*: FKeySession
    auxEditSession*: EditSession

proc globalFont*(s: State): TVFont {.inline.} =
  return s.globalStyle.font

proc mkNewState*(): State =
  State(currentEditSession: mkEditSession(),
        gridSize: GridSizeDescriptor(w: 0, h: 0),
        globalStyle: mkStyle(),
        keyMap: mkFKeyMap(),
        keySession: mkFKeySession(),
        auxEditSession: mkEditSession()
  )

proc loadText*(st: State, s: string, name: string = "*unnamed*", fullPath: string = ""): void =
  st.currentEditSession.textBuffer = s.fromString
  st.currentEditSession.textBuffer.name = name
  st.currentEditSession.textBuffer.fullPath = fullPath
  st.auxEditSession.textBuffer = (name & " | " & fullPath).fromString
  st.auxEditSession.textBuffer.name = "*aux*"
  st.auxEditSession.textBuffer.fullPath = ""
  
                              
