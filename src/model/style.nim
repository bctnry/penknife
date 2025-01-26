
type
  Style* = ref object
    fgColor*: tuple[
      r: uint8,
      g: uint8,
      b: uint8,
      a: uint8
    ]
    bgColor*: tuple[
      r: uint8,
      g: uint8,
      b: uint8,
      a: uint8
    ]
    font*: TVFont


