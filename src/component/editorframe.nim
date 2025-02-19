import sdl2
import titlebar
import editorview
import cursorview
import linenumberpanel
import ../model/[state, editsession, textbuffer]
import ../aux

type
  EditorFrame* = ref object
    parentState*: State
    titleBar*: TitleBar
    lineNumberPanel*: LineNumberPanel
    editorView*: EditorView
    cursor*: CursorView
    dstrect*: Rect
    focus: bool

proc mkEditorFrame*(st: State): EditorFrame =
  return EditorFrame(
    parentState: st,
    titleBar: mkTitleBar(st),
    lineNumberPanel: mkLineNumberPanel(st),
    editorView: mkEditorView(st),
    cursor: mkCursorView(st)
  )
    

proc relayout*(l: EditorFrame, x: cint, y: cint, gridWidth: cint, gridHeight: cint): void =
  l.titleBar.relayout(x+0, y+0, gridWidth, 1)
  l.lineNumberPanel.relayout(0, y+TITLE_BAR_HEIGHT)

  let st = l.parentState  
  let session = st.currentEditSession
  let maxLineNumber = min(session.viewPort.y+session.viewPort.h,
                          session.textBuffer.lineCount())
  let lnpWidth = (digitCount(maxLineNumber) + 1 + VIEWPORT_GAP).cint
  l.editorView.relayout(lnpWidth, 1, gridWidth-lnpWidth, gridHeight-1)

  l.cursor.calibrate(lnpWidth, 1)
  
proc render*(l: EditorFrame, renderer: RendererPtr): void =
  renderer.render(l.lineNumberPanel)
  renderer.render(l.editorView)
  renderer.render(l.titleBar)
  
    
