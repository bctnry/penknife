import std/unicode
import sdl2
import tvfont
import texture
import ../aux

proc isFullWidthByFont*(k: Rune, font: TVFont): bool {.inline.} =
  let v = font.determineRuneGridWidth(k)
  return if v == 0: k.isFullWidth else: v == 2
