type
  TextBufferView* = ref object
    parent: EditorView
    dstrect: Rect
    lateral: GenericWindow

proc getWidth(tb: TextBufferView): int =
  let vp = tb.parent.session.viewPort
  let bound = min(vp.y + vp.h, tb.parent.session.textBuffer.lineCount())
  var res = 1
  while bound > 0:
    res += 1
    bound = bound div 10
  return res + VIEWPORT_GAP

proc relayout*(tb: TextBufferView, evLateral: GenericWindow): void =
  let w = tb.getWidth()
  tb.lateral.offsetX = evLateral.offsetX + w
  tb.lateral.offsetY = evLateral.offsetY - 1
  tb.lateral.w = evLateral.w - w
  tb.lateral.h = evLateral.h - 2
    
proc mkTextBufferView*(parent: EditorView): TitleBar =
  return TitleBar(
    parent: parent,
    dstrect: (x: 0, y: 0, w: 0, h: 0),
    lateral: mkGenericWindow()
  )

proc clip(x: cint, l: cint, r: cint): cint =
  return (if x < l: l elif x > r: r else: x)

proc render*(renderer: RendererPtr, tb: TextBufferView): void =
  let ss = tb.parent.session
  let baselinePX = tb.lateral.offsetX * tb.parent.gridSizeW
  let offsetPY = tb.lateral.offsetY * tb.parent.gridSizeH
  # render edit viewport
  let renderRowBound = min(ss.viewPort.y+ss.viewPort.h, ss.session.lineCount())
  let selectionRangeStart = min(ss.selection.first, ss.selection.last)
  let selectionRangeEnd = max(ss.selection.first, ss.selection.last)
  let fgColor = tb.parent.style.fgColor
  let bgColor = tb.parent.style.bgColor
  let font = tb.parent.style.font
  for i in ss.viewPort.y..<renderRowBound:
    let line = ss.textBuffer.getLine(i)
    let renderColBound = min(ss.viewPort.x + ss.viewPort.w, line.len)
    if renderColBound <= ss.viewPort.x:
      # when: (1) selection is active; (2) row is in selection; (3) row is
      # empty after clipping, we need to display an indicator in the form
      # of a rectangle the size of a single character. this is the behaviour
      # of emacs. we now do the same thing here.
      if ss.selectionInEffect and selectionRangeStart.y < i and i < selectionRangeEnd.y:
        tb.dstrect.x = baselinePX.cint
        tb.dstrect.y = offsetPY + ((i-ss.viewPort.y)*tb.parent.gridSizeH).cint
        tb.dstrect.w = tb.parent.gridSizeW
        tb.dstrect.h = tb.parent.gridSizeH
        renderer.setDrawColor(tb.parent.style.fgColor)
        renderer.fillRect(tb.dstrect.addr)
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
        var leftPartTexture = renderer.mkTextTexture(
          font, clippedLine[0..<splittingPoint1].cstring, fgColor
        )
        var middlePartTexture = renderer.mkTextTexture(
          font, clippedLine[splittingPoint1..<splittingPoint2].cstring, bgColor
        )
        var rightPartTexture = renderer.mkTextTexture(
          font, clippedLine.substr(splittingPoint2).cstring, fgColor
        )
        tb.dstrect.y = offsetPY + ((i-ss.viewPort.y+1)*tb.parent.gridSizeH - max(max(leftPartTexture.height, rightPartTexture.height), tb.parent.gridSizeH)).cint
        if not leftPartTexture.isNil:
          tb.dstrect.x = baselinePX
          tb.dstrect.w = leftPartTexture.w
          tb.dstrect.h = leftPartTexture.h
          renderer.copyEx(leftPartTexture.raw, nil, tb.dstrect.addr, 0.cdouble, nil)
        if not middlePartTexture.isNil:
          tb.dstrect.x = (baselinePX+leftPartTexture.width).cint
          tb.dstrect.w = middlePartTexture.width.cint
          tb.dstrect.h = tb.parent.gridSizeH
          renderer.setDrawColor(fgColor)
          renderer.fillRect(tb.dstrect.addr)
          tb.dstrect.h = middlePartTexture.height.cint
          renderer.copyEx(middlePartTexture.raw, nil, tb.dstrect.addr, 0.cdouble, nil)
        if not rightPartTexture.isNil:
          tb.dstrect.x = (baselinePX+leftPartTexture.width+middlePartTexture.width).cint
          tb.dstrect.w = rightPartTexture.width.cint
          tb.dstrect.h = rightPartTexture.height.cint
          renderer.copyEx(rightPartTexture.raw, nil, tb.dstrect.addr, 0.cdouble, nil)
        leftPartTexture.dispose()
        middlePartTexture.dispose()
        rightPartTexture.dispose()
      # when the line is the first line or the last line of a multiline selection.
      elif selectionRangeStart.y == i or i == selectionRangeEnd.y and clippedLine.len > 0:
        let splittingPoint = if i == selectionRangeStart.y: selectionRangeStart.x else: selectionRangeEnd.x
        # NOTE THAT the splitting point wouldn't always be in the clipped range.
        # we treat it the same as if the endpoints are at the start/end of the line        # since some nim builtin doesn't handle out-of-range values so we do the
        # tedious part here.
        let splittingPointRelativeX = (splittingPoint-ss.viewPort.x).clip(0, clippedLineLen.cint)
        let leftPart = clippedLine[0..<splittingPointRelativeX].cstring
        let rightPart = clippedLine.substr(splittingPointRelativeX).cstring
        let baselineY = (i-ss.viewPort.y+1)*tb.gridSizeH
        var leftPartTexture = renderer.mkTextTexture(
          font, leftPart, if i == selectionRangeStart.y: fgColor else: bgColor
        )
        var leftPartTextureWidth = if leftPartTexture.isNil: 0 else: leftPartTexture.w
        var rightPartTexture = renderer.mkTextTexture(
          font, rightPart, if i == selectionRangeStart.y: bgColor else: fgColor
        )
        var rightPartTextureWidth = if rightPartTexture.isNil: 0 else: rightPartTexture.w
        # draw inverted background.
        # NOTE THAT baselineY is the *bottom* of the current line.
        tb.dstrect.x = (if i == selectionRangeStart.y: leftPartTextureWidth else: 0).cint + baselineX
        tb.dstrect.y = offsetPY + (baselineY-tb.parent.gridSizeH).cint
        tb.dstrect.w = (if i == selectionRangeStart.y: rightPartTextureWidth else: leftPartTextureWidth).cint
        tb.dstrect.h = tb.parent.gridSizeH
        renderer.setDrawColor(fgColor)
        renderer.fillRect(tb.dstrect.addr)
        # draw the parts.
        if not leftPartTexture.isNil:
          tb.dstrect.x = baselinePX
          tb.dstrect.w = leftPartTextureWidth.cint
          renderer.copyEx(leftPartTexture.raw, nil, tb.dstrect.addr, 0.cdouble, nil)
        if not rightPartTexture.isNil:
          tb.dstrect.x = baselinePX + leftPartTextureWidth.cint
          tb.dstrect.w = rightPartTextureWidth.cint
          renderer.copyEx(rightPartTexture.raw, nil, tb.dstrect.addr, 0.cdouble, nil)
        leftPartTexture.dispose()
        rightPartTexture.dispose()
      elif selectionRangeStart.y < i and i < selectionRangeEnd.y:
        let texture = renderer.mkTextTexture(
          font, clippedLine.cstring, bgColor
        )
        tb.dstrect.x = baselinePX
        tb.dstrect.y = offsetPY + ((i-ss.viewPort.y)*tb.parent.gridSizeH).cint
        tb.dstrect.w = if texture.isNil: tb.parent.gridSizeW else: texture.w
        tb.dstrect.h = tb.parent.gridSizeH
        renderer.setDrawColor(fgColor)
        renderer.fillRect(tb.dstrect.addr)
        if not texture.isNil:
          renderer.copyEx(texture.raw, nil, tb.dstrect.addr, 0.cdouble, nil)
          texture.dispose()

    if not ss.selectionInEffect or
       i < selectionRangeStart.y or
       i > selectionRangeEnd.y:
      if renderer.renderTextSolid(
        tb.dstrect.addr,
        font, clippedLine.cstring,
        baselinePX, offsetPY+((i-ss.viewPort.y)*tb.parent.gridSizeH).cint,
        fgColor
      ) == -1: continue
  
proc renderWith*(tb: TitleBar, renderer: RendererPtr): void =
  renderer.render(tb)
  
