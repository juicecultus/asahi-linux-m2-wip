#!/usr/bin/env python3
"""
Boot macOS under m1n1 hypervisor using chunked kernel transfer.
Monkey-patches ProxyUtils.compressed_writemem to send in small chunks.
"""
import sys, pathlib, time, gzip, traceback
sys.path.append(str(pathlib.Path(__file__).resolve().parents[0] / ".." / "repos" / "m1n1" / "proxyclient"))

import argparse

parser = argparse.ArgumentParser(description='Boot macOS under HV with chunked transfer')
parser.add_argument('-s', '--symbols', type=pathlib.Path)
parser.add_argument('-m', '--script', type=pathlib.Path, action='append', default=[])
parser.add_argument('-c', '--command', action="append", default=[])
parser.add_argument('-S', '--shell', action="store_true")
parser.add_argument('-l', '--logfile', type=pathlib.Path)
parser.add_argument('-C', '--cpus', default=None)
parser.add_argument('payload', type=pathlib.Path)
parser.add_argument('boot_args', default=[], nargs="*")
args = parser.parse_args()

from m1n1.proxy import *
from m1n1.proxyutils import *
from m1n1.utils import *
from m1n1.shell import run_shell
from m1n1.hv import HV
from m1n1.hw.pmu import PMU

CHUNK_SIZE = 2 * 1024 * 1024  # 2MB per writemem call
DELAY = 0.5                   # seconds between chunks

# Monkey-patch compressed_writemem: use gzip level 9 to minimize total USB bytes
_orig_compressed_writemem = ProxyUtils.compressed_writemem

def chunked_compressed_writemem(self, dest, data, progress=None):
    if not len(data):
        return
    payload = gzip.compress(data, compresslevel=9)
    compressed_size = len(payload)
    print(f"Compressed {len(data)/1024/1024:.1f} MB -> {compressed_size/1024/1024:.1f} MB (level 9)")

    with self.heap.guarded_malloc(compressed_size) as compressed_addr:
        total = len(payload)
        sent = 0
        chunk_num = 0
        num_chunks = (total + CHUNK_SIZE - 1) // CHUNK_SIZE
        while sent < total:
            end = min(sent + CHUNK_SIZE, total)
            chunk = payload[sent:end]
            chunk_num += 1
            print(f"  Chunk {chunk_num}/{num_chunks}: {len(chunk)} bytes ...", end="", flush=True)
            self.iface.writemem(compressed_addr + sent, chunk, progress=False)
            print(" OK")
            sent = end
            if sent < total:
                time.sleep(DELAY)
        print(f"Transfer done: {chunk_num} chunks, {total/1024/1024:.1f} MB total")

        timeout = self.iface.dev.timeout
        self.iface.dev.timeout = None
        try:
            decompressed_size = self.proxy.gzdec(compressed_addr, compressed_size, dest, len(data))
        finally:
            self.iface.dev.timeout = timeout
        assert decompressed_size == len(data)

ProxyUtils.compressed_writemem = chunked_compressed_writemem

# Standard HV boot flow (same as run_guest.py)
iface = UartInterface()
p = M1N1Proxy(iface, debug=False)
bootstrap_port(iface, p)
u = ProxyUtils(p, heap_size=128 * 1024 * 1024)

hv = HV(iface, p, u)
hv.init()

if args.cpus:
    avail = [i.name for i in hv.adt["/cpus"]]
    want = set(f"cpu{i}" for i in args.cpus)
    for cpu in avail:
        if cpu in want:
            continue
        try:
            del hv.adt[f"/cpus/{cpu}"]
            print(f"Disabled {cpu}")
        except KeyError:
            continue

if args.logfile:
    hv.set_logfile(args.logfile.open("w"))

if len(args.boot_args) > 0:
    boot_args = " ".join(args.boot_args)
    hv.set_bootargs(boot_args)

symfile = None
if args.symbols:
    symfile = args.symbols.open("rb")

payload = args.payload.open("rb")
hv.load_macho(payload, symfile=symfile)

PMU(u).reset_panic_counter()

for i in args.script:
    try:
        hv.run_script(i)
    except:
        traceback.print_exc()
        args.shell = True

for i in args.command:
    try:
        hv.run_code(i)
    except:
        traceback.print_exc()
        args.shell = True

if args.shell:
    run_shell(hv.shell_locals, "Entering hypervisor shell. Type ^D to start the guest.")

hv.start()

run_shell(hv.shell_locals, "Hypervisor exited. Entering shell.")

p.smp_stop_secondaries(True)
p.sleep(True)
