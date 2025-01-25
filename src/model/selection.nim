import cursor

type
  LinearSelection* = ref object
    first*: Cursor
    last*: Cursor
    
proc `in`*(c: Cursor, s: LinearSelection): bool =
  let start = min(s.first, s.last)
  let last = max(s.first, s.last)
  return c.between(start, last)

  
