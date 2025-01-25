import sdl2/ttf

type
  TVFont* = ref object
    raw*: FontPtr
    w*: cint
    h*: cint
  
proc loadFont*(file: cstring, f: var TVFont, size: int): bool =
  let font = ttf.openFont(file, size.cint)
  if font.isNil:
    return false
  f.raw = font
  discard ttf.sizeUtf8(font, "x".cstring, f.w.addr, f.h.addr)
  return true

  
