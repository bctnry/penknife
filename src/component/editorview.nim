import sdl2
import ../model/[state, textbuffer, cursor]
import ../ui/[sdl2_utils, texture]

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
    let line = st.session.getLine(i)
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
        renderer.setDrawColor(st.fgColor.r, st.fgColor.g, st.fgColor.b)
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
        var leftPartTexture = renderer.mkTextTexture(
          st.globalFont, clippedLine[0..<splittingPoint1].cstring, st.fgColor
        )
        var middlePartTexture = renderer.mkTextTexture(
          st.globalFont, clippedLine[splittingPoint1..<splittingPoint2].cstring, st.bgColor
        )
        var rightPartTexture = renderer.mkTextTexture(
          st.globalFont, clippedLine.substr(splittingPoint2).cstring, st.fgColor
        )
        ew.dstrect.y = offsetPY + ((i-st.viewPort.y+1)*st.gridSize.h - max(max(leftPartTexture.height, rightPartTexture.height), st.gridSize.h)).cint
        if not leftPartTexture.isNil:
          ew.dstrect.x = baselineX
          ew.dstrect.w = leftPartTexture.w
          ew.dstrect.h = leftPartTexture.h
          renderer.copyEx(leftPartTexture.raw, nil, ew.dstrect.addr, 0.cdouble, nil)
        if not middlePartTexture.isNil:
          ew.dstrect.x = (baselineX+leftPartTexture.width).cint
          ew.dstrect.w = middlePartTexture.width.cint
          ew.dstrect.h = st.gridSize.h
          renderer.setDrawColor(st.fgColor.r, st.fgColor.g, st.fgColor.b)
          renderer.fillRect(ew.dstrect)
          ew.dstrect.h = middlePartTexture.height.cint
          renderer.copyEx(middlePartTexture.raw, nil, ew.dstrect.addr, 0.cdouble, nil)
        if not rightPartTexture.isNil:
          ew.dstrect.x = (baselineX+leftPartTexture.width+middlePartTexture.width).cint
          ew.dstrect.w = rightPartTexture.width.cint
          ew.dstrect.h = rightPartTexture.height.cint
          renderer.copyEx(rightPartTexture.raw, nil, ew.dstrect.addr, 0.cdouble, nil)
        leftPartTexture.dispose()
        middlePartTexture.dispose()
        rightPartTexture.dispose()
      # when the line is the first line or the last line of a multiline selection.
      elif selectionRangeStart.y == i or i == selectionRangeEnd.y and clippedLine.len > 0:
        let splittingPoint = if i == selectionRangeStart.y: selectionRangeStart.x else: selectionRangeEnd.x
        # NOTE THAT the splitting point wouldn't always be in the clipped range.
        # we treat it the same as if the endpoints are at the start/end of the line        # since some nim builtin doesn't handle out-of-range values so we do the
        # tedious part here.
        let splittingPointRelativeX = (splittingPoint-st.viewPort.x).clip(0, clippedLineLen.cint)
        let leftPart = clippedLine[0..<splittingPointRelativeX].cstring
        let rightPart = clippedLine.substr(splittingPointRelativeX).cstring
        let baselineY = (i-st.viewPort.y+1)*st.gridSize.h
        var leftPartTexture = renderer.mkTextTexture(
          st.globalFont, leftPart, if i == selectionRangeStart.y: st.fgColor else: st.bgColor
        )
        var leftPartTextureWidth = if leftPartTexture.isNil: 0 else: leftPartTexture.w
        var rightPartTexture = renderer.mkTextTexture(
          st.globalFont, rightPart, if i == selectionRangeStart.y: st.bgColor else: st.fgColor
        )
        var rightPartTextureWidth = if rightPartTexture.isNil: 0 else: rightPartTexture.w
        # draw inverted background.
        # NOTE THAT baselineY is the *bottom* of the current line.
        ew.dstrect.x = (if i == selectionRangeStart.y: leftPartTextureWidth else: 0).cint + baselineX
        ew.dstrect.y = offsetPY + (baselineY-st.gridSize.h).cint
        ew.dstrect.w = (if i == selectionRangeStart.y: rightPartTextureWidth else: leftPartTextureWidth).cint
        ew.dstrect.h = st.gridSize.h
        renderer.setDrawColor(st.fgColor.r, st.fgColor.g, st.fgColor.b)
        renderer.fillRect(ew.dstrect.addr)
        # draw the parts.
        if not leftPartTexture.isNil:
          ew.dstrect.x = baselineX
          ew.dstrect.w = leftPartTextureWidth.cint
          renderer.copyEx(leftPartTexture.raw, nil, ew.dstrect.addr, 0.cdouble, nil)
        if not rightPartTexture.isNil:
          ew.dstrect.x = baselineX + leftPartTextureWidth.cint
          ew.dstrect.w = rightPartTextureWidth.cint
          renderer.copyEx(rightPartTexture.raw, nil, ew.dstrect.addr, 0.cdouble, nil)
        leftPartTexture.dispose()
        rightPartTexture.dispose()
      elif selectionRangeStart.y < i and i < selectionRangeEnd.y:
        let texture = renderer.mkTextTexture(
          st.globalFont, clippedLine.cstring, st.bgColor
        )
        ew.dstrect.x = baselineX
        ew.dstrect.y = offsetPY + ((i-st.viewPort.y)*st.gridSize.h).cint
        ew.dstrect.w = if texture.isNil: st.gridSize.w else: texture.w
        ew.dstrect.h = st.gridSize.h
        renderer.setDrawColor(st.fgColor.r, st.fgColor.g, st.fgColor.b)
        renderer.fillRect(ew.dstrect.addr)
        if not texture.isNil:
          renderer.copyEx(texture.raw, nil, ew.dstrect.addr, 0.cdouble, nil)
          texture.dispose()

    if not st.selectionInEffect or
       i < selectionRangeStart.y or
       i > selectionRangeEnd.y:
      if renderer.renderTextSolid(
        ew.dstrect.addr,
        st.globalFont, clippedLine.cstring,
        baselineX, offsetPY+((i-st.viewPort.y)*st.gridSize.h).cint,
        st.fgColor
      ) == -1: continue
        
proc renderWith*(ew: EditorView, renderer: RendererPtr): void =
  renderer.render(ew)

  
