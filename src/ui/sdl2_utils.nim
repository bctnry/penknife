from sdl2 import color, Color

proc fromHexDigit(x: char): int {.inline.} =
  if 'a' <= x and x <= 'f': return (x.ord - 'a'.ord + 10)
  elif 'A' <= x and x <= 'F': return (x.ord - 'A'.ord + 10)
  elif '0' <= x and x <= '9': return (x.ord - '0'.ord)
  else: return 0

proc parseColor*(x: string): Color =
  # only support #rrggbb
  if not x.len == 7: return sdl2.color(0, 0, 0, 0)
  let r = (x[1].fromHexDigit * 16 + x[2].fromHexDigit).uint8
  let g = (x[3].fromHexDigit * 16 + x[4].fromHexDigit).uint8
  let b = (x[5].fromHexDigit * 16 + x[6].fromHexDigit).uint8
  return sdl2.color(r.cint, g.cint, b.cint, 0)
  
proc loadColorFromString*(c: var Color, x: string): void =
  if not x.len == 7: return
  c.r = (x[1].fromHexDigit * 16 + x[2].fromHexDigit).uint8
  c.g = (x[3].fromHexDigit * 16 + x[4].fromHexDigit).uint8
  c.b = (x[5].fromHexDigit * 16 + x[6].fromHexDigit).uint8
  c.a = 0
  return
  
