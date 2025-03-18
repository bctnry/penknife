import std/tables
import sdl2
import ../ui/tvfont

type
  StyleColorClass* = enum
    MAIN_FOREGROUND
    MAIN_BACKGROUND
    MAIN_SELECT_FOREGROUND
    MAIN_SELECT_BACKGROUND
    AUX_FOREGROUND
    AUX_BACKGROUND
    AUX_SELECT_FOREGROUND
    AUX_SELECT_BACKGROUND
    MAIN_LINENUMBER_FOREGROUND
    MAIN_LINENUMBER_BACKGROUND
    MAIN_LINENUMBER_SELECT_FOREGROUND
    MAIN_LINENUMBER_SELECT_BACKGROUND
    MAIN_COMMENT_FOREGROUND   # for comments.
    MAIN_KEYWORD_FOREGROUND   # for keywords.
    MAIN_AUXKEYWORD_FOREGROUND   # for "aux keywords"
    MAIN_STRING_FOREGROUND    # for string literals
    MAIN_TYPE_FOREGROUND    # for types
    MAIN_SPECIALID_FOREGROUND    # for identifiers at special positions
    STATUSBAR_BACKGROUND
    STATUSBAR_FOREGROUND

proc `$`(scc: StyleColorClass): string =
  case scc:
    of MAIN_FOREGROUND: "MAIN_FOREGROUND"
    of MAIN_BACKGROUND: "MAIN_BACKGROUND"
    of MAIN_SELECT_FOREGROUND: "MAIN_SELECT_FOREGROUND"
    of MAIN_SELECT_BACKGROUND: "MAIN_SELECT_BACKGROUND"
    of AUX_FOREGROUND: "AUX_FOREGROUND"
    of AUX_BACKGROUND: "AUX_BACKGROUND"
    of AUX_SELECT_FOREGROUND: "AUX_SELECT_FOREGROUND"
    of AUX_SELECT_BACKGROUND: "AUX_SELECT_BACKGROUND"
    of MAIN_LINENUMBER_FOREGROUND: "MAIN_LINENUMBER_FOREGROUND"
    of MAIN_LINENUMBER_BACKGROUND: "MAIN_LINENUMBER_BACKGROUND"
    of MAIN_LINENUMBER_SELECT_FOREGROUND: "MAIN_LINENUMBER_SELECT_FOREGROUND"
    of MAIN_LINENUMBER_SELECT_BACKGROUND: "MAIN_LINENUMBER_SELECT_BACKGROUND"
    of MAIN_COMMENT_FOREGROUND: "MAIN_COMMENT_FOREGROUND"
    of MAIN_KEYWORD_FOREGROUND: "MAIN_KEYWORD_FOREGROUND"
    of MAIN_AUXKEYWORD_FOREGROUND: "MAIN_AUXKEYWORD_FOREGROUND"
    of MAIN_STRING_FOREGROUND: "MAIN_STRING_FOREGROUND"
    of MAIN_TYPE_FOREGROUND: "MAIN_TYPE_FOREGROUND"
    of MAIN_SPECIALID_FOREGROUND: "MAIN_SPECIALID_FOREGROUND"
    of STATUSBAR_BACKGROUND: "STATUSBAR_BACKGROUND"
    of STATUSBAR_FOREGROUND: "STATUSBAR_FOREGROUND"

proc fallback*(scc: StyleColorClass): StyleColorClass =
  case scc:
    of MAIN_COMMENT_FOREGROUND: MAIN_FOREGROUND
    of MAIN_KEYWORD_FOREGROUND: MAIN_FOREGROUND
    of MAIN_AUXKEYWORD_FOREGROUND: MAIN_KEYWORD_FOREGROUND
    of MAIN_STRING_FOREGROUND: MAIN_FOREGROUND
    of MAIN_TYPE_FOREGROUND: MAIN_FOREGROUND
    of MAIN_SPECIALID_FOREGROUND: MAIN_FOREGROUND
    of MAIN_LINENUMBER_FOREGROUND: MAIN_FOREGROUND
    of MAIN_LINENUMBER_BACKGROUND: MAIN_BACKGROUND
    of MAIN_LINENUMBER_SELECT_FOREGROUND: MAIN_SELECT_FOREGROUND
    of MAIN_LINENUMBER_SELECT_BACKGROUND: MAIN_SELECT_BACKGROUND
    of STATUSBAR_FOREGROUND: AUX_FOREGROUND
    of STATUSBAR_BACKGROUND: AUX_BACKGROUND
    else: return scc

type
  Style* = ref object
    colorDict*: TableRef[StyleColorClass, sdl2.Color]
    font*: TVFont

proc mkStyle*(): Style =
  let s = newTable[StyleColorClass, sdl2.Color]()
  return Style(colorDict: s, font: TVFont(raw: nil, w: 0, h: 0))
  
proc getColor*(s: Style, scc: StyleColorClass): sdl2.Color =
  var oldScc = scc
  var newScc = scc
  while (not s.colorDict.hasKey(oldScc)):
    newScc = oldScc.fallback
    if newScc == oldScc: return s.colorDict[MAIN_FOREGROUND]
    oldScc = newScc
  return s.colorDict[oldScc]

proc fromHexDigit(x: char): int {.inline.} =
  if 'a' <= x and x <= 'f': return (x.ord - 'a'.ord + 10)
  elif 'A' <= x and x <= 'F': return (x.ord - 'A'.ord + 10)
  elif '0' <= x and x <= '9': return (x.ord - '0'.ord)
  else: return 0

proc setColorByString*(s: Style, scc: StyleColorClass, cstr: string): void =
  echo "set color ", scc, " by ", cstr
  if (cstr.len != 7) and (cstr.len != 9) : return
  if not s.colorDict.hasKey(scc): s.colorDict[scc] = sdl2.color(0, 0, 0, 0)
  s.colorDict[scc].r = (cstr[1].fromHexDigit * 16 + cstr[2].fromHexDigit).uint8
  s.colorDict[scc].g = (cstr[3].fromHexDigit * 16 + cstr[4].fromHexDigit).uint8
  s.colorDict[scc].b = (cstr[5].fromHexDigit * 16 + cstr[6].fromHexDigit).uint8
  if cstr.len == 9:
    s.colorDict[scc].a = (cstr[7].fromHexDigit * 16 + cstr[8].fromHexDigit).uint8

proc mainColor*(s: Style): sdl2.Color =
  return s.colorDict[MAIN_FOREGROUND]

proc backgroundColor*(s: Style): sdl2.Color =
  return s.colorDict[MAIN_BACKGROUND]
  
proc auxColor*(s: Style): sdl2.Color =
  return s.colorDict[AUX_FOREGROUND]
  
proc highlightColor*(s: Style): sdl2.Color =
  return s.colorDict[AUX_BACKGROUND]

