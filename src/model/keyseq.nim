import std/[tables, options]
import sdl2
import editsession
import style

type
  FKeyDescriptor = string
  StateInterface* = ref object
    currentEditSession*: proc (): EditSession
    globalStyle*: proc (): Style
  FKeyCallback* = proc (stateInterface: StateInterface): void
  FKeyMapNodeType* = enum
    FKEYMAP_SUBMAP
    FKEYMAP_CALLBACK
  FKeyMapNode* = ref object
    case kind*: FKeyMapNodeType
    of FKEYMAP_CALLBACK:
      cValue*: FKeyCallback
    of FKEYMAP_SUBMAP:
      nMap*: TableRef[FKeyDescriptor, FKeyMapNode]
  FKeyMap* = ref object
    nMap*: TableRef[FKeyDescriptor, FKeyMapNode]

proc mkFKeyMap*(): FKeyMap =
  return FKeyMap(
    nMap: newTable[FKeyDescriptor, FKeyMapNode]()
  )

# the key descriptor comes in the following format:
#     [C][M][S]-[key] - Ctrl/Meta/Shift + [key]
# e.g. Ctrl+s is C-s, Ctrl+Meta+k is CM-k, Ctrl+Meta+Shift+Up is CMS-<up>
# this might be confusing but there's no .
#     Ctrl+C is C-c
#     Ctrl+M is C-M
#     Meta+C is M-C
#     Meta+M is M-M
#     Ctrl+Shift+C is C-C
# [key] could be any printable characters that is not white space or:
#     <up>  - up arrow
#     <left>  - left arrow
#     <down>  - down arrow
#     <right>  - right arrow
#     <pgup>  - page up
#     <pgdn>  - page down
#     <home>  - home
#     <end>   - end
#     <ins>   - insert
#     <f1> ~ <f12>   - F1 ~ F12
#     <tab>   - tab
#     <backspc>    - back space
#     <esc>   - escape

proc registerFKeyCallback*(fkm: FKeyMap, kseq: seq[FKeyDescriptor], callback: FKeyCallback): bool =
  var i = 0
  var subj = fkm.nMap
  while i < kseq.len:
    let p = kseq[i]
    if not subj.hasKey(p):
      if i == kseq.len-1:
        subj[p] = FKeyMapNode(kind: FKEYMAP_CALLBACK, cValue: callback)
      else:
        let newSubmap = newTable[FKeyDescriptor, FKeyMapNode]()
        subj[p] = FKeyMapNode(kind: FKEYMAP_SUBMAP, nMap: newSubmap)
        subj = newSubmap
    elif i == kseq.len-1:
      if subj[p].kind == FKEYMAP_CALLBACK:
        subj[p].cValue = callback
      else:
        return false
    else:
      let newSubmap = newTable[FKeyDescriptor, FKeyMapNode]()
      subj[p] = FKeyMapNode(kind: FKEYMAP_SUBMAP, nMap: newSubmap)
      subj = newSubmap
    i += 1
  return true

proc resolve*(fkm: FKeyMap, kd: FKeyDescriptor): Option[FKeyMapNode] =
  if not fkm.nMap.hasKey(kd): return none(FKeyMapNode)
  else: return some(fkm.nMap[kd])

proc resolve*(fkmn: FKeyMapNode, kd: FKeyDescriptor): Option[FKeyMapNode] =
  case fkmn.kind:
    of FKEYMAP_SUBMAP:
      if not fkmn.nMap.hasKey(kd): return none(FKeyMapNode)
      else: return some(fkmn.nMap[kd])
    else:
      return none(FKeyMapNode)

proc resolve*(fkmn: Option[FKeyMapNode], kd: FKeyDescriptor): Option[FKeyMapNode] =
  if fkmn.isNone(): return none(FKeyMapNode)
  return fkmn.get.resolve(kd)
  
