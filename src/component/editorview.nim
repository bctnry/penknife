import sdl2
import ../model/[state, textbuffer, cursor, editsession, style]
import ../ui/[tvfont]

# cursor.

type
  EditorView* = ref object
    parentState*: State
    dstrect*: Rect
    offsetX*: cint
    offsetY*: cint
    width*: cint
    height*: cint

proc clip(x: cint, l: cint, r: cint): cint =
  return (if x < l: l elif x > r: r else: x)
  
proc mkEditorView*(st: State): EditorView =
  return EditorView(
    parentState: st,
    dstrect: (x: 0.cint, y: 0.cint, w: 0.cint, h: 0.cint),
    offsetX: 0,
    offsetY: 0,
    width: 0,
    height: 0
  )

proc relayout*(ev: EditorView, x: cint, y: cint, width: cint, height: cint): void =
  ev.offsetX = x
  ev.offsetY = y
  ev.width = width
  ev.height = height
  ev.parentState.currentEditSession.relayout(width, height)
  
proc render*(renderer: RendererPtr, ev: EditorView): void =
  let st = ev.parentState
  let ss = st.mainEditSession
  let baselineX = (ev.offsetX*st.gridSize.w).cint
  let offsetPY = (ev.offsetY*st.gridSize.h).cint
  # render edit viewport
  let renderRowBound = min(ss.viewPort.y+ev.height, min(ss.viewPort.y+ss.viewPort.h, ss.textBuffer.lineCount()))
  let selectionRangeStart = min(ss.selection.first, ss.selection.last)
  let selectionRangeEnd = max(ss.selection.first, ss.selection.last)
  for i in ss.viewPort.y..<renderRowBound:
    let line = ss.textBuffer.getLineOfRune(i)
    let renderColBound = min(ss.viewPort.x+ss.viewPort.w, line.len)
    if renderColBound <= ss.viewPort.x:
      # when: (1) selection is active; (2) row is in selection; (3) row is
      # empty after clipping, we need to display an indicator in the form
      # of a rectangle the size of a single character. this is the behaviour
      # of emacs. we now do the same thing here.
      if ss.selectionInEffect and selectionRangeStart.y < i and i < selectionRangeEnd.y:
        ev.dstrect.x = baselineX.cint
        ev.dstrect.y = offsetPY + ((i-ss.viewPort.y)*st.gridSize.h).cint
        ev.dstrect.w = st.gridSize.w
        ev.dstrect.h = st.gridSize.h
        renderer.setDrawColor(st.globalStyle.highlightColor.r,
                              st.globalStyle.highlightColor.g,
                              st.globalStyle.highlightColor.b)
        renderer.fillRect(ev.dstrect.addr)
      continue
    let clippedLine = line[ss.viewPort.x..<renderColBound]
    let clippedLineLen = renderColBound - ss.viewPort.x
      # Note that we render selection range in invert color.
    # the beginning and the ending lines of selection range needs special
    # treatment (since we can have the selection starts or ends in the middle
    # of a line) but the lines in between can be safely rendered in invert
    # color as a whole.
    # we calculate the position of cursor & render it separately later.
    # since we've sorted the selection range endpoints using min and max above
    # we can safely render the rightPart of the line at selectionRangeStart and
    # the leftPart of the line line at selectionRangeEnd in invert color.
    # if we have selection we render special lines separately.
    if ss.selectionInEffect:
      # when the selection is within a single line
      if selectionRangeStart.y == selectionRangeEnd.y and i == selectionRangeStart.y:
        let splittingPoint1 = (selectionRangeStart.x - ss.viewPort.x).clip(0, clippedLineLen.cint)
        let splittingPoint2 = (selectionRangeEnd.x - ss.viewPort.x).clip(0, clippedLineLen.cint)
        let leftPart = clippedLine[0..<splittingPoint1]
        let middlePart = clippedLine[splittingPoint1..<splittingPoint2]
        let rightPart = clippedLine[splittingPoint2..<clippedLine.len]
        let leftPartWidth = st.globalFont.calculateWidth(leftPart, renderer)
        let y = offsetPY + ((i-ss.viewPort.y+1)*st.gridSize.h - st.gridSize.h).cint
        var x = baselineX
        if middlePart.len > 0:
          ev.dstrect.y = y.cint
          ev.dstrect.x = (baselineX+leftPartWidth).cint
          ev.dstrect.w = st.globalStyle.font.calculateWidth(middlePart, renderer).cint
          ev.dstrect.h = st.gridSize.h
          renderer.setDrawColor(st.globalStyle.highlightColor.r,
                                st.globalStyle.highlightColor.g,
                                st.globalStyle.highlightColor.b)
          renderer.fillRect(ev.dstrect)
        x += st.globalStyle.font.renderUTF8Blended(leftPart, renderer, nil, x, y, false)
        x += st.globalStyle.font.renderUTF8Blended(middlePart, renderer, nil, x, y, true)
        x += st.globalStyle.font.renderUTF8Blended(rightPart, renderer, nil, x, y, false)
        
      # when the line is the first line or the last line of a multiline selection.
      elif selectionRangeStart.y == i or i == selectionRangeEnd.y and clippedLine.len > 0:
        let splittingPoint = if i == selectionRangeStart.y: selectionRangeStart.x else: selectionRangeEnd.x
        # NOTE THAT the splitting point wouldn't always be in the clipped range.
        # we treat it the same as if the endpoints are at the start/end of the line        # since some nim builtin doesn't handle out-of-range values so we do the
        # tedious part here.
        let splittingPointRelativeX = (splittingPoint-ss.viewPort.x).clip(0, clippedLineLen.cint)
        let leftPart = clippedLine[0..<splittingPointRelativeX]
        let rightPart = clippedLine[splittingPointRelativeX..<clippedLine.len]
        let leftPartWidth = st.globalStyle.font.calculateWidth(leftPart, renderer)
        let rightPartWidth = st.globalStyle.font.calculateWidth(rightPart, renderer)
        let baselineY = (i-ss.viewPort.y)*st.gridSize.h
        # draw inverted background.
        # NOTE THAT baselineY is the *bottom* of the current line.
        ev.dstrect.x = (if i == selectionRangeStart.y: leftPartWidth else: 0).cint + baselineX
        ev.dstrect.y = (offsetPY + baselineY).cint
        ev.dstrect.w = (if i == selectionRangeStart.y: rightPartWidth else: leftPartWidth).cint
        ev.dstrect.h = st.gridSize.h
        renderer.setDrawColor(st.globalStyle.highlightColor.r,
                              st.globalStyle.highlightColor.g,
                              st.globalStyle.highlightColor.b)
        renderer.fillRect(ev.dstrect.addr)
        # draw the parts.
        if leftPartWidth > 0:
          discard st.globalStyle.font.renderUTF8Blended(
            leftPart, renderer, nil, baselineX, ev.dstrect.y,
            not (i == selectionRangeStart.y)
          )
        if rightPartWidth > 0:
          discard st.globalStyle.font.renderUTF8Blended(
            rightPart, renderer, nil, (baselineX+leftPartWidth).cint, ev.dstrect.y,
            i == selectionRangeStart.y
          )
      elif selectionRangeStart.y < i and i < selectionRangeEnd.y:
        ev.dstrect.x = baselineX
        ev.dstrect.y = offsetPY + ((i-ss.viewPort.y)*st.gridSize.h).cint
        ev.dstrect.w = if clippedLine.len() <= 0: st.gridSize.w
                       else: st.globalStyle.font.calculateWidth(clippedLine, renderer).cint
        ev.dstrect.h = st.gridSize.h
        renderer.setDrawColor(st.globalStyle.highlightColor.r,
                              st.globalStyle.highlightColor.g,
                              st.globalStyle.highlightColor.b)
        renderer.fillRect(ev.dstrect.addr)
        discard st.globalStyle.font.renderUTF8Blended(
          clippedLine, renderer, nil, baselineX, ev.dstrect.y, true
        )

    if not ss.selectionInEffect or
       i < selectionRangeStart.y or
       i > selectionRangeEnd.y:
      discard st.globalStyle.font.renderUTF8Blended(
        clippedLine, renderer, nil, baselineX,
        offsetPY+((i-ss.viewPort.y)*st.gridSize.h).cint,
        false
      )
        
proc renderWith*(ew: EditorView, renderer: RendererPtr): void =
  renderer.render(ew)

  
