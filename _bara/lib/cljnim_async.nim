# Simplified core.async for Bara Lang
# Provides channels with put!/take!/close! and go blocks
import deques, locks

type
  ChannelObj* = ref object
    buf*: Deque[int]  # simplified: int values only for MVP
    capacity*: int
    lock*: Lock
    closed*: bool

  Channel* = ref ChannelObj

proc newChannel*(capacity: int = 0): Channel =
  result = ChannelObj(capacity: capacity, closed: false)
  result.buf = initDeque[int]()
  initLock(result.lock)

proc put*(ch: Channel, val: int): bool =
  withLock ch.lock:
    if ch.closed: return false
    if ch.capacity > 0 and ch.buf.len >= ch.capacity:
      return false
    ch.buf.addLast(val)
    return true

proc take*(ch: Channel): (bool, int) =
  withLock ch.lock:
    if ch.buf.len == 0:
      return (false, 0)
    return (true, ch.buf.popFirst())

proc close*(ch: Channel) =
  withLock ch.lock:
    ch.closed = true
