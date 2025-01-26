type
  GenericWindow* = ref object
    offsetX*: int
    offsetY*: int
    w*: int
    h*: int
    
proc mkGenericWindow*(): GenericWindow =
  return GenericWindow(offsetX: 0, offsetY: 0, w: 0, h: 0)
  
