import math, struct, zlib, sys
N, SS = 64, 4                      # output size, supersampling
tga_out, png_out = sys.argv[1], sys.argv[2]
c = N / 2
R_OUT, R_IN, EDGE = 29.5, 20.0, 1.6
GAP = math.radians(5)              # gap between segments
# clockwise from the top: orange, yellow, green, gray, red
SEGS = [(255,128,64), (255,230,0), (64,191,64), (128,128,128), (255,40,40)]
LEAF, LEAF_DARK = (80,200,90), (20,70,30)

# Sprig: a curved stem from bottom-left to top-right with alternating leaves.
P0, P1, P2 = (c - 17, c + 20), (c - 6, c + 1), (c + 10, c - 13)   # base sits under the ring   # quadratic bezier
def bez(t):
    return ((1-t)**2*P0[0] + 2*(1-t)*t*P1[0] + t*t*P2[0], (1-t)**2*P0[1] + 2*(1-t)*t*P1[1] + t*t*P2[1])
def tangent(t):
    dx = 2*(1-t)*(P1[0]-P0[0]) + 2*t*(P2[0]-P1[0]); dy = 2*(1-t)*(P1[1]-P0[1]) + 2*t*(P2[1]-P1[1])
    l = math.hypot(dx, dy); return dx/l, dy/l
STEM = [bez(i / 60) for i in range(61)]
LEAVES = []   # (base x, base y, dir x, dir y, length, width)
for t, side, L in [(0.36, 1, 11.0), (0.50, -1, 10.5), (0.66, 1, 9.0), (0.80, -1, 7.5)]:
    bx, by = bez(t); tx, ty = tangent(t)
    a = math.radians(42) * side
    dx, dy = tx*math.cos(a) - ty*math.sin(a), tx*math.sin(a) + ty*math.cos(a)
    LEAVES.append((bx, by, dx, dy, L, L * 0.30))
tx, ty = tangent(1.0)
LEAVES.append((P2[0] - tx, P2[1] - ty, tx, ty, 8.0, 2.6))  # leaf at the tip
LEAF_LIGHT = (130, 220, 110)

def leaf(x, y):
    best = None
    for bx, by, dx, dy, L, W in LEAVES:
        u = (x - bx) * dx + (y - by) * dy          # along the leaf
        v = -(x - bx) * dy + (y - by) * dx         # across
        if 0 <= u <= L:
            k = u / L
            half = W * math.sin(math.pi * k) ** 0.8  # pointed at both ends
            if abs(v) <= half:
                if half - abs(v) < 0.7:
                    return LEAF_DARK                 # outline wins over everything
                best = LEAF_LIGHT if (v < 0 and abs(v) > 0.5) else LEAF
    if best:
        return best
    d = min(math.hypot(x - sx, y - sy) for sx, sy in STEM)
    if d < 1.5:
        return (125, 82, 45) if d < 0.9 else (55, 32, 15)  # brown stem
    return None

def sample(x, y):
    d = math.hypot(x - c, y - c)
    if R_IN - EDGE <= d <= R_OUT + EDGE:
        ang = (math.atan2(x - c, -(y - c)) + 2 * math.pi) % (2 * math.pi)  # 0 = top, clockwise
        seg = int(ang / (2 * math.pi / len(SEGS)))
        local = ang - seg * 2 * math.pi / len(SEGS)
        span = 2 * math.pi / len(SEGS)
        inside_band = R_IN <= d <= R_OUT
        gap_px = min(local, span - local) * d
        if inside_band and gap_px > GAP * d / 2 + EDGE:
            return SEGS[seg] + (255,)
        if gap_px > GAP * d / 2:
            return (15, 15, 15, 255)          # dark outline
        # in the gap between segments: the branch shows through
    p = leaf(x, y)
    return p + (255,) if p else None

def render(M, ss, pad=0.0):
    """Render at M x M pixels (the design is drawn on a 64 px grid); pad = margin as a fraction."""
    k = N / M * (1 + 2 * pad)
    off = -N * pad
    out = []
    for y in range(M):
        row = []
        for x in range(M):
            acc = [0, 0, 0, 0]
            for sy in range(ss):
                for sx in range(ss):
                    p = sample((x + (sx + .5) / ss) * k + off, (y + (sy + .5) / ss) * k + off)
                    if p:
                        for i in range(3): acc[i] += p[i] * p[3] / 255
                        acc[3] += p[3]
            a = acc[3] / (ss * ss)
            rgb = [int(round(acc[i] / (acc[3] / 255))) if acc[3] else 0 for i in range(3)]
            row.append((*rgb, int(round(a))))
        out.append(row)
    return out

def chunk(t, d): return struct.pack('>I', len(d)) + t + d + struct.pack('>I', zlib.crc32(t + d) & 0xffffffff)
def write_png_rgba(path, px):
    M = len(px)
    raw = b''.join(b'\x00' + b''.join(bytes(p) for p in row) for row in px)
    open(path, 'wb').write(b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', M, M, 8, 6, 0, 0, 0))
                           + chunk(b'IDAT', zlib.compress(raw, 9)) + chunk(b'IEND', b''))

# usage: mkicon.py Icon.tga preview.png [logo.png [size]]
if len(sys.argv) > 3:
    size = int(sys.argv[4]) if len(sys.argv) > 4 else 400
    write_png_rgba(sys.argv[3], render(size, 3, pad=0.06))

pix = render(N, SS)

# TGA (BGRA, top-left origin)
with open(tga_out, 'wb') as f:
    f.write(struct.pack('<BBBHHBHHHHBB', 0, 0, 2, 0, 0, 0, 0, 0, N, N, 32, 8 | 0x20))
    for row in pix:
        for r, g, b, a in row: f.write(bytes((b, g, r, a)))

# PNG preview, scaled 4x on a dark background
S, BG = 4, (30, 30, 34)
raw = b''
for row in pix:
    line = b'\x00'
    for r, g, b, a in row:
        m = a / 255
        px = bytes(int(v * m + bg * (1 - m)) for v, bg in zip((r, g, b), BG))
        line += px * S
    raw += line * S
png = b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', N*S, N*S, 8, 2, 0, 0, 0)) + chunk(b'IDAT', zlib.compress(raw, 9)) + chunk(b'IEND', b'')
open(png_out, 'wb').write(png)
