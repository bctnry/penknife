import sdl2

type
  Style* = ref object
    mainColor*: sdl2.Color
    backgroundColor*: sdl2.Color
    auxColor*: sdl2.Color
    highlightColor*: sdl2.Color

proc mkStyle*(
  mainColor: sdl2.Color = (r: 0x00, g: 0x00, b: 0x00, a: 0x00),
  backgroundColor: sdl2.Color = (r: 0xe0, g: 0xe0, b: 0xe0, a: 0x00),
  auxColor: sdl2.Color = (r: 0xff, g: 0xff, b: 0xff, a: 0x00),
  highlightColor: sdl2.Color = (r: 0x00, g: 0x00, b: 0x00, a: 0x00)
): Style =
    return Style(mainColor: mainColor,
                 backgroundColor: backgroundColor,
                 auxColor: auxColor,
                 highlightColor: highlightColor)

