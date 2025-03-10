import sdl2
import titlebar
import editorview
import cursorview
import linenumberpanel
import ../model/[state, editsession, textbuffer]
import ../ui/layouter
import ../aux

type
  EditorFrame* = ref object
    parentState*: State
    titleBar*: TitleBar
    lineNumberPanel*: LineNumberPanel
    editorView*: EditorView
    cursor*: CursorView
    auxCursor*: CursorView
    dstrect*: Rect
    focus: bool
    layout*: LayoutNode

proc mkEditorFrame*(st: State): EditorFrame =
  var ef = EditorFrame(
    parentState: st,
    titleBar: mkTitleBar(st),
    lineNumberPanel: mkLineNumberPanel(st),
    editorView: mkEditorView(st),
    cursor: mkCursorView(st),
    auxCursor: mkCursorView(st),
    layout: mkLayoutNode(0, 0)
  )
  ef.cursor.residingSession = st.mainEditSession
  ef.auxCursor.residingSession = st.auxEditSession
  let layout = ef.layout
  layout.onResize = (
    proc (newWidth: int, newHeight: int): void =
      let offsetY = ef.parentState.auxEditSession.textBuffer.lineCount().cint
      ef.titleBar.relayout(0, 0, newWidth.cint, offsetY.cint)
      ef.lineNumberPanel.relayout(0, offsetY)
      let session = st.currentEditSession
      let maxLineNumber = min(session.viewPort.y+session.viewPort.h,
                              session.textBuffer.lineCount())
      let lnpWidth = (digitCount(maxLineNumber) + 1 + VIEWPORT_GAP).cint
      ef.editorView.relayout(lnpWidth, offsetY, (newWidth-lnpWidth).cint, (newHeight-offsetY).cint)
      ef.auxCursor.calibrate(0, 0)
      ef.cursor.calibrate(lnpWidth, offsetY)
  )
  let auxSession = st.auxEditSession
  let auxBuffer = auxSession.textBuffer
  auxSession.textBuffer.onChange = (
    proc (): void =
      layout.onResize(st.windowWidth, st.windowHeight)
  )
  auxSession.onCursorMove = (
    proc (oldX: cint, oldY: cint): void =
      if auxSession.cursor.y == auxBuffer.lineCount():
        auxSession.cursor.y -= 1
        auxSession.cursor.x = auxBuffer.getLineLength(auxBuffer.lineCount()-1).cint
  )
  return ef
    

proc relayout*(l: EditorFrame, x: cint, y: cint, gridWidth: cint, gridHeight: cint): void =
  l.layout.onResize(gridWidth, gridHeight)

proc render*(l: EditorFrame, renderer: RendererPtr): void =
  renderer.render(l.lineNumberPanel)
  renderer.render(l.editorView)
  renderer.render(l.titleBar)
  
    
