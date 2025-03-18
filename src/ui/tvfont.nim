import std/[unicode, tables]
import sdl2
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
    colorList: seq[sdl2.Color]
    fontCache: TableRef[int, TableRef[Rune, Glyph]]
    mainColor: sdl2.Color
    auxColor: sdl2.Color
    
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
  f.colorList = @[]
  f.fontCache = newTable[int, TableRef[Rune, Glyph]]()
  return true

proc loadFont*(file: cstring, size: int): TVFont =
  ##[
  load a font specified by path `file` and size `size`.
  returns `nil` when sdl_ttf failed to load the font.
  the "font's width" and "font's height" is solely determined by the
  width & height of the character `x`. you can see this is truly for
  monospace fonts...
  ]##
  var res = TVFont(raw: nil, w: 0, h: 0, colorList: @[], fontCache: nil)
  if not res.loadFont(file, size): return nil
  return res

proc `==`(c1: sdl2.Color, c2: sdl2.Color): bool =
  return (c1.r == c2.r) and (c1.g == c2.g) and (c1.b == c2.b) and (c1.a == c2.a)
  
proc registerColor*(f: TVFont, c: sdl2.Color): int =
  var i = 0
  while i < f.colorList.len:
    if f.colorList[i] == c:
      if not f.fontCache.hasKey(i):
        f.fontCache[i] = newTable[Rune, Glyph]()
      return i
    i += 1
  var res = f.colorList.len
  f.colorList.add(c)
  f.fontCache[res] = newTable[Rune, Glyph]()
  return res

proc fromHexDigit(x: char): int {.inline.} =
  if 'a' <= x and x <= 'f': return (x.ord - 'a'.ord + 10)
  elif 'A' <= x and x <= 'F': return (x.ord - 'A'.ord + 10)
  elif '0' <= x and x <= '9': return (x.ord - '0'.ord)
  else: return 0

proc parseColor(x: string): Color =
  if (not x.len == 7) and (not x.len == 9): return sdl2.color(0, 0, 0, 0)
  let r = (x[1].fromHexDigit * 16 + x[2].fromHexDigit).uint8
  let g = (x[3].fromHexDigit * 16 + x[4].fromHexDigit).uint8
  let b = (x[5].fromHexDigit * 16 + x[6].fromHexDigit).uint8
  let a = if x.len == 9:
            (x[7].fromHexDigit * 16 + x[8].fromHexDigit).uint8
          else:
            0
  return sdl2.color(r.cint, g.cint, b.cint, a)
  
proc registerColorByString*(f: TVFont, cs: string): int =
  var c = parseColor(cs)
  return f.registerColor(c)

proc determineRuneGridWidth*(f: TVFont, r: Rune): int =
  for k in f.fontCache.keys:
    let cache = f.fontCache[k]
    if cache.hasKey(r): return if cache[r].w > f.w: return 2 else: 1
  return 0

proc disposeFontColorCache(f: TVFont): void =
  for k in f.fontCache.keys:
    let cache = f.fontCache[k]
    for kk in cache.keys:
      cache[kk].raw.destroy()
    for kk in cache.keys:
      cache.del(kk)
  for k in f.fontCache.keys:
    f.fontCache.del(k)

proc useNewMainColor*(f: TVFont, color: sdl2.Color): void =
  f.mainColor = color
  discard f.registerColor(color)

proc useNewAuxColor*(f: TVFont, color: sdl2.Color): void =
  f.auxColor = color
  discard f.registerColor(color)
  
proc dispose*(f: TVFont): void =
  f.disposeFontColorCache()

proc determineBgColor(c: sdl2.Color): sdl2.Color =
  if (c.r == 0 and c.g == 0 and c.b == 0):
    return (r: 0xff, g: 0xff, b: 0xff, a: 0x00)
  else:
    return (r: 0x00, g: 0x00, b: 0x00, a: 0x00)

proc refreshCache*(f: TVFont, renderer: RendererPtr, r: Rune, color: sdl2.Color): void =
  let colorId = f.registerColor(color)
  let colorCache = f.fontCache[colorId]
  if not colorCache.hasKey(r):
    var chSurface = f.raw.renderUTF8BlendedWrapped(
      r.toUTF8().cstring,
      color,
      0
    )
    let w = chSurface.w
    let h = chSurface.h
    let texture = renderer.createTextureFromSurface(chSurface)
    chSurface.freeSurface()
    colorCache[r] = (raw: texture, w: w, h: h)

proc getFontCache(f: TVFont, color: sdl2.Color): TableRef[Rune, Glyph] {.inline.} =
  let colorId = f.registerColor(color)
  return f.fontCache[colorId]
    
proc retrieveGlyph*(f: TVFont, r: Rune, color: sdl2.Color): Glyph {.inline.} =
  return f.getFontCache(color)[r]

proc calculateWidth*(f: TVFont, r: seq[Rune], renderer: RendererPtr): int =
  var res = 0
  for k in r:
    var found = false
    for cc in f.fontCache.keys:
      if not f.fontCache[cc].hasKey(k): continue
      res += f.fontCache[cc][k].w
      found = true
      break
    if not found:
      f.refreshCache(renderer, k, f.mainColor)
      res += f.getFontCache(f.mainColor)[k].w
  return res
proc calculateWidth*(f: TVFont, r: string, renderer: RendererPtr): int =
  return calculateWidth(f, r.toRunes, renderer)
  
var dstrect: Rect = (x: 0, y: 0, w: 0, h: 0)
proc renderUTF8Blended*(f: TVFont, s: seq[Rune], renderer: RendererPtr, target: TexturePtr, targetX: cint, targetY: cint, color: sdl2.Color): cint =
  var i = 0
  let fontCache = f.getFontCache(color)
  let oldRenderTarget = renderer.getRenderTarget()
  renderer.setRenderTarget(target)
  dstrect.x = targetX
  dstrect.y = targetY
  while i < s.len:
    let k = s[i]
    f.refreshCache(renderer, k, color)
    let glyph = fontCache[k]
    dstrect.w = glyph.w
    dstrect.h = glyph.h
    renderer.copy(glyph.raw, nil, dstrect.addr)
    dstrect.x += glyph.w
    i += 1
  renderer.setRenderTarget(oldRenderTarget)
  return dstrect.x-targetX
  
proc renderUTF8Blended*(f: TVFont, s: string, renderer: RendererPtr, target: TexturePtr, targetX: cint, targetY: cint, color: sdl2.Color): cint {.inline.} =
  return renderUTF8Blended(f, s.toRunes, renderer, target, targetX, targetY, color)

proc renderUTF8BlendedWrapped*(f: TVFont, s: seq[Rune], renderer: RendererPtr, target: TexturePtr, targetX: cint, targetY: cint, color: sdl2.Color, wrapPixelWidth: int = 0): void =
  let oldRenderTarget = renderer.getRenderTarget()
  renderer.setRenderTarget(target)
  var i = 0
  let fontCache = f.getFontCache(color)
  var currentLineW = 0
  dstrect.x = targetX
  dstrect.y = targetY
  while i < s.len:
    let k = s[i]
    f.refreshCache(renderer, k, color)
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

proc renderUTF8BlendedWrapped*(f: TVFont, s: string, renderer: RendererPtr, target: TexturePtr, targetX: cint, targetY: cint, color: sdl2.Color, wrapPixelWidth: int = 0): void {.inline.} =
  renderUTF8BlendedWrapped(f, s.toRunes, renderer, target, targetX, targetY, color, wrapPixelWidth)

