import sdl2

# this code probably is very bad - I don't have good feelings about this one.

type
  Timer* = ref object
    startedAt*: uint32
    pausedAt*: uint32
    ticksPassed*: uint32
    paused: bool
    started: bool

proc mkTimer*(): Timer =
  return Timer(startedAt: 0,
               pausedAt: 0,
               ticksPassed: 0,
               started: false,
               paused: false)

proc start*(t: var Timer): void =
  t.started = true
  t.paused = false
  t.startedAt = sdl2.getTicks()
  t.pausedAt = 0

proc pause*(t: var Timer): void =
  if t.startedAt > 0 and not t.paused:
    t.paused = true
    t.pausedAt = sdl2.getTicks()
    t.ticksPassed += t.pausedAt - t.startedAt
    t.startedAt = 0

proc resume*(t: var Timer): void =
  if t.started and t.paused:
    t.paused = false
    t.startedAt = sdl2.getTicks()
    t.pausedAt = 0

proc stop*(t: var Timer): void =
  t.paused = false
  t.pausedAt = 0
  t.started = false
  t.startedAt = 0
  t.ticksPassed = 0
                 
type
  Timeout* = ref object
    isInterval: bool
    t: Timer
    timeMS: uint32
    callback: proc (): void

proc paused*(x: Timeout): bool = x.t.paused
proc stopped*(x: Timeout): bool = x.t.started == false
proc started*(x: Timeout): bool = x.t.started

proc mkTimeout*(callback: proc(): void, timeMS: uint32): Timeout =
  return Timeout(isInterval: false, t: mkTimer(), timeMS: timeMS, callback: callback)

proc mkInterval*(callback: proc(): void, timeMS: uint32): Timeout =
  return Timeout(isInterval: true, t: mkTimer(), timeMS: timeMS, callback: callback)

proc start*(timeout: Timeout): void =
  timeout.t.start()

proc check*(timeout: Timeout): void =
  let t = sdl2.getTicks()
  if timeout.started and not timeout.t.paused and
     t - timeout.t.startedAt + timeout.t.ticksPassed >= timeout.timeMS:
    timeout.callback()
    if timeout.isInterval:
      timeout.t.ticksPassed = 0
      timeout.t.startedAt = t
    else:
      timeout.t.stop()

proc stop*(timeout: Timeout): void =
  timeout.t.stop()
    
  
