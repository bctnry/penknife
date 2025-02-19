type
  ViewPort* = ref object
    x*: cint
    y*: cint
    w*: cint
    h*: cint
    
proc mkNewViewPort*(): ViewPort =
  return ViewPort(x: 0, y: 0, w: 0, h: 0)
  
