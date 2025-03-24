import std/strutils
import std/paths
import model/[editsession, state, textbuffer]

# penknife control language.
#
# [n]   -  go to line number [n]
# [n]+  -  go to the line [n] lines after the current line.
# [n]-  -  go to the line [n] lines before the current line.
# [string]>   -  search [string] from the cursor, forward.
# [string]<   -  search [string] from the cursor, backward.
# [string1]=[string2]>   -  replace [string1] with [string2]
# [string1]=[string2]<   -  replace [string1] with [string2]
# /[pat1]/=[pat2]>    -  regex replace [pat1] with [pat2]
# /[pat1]/=[pat2]<    -  regex replace [pat1] with [pat2]
# [id]  -  any registered command


proc isNumber(s: string): bool =
  for c in s:
    if not ('0' <= c and c <= '9'): return false
  return true

proc interpretControlCommand*(s: string, st: State, shouldReload: var bool, shouldQuit: var bool): void =
  if s.isNumber:
    let (line, col) = st.mainEditSession.textBuffer.resolvePosition(s.parseInt, st.mainEditSession.cursor.x)
    st.mainEditSession.setCursor(line, col)
  elif s == "Open":
    let aux = st.auxEditSession
    let titleStr = aux.textBuffer.getLine(0)
    let ss = titleStr.split('|', maxsplit=1)
    let filePath = (if ss.len >= 2: ss[1] else: ss[0]).strip()
    let newName = $filePath.Path.extractFilename()
    let f = open(filePath, fmRead)
    let s = f.readAll()
    f.close()
    st.loadText(s, name=newName, fullPath=filePath)
  elif s == "Save":
    let aux = st.auxEditSession
    let main = st.mainEditSession
    let titleStr = aux.textBuffer.getLine(0)
    let ss = titleStr.split('|', maxsplit=1)
    let filePath = (if ss.len >= 2: ss[1] else: ss[0]).strip()
    let newName = (if ss.len >= 2: ss[0] else: $filePath.Path.extractFilename())
    let data = main.textBuffer.toString()
    main.textBuffer.name = newName
    let f = open(filePath, fmWrite)
    f.write(data)
    f.flushFile()
    f.close()
    main.textBuffer.dirty = false
  elif s == "Exit":
    shouldReload = false
    shouldQuit = true
  else:
    let trimmed = s.strip()
    if trimmed.endsWith("+"):
      let parg = trimmed[0..<trimmed.len()-1]
      if parg.isNumber:
        let currentLine = st.mainEditSession.cursor.y
        let offsetY = parg.parseInt
        let (line, col) = st.mainEditSession.textBuffer.resolvePosition(currentLine+offsetY, st.mainEditSession.cursor.x)
        st.mainEditSession.setCursor(line, col)
      elif trimmed.endsWith("-"):
        let parg = trimmed[0..<trimmed.len()-1]
        if parg.isNumber:
          let currentLine = st.mainEditSession.cursor.y
          let offsetY = parg.parseInt
          let (line, col) = st.mainEditSession.textBuffer.resolvePosition(currentLine-offsetY, st.mainEditSession.cursor.x)
          st.mainEditSession.setCursor(line, col)
          
  
  discard
  
