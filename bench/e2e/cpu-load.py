"""Keeps <n> processes busy for <seconds>, to imitate a slow, loaded PC in tests. Test use only.

  python cpu-load.py <n> <seconds>
"""
import multiprocessing, sys, time


def spin(until):
    while time.time() < until:
        pass


if __name__ == "__main__":
    n, secs = int(sys.argv[1]), float(sys.argv[2])
    until = time.time() + secs
    ps = [multiprocessing.Process(target=spin, args=(until,)) for _ in range(n)]
    for p in ps:
        p.start()
    for p in ps:
        p.join()
