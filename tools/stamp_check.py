#!/usr/bin/env python3
"""Does this .exe carry its own icon and version block?

WHY THIS EXISTS RATHER THAN A GREP OF THE EXPORT LOG. `export.sh` used to
decide the question by grepping Godot's output for the word "rcedit", and
Godot prints `rcedit (<path>):` as a HEADING over that stage whether or not
anything went wrong — so once rcedit was actually wired up and working, the
build still reported "no rcedit, so the exe carries no icon or version block"
about an exe that had both. A harness that reads a log is asking the builder
how it went; this one opens the artefact a player downloads and looks.

Walks the PE resource directory by hand (no pefile in this container) and
reports the three things a Windows Explorer Details tab shows and nobody in
this repo has a Windows machine to check:

  RT_GROUP_ICON / RT_ICON (types 14 / 3) — the taskbar and library icon
  RT_VERSION      (type 16)              — product name, company, version

Exits non-zero when any of them is missing, so it can be the release gate.
"""
import struct
import sys


def _sections(d):
    pe = struct.unpack_from("<I", d, 0x3C)[0]
    if d[pe:pe + 4] != b"PE\0\0":
        raise ValueError("not a PE file")
    nsec = struct.unpack_from("<H", d, pe + 6)[0]
    opt = struct.unpack_from("<H", d, pe + 20)[0]
    magic = struct.unpack_from("<H", d, pe + 24)[0]
    dd = pe + 24 + (108 if magic == 0x20B else 92) + 4
    rsrc_rva = struct.unpack_from("<I", d, dd + 2 * 8)[0]
    base = secs = pe + 24 + opt
    for i in range(nsec):
        o = secs + i * 40
        va, _raw_sz, raw_ptr = struct.unpack_from("<III", d, o + 12)
        if va == rsrc_rva:
            return raw_ptr, va
    raise ValueError("no .rsrc section")


def resource_types(path):
    """{type_id: total bytes} for every top-level resource type in the file."""
    d = open(path, "rb").read()
    base, vbase = _sections(d)

    def entries(off):
        n1, n2 = struct.unpack_from("<HH", d, base + off + 12)
        return [struct.unpack_from("<II", d, base + off + 16 + i * 8)
                for i in range(n1 + n2)]

    out = {}
    for nid, ofs in entries(0):
        total = 0
        for _n2, o2 in entries(ofs & 0x7FFFFFFF):
            for _n3, o3 in entries(o2 & 0x7FFFFFFF):
                _rva, sz = struct.unpack_from("<II", d, base + (o3 & 0x7FFFFFFF))
                total += sz
        out[nid & 0x7FFFFFFF] = total
    return out, d


def main(argv):
    if len(argv) < 2:
        print("usage: stamp_check.py <exe> [expected strings...]")
        return 2
    path = argv[1]
    try:
        types, data = resource_types(path)
    except Exception as exc:                                  # noqa: BLE001
        print("  cannot read %s as a PE file: %s" % (path, exc))
        return 1

    bad = 0
    # RT_ICON is 3, RT_GROUP_ICON is 14, RT_VERSION is 16.
    if types.get(14, 0) == 0 or types.get(3, 0) == 0:
        print("  no icon in the exe — it wears the Godot template's")
        bad = 1
    if types.get(16, 0) == 0:
        print("  no version block — the Details tab is blank")
        bad = 1
    # The version block stores its strings as UTF-16, which is why a plain
    # `strings` over the file finds the product name once (in the pck) and
    # misses the resource entirely.
    for want in argv[2:]:
        if data.count(want.encode("utf-16-le")) == 0:
            print("  version block does not say %r" % want)
            bad = 1
    if not bad:
        print("  stamped: icon %d bytes, version block %d bytes, %s"
              % (types.get(3, 0) + types.get(14, 0), types.get(16, 0),
                 ", ".join(repr(a) for a in argv[2:]) or "no strings checked"))
    return bad


if __name__ == "__main__":
    sys.exit(main(sys.argv))
