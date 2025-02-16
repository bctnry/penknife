import std/unicode
import sdl2
import tvfont
import texture
import ../aux

proc isFullWidthByFont*(k: Rune, font: TVFont): bool {.inline.} =
  let v = font.determineRuneGridWidth(k)
  return if v == 0: k.isFullWidth else: v == 2
  
proc mkTextTexture*(renderer: RendererPtr, gfont: TVFont, str: cstring, invert: bool = false): LTexture =
  if str.len == 0: return nil
  let surface = gfont.renderUtf8Blended($str, renderer, invert)
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
                      invert: bool = false): cint =
    # if str is empty surface would be nil, so we have to
    # do it here to separate it from the case where there's
    # a surface creation error.
    if str.len == 0: return 0
    let texture = renderer.mkTextTexture(gfont, str, invert)
    let w = texture.w
    dstrect.x = x
    dstrect.y = y
    dstrect.w = texture.w
    dstrect.h = texture.h
    renderer.copyEx(texture.raw, nil, dstrect, 0.cdouble, nil)
    texture.dispose()
    return w
    
