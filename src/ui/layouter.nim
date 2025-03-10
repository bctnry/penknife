type
  LayoutNodeType* = enum
    SINGULAR
    HORIZONTAL
    VERTICAL

  LayoutNode* = ref object
    onResize*: proc (newWidth: int, newHeight: int): void
    w*: int
    h*: int
    parent*: LayoutNode
    case lType*: LayoutNodeType:
    of SINGULAR:
      nil
    of HORIZONTAL:
      left*: LayoutNode
      right*: LayoutNode
    of VERTICAL:
      top*: LayoutNode
      bottom*: LayoutNode

proc mkLayoutNode*(w: int, h: int): LayoutNode =
  return LayoutNode(
    lType: SINGULAR,
    w: w,
    h: h,
    onResize: nil,
    parent: nil
  )

proc resize*(ln: var LayoutNode, w: int, h: int): void =
  # if ln singular: set w & h
  # if ln vertical:
  #   set left h = h
  #   set right h = h
  #   set left w += dw/2
  #   set right w += dw/2
  # if in horizontal:
  #   set top w = w
  #   set bottom w = w
  #   set top h += dh/2
  #   set bottom h += dh/2
  var lnstk: seq[(LayoutNode, int, int)] = @[(ln, w, h)]
  while lnstk.len > 0:
    var (subj, targetW, targetH) = lnstk.pop()
    case subj.lType:
      of SINGULAR:
        subj.w = targetW
        subj.h = targetH
        if not subj.onResize.isNil: subj.onResize(targetW, targetH)
      of VERTICAL:
        let dw = subj.w - targetW
        subj.w = targetW
        subj.h = targetH
        if not subj.onResize.isNil: subj.onResize(targetW, targetH)
        lnstk.add((subj.left, subj.left.w + dw div 2, targetH))
        lnstk.add((subj.right, subj.right.w + dw - dw div 2, targetH))
      of HORIZONTAL:
        let dh = subj.h - targetH
        subj.w = targetW
        subj.h = targetH
        if not subj.onResize.isNil: subj.onResize(targetW, targetH)
        lnstk.add((subj.top, targetW, subj.top.h + dh div 2))
        lnstk.add((subj.bottom, targetW, subj.bottom.h + dh - dh div 2))

proc splitVertical*(ln: var LayoutNode): bool =
  if ln.lType != SINGULAR: return false
  ln.lType = VERTICAL
  var left = mkLayoutNode(ln.w div 2, ln.h)
  left.parent = ln
  ln.left = left
  var right = mkLayoutNode(ln.w - ln.w div 2, ln.h)
  right.parent = ln
  ln.right = right
  return true

proc splitHorizontal*(ln: var LayoutNode): bool =
  if ln.lType != SINGULAR: return false
  ln.lType = HORIZONTAL
  var top = mkLayoutNode(ln.w, ln.h div 2)
  top.parent = ln
  ln.top = top
  var bottom = mkLayoutNode(ln.w, ln.h - ln.h div 2)
  bottom.parent = ln
  ln.bottom = bottom
  return true

proc deleteLeft*(ln: var LayoutNode): bool =
  if ln.lType != VERTICAL: return false
  let right = ln.right
  ln.lType = SINGULAR

  
