"""A stand-in for a background program that reads the clipboard soon after every change without identifying itself
(no window) and ignores the "do not monitor" markers. Test use only; reads, never writes.

  python clipboard-reactor.py <delay ms> <seconds> <log file>
"""
import ctypes, sys, time
from ctypes import wintypes as W

u32, k32 = ctypes.WinDLL("user32"), ctypes.WinDLL("kernel32")
LRESULT = ctypes.c_ssize_t
WNDPROC = ctypes.WINFUNCTYPE(LRESULT, W.HWND, W.UINT, W.WPARAM, W.LPARAM)
u32.DefWindowProcW.restype = LRESULT
u32.DefWindowProcW.argtypes = [W.HWND, W.UINT, W.WPARAM, W.LPARAM]
u32.CreateWindowExW.restype = W.HWND
u32.CreateWindowExW.argtypes = [W.DWORD, W.LPCWSTR, W.LPCWSTR, W.DWORD, ctypes.c_int, ctypes.c_int, ctypes.c_int, ctypes.c_int, W.HWND, W.HMENU, W.HINSTANCE, W.LPVOID]
u32.GetClipboardData.restype = W.HANDLE
k32.GlobalLock.restype = W.LPVOID
k32.GlobalLock.argtypes = [W.HANDLE]
k32.GlobalUnlock.argtypes = [W.HANDLE]

class WNDCLASSW(ctypes.Structure):
    _fields_ = [("style", W.UINT), ("lpfnWndProc", WNDPROC), ("cbClsExtra", ctypes.c_int), ("cbWndExtra", ctypes.c_int), ("hInstance", W.HINSTANCE),
                ("hIcon", W.HICON), ("hCursor", W.HANDLE), ("hbrBackground", W.HBRUSH), ("lpszMenuName", W.LPCWSTR), ("lpszClassName", W.LPCWSTR)]

delay, secs, logf = int(sys.argv[1]) / 1000, float(sys.argv[2]), sys.argv[3]
due = []

def proc(h, msg, wp, lp):
    if msg == 0x031D:  # WM_CLIPBOARDUPDATE
        due.append(time.perf_counter() + delay)
        return 0
    return u32.DefWindowProcW(h, msg, wp, lp)

wndproc = WNDPROC(proc)
cls = WNDCLASSW(lpfnWndProc=wndproc, hInstance=k32.GetModuleHandleW(None), lpszClassName="EsyTypeTestReactor")
u32.RegisterClassW(ctypes.byref(cls))
hwnd = u32.CreateWindowExW(0, "EsyTypeTestReactor", "", 0, 0, 0, 0, 0, W.HWND(-3), None, cls.hInstance, None)
u32.AddClipboardFormatListener(hwnd)
end, msg = time.perf_counter() + secs, W.MSG()
with open(logf, "a", encoding="utf-8") as log:
    while time.perf_counter() < end:
        while u32.PeekMessageW(ctypes.byref(msg), hwnd, 0, 0, 1):
            u32.TranslateMessage(ctypes.byref(msg)); u32.DispatchMessageW(ctypes.byref(msg))
        if due and time.perf_counter() >= due[0]:
            due.pop(0)
            if u32.OpenClipboard(None):  # no window: cannot be identified
                h = u32.GetClipboardData(13)
                text = ""
                if h:
                    p = k32.GlobalLock(h)
                    text = ctypes.wstring_at(p)[:40] if p else ""
                    k32.GlobalUnlock(h)
                u32.CloseClipboard()
                log.write(f"{time.strftime('%H:%M:%S')} read {text!r}\n"); log.flush()
        time.sleep(0.002)
u32.RemoveClipboardFormatListener(hwnd)
