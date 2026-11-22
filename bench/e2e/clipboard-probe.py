"""Measures when a program reads the clipboard during a paste. Test use only.

Does what EsyType's paste does (offers the dictation as a delayed-rendering "promise", presses Shift+Insert, keeps
the text for `hold` ms after the first request, then puts the user's clipboard back), except that the user's
clipboard is also put back as a promise, so every later read is seen and logged too.

  python clipboard-probe.py <target hwnd> <dictation> <user clipboard text> <hold ms> <watch ms>

Prints one JSON object: the requests with times (ms after the paste key), which text each got, and where the
foreground was. Sends keys only if <target hwnd> is the foreground window.
"""
import ctypes, json, sys, time
from ctypes import wintypes as W

u32, k32 = ctypes.WinDLL("user32", use_last_error=True), ctypes.WinDLL("kernel32", use_last_error=True)
LRESULT = ctypes.c_ssize_t
WNDPROC = ctypes.WINFUNCTYPE(LRESULT, W.HWND, W.UINT, W.WPARAM, W.LPARAM)
u32.DefWindowProcW.restype = LRESULT
u32.DefWindowProcW.argtypes = [W.HWND, W.UINT, W.WPARAM, W.LPARAM]
u32.CreateWindowExW.restype = W.HWND
u32.CreateWindowExW.argtypes = [W.DWORD, W.LPCWSTR, W.LPCWSTR, W.DWORD, ctypes.c_int, ctypes.c_int, ctypes.c_int, ctypes.c_int, W.HWND, W.HMENU, W.HINSTANCE, W.LPVOID]
u32.SetClipboardData.restype = W.HANDLE
u32.SetClipboardData.argtypes = [W.UINT, W.HANDLE]
u32.GetOpenClipboardWindow.restype = W.HWND
u32.GetForegroundWindow.restype = W.HWND
k32.GlobalAlloc.restype = W.HGLOBAL
k32.GlobalLock.restype = W.LPVOID
k32.GlobalLock.argtypes = [W.HGLOBAL]
k32.GlobalUnlock.argtypes = [W.HGLOBAL]

class WNDCLASSW(ctypes.Structure):
    _fields_ = [("style", W.UINT), ("lpfnWndProc", WNDPROC), ("cbClsExtra", ctypes.c_int), ("cbWndExtra", ctypes.c_int), ("hInstance", W.HINSTANCE),
                ("hIcon", W.HICON), ("hCursor", W.HANDLE), ("hbrBackground", W.HBRUSH), ("lpszMenuName", W.LPCWSTR), ("lpszClassName", W.LPCWSTR)]

class KEYBDINPUT(ctypes.Structure):
    _fields_ = [("wVk", W.WORD), ("wScan", W.WORD), ("dwFlags", W.DWORD), ("time", W.DWORD), ("dwExtraInfo", ctypes.c_size_t)]

class MOUSEINPUT(ctypes.Structure):
    _fields_ = [("dx", W.LONG), ("dy", W.LONG), ("mouseData", W.DWORD), ("dwFlags", W.DWORD), ("time", W.DWORD), ("dwExtraInfo", ctypes.c_size_t)]

class INPUT(ctypes.Structure):
    class _U(ctypes.Union):
        _fields_ = [("ki", KEYBDINPUT), ("mi", MOUSEINPUT)]
    _anonymous_ = ("u",)
    _fields_ = [("type", W.DWORD), ("u", _U)]

CF_UNICODETEXT, WM_RENDERFORMAT, WM_RENDERALLFORMATS = 13, 0x0305, 0x0306
target, dictation, user_text, hold, watch = int(sys.argv[1]), sys.argv[2], sys.argv[3], int(sys.argv[4]), int(sys.argv[5])
pre = int(sys.argv[6]) if len(sys.argv) > 6 else 150          # ms between offering and the paste key, as EsyType's 150
markers = len(sys.argv) > 7 and sys.argv[7] == "1"            # add the clipboard-history / monitor exclusion formats, as EsyType does
reoffer = len(sys.argv) > 8 and sys.argv[8] == "1"            # after each read, put the promise back so later reads are seen too
state = {"phase": "before", "t0": time.perf_counter()}  # 'before': times are ms after offering
log = []

def ms():
    return round((time.perf_counter() - state["t0"]) * 1000)

def pid_of(h):
    pid = W.DWORD()
    u32.GetWindowThreadProcessId(h, ctypes.byref(pid))
    return pid.value

def put_text(text):
    data = (text.replace("\n", "\r\n") + "\0").encode("utf-16-le")
    g = k32.GlobalAlloc(0x0002, len(data))
    p = k32.GlobalLock(g)
    ctypes.memmove(p, data, len(data))
    k32.GlobalUnlock(g)
    u32.SetClipboardData(CF_UNICODETEXT, g)

def proc(h, msg, wp, lp):
    if msg == WM_RENDERFORMAT:
        opener = u32.GetOpenClipboardWindow()
        phase = state["phase"]
        log.append({"ms": ms(), "phase": phase, "format": wp, "opener_pid": pid_of(opener) if opener else None})
        if phase == "before":
            return 0  # refused, as EsyType refuses requests before the paste key
        if wp == CF_UNICODETEXT:
            put_text(dictation if phase == "dictation" else user_text)
            if reoffer and phase == "dictation":
                state["again"] = True
        return 0
    if msg == WM_RENDERALLFORMATS:
        return 0
    return u32.DefWindowProcW(h, msg, wp, lp)

wndproc = WNDPROC(proc)
cls = WNDCLASSW(lpfnWndProc=wndproc, hInstance=k32.GetModuleHandleW(None), lpszClassName="EsyTypeClipboardProbe")
u32.RegisterClassW(ctypes.byref(cls))
hwnd = u32.CreateWindowExW(0, "EsyTypeClipboardProbe", "", 0, 0, 0, 0, 0, W.HWND(-3), None, cls.hInstance, None)

def promise():
    u32.EmptyClipboard(); u32.SetClipboardData(CF_UNICODETEXT, None)
    if markers:
        for m in ("ExcludeClipboardContentFromMonitorProcessing", "CanIncludeInClipboardHistory", "CanUploadToCloudClipboard"):
            g = k32.GlobalAlloc(0x0002, 4); ctypes.memset(k32.GlobalLock(g), 0, 4); k32.GlobalUnlock(g)
            u32.SetClipboardData(u32.RegisterClipboardFormatW(m), g)

def pump(d_ms):
    end = time.perf_counter() + d_ms / 1000
    msg = W.MSG()
    while True:
        while u32.PeekMessageW(ctypes.byref(msg), hwnd, 0, 0, 1):
            u32.TranslateMessage(ctypes.byref(msg)); u32.DispatchMessageW(ctypes.byref(msg))
        # once the reader has closed the clipboard (one try per loop, never blocking)
        if state.get("again") and state["phase"] == "dictation" and u32.OpenClipboard(hwnd):
            promise(); u32.CloseClipboard(); state["again"] = False
            log.append({"ms": ms(), "phase": "re-offered", "format": 0, "opener_pid": None})
        if time.perf_counter() >= end:
            return
        time.sleep(0.002)

def offer():
    for _ in range(25):
        if u32.OpenClipboard(hwnd):
            promise(); u32.CloseClipboard()
            return True
        time.sleep(0.02)
    return False

def key(vk, up, ext=False):
    i = INPUT(type=1)
    i.ki = KEYBDINPUT(wVk=vk, dwFlags=(2 if up else 0) | (1 if ext else 0), dwExtraInfo=0x45535954)
    return i

result = {"sent": False}
if u32.GetForegroundWindow() != target:
    result["error"] = "target not in front; no keys sent"
elif not offer():
    result["error"] = "clipboard busy"
else:
    pump(pre)
    result["before"] = [dict(r, ms=r["ms"]) for r in log]
    state["phase"], state["t0"] = "dictation", time.perf_counter()
    keys = (INPUT * 4)(key(0x10, False), key(0x2D, False, True), key(0x2D, True, True), key(0x10, True))
    result["sent"] = u32.SendInput(4, keys, ctypes.sizeof(INPUT)) == 4
    t = time.perf_counter()
    while not any(r["phase"] == "dictation" for r in log) and time.perf_counter() - t < 3:
        pump(5)
    if any(r["phase"] == "dictation" for r in log):
        if hold < 0:
            # Wait for the target to process a no-op message (it has finished handling the key), then -hold ms more.
            # Sent messages to this thread (render requests) are still handled while waiting.
            res = ctypes.c_size_t()
            u32.SendMessageTimeoutW(W.HWND(target), 0, 0, 0, 0x0002, 3000, ctypes.byref(res))  # WM_NULL, SMTO_ABORTIFHUNG
            result["idle_ms"] = ms()
            pump(-hold)
        else:
            pump(hold)
    result["restored_ms"] = ms()
    offer()  # the user's clipboard, as a promise, so later reads are seen
    state["phase"] = "restored"
    pump(watch)
    # Leave real data on the clipboard: the user's text.
    if u32.OpenClipboard(hwnd):
        u32.EmptyClipboard(); put_text(user_text); u32.CloseClipboard()
u32.DestroyWindow(hwnd)
result["requests"] = log
print(json.dumps(result))
