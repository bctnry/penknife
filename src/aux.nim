import std/unicode
import sdl2

proc makeRune*(ch: char): Rune {.inline.} =
  return ($ch).runeAt(0)
  
# these ranges are designated as east asian wide and east asian fullwidth:
# ('0x3250', '0xa48c')
# ('0xac00', '0xd7a3')
# ('0xf900', '0xfaff')
# ('0xff01', '0xff60')
# ('0xffe0', '0xffe6')
# ('0x20000', '0x3ffff')
# there are many more but these are the ones i'm checking
proc makeRune*(n: int32): Rune {.compileTime.} =
  var res: string = ""
  if n <= 0x7f: res.add((n.uint8 and 0xff).chr)
  elif n <= 0x7ff:
    let b1 = 0xc0 or (n shr 6)
    let b2 = 0x80 or (n and 0x3f)
    res.add(b1.chr)
    res.add(b2.chr)
  elif n <= 0xffff:
    let b1 = 0xe0 or (n shr 12)
    let b2 = 0x80 or ((n shr 6) and 0x3f)
    let b3 = 0x80 or (n and 0x3f)
    res.add(b1.chr)
    res.add(b2.chr)
    res.add(b3.chr)
  else:
    let b1 = 0xf0 or (n shr 18)
    let b2 = 0x80 or ((n shr 12) and 0x3f)
    let b3 = 0x80 or ((n shr 6) and 0x3f)
    let b4 = 0x80 or (n and 0x3f)
    res.add(b1.chr)
    res.add(b2.chr)
    res.add(b3.chr)
    res.add(b4.chr)
  return res.toRunes()[0]
const RANGE1_BEGIN = 0x3250.makeRune()
const RANGE1_END = 0xa48c.makeRune()
const RANGE2_BEGIN = 0xac00.makeRune()
const RANGE2_END = 0x7da3.makeRune()
const RANGE3_BEGIN = 0xf900.makeRune()
const RANGE3_END = 0xfaff.makeRune()
const RANGE4_BEGIN = 0xff01.makeRune()
const RANGE4_END = 0xff60.makeRune()
const RANGE5_BEGIN = 0xffe0.makeRune()
const RANGE5_END = 0xffe6.makeRune()
const RANGE6_BEGIN = 0x20000.makeRune()
const RANGE6_END = 0x3ffff.makeRune()

proc isFullWidth*(ch: Rune): bool =
  return (
    (RANGE1_BEGIN <=% ch and ch <=% RANGE1_END) or
    (RANGE2_BEGIN <=% ch and ch <=% RANGE2_END) or
    (RANGE3_BEGIN <=% ch and ch <=% RANGE3_END) or
    (RANGE4_BEGIN <=% ch and ch <=% RANGE4_END) or
    (RANGE5_BEGIN <=% ch and ch <=% RANGE5_END) or
    (RANGE6_BEGIN <=% ch and ch <=% RANGE6_END)
  )
  

proc digitCount*(x: int): int =
  var m = 10
  var res = 1
  while m < x:
    m *= 10
    res += 1
  return res
  

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

  
