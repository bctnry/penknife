import sdl2

type
  LTexture* = ref object
    raw*: TexturePtr
    w*: cint
    h*: cint

proc width*(x: LTexture): int =
  if x.isNil: return 0
  else: return x.w
proc height*(x: LTexture): int =
  if x.isNil: return 0
  else: return x.h

proc dispose*(x: LTexture): void =
  if x == nil: return
  var xx = x
  if not xx.raw.isNil:
    xx.raw.destroy()
    xx.raw = nil
    
