import std/unicode
import sdl2
import ../model/[state, textbuffer, cursor]
import ../ui/[sdl2_ui_utils, tvfont]

# cursor.

type
  EditorView* = ref object
    parentState*: State
    dstrect*: Rect

proc clip(x: cint, l: cint, r: cint): cint =
  return (if x < l: l elif x > r: r else: x)
  
proc mkEditorView*(st: State): EditorView =
  return EditorView(
    parentState: st,
    dstrect: (x: 0.cint, y: 0.cint, w: 0.cint, h: 0.cint)
  )

proc render*(renderer: RendererPtr, ew: EditorView): void =
  let st = ew.parentState
  let baselineX = (st.viewPort.offset*st.gridSize.w).cint
  let offsetPY = (st.viewPort.offsetY*st.gridSize.h).cint
  # render edit viewport
  let renderRowBound = min(st.viewPort.y+st.viewPort.h, st.session.lineCount())
  let selectionRangeStart = min(st.selection.first, st.selection.last)
  let selectionRangeEnd = max(st.selection.first, st.selection.last)
  for i in st.viewPort.y..<renderRowBound:
    let line = st.session.getLineOfRune(i)
    let renderColBound = min(st.viewPort.x+st.viewPort.w, line.len)
    if renderColBound <= st.viewPort.x:
      # when: (1) selection is active; (2) row is in selection; (3) row is
      # empty after clipping, we need to display an indicator in the form
      # of a rectangle the size of a single character. this is the behaviour
      # of emacs. we now do the same thing here.
      if st.selectionInEffect and selectionRangeStart.y < i and i < selectionRangeEnd.y:
        ew.dstrect.x = baselineX.cint
        ew.dstrect.y = offsetPY + ((i-st.viewPort.y)*st.gridSize.h).cint
        ew.dstrect.w = st.gridSize.w
        ew.dstrect.h = st.gridSize.h
        renderer.setDrawColor(st.globalStyle.highlightColor.r,
                              st.globalStyle.highlightColor.g,
                              st.globalStyle.highlightColor.b)
        renderer.fillRect(ew.dstrect.addr)
      continue
    let clippedLine = line[st.viewPort.x..<renderColBound]
    let clippedLineLen = renderColBound - st.viewPort.x
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
    if st.selectionInEffect:
      # when the selection is within a single line
      if selectionRangeStart.y == selectionRangeEnd.y and i == selectionRangeStart.y:
        let splittingPoint1 = (selectionRangeStart.x - st.viewPort.x).clip(0, clippedLineLen.cint)
        let splittingPoint2 = (selectionRangeEnd.x - st.viewPort.x).clip(0, clippedLineLen.cint)
        let leftPart = clippedLine[0..<splittingPoint1]
        let middlePart = clippedLine[splittingPoint1..<splittingPoint2]
        let rightPart = clippedLine[splittingPoint2..<clippedLine.len]
        let leftPartWidth = st.globalFont.calculateWidth(leftPart, renderer)
        let y = offsetPY + ((i-st.viewPort.y+1)*st.gridSize.h - st.gridSize.h).cint
        var x = baselineX
        if middlePart.len > 0:
          ew.dstrect.y = y.cint
          ew.dstrect.x = (baselineX+leftPartWidth).cint
          ew.dstrect.w = st.globalFont.calculateWidth(middlePart, renderer).cint
          ew.dstrect.h = st.gridSize.h
          renderer.setDrawColor(st.globalStyle.highlightColor.r,
                                st.globalStyle.highlightColor.g,
                                st.globalStyle.highlightColor.b)
          renderer.fillRect(ew.dstrect)
        x += st.globalFont.renderUTF8Blended(leftPart, renderer, nil, x, y, false)
        x += st.globalFont.renderUTF8Blended(middlePart, renderer, nil, x, y, true)
        x += st.globalFont.renderUTF8Blended(rightPart, renderer, nil, x, y, false)
        
      # when the line is the first line or the last line of a multiline selection.
      elif selectionRangeStart.y == i or i == selectionRangeEnd.y and clippedLine.len > 0:
        let splittingPoint = if i == selectionRangeStart.y: selectionRangeStart.x else: selectionRangeEnd.x
        # NOTE THAT the splitting point wouldn't always be in the clipped range.
        # we treat it the same as if the endpoints are at the start/end of the line        # since some nim builtin doesn't handle out-of-range values so we do the
        # tedious part here.
        let splittingPointRelativeX = (splittingPoint-st.viewPort.x).clip(0, clippedLineLen.cint)
        let leftPart = clippedLine[0..<splittingPointRelativeX]
        let rightPart = clippedLine[splittingPointRelativeX..<clippedLine.len]
        let leftPartWidth = st.globalFont.calculateWidth(leftPart, renderer)
        let rightPartWidth = st.globalFont.calculateWidth(rightPart, renderer)
        let baselineY = (i-st.viewPort.y)*st.gridSize.h
        # draw inverted background.
        # NOTE THAT baselineY is the *bottom* of the current line.
        ew.dstrect.x = (if i == selectionRangeStart.y: leftPartWidth else: 0).cint + baselineX
        ew.dstrect.y = (offsetPY + baselineY).cint
        ew.dstrect.w = (if i == selectionRangeStart.y: rightPartWidth else: leftPartWidth).cint
        ew.dstrect.h = st.gridSize.h
        renderer.setDrawColor(st.globalStyle.highlightColor.r,
                              st.globalStyle.highlightColor.g,
                              st.globalStyle.highlightColor.b)
        renderer.fillRect(ew.dstrect.addr)
        # draw the parts.
        if leftPartWidth > 0:
          discard st.globalFont.renderUTF8Blended(
            leftPart, renderer, nil, baselineX, ew.dstrect.y,
            not (i == selectionRangeStart.y)
          )
        if rightPartWidth > 0:
          discard st.globalFont.renderUTF8Blended(
            rightPart, renderer, nil, (baselineX+leftPartWidth).cint, ew.dstrect.y,
            i == selectionRangeStart.y
          )
      elif selectionRangeStart.y < i and i < selectionRangeEnd.y:
        ew.dstrect.x = baselineX
        ew.dstrect.y = offsetPY + ((i-st.viewPort.y)*st.gridSize.h).cint
        ew.dstrect.w = if clippedLine.len() <= 0: st.gridSize.w
                       else: st.globalFont.calculateWidth(clippedLine, renderer).cint
        ew.dstrect.h = st.gridSize.h
        renderer.setDrawColor(st.globalStyle.highlightColor.r,
                              st.globalStyle.highlightColor.g,
                              st.globalStyle.highlightColor.b)
        renderer.fillRect(ew.dstrect.addr)
        discard st.globalFont.renderUTF8Blended(
          clippedLine, renderer, nil, baselineX, ew.dstrect.y, true
        )

    if not st.selectionInEffect or
       i < selectionRangeStart.y or
       i > selectionRangeEnd.y:
      discard st.globalFont.renderUTF8Blended(
        clippedLine, renderer, nil, baselineX,
        offsetPY+((i-st.viewPort.y)*st.gridSize.h).cint,
        false
      )
        
proc renderWith*(ew: EditorView, renderer: RendererPtr): void =
  renderer.render(ew)

  
