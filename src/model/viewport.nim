type
  ViewPort* = ref object
    # col offset in document (grid)
    x*: cint
    # row offset in document (grid)
    y*: cint
    # width (grid)
    w*: cint
    # height (grid)
    h*: cint

proc mkNewViewPort*(x: cint = 0, y: cint = 0, w: cint = 0, h: cint = 0): ViewPort =
  return ViewPort(x: x, y: y, w: w, h: h)

    
