import cursor
import textbuffer
import selection

type
  EditSession* = ref object
    textBuffer*: TextBuffer
    # NOTE: selection remains non-nil at all time to (try to) prevent frequent
    # small object allcation.
    selection*: LinearSelection
    selectionInEffect*: bool
    cursor*: Cursor

proc mkEditSession*(): EditSession =
  return EditSession(
    cursor: mkNewCursor(),
    textBuffer: "".fromString,
    selection: LinearSelection(
      first: Cursor(x: 0, y: 0, expectingX: 0),
      last: Cursor(x: 0, y: 0, expectingX: 0)
    ),
    selectionInEffect: false
  )
  
