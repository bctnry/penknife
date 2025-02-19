import std/[unicode, tables, sequtils]
import sdl2
import sdl2_utils
import sdl2/ttf
import ../aux

type
  Glyph* = tuple[
    raw: TexturePtr,
    w: cint,
    h: cint
  ]
  TVFont* = ref object
    raw*: FontPtr
    w*: cint
    h*: cint
    # the naming is hard for this one.
    # calling it fg/bg color is wrong, since it's technically "fg color when
    # not selected" and "fg color when selected".
    mainColor: sdl2.Color
    auxColor: sdl2.Color
    fontCache: TableRef[Rune, Glyph]
    auxFontCache: TableRef[Rune, Glyph]
    
proc loadFont*(f: var TVFont, file: cstring, size: int): bool =
  ##[
  load a font specified by path `file` and size `size`.
  returns `false` when sdl_ttf failed to load the font.
  the "font's width" and "font's height" is solely determined by the
  width & height of the character `x`. you can see this is truly for
  monospace fonts...
  ]##
  let font = ttf.openFont(file, size.cint)
  if font.isNil: return false
  f.raw = font
  discard ttf.sizeUtf8(font, "x".cstring, f.w.addr, f.h.addr)
  f.fontCache = newTable[Rune, Glyph]()
  f.auxFontCache = newTable[Rune, Glyph]()
  return true

proc loadFont*(file: cstring, size: int): TVFont =
  ##[
  load a font specified by path `file` and size `size`.
  returns `nil` when sdl_ttf failed to load the font.
  the "font's width" and "font's height" is solely determined by the
  width & height of the character `x`. you can see this is truly for
  monospace fonts...
  ]##
  var res = TVFont(raw: nil, w: 0, h: 0, fontCache: nil, auxFontCache: nil)
  if not res.loadFont(file, size): return nil
  return res

proc determineRuneGridWidth*(f: TVFont, r: Rune): int =
  if f.fontCache.hasKey(r): return if f.fontCache[r].w > f.w: return 2 else: 1
  if f.auxFontCache.hasKey(r): return if f.fontCache[r].w > f.w: return 2 else: 1
  return 0

proc disposeMainColorCache(f: TVFont): void =
  if f.fontCache.isNil: return
  for k in f.fontCache.keys:
    f.fontCache[k].raw.destroy()
  f.fontCache = nil

proc disposeAuxColorCache(f: TVFont): void =
  if f.auxFontCache.isNil: return
  for k in f.auxFontCache.keys:
    f.auxFontCache[k].raw.destroy()
  f.auxFontCache = nil

proc useNewMainColor*(f: TVFont, fgColor: sdl2.Color): void =
  f.disposeMainColorCache()
  f.mainColor = fgColor
  f.fontCache = newTable[Rune, Glyph]()

proc useNewAuxColor*(f: TVFont, bgColor: sdl2.Color): void =
  f.disposeAuxColorCache()
  f.auxColor = bgColor
  f.auxFontCache = newTable[Rune, Glyph]()
  
proc dispose*(f: TVFont): void =
  f.disposeMainColorCache()
  f.disposeAuxColorCache()

proc determineBgColor(c: sdl2.Color): sdl2.Color =
  if (c.r == 0 and c.g == 0 and c.b == 0):
    return (r: 0xff, g: 0xff, b: 0xff, a: 0x00)
  else:
    return (r: 0x00, g: 0x00, b: 0x00, a: 0x00)


proc refreshCache*(f: TVFont, r: Rune, renderer: RendererPtr, invert: bool = false): void =
  let fgColor = if invert: f.auxColor else: f.mainColor
  let fontCache = if invert: f.auxFontCache else: f.fontCache
  if not fontCache.hasKey(r):
    var chSurface = f.raw.renderUTF8BlendedWrapped(
      r.toUTF8().cstring,
      fgColor,
      0
    )
    let w = chSurface.w
    let h = chSurface.h
    let texture = renderer.createTextureFromSurface(chSurface)
    chSurface.freeSurface()
    fontCache[r] = (raw: texture, w: w, h: h)

proc retrieveGlyph*(f: TVFont, r: Rune, aux: bool = false): Glyph =
  let fc = if aux: f.auxFontCache else: f.fontCache
  return fc[r]

proc calculateWidth*(f: TVFont, r: seq[Rune], renderer: RendererPtr): int =
  var res = 0
  for k in r:
    f.refreshCache(k, renderer)
    res += f.fontCache[k].w
  return res
proc calculateWidth*(f: TVFont, r: string, renderer: RendererPtr): int =
  return calculateWidth(f, r.toRunes, renderer)
  
var dstrect: Rect = (x: 0, y: 0, w: 0, h: 0)
proc renderUTF8Blended*(f: TVFont, s: seq[Rune], renderer: RendererPtr, target: TexturePtr, targetX: cint, targetY: cint, inverted: bool = false): cint =
  var i = 0
  let fontCache = if inverted: f.auxFontCache else: f.fontCache
  let oldRenderTarget = renderer.getRenderTarget()
  renderer.setRenderTarget(target)
  dstrect.x = targetX
  dstrect.y = targetY
  while i < s.len:
    let k = s[i]
    f.refreshCache(k, renderer, inverted)
    let glyph = fontCache[k]
    dstrect.w = glyph.w
    dstrect.h = glyph.h
    renderer.copy(glyph.raw, nil, dstrect.addr)
    dstrect.x += glyph.w
    i += 1
  renderer.setRenderTarget(oldRenderTarget)
  return dstrect.x-targetX
  
proc renderUTF8Blended*(f: TVFont, s: string, renderer: RendererPtr, target: TexturePtr, targetX: cint, targetY: cint, inverted: bool = false): cint =
  return renderUTF8Blended(f, s.toRunes, renderer, target, targetX, targetY, inverted)

proc renderUTF8BlendedWrapped*(f: TVFont, s: seq[Rune], renderer: RendererPtr, target: TexturePtr, targetX: cint, targetY: cint, wrapPixelWidth: int = 0, inverted: bool = false): void =
  let fgColor = if inverted: f.auxColor else: f.mainColor
  let oldRenderTarget = renderer.getRenderTarget()
  renderer.setRenderTarget(target)
  var i = 0
  let fontCache = if inverted: f.auxFontCache else: f.fontCache
  var currentLineW = 0
  dstrect.x = targetX
  dstrect.y = targetY
  while i < s.len:
    let k = s[i]
    f.refreshCache(k, renderer, inverted)
    let glyph = fontCache[k]
    let shouldAddNewLine = (s[i] == '\n'.makeRune) or (
      wrapPixelWidth > 0 and (currentLineW + glyph.w > wrapPixelWidth)
    )
    if shouldAddNewLine:
      dstrect.y += glyph.h
      dstrect.x = targetX
      currentLineW = 0
      if s[i] != '\n'.makeRune:
        # we added the new line but we didn't add the character.
        dstrect.w = glyph.w
        dstrect.h = glyph.h
        renderer.copy(glyph.raw, nil, dstrect.addr)
        dstrect.x += glyph.w
        currentLineW += glyph.w
    else:
      dstrect.w = glyph.w
      dstrect.h = glyph.h
      renderer.copy(glyph.raw, nil, dstrect.addr)
      dstrect.x += glyph.w
      currentLineW += glyph.w
    i += 1
  renderer.setRenderTarget(oldRenderTarget)

proc renderUTF8BlendedWrapped*(f: TVFont, s: string, renderer: RendererPtr, target: TexturePtr, targetX: cint, targetY: cint, wrapPixelWidth: int = 0, inverted: bool = false): void =
  renderUTF8BlendedWrapped(f, s.toRunes, renderer, target, targetX, targetY, wrapPixelWidth, inverted)

