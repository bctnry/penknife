import sdl2
import ../model/[state, textbuffer, cursor]
import ../ui/[sdl2_utils, texture]

# cursor.

type
  EditorView* = ref object
    parent: EditorWindow
    session*: EditSession
    dstrect: Rect
    lineNumberPanel: LineNumberPanel
    titleBar: TitleBar
    statusLine: StatusLine
    lineNumberPanelShown: bool
    textBufferView: TextBufferView
    lateral: GenericWindow
    
proc style*(ev: EditorView): cint =
  return ev.parent.style
proc gridSizeW*(ev: EditorView): cint =
  return ev.style.font.w
proc gridSizeH*(ev: EditorView): cint =
  return ev.style.font.h

proc relayout*(ev: EditorView, ewLateral: GenericWindow): void =
  ev.lateral.offsetX = ewLateral.offsetX
  ev.lateral.offsetY = ewLateral.offsetY
  ev.lateral.w = ewLateral.w
  ev.lateral.h = ewLateral.h - 1

proc mkEditorView*(parent: EditorWindow): EditorView =
  var ev = EditorView(
    parent: parent,
    dstrect: (x: 0.cint, y: 0.cint, w: 0.cint, h: 0.cint),
    session: mkEditSession(),
    lineNumberPanel: nil,
    titleBar: nil,
    statusLine: nil,
    lineNumberPanelShown: true,
    textBufferView: nil,
    lateral: mkGenericWindow()
  )
  var lineNumberPanel = mkLineNumberPanel(ev)
  var titleBar = mkTitleBar(ev)
  var statusLine = mkStatusLine(ev)
  var textBufferView = mkTextBufferView(ev)
  ev.lineNumberPanel = lineNumberPanel
  ev.titleBar = titleBar
  ev.statusLine = statusLine
  ev.textBufferView = textBufferView
  return ev

proc render*(renderer: RendererPtr, ev: EditorView): void =
  renderer.render(ev.titleBar)
  renderer.render(ev.statusLine)
  if ev.lineNumberPanelShown:
    renderer.render(ev.lineNumberPanel)
  renderer.render(ev.textBufferView)
        
proc renderWith*(ew: EditorView, renderer: RendererPtr): void =
  renderer.render(ew)

  
