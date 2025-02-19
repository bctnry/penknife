import sdl2
import texture

proc createNewARGBSurface*(width: cint, height: cint): SurfacePtr =
  ## creates a new ARGB_8888 surface.
  return createRGBSurface(0, width, height, 32, 0xff0000, 0xff00, 0xff, 0xff0000.uint32)

proc makeLTextureWith*(surface: SurfacePtr, renderer: RendererPtr): LTexture =
  let w = surface.w
  let h = surface.h
  let t = renderer.createTextureFromSurface(surface)
  return LTexture(raw: t, w: w, h: h)

var srcrect: Rect = (x: 0, y: 0, w: 0, h: 0)
var dstrect: Rect = (x: 0, y: 0, w: 0, h: 0)
proc verticalSplitSurface*(original: SurfacePtr, x: cint): (SurfacePtr, SurfacePtr) =
  ## vertically split a surface.
  ## and by vertically i mean the split itself is vertical (i.e. this
  ## would return a *left* part and a *right* part). the original
  ## surface would be freed for you.
  if x <= 0: return (nil, original)
  elif x >= original.w: return (original, nil)
  var left = createRGBSurface(0.cint, x, original.h.cint, original.format.BitsPerPixel.cint, original.format.Rmask, original.format.Gmask, original.format.Bmask, original.format.Amask)
  var right = createRGBSurface(0.cint, (original.w-x).cint, original.h, original.format.BitsPerPixel.cint, original.format.Rmask, original.format.Gmask, original.format.Bmask, original.format.Amask)
  srcrect.x = 0
  srcrect.y = 0
  srcrect.w = x
  srcrect.h = original.h
  blitSurface(original, srcrect.addr, left, nil)
  srcrect.x = original.w - x
  srcrect.w = original.w - x
  blitSurface(original, srcrect.addr, right, nil)
  original.freeSurface()
  return (left, right)

type
  HorizontalCombineAlignment* = enum
    HCA_TOP
    HCA_BOTTOM
    HCA_CENTER
  
proc horizontalMergeSurface*(source: openArray[SurfacePtr], alignment: HorizontalCombineAlignment = HCA_TOP): SurfacePtr =
  ## horizontally combine a list of surfaces.
  ## and by horizontally i mean the original surfaces are arranged
  ## horizontally (i.e. left to right). the resulting surface will
  ## have the height of the tallest surface and the width of all
  ## combined.
  ## the original surfaces are *not* freed.
  ## note that the `alignment` parameter does not have any effect
  ## currently and is expected to be fixed later.
  var width: cint = 0
  var height: cint = 0
  for k in source:
    width += k.w
    height = max(height, k.h)
  var res = createNewARGBSurface(width, height)
  dstrect.x = 0
  dstrect.y = 0
  for k in source:
    dstrect.w = k.w
    dstrect.h = k.h
    blitSurface(k, nil, res, dstrect.addr)
    dstrect.x += k.w
  res = res.convertSurface(res.format, 0)
  return res
  
