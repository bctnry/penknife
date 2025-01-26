import editorview

type
  EditorWindow* = ref object
    style*: Style
    editorView*: EditorView
    lateral: GenericWindow
    # currently minibuffer is a one-line text/textfield.
    # the problem is minibuffer and the current text buffer shares the same
    # source of events.
    minibufferView: MinibufferView
    minibufferText*: string
    minibufferMode*: bool
    minibufferInputCursor*: int
    minibufferInputValue*: seq[Rune]

proc gridSizeW*(ev: EditorWindow): cint =
  return ev.style.font.w
proc gridSizeH*(ev: EditorWindow): cint =
  return ev.style.font.h

proc mkEditorWindow*(st: Style, pw: int, ph: int): EditorWindow =
  var ew = EditorWindow(
    style: st,
    editorView: nil,
    lateral: mkGenericWindow(),
    minibufferView: nil
    minibufferText: "",
    minibufferMode: false,
    minibufferInputCursor: 0,
    minibufferInputValue: @[]
  )
  var ev = mkEditorView(ew)
  var mv = mkMinibufferView(ew)
  ew.editorView = ev
  ew.minibufferView = mv
  lateral.offsetX = 0
  lateral.offsetY = 0
  lateral.w = pw div st.font.w
  lateral.h = ph div st.font.h

