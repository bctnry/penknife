import std/strtabs
import std/[files, paths, syncio]
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
const CONFIG_KEY_MAIN_FOREGROUND_COLOR* = "main_foreground_color"
const CONFIG_KEY_MAIN_BACKGROUND_COLOR* = "main_background_color"
const CONFIG_KEY_MAIN_SELECT_FOREGROUND_COLOR* = "main_select_foreground_color"
const CONFIG_KEY_MAIN_SELECT_BACKGROUND_COLOR* = "main_select_background_color"
const CONFIG_KEY_AUX_FOREGROUND_COLOR* = "aux_foreground_color"
const CONFIG_KEY_AUX_BACKGROUND_COLOR* = "aux_background_color"
const CONFIG_KEY_AUX_SELECT_FOREGROUND_COLOR* = "aux_select_foreground_color"
const CONFIG_KEY_AUX_SELECT_BACKGROUND_COLOR* = "aux_select_background_color"
const CONFIG_KEY_MAIN_LINENUMBER_FOREGROUND_COLOR* = "main_linenumber_foreground_color"
const CONFIG_KEY_MAIN_LINENUMBER_BACKGROUND_COLOR* = "main_linenumber_background_color"
const CONFIG_KEY_MAIN_LINENUMBER_SELECT_FOREGROUND_COLOR* = "main_linenumber_select_foreground_color"
const CONFIG_KEY_MAIN_LINENUMBER_SELECT_BACKGROUND_COLOR* = "main_linenumber_select_background_color"
const CONFIG_KEY_MAIN_COMMENT_FOREGROUND_COLOR* = "main_comment_foreground_color"
const CONFIG_KEY_MAIN_KEYWORD_FOREGROUND_COLOR* = "main_keyword_foreground_color"
const CONFIG_KEY_MAIN_AUXKEYWORD_FOREGROUND_COLOR* = "main_auxkeyword_foreground_color"
const CONFIG_KEY_MAIN_STRING_FOREGROUND_COLOR* = "main_string_foreground_color"
const CONFIG_KEY_MAIN_TYPE_FOREGROUND_COLOR* = "main_type_foreground_color"
const CONFIG_KEY_MAIN_SPECIALID_FOREGROUND_COLOR* = "main_specialid_foreground_color"

proc getGlobalConfig*(key: string): string =
  if not config.hasKey(key): return ""
  else: return config[key]
  
