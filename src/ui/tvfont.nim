import std/[unicode, tables, sequtils]
import sdl2
import sdl2_utils
import sdl2/ttf

type
  TVFont* = ref object
    raw*: FontPtr
    w*: cint
    h*: cint
    # the naming is hard for this one.
    # calling it fg/bg color is wrong, since it's technically "fg color when
    # not selected" and "fg color when selected".
    mainColor: sdl2.Color
    auxColor: sdl2.Color
    fontCache: TableRef[Rune, SurfacePtr]
    auxFontCache: TableRef[Rune, SurfacePtr]
    
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
  f.fontCache = newTable[Rune, SurfacePtr]()
  f.auxFontCache = newTable[Rune, SurfacePtr]()
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

proc initFontCache*(f: TVFont, s: seq[Rune], renderer: RendererPtr, mainColor: sdl2.Color, auxColor: sdl2.Color): void =
  if f.fontCache.isNil: f.fontCache = newTable[Rune, SurfacePtr]()
  if f.auxFontCache.isNil: f.auxFontCache = newTable[Rune, SurfacePtr]()
  for k in s:
    if f.fontCache.hasKey(k): continue
    let surface = f.raw.renderUTF8BlendedWrapped(
      k.toUTF8().cstring,
      mainColor,
      0
    )
    f.fontCache[k] = surface
    let surface2 = f.raw.renderUTF8BlendedWrapped(
      k.toUTF8().cstring,
      auxColor,
      0
    )
    f.auxFontCache[k] = surface2
    f.mainColor = mainColor
    f.auxColor = auxColor

proc determineRuneGridWidth*(f: TVFont, r: Rune): int =
  if f.fontCache.hasKey(r): return if f.fontCache[r].w > f.w: return 2 else: 1
  if f.auxFontCache.hasKey(r): return if f.fontCache[r].w > f.w: return 2 else: 1
  return 0

proc disposeMainColorCache(f: TVFont): void =
  if f.fontCache.isNil: return
  for k in f.fontCache.keys:
    f.fontCache[k].freeSurface()
  f.fontCache = nil

proc disposeAuxColorCache(f: TVFont): void =
  if f.auxFontCache.isNil: return
  for k in f.auxFontCache.keys:
    f.auxFontCache[k].freeSurface()
  f.auxFontCache = nil

proc useNewMainColor*(f: TVFont, fgColor: sdl2.Color): void =
  f.disposeMainColorCache()
  f.mainColor = fgColor
  f.fontCache = newTable[Rune, SurfacePtr]()

proc useNewAuxColor*(f: TVFont, bgColor: sdl2.Color): void =
  f.disposeAuxColorCache()
  f.auxColor = bgColor
  f.auxFontCache = newTable[Rune, SurfacePtr]()
  
proc dispose*(f: TVFont): void =
  f.disposeMainColorCache()
  f.disposeAuxColorCache()

proc determineBgColor(c: sdl2.Color): sdl2.Color =
  if (c.r == 0 and c.g == 0 and c.b == 0):
    return (r: 0xff, g: 0xff, b: 0xff, a: 0x00)
  else:
    return (r: 0x00, g: 0x00, b: 0x00, a: 0x00)


proc refreshCache*(f: TVFont, r: Rune, invert: bool = false): void =
  let fgColor = if invert: f.auxColor else: f.mainColor
  let fontCache = if invert: f.auxFontCache else: f.fontCache
  if not fontCache.hasKey(r):
    var chSurface = f.raw.renderUTF8BlendedWrapped(
      r.toUTF8().cstring,
      fgColor,
      0
    )
    chSurface = chSurface.convertSurface(chSurface.format, 0)
    fontCache[r] = chSurface

proc retrieveGlyph*(f: TVFont, r: Rune, aux: bool = false): SurfacePtr =
  f.refreshCache(r, aux)
  let fc = if aux: f.auxFontCache else: f.fontCache
  return fc[r]

proc renderGlyphWithBackground*(f: TVFont, r: Rune, bgColor: Color, aux: bool = false): SurfacePtr =
  f.refreshCache(r, aux)
  let fc = if aux: f.auxFontCache else: f.fontCache
  let newSurface = createNewARGBSurface(fc[r].w, fc[r].h)
  newSurface.fillRect(nil, newSurface.format.mapRGB(bgColor.r, bgColor.g, bgColor.b))
  blitSurface(fc[r], nil, newSurface, nil)
  return newSurface
  
var dstrect: Rect = (x: 0, y: 0, w: 0, h: 0)
proc renderUTF8Blended*(f: TVFont, s: string, renderer: RendererPtr, inverted: bool = false): SurfacePtr =
  let fgColor = if inverted: f.auxColor else: f.mainColor
  var resH: cint = 0
  var resW: cint = 0
  var i = 0
  let fontCache = if inverted: f.auxFontCache else: f.fontCache
  while i < s.len:
    let k = s.runeAt(i)
    let kSize = s.runeLenAt(i)
    f.refreshCache(k, inverted)
    resH = max(resH, fontCache[k].h).cint
    resW += fontCache[k].w.cint
    i += kSize
  let surface = createRGBSurface(0, resW, resH, 24, 0, 0, 0, 0)
  if surface.isNil:
    echo $getError()
  dstrect.x = 0
  dstrect.y = 0
  dstrect.w = resW
  dstrect.h = resH
  let bgColor = determineBgColor(fgColor)
  let bgColorMapped = surface.format.mapRGB(bgColor.r, bgColor.g, bgColor.b)
  discard surface.fillRect(dstrect.addr, bgColorMapped)
  i = 0
  while i < s.len:
    let k = s.runeAt(i)
    let kSize = s.runeLenAt(i)
    let charSurface = fontCache[k]
    dstrect.w = charSurface.w
    dstrect.h = charSurface.h
    blitSurface(charSurface, nil, surface, dstrect.addr)
    dstrect.x += charSurface.w
    i += kSize
  discard surface.setColorKey(1, bgColorMapped)
  return surface


const SDL2_WIDTH_LIMIT = 16383
const SDL2_HEIGHT_LIMIT = 16383
proc renderUTF8BlendedHugeCanvas*(f: TVFont, s: string, renderer: RendererPtr, inverted: bool = false): seq[SurfacePtr] =
  ## Render a string in UTF-8 into a list of surfaces *as one single line*.
  ## Note that the result returned from this function is not meant to be
  ## used with `MultiPageCanvas`, since `MultiPageCanvas` is used for
  ## vertically-arranged surfaces and this is horizontal.
  ## SDL2 limits the width & height of a surface to be under 16384 pixels
  ## (surfaces with larger sizes will neither render properly nor generate
  ## an error) but there would be times when you accidentally render a
  ## very very long string that surpasses the limit. The result should be
  ## arranged in a row from left to right when being rendered. The reason
  ## why it's only a `seq[SurfacePtr]` instead of a `seq[seq[SurfacePtr]]`
  ## is that I don't expect one single line of text would have a height
  ## bigger than this limit since that requires the font to be loaded with
  ## a ridiculously big font size.
  let fgColor = if inverted: f.auxColor else: f.mainColor
  var res: seq[SurfacePtr] = @[]
  var resH: cint = 0
  var resW: cint = 0
  var i = 0
  let fontCache = if inverted: f.auxFontCache else: f.fontCache
  while i < s.len:
    let stp = i
    resW = 0
    resH = 0
    while i < s.len:
      let k = s.runeAt(i)
      let kSize = s.runeLenAt(i)
      f.refreshCache(k, inverted)
      if resW + fontCache[k].w.cint >= SDL2_WIDTH_LIMIT: break
      resH = max(resH, fontCache[k].h).cint
      resW += fontCache[k].w.cint
      i += kSize
    let bound = i
    let surface = createRGBSurface(0, resW, resH, 24, 0, 0, 0, 0)
    dstrect.x = 0
    dstrect.y = 0
    dstrect.w = resW
    dstrect.h = resH
    let bgColor = determineBgColor(fgColor)
    let bgColorMapped = surface.format.mapRGB(bgColor.r, bgColor.g, bgColor.b)
    discard surface.fillRect(dstrect.addr, bgColorMapped)
    i = stp
    while i < bound:
      let k = s.runeAt(i)
      let kSize = s.runeLenAt(i)
      f.refreshCache(k, inverted)
      let charSurface = fontCache[k]
      dstrect.w = charSurface.w
      dstrect.h = charSurface.h
      blitSurface(charSurface, nil, surface, dstrect.addr)
      dstrect.x += charSurface.w
      i += kSize
    discard surface.setColorKey(1, bgColorMapped)
    res.add(surface)
  return res

proc renderUTF8BlendedWrapped*(f: TVFont, s: string, renderer: RendererPtr, wrapPixelWidth: int = 0, inverted: bool = false): SurfacePtr =
  let fgColor = if inverted: f.auxColor else: f.mainColor
  var resH: cint = 0
  var resW: cint = 0
  var currentLineH: cint = 0
  var currentLineW: cint = 0
  var i = 0
  let fontCache = if inverted: f.auxFontCache else: f.fontCache
  while i < s.len:
    let k = s.runeAt(i)
    let kSize = s.runeLenAt(i)
    f.refreshCache(k, inverted)
    let shouldAddNewLine = (s[i] == '\n') or (
      wrapPixelWidth > 0 and (currentLineW + fontCache[k].w > wrapPixelWidth)
    )
    if shouldAddNewLine:
      resH += currentLineH
      resW = max(resW, currentLineW)
      currentLineH = f.h
      currentLineW = 0
      if s[i] != '\n':
        # we added the new line but we didn't add the character.
        currentLineW += fontCache[k].w
        currentLineH = max(currentLineH, fontCache[k].h)
    else:
      currentLineH = max(currentLineH, fontCache[k].h)
      currentLineW += fontCache[k].w
    i += kSize
  if currentLineH > 0: resH += currentLineH
  if currentLineW > 0: resW = max(currentLineW, resW)
  currentLineH = 0
  currentLineW = 0
  let surface = createRGBSurface(0, resW, resH, 24, 0, 0, 0, 0)
  dstrect.x = 0
  dstrect.y = 0
  dstrect.w = resW
  dstrect.h = resH
  let bgColor = determineBgColor(fgColor)
  let bgColorMapped = surface.format.mapRGB(bgColor.r, bgColor.g, bgColor.b)
  discard surface.fillRect(dstrect.addr, bgColorMapped)
  i = 0
  while i < s.len:
    let k = s.runeAt(i)
    let kSize = s.runeLenAt(i)
    let charSurface = fontCache[k]
    f.refreshCache(k, inverted)
    let shouldAddNewLine = (s[i] == '\n') or (
      wrapPixelWidth > 0 and (dstrect.x + fontCache[k].w > wrapPixelWidth)
    )
    if shouldAddNewLine:
      dstrect.y += currentLineH
      dstrect.x = 0
      currentLineH = f.h
      currentLineW = 0
      if s[i] != '\n':
        # we added the new line but we didn't add the character.
        dstrect.w = charSurface.w
        dstrect.h = charSurface.h
        blitSurface(charSurface, nil, surface, dstrect.addr)
        dstrect.x += charSurface.w
        currentLineW += charSurface.w
        currentLineH = max(currentLineH, charSurface.h)
    else:
      dstrect.w = charSurface.w
      dstrect.h = charSurface.h
      blitSurface(charSurface, nil, surface, dstrect.addr)
      dstrect.x += charSurface.w
      currentLineW += charSurface.w
      currentLineH = max(currentLineH, charSurface.h)
    i += kSize
  discard surface.setColorKey(1, bgColorMapped)
  return surface

proc renderUTF8BlendedWrappedHugeCanvas*(f: TVFont, s: string, renderer: RendererPtr, wrapPixelWidth: int = 0, inverted: bool = false): seq[SurfacePtr] =
  let fgColor = if inverted: f.auxColor else: f.mainColor
  var res: seq[SurfacePtr] = @[]
  var resW: cint = 0
  var resH: cint = 0
  var i = 0
  let bgColor = determineBgColor(fgColor)
  let fontCache = if inverted: f.auxFontCache else: f.fontCache
  while i < s.len:
    let stp = i
    var currentLineH: cint = 0
    var currentLineW: cint = 0
    while i < s.len:
      let k = s.runeAt(i)
      let kSize = s.runeLenAt(i)
      f.refreshCache(k, inverted)
      let shouldAddNewLine = (s[i] == '\n') or (
        wrapPixelWidth > 0 and (currentLineW + fontCache[k].w > wrapPixelWidth)
      )
      if shouldAddNewLine:
        if resH + currentLineH >= SDL2_HEIGHT_LIMIT: break
        resH += currentLineH
        resW = max(resW, currentLineW)
        currentLineH = f.h
        currentLineW = 0
        if s[i] != '\n':
          currentLineW += fontCache[k].w
          currentLineH = max(currentLineH, fontCache[k].h)
      else:
        currentLineW += fontCache[k].w
        currentLineH = max(currentLineH, fontCache[k].h)
      i += kSize
    if currentLineH > 0: resH += currentLineH
    if currentLineW > 0: resW = max(currentLineW, resW)
    currentLineH = 0
    currentLineW = 0
    let bound = i
    let surface = createRGBSurface(0, resW, resH, 24, 0, 0, 0, 0)
    dstrect.x = 0
    dstrect.y = 0
    dstrect.w = resW
    dstrect.h = resH
    let bgColorMapped = (surface.format.mapRGB(bgColor.r, bgColor.g, bgColor.b))
    discard surface.fillRect(dstrect.addr, bgColorMapped)
    i = stp
    while i < bound:
      let k = s.runeAt(i)
      let kSize = s.runeLenAt(i)
      let charSurface = fontCache[k]
      f.refreshCache(k, inverted)
      let shouldAddNewLine = (s[i] == '\n') or (
        wrapPixelWidth > 0 and (dstrect.x + charSurface.w > wrapPixelWidth)
      )
      if shouldAddNewLine:
        dstrect.y += currentLineH
        dstrect.x = 0
        currentLineH = f.h
        currentLineW = 0
        if s[i] != '\n':
          # we added the new line but we didn't add the character.
          dstrect.w = charSurface.w
          dstrect.h = charSurface.h
          blitSurface(charSurface, nil, surface, dstrect.addr)
          dstrect.x += charSurface.w
          currentLineW += charSurface.w
          currentLineH = max(currentLineH, charSurface.h)
      else:
        dstrect.w = charSurface.w
        dstrect.h = charSurface.h
        blitSurface(charSurface, nil, surface, dstrect.addr)
        dstrect.x += charSurface.w
        currentLineW += charSurface.w
        currentLineH = max(currentLineH, charSurface.h)
      i += kSize
    discard surface.setColorKey(1, bgColorMapped)
    res.add(surface)
  return res

      
