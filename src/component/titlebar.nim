import sdl2
import ../model/[state, textbuffer, style, cursor, editsession]
import ../ui/[tvfont]

type
  TitleBar* = ref object
    parentState*: State
    dstrect*: Rect
    offsetX*: cint
    offsetY*: cint
    width*: cint
    height*: cint

proc clip(x: cint, l: cint, r: cint): cint =
  return (if x < l: l elif x > r: r else: x)
  
proc mkTitleBar*(st: State): TitleBar =
  return TitleBar(
    parentState: st,
    dstrect: (x: 0, y: 0, w: 0, h: 0),
    offsetX: 0,
    offsetY: 0,
    width: 0,
    height: 0,
  )

proc relayout*(tb: TitleBar, x: cint, y: cint, w: cint, h: cint): void =
  tb.offsetX = x
  tb.offsetY = y
  tb.width = w
  tb.height = h

proc render*(renderer: RendererPtr, tb: TitleBar): void =
  # NOTE: titlebar has the same behaviour as editorview except that:
  # + its height is set to be always the same as the aux buffer (through onChange
  #   callback of aux buffer)
  # + the color is different
  # maybe this should be combined into one single component with editorview but
  # we'll see.
  let st = tb.parentState
  let ss = st.auxEditSession
  tb.dstrect.x = tb.offsetX*st.gridSize.w
  tb.dstrect.y = tb.offsetY*st.gridSize.h
  tb.dstrect.w = tb.width*st.gridSize.w
  tb.dstrect.h = tb.height*st.gridSize.h
  let bgColor = st.globalStyle.getColor(AUX_BACKGROUND)
  renderer.setDrawColor(bgColor.r, bgColor.g, bgColor.b)
  renderer.fillRect(tb.dstrect)
  let baselineX = (tb.offsetX*st.gridSize.w).cint
  let offsetPY = (tb.offsetY*st.gridSize.h).cint
  let renderRowBound = min(ss.viewPort.y+tb.height, min(ss.viewPort.y+ss.viewPort.h, ss.textBuffer.lineCount()))
  let selectionRangeStart = min(ss.selection.first, ss.selection.last)
  let selectionRangeEnd = max(ss.selection.first, ss.selection.last)
  for i in 0..<ss.textBuffer.lineCount():
    let line = ss.textBuffer.getLineOfRune(i)
    let renderColBound = min(ss.viewPort.x+ss.viewPort.w, line.len)
    if renderColBound <= ss.viewPort.x:
      # when: (1) selection is active; (2) row is in selection; (3) row is
      # empty after clipping, we need to display an indicator in the form
      # of a rectangle the size of a single character. this is the behaviour
      # of emacs. we now do the same thing here.
      if ss.selectionInEffect and selectionRangeStart.y < i and i < selectionRangeEnd.y:
        tb.dstrect.x = baselineX.cint
        tb.dstrect.y = offsetPY + ((i-ss.viewPort.y)*st.gridSize.h).cint
        tb.dstrect.w = st.gridSize.w
        tb.dstrect.h = st.gridSize.h
        let bgColor: sdl2.Color = st.globalStyle.getColor(AUX_SELECT_BACKGROUND)
        renderer.setDrawColor(bgColor.r, bgColor.g, bgColor.b)
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
        let leftPart = clippedLine[0..<splittingPoint1]
        let middlePart = clippedLine[splittingPoint1..<splittingPoint2]
        let rightPart = clippedLine[splittingPoint2..<clippedLine.len]
        let leftPartWidth = st.globalFont.calculateWidth(leftPart, renderer)
        let y = offsetPY + ((i-ss.viewPort.y+1)*st.gridSize.h - st.gridSize.h).cint
        var x = baselineX
        if middlePart.len > 0:
          tb.dstrect.y = y.cint
          tb.dstrect.x = (baselineX+leftPartWidth).cint
          tb.dstrect.w = st.globalStyle.font.calculateWidth(middlePart, renderer).cint
          tb.dstrect.h = st.gridSize.h
          let bgColor: sdl2.Color = st.globalStyle.getColor(AUX_SELECT_BACKGROUND)
          renderer.setDrawColor(bgColor.r, bgColor.g, bgColor.b)
          renderer.fillRect(tb.dstrect)
        x += st.globalStyle.font.renderUTF8Blended(leftPart, renderer, nil, x, y, st.globalStyle.getColor(AUX_FOREGROUND))
        x += st.globalStyle.font.renderUTF8Blended(middlePart, renderer, nil, x, y, st.globalStyle.getColor(AUX_SELECT_FOREGROUND))
        x += st.globalStyle.font.renderUTF8Blended(rightPart, renderer, nil, x, y, st.globalStyle.getColor(AUX_FOREGROUND))
        
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
        tb.dstrect.x = (if i == selectionRangeStart.y: leftPartWidth else: 0).cint + baselineX
        tb.dstrect.y = (offsetPY + baselineY).cint
        tb.dstrect.w = (if i == selectionRangeStart.y: rightPartWidth else: leftPartWidth).cint
        tb.dstrect.h = st.gridSize.h
        let bgColor: sdl2.Color = st.globalStyle.getColor(AUX_SELECT_BACKGROUND)
        renderer.setDrawColor(bgColor.r, bgColor.g, bgColor.b)
        renderer.fillRect(tb.dstrect.addr)
        # draw the parts.
        if leftPartWidth > 0:
          discard st.globalStyle.font.renderUTF8Blended(
            leftPart, renderer, nil, baselineX, tb.dstrect.y,
            st.globalStyle.getColor(
              if i == selectionRangeStart.y: AUX_FOREGROUND
              else: AUX_SELECT_FOREGROUND
            )
          )
        if rightPartWidth > 0:
          discard st.globalStyle.font.renderUTF8Blended(
            rightPart, renderer, nil, (baselineX+leftPartWidth).cint, tb.dstrect.y,
            st.globalStyle.getColor(
              if i == selectionRangeStart.y: AUX_SELECT_FOREGROUND
              else: AUX_FOREGROUND
            )
          )
      elif selectionRangeStart.y < i and i < selectionRangeEnd.y:
        tb.dstrect.x = baselineX
        tb.dstrect.y = offsetPY + ((i-ss.viewPort.y)*st.gridSize.h).cint
        tb.dstrect.w = if clippedLine.len() <= 0: st.gridSize.w
                       else: st.globalStyle.font.calculateWidth(clippedLine, renderer).cint
        tb.dstrect.h = st.gridSize.h
        let bgColor: sdl2.Color = st.globalStyle.getColor(AUX_SELECT_BACKGROUND)
        renderer.setDrawColor(bgColor.r, bgColor.g, bgColor.b)
        renderer.fillRect(tb.dstrect.addr)
        discard st.globalStyle.font.renderUTF8Blended(
          clippedLine, renderer, nil, baselineX, tb.dstrect.y,
          st.globalStyle.getColor(AUX_SELECT_FOREGROUND)
        )

    if not ss.selectionInEffect or
       i < selectionRangeStart.y or
       i > selectionRangeEnd.y:
      discard st.globalStyle.font.renderUTF8Blended(
        clippedLine, renderer, nil, baselineX,
        offsetPY+((i-ss.viewPort.y)*st.gridSize.h).cint,
        st.globalStyle.getColor(AUX_FOREGROUND)
      )
  
proc renderWith*(tb: TitleBar, renderer: RendererPtr): void =
  renderer.render(tb)
  

