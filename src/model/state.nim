import std/unicode
from sdl2 import color
import textbuffer
import cursor
import selection
import editsession
import style
import ../ui/tvfont
import viewport

  
type
  GridSizeDescriptor* = ref object
    w*: cint
    h*: cint
  State* = ref object
    currentEditSession*: EditSession
    gridSize*: GridSizeDescriptor
    globalStyle*: Style

proc globalFont*(s: State): TVFont {.inline.} =
  return s.globalStyle.font

proc mkNewState*(): State =
  State(currentEditSession: mkEditSession(),
        gridSize: GridSizeDescriptor(w: 0, h: 0),
        globalStyle: mkStyle()
  )

proc loadText*(st: State, s: string, name: string = "*unnamed*", fullPath: string = ""): void =
  st.currentEditSession.textBuffer = s.fromString
  st.currentEditSession.textBuffer.name = name
  st.currentEditSession.textBuffer.fullPath = fullPath
                              
