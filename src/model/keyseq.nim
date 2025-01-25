import std/tables
import sdl2
# NOTE: this directly uses sdl2's scancode definitions.

type
  FKey* = tuple[ctrl: bool, alt: bool, scancode: sdl2.Scancode]
  FKeyCallback* = proc (): void
  FKeyMap* = ref object
    ctrlOnly*: TableRef[cint, FKeyCallback]
    altOnly*: TableRef[cint, FKeyCallback]
    ctrlAlt*: TableRef[cint, FKeyCallback]

proc mkFKeyMap*(): FKeyMap =
  return FKeyMap(
    ctrlOnly: newTable[cint, FKeyCallback](),
    altOnly: newTable[cint, FKeyCallback](),
    ctrlAlt: newTable[cint, FKeyCallback]()
  )

# the key descriptor comes in the following format:
#     C[key] - Ctrl + [key]
#     M[key] - Meta + [key]
#     CM[key] - Ctrl + Meta + [key]
# e.g. Ctrl+s is Cs, Ctrl+Meta+k is CMk
# this might be confusing but there's no [].
#     Ctrl+C is CC
#     Ctrl+M is CM (CM couldn't be Ctrl+Meta because that's not
#                   a full key combo)
#     Meta+C is MC (and not CM)
#     Meta+M is MM
proc keyToString*(fk: FKey): string =
  var res: string = ""
  if fk.ctrl: res &= "C"
  if fk.alt: res &= "M"
  res &= fk.scancode.getScancodeName()
  return res

proc registerKeyProcedure*(fkm: var FKeyMap, fk: FKey, callback: proc (): void): void =
  var m = (if fk.ctrl and fk.alt:
             fkm.ctrlAlt
           elif fk.ctrl:
             fkm.ctrlOnly
           elif fk.alt:
             fkm.altOnly
           else:
             raise newException(ValueError, "command key must have a prefix"))
  m[fk[2].cint] = callback

proc call*(fkm: var FKeymap, ctrl: bool, alt: bool, scancode: sdl2.Scancode): void =
  var m = (if ctrl and alt:
             fkm.ctrlAlt
           elif ctrl:
             fkm.ctrlOnly
           elif alt:
             fkm.altOnly
           else:
             raise newException(ValueError, "command key must have a prefix"))
  m[scancode.cint]()
  
  
  
