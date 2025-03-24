import std/unicode
import cursor

type
  # I don't have a better name for this for now.
  UndoRedoPieceType* = enum
    UR_INSERT
    UR_DELETE
  # it's easier to model this from the "post" state's perspective. for
  # example:
  #[
    aaa[bbbaba]bccc  -->  aaabccc
    1.    kind: delete, position: 3, data: bbbaba
    aaa[]bccc  -->  aaakkkvkbccc
    2.    kind: insert, position: 3, data: kkkvk
    aaakkk[vkb]ccc  -->  aaakkkccc
    3.    kind: delete, position: 6, data: vkb
  ]#
  # position always mean "left most position" (so e.g. the action 2 in the
  # example is position 3 instead of posiition 3+5=8), since left most
  # position "wouldn't change" before and after an insert/delete so the
  # implementation of both undo and redo would be easier.
  # undo starts from 3:
  # 1.  (undo-ing 3)  insert vkb at position 6
  # 2.  (undo-ing 2)  delete kkkvk at position 3
  # 3.  (undo-ing 1)  insert bbbaba at position 3
  # redo:
  # 1.  after undo-ing 2:
  #       aaabccc
  # 2.  (redo-ing 2) insert kkkvk at position 3
  #       aaakkkvkbccc
  # 3.  (redo-ing 3) delete vkb at position 6
  #       aaakkkccc
  UndoRedoPiece* = ref object
    kind*: UndoRedoPieceType
    postPosition*: Cursor
    data*: seq[Rune]
  UndoRedoStack* = ref object
    pieces*: seq[UndoRedoPiece]
    i*: int

proc `$`*(urpt: UndoRedoPieceType): string =
  case urpt:
    of UR_DELETE: "UR_DELETE"
    of UR_INSERT: "UR_INSERT"
    
proc `$`*(urp: UndoRedoPiece): string =
  return "UndoRedoPiece(" & $urp.kind & "," & $urp.postPosition & "," & ($urp.data) & ")"
proc `$`*(urs: UndoRedoStack): string =
  return "(" & $urs.pieces & "," & $urs.i & ")"

proc mkUndoRedoStack*(): UndoRedoStack =
  return UndoRedoStack(pieces: @[], i: -1)
    
