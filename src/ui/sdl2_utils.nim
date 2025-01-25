import sdl2
from sdl2/ttf import renderUtf8Blended
from font import TVFont
from texture import LTexture, dispose

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

proc mkTextTexture*(renderer: RendererPtr, gfont: TVFont, str: cstring, color: sdl2.Color): LTexture =
  if str.len == 0: return nil
  let surface = gfont.raw.renderUtf8Blended(str, color)
  if surface.isNil: return nil
  let w = surface.w
  let h = surface.h
  let texture = renderer.createTextureFromSurface(surface)
  if texture.isNil:
    surface.freeSurface()
    return nil
  surface.freeSurface()
  return LTexture(raw: texture, w: w, h: h)
  
proc renderTextSolid*(renderer: RendererPtr, dstrect: ptr Rect,
                      gfont: TVFont,
                      str: cstring,
                      x: cint, y: cint,
                      color: sdl2.Color): cint =
    # if str is empty surface would be nil, so we have to
    # do it here to separate it from the case where there's
    # a surface creation error.
    if str.len == 0: return 0
    let texture = renderer.mkTextTexture(gfont, str, color)
    let w = texture.w
    dstrect.x = x
    dstrect.y = y
    dstrect.w = texture.w
    dstrect.h = texture.h
    renderer.copyEx(texture.raw, nil, dstrect, 0.cdouble, nil)
    texture.dispose()
    return w
    
