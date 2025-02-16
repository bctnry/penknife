import std/strtabs
import std/[files, dirs, paths, syncio]
import std/strutils

var config: StringTableRef

proc loadGlobalConfig*(): bool =
  echo fileExists("./penknife.config".Path)
  if not fileExists("./penknife.config".Path): return false
  let f = open("./penknife.config", fmRead)
  let s = f.readAll()
  f.close()
  config = newStringTable()
  for k in s.split("\n"):
    if k.strip().startsWith("#"): continue
    if k.strip().len <= 0: continue
    let kk = k.split("=", maxsplit=1)
    if kk.len == 1:
      config[kk[0]] = "true"
    else:
      config[kk[0]] = kk[1]
  return true

const CONFIG_KEY_FONT_PATH* = "font_path"
const CONFIG_KEY_FONT_SIZE* = "font_size"
const CONFIG_MAIN_COLOR* = "main_color"
const CONFIG_HIGHLIGHT_COLOR* = "hl_color"
const CONFIG_AUX_COLOR* = "aux_color"
const CONFIG_BACKGROUND_COLOR* = "bg_color"

proc getGlobalConfig*(key: string): string =
  if not config.hasKey(key): return ""
  else: return config[key]
  
