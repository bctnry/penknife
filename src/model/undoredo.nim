import cursor

type
  # I don't have a better name for this for now.
  UndoRedoPieceType* = enum
    UR_INSERT
    UR_DELETE
  UndoRedoPiece* = ref object
    kind*: UndoRedoPieceType
    location*: Cursor
    data*: seq[Rune]
    
    
