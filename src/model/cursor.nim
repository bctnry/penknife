import std/unicode

type
  Cursor* = ref object
    # column (grid)
    x*: cint
    # row (grid)
    y*: cint
    # expecting column (grid).
    # when the cursor moves up and down the engine would try to put it at
    # this column.
    expectingX*: cint

proc mkNewCursor*(x: cint = 0, y: cint = 0): Cursor = Cursor(x: x, y: y)

proc `$`*(c: Cursor): string =
  return "(" & $c.y & "," & $c.x & "[" & $c.expectingX & "])"

# NOTE: we don't check `expectingX` here since it's only for ergonomic cursor movements.
proc `<`*(x: Cursor, y: Cursor): bool =
  if x.y < y.y: return true
  elif x.y > y.y: return false
  else: return x.x < y.x

proc `==`*(x: Cursor, y: Cursor): bool =
  return x.x == y.x and x.y == y.y
  
proc `<=`*(x: Cursor, y: Cursor): bool =
  return x < y or x == y

proc `>`*(x: Cursor, y: Cursor): bool = not (x <= y)
proc `>=`*(x: Cursor, y: Cursor): bool = not (x < y)
  
proc min*(x: Cursor, y: Cursor): Cursor =
  if x <= y: x else: y
proc max*(x: Cursor, y: Cursor): Cursor =
  if x >= y: x else: y

proc between*(x: cint, y: cint, start: Cursor, last: Cursor): bool =
  return (
    (start.y < y and y < last.y) or
    (start.y == y and x >= start.x) or
    (last.y == y and x <= last.x)
  )

proc between*(c: Cursor, start: Cursor, last: Cursor): bool =
  return (
    (start.y < c.y and c.y < last.y) or
    (start.y == c.y and c.x >= start.x) or
    (last.y == c.y and c.x <= last.x)
  )

proc advanceWith*(c: Cursor, r: seq[Rune]): Cursor =
  var line = c.y
  var col = c.x
  for k in r:
    if $k == "\n":
      line += 1
      col = 0
    else:
      col += 1
  return Cursor(x: col, y: line, expectingX: col)
  
proc clone*(c: Cursor): Cursor =
  return Cursor(x: c.x, y: c.y, expectingX: c.expectingX)
  
