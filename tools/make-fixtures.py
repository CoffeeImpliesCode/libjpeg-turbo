#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# See ../FORK-LICENSE.md for what that identifier covers.

"""Independent encoder for this SDK's JPEG test fixtures.

This program does not use libjpeg, libjpeg-turbo, Pillow, ImageMagick or any
other image library. It writes a baseline sequential DCT-coded stream from
ITU-T T.81: a JFIF `APP0`, a `DQT` pair, a baseline `SOF0`, the four `DHT`
tables of T.81 Annex K, a `SOS`, entropy-coded data and `EOI`.

Two properties of the chosen fixtures make the expected decoded pixels a
hand-computable answer rather than something read back out of a decoder:

  * Both quantisation tables are all ones, so a coefficient is quantised to its
    own nearest integer and the round trip through the quantiser is exact.
  * Every block in every fixture is flat, so its forward DCT has a single
    non-zero coefficient, `F(0,0) = 8 * (sample - 128)` for a flat block of
    eight by eight samples (T.81 equation A.2 with `C(0) = 1/sqrt(2)` gives
    `(1/4) * (1/2) * 64 * d = 8d`). The inverse DCT of a DC-only block is that
    same value divided by eight, so the level shift back returns the original
    sample exactly.

The colour fixture is flat in the other sense too: for `R = G = B = v` the
JFIF forward transform gives `Y = v` and `Cb = Cr = 128` exactly, because the
three fixed-point luma constants sum to exactly 2^16, and the inverse transform
of `Cb = Cr = 128` is the identity. So an all-grey RGB fixture decodes to
exactly `(v, v, v)`.

Re-running this program must reproduce the same bytes. The comparison against
the recorded SHA-256 digests is a provenance check rather than a behavioural
gate.

Usage:
    python3 tools/make-fixtures.py <output-directory>
"""

import math
import os
import struct
import sys

# T.81 Annex K standard Huffman tables.

DC_LUMA_BITS = (0, 1, 5, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0)
DC_LUMA_VALS = tuple(range(12))

DC_CHROMA_BITS = (0, 3, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0)
DC_CHROMA_VALS = tuple(range(12))

AC_LUMA_BITS = (0, 2, 1, 3, 3, 2, 4, 3, 5, 5, 4, 4, 0, 0, 1, 0x7D)
AC_LUMA_VALS = (
    0x01, 0x02, 0x03, 0x00, 0x04, 0x11, 0x05, 0x12,
    0x21, 0x31, 0x41, 0x06, 0x13, 0x51, 0x61, 0x07,
    0x22, 0x71, 0x14, 0x32, 0x81, 0x91, 0xA1, 0x08,
    0x23, 0x42, 0xB1, 0xC1, 0x15, 0x52, 0xD1, 0xF0,
    0x24, 0x33, 0x62, 0x72, 0x82, 0x09, 0x0A, 0x16,
    0x17, 0x18, 0x19, 0x1A, 0x25, 0x26, 0x27, 0x28,
    0x29, 0x2A, 0x34, 0x35, 0x36, 0x37, 0x38, 0x39,
    0x3A, 0x43, 0x44, 0x45, 0x46, 0x47, 0x48, 0x49,
    0x4A, 0x53, 0x54, 0x55, 0x56, 0x57, 0x58, 0x59,
    0x5A, 0x63, 0x64, 0x65, 0x66, 0x67, 0x68, 0x69,
    0x6A, 0x73, 0x74, 0x75, 0x76, 0x77, 0x78, 0x79,
    0x7A, 0x83, 0x84, 0x85, 0x86, 0x87, 0x88, 0x89,
    0x8A, 0x92, 0x93, 0x94, 0x95, 0x96, 0x97, 0x98,
    0x99, 0x9A, 0xA2, 0xA3, 0xA4, 0xA5, 0xA6, 0xA7,
    0xA8, 0xA9, 0xAA, 0xB2, 0xB3, 0xB4, 0xB5, 0xB6,
    0xB7, 0xB8, 0xB9, 0xBA, 0xC2, 0xC3, 0xC4, 0xC5,
    0xC6, 0xC7, 0xC8, 0xC9, 0xCA, 0xD2, 0xD3, 0xD4,
    0xD5, 0xD6, 0xD7, 0xD8, 0xD9, 0xDA, 0xE1, 0xE2,
    0xE3, 0xE4, 0xE5, 0xE6, 0xE7, 0xE8, 0xE9, 0xEA,
    0xF1, 0xF2, 0xF3, 0xF4, 0xF5, 0xF6, 0xF7, 0xF8,
    0xF9, 0xFA,
)

AC_CHROMA_BITS = (0, 2, 1, 2, 4, 4, 3, 4, 7, 5, 4, 4, 0, 1, 2, 0x77)
AC_CHROMA_VALS = (
    0x00, 0x01, 0x02, 0x03, 0x11, 0x04, 0x05, 0x21,
    0x31, 0x06, 0x12, 0x41, 0x51, 0x07, 0x61, 0x71,
    0x13, 0x22, 0x32, 0x81, 0x08, 0x14, 0x42, 0x91,
    0xA1, 0xB1, 0xC1, 0x09, 0x23, 0x33, 0x52, 0xF0,
    0x15, 0x62, 0x72, 0xD1, 0x0A, 0x16, 0x24, 0x34,
    0xE1, 0x25, 0xF1, 0x17, 0x18, 0x19, 0x1A, 0x26,
    0x27, 0x28, 0x29, 0x2A, 0x35, 0x36, 0x37, 0x38,
    0x39, 0x3A, 0x43, 0x44, 0x45, 0x46, 0x47, 0x48,
    0x49, 0x4A, 0x53, 0x54, 0x55, 0x56, 0x57, 0x58,
    0x59, 0x5A, 0x63, 0x64, 0x65, 0x66, 0x67, 0x68,
    0x69, 0x6A, 0x73, 0x74, 0x75, 0x76, 0x77, 0x78,
    0x79, 0x7A, 0x82, 0x83, 0x84, 0x85, 0x86, 0x87,
    0x88, 0x89, 0x8A, 0x92, 0x93, 0x94, 0x95, 0x96,
    0x97, 0x98, 0x99, 0x9A, 0xA2, 0xA3, 0xA4, 0xA5,
    0xA6, 0xA7, 0xA8, 0xA9, 0xAA, 0xB2, 0xB3, 0xB4,
    0xB5, 0xB6, 0xB7, 0xB8, 0xB9, 0xBA, 0xC2, 0xC3,
    0xC4, 0xC5, 0xC6, 0xC7, 0xC8, 0xC9, 0xCA, 0xD2,
    0xD3, 0xD4, 0xD5, 0xD6, 0xD7, 0xD8, 0xD9, 0xDA,
    0xE2, 0xE3, 0xE4, 0xE5, 0xE6, 0xE7, 0xE8, 0xE9,
    0xEA, 0xF2, 0xF3, 0xF4, 0xF5, 0xF6, 0xF7, 0xF8,
    0xF9, 0xFA,
)

# T.81 figure B.1, the zig-zag order of coefficients within a block.
ZIGZAG = (
     0,  1,  8, 16,  9,  2,  3, 10,
    17, 24, 32, 25, 18, 11,  4,  5,
    12, 19, 26, 33, 40, 48, 41, 34,
    27, 20, 13,  6,  7, 14, 21, 28,
    35, 42, 49, 56, 57, 50, 43, 36,
    29, 22, 15, 23, 30, 37, 44, 51,
    58, 59, 52, 45, 38, 31, 39, 46,
    53, 60, 61, 54, 47, 55, 62, 63,
)


def build_code_table(bits, values):
    """The canonical Huffman assignment of T.81 Annex C.

    Codes are assigned in order of increasing length; the value list is sorted
    within each length, which is what makes this canonical.
    """
    table = {}
    code = 0
    index = 0
    for length in range(1, 17):
        for _ in range(bits[length - 1]):
            table[values[index]] = (code, length)
            index += 1
            code += 1
        code <<= 1
    return table


DC_LUMA = build_code_table(DC_LUMA_BITS, DC_LUMA_VALS)
DC_CHROMA = build_code_table(DC_CHROMA_BITS, DC_CHROMA_VALS)
AC_LUMA = build_code_table(AC_LUMA_BITS, AC_LUMA_VALS)
AC_CHROMA = build_code_table(AC_CHROMA_BITS, AC_CHROMA_VALS)


class BitWriter:
    """Entropy-coded segment with T.81's `0xFF 0x00` byte stuffing.

    T.81 section B.1.1.5: a byte value of `0xFF` in the entropy-coded data is
    followed by `0x00`, so that a `0xFF` followed by a marker byte can never be
    mistaken for one.
    """

    def __init__(self):
        self.out = bytearray()
        self.buffer = 0
        self.count = 0

    def write(self, code, length):
        for shift in range(length - 1, -1, -1):
            self.buffer = (self.buffer << 1) | ((code >> shift) & 1)
            self.count += 1
            if self.count == 8:
                byte = self.buffer & 0xFF
                self.out.append(byte)
                if byte == 0xFF:
                    self.out.append(0x00)
                self.buffer = 0
                self.count = 0

    def flush(self):
        """Pad the final byte with 1 bits, as T.81 section B.1.2.3 requires."""
        while self.count != 0:
            self.write(1, 1)
        return bytes(self.out)


def category(value):
    """The number of bits needed to carry `value`, i.e. T.81's SSSS."""
    magnitude = abs(value)
    size = 0
    while magnitude:
        size += 1
        magnitude >>= 1
    return size


def fdct(block):
    """The separable float forward DCT of T.81 equation A.2."""
    out = [0.0] * 64
    for u in range(8):
        cu = (1.0 / math.sqrt(2.0)) if u == 0 else 1.0
        for v in range(8):
            cv = (1.0 / math.sqrt(2.0)) if v == 0 else 1.0
            total = 0.0
            for y in range(8):
                for x in range(8):
                    total += (
                        block[y * 8 + x]
                        * math.cos((2 * x + 1) * u * math.pi / 16.0)
                        * math.cos((2 * y + 1) * v * math.pi / 16.0)
                    )
            out[v * 8 + u] = 0.25 * cu * cv * total
    return out


def quantise(coefficients):
    """Round each coefficient to the nearest integer; the tables are all ones."""
    return [
        int(math.floor(value + 0.5)) if value >= 0 else -int(math.floor(-value + 0.5))
        for value in coefficients
    ]


def encode_block(writer, samples, previous_dc, dc_table, ac_table):
    """One 8x8 block: level shift, DCT, quantise, zig-zag, DC diff, AC run-length."""
    shifted = [sample - 128 for sample in samples]
    coefficients = quantise(fdct(shifted))
    zigzag = [coefficients[ZIGZAG[k]] for k in range(64)]

    diff = zigzag[0] - previous_dc
    size = category(diff)
    writer.write(*dc_table[size])
    if size:
        # T.81 section F.1.2.1: the value is the one's complement of the
        # negative representation, so the bit pattern of a negative value is
        # the same as the positive one of the same magnitude.
        writer.write(diff if diff > 0 else diff + (1 << size) - 1, size)

    run = 0
    for k in range(1, 64):
        value = zigzag[k]
        if value == 0:
            run += 1
            continue
        while run > 15:
            writer.write(*ac_table[0xF0])  # ZRL: a run of sixteen zeroes.
            run -= 16
        size = category(value)
        writer.write(*ac_table[(run << 4) | size])
        writer.write(value if value > 0 else value + (1 << size) - 1, size)
        run = 0
    if run:
        writer.write(*ac_table[0x00])  # EOB.
    return zigzag[0]


def marker(kind, payload):
    return bytes([0xFF, kind]) + struct.pack(">H", len(payload) + 2) + payload


def build_dqt(table_id):
    """A `DQT` segment whose sixteen entries are all one, in zig-zag order."""
    return marker(0xDB, bytes([table_id]) + bytes([1] * 64))


def build_dht(class_and_id, bits, values):
    payload = bytes([class_and_id]) + bytes(bits) + bytes(values)
    return marker(0xC4, payload)


def build_sof0(width, height, components):
    payload = bytes([8]) + struct.pack(">HH", height, width) + bytes([len(components)])
    for identifier, table in components:
        payload += bytes([identifier, 0x11, table])  # 0x11: 1x1 sampling.
    return marker(0xC0, payload)


def build_sos(components):
    payload = bytes([len(components)])
    for identifier, dc_ac in components:
        payload += bytes([identifier, dc_ac])
    payload += bytes([0, 63, 0])
    return marker(0xDA, payload)


def build_app0():
    payload = b"JFIF\x00" + bytes([1, 1, 0]) + struct.pack(">HH", 1, 1) + bytes([0, 0])
    return marker(0xE0, payload)


def encode(width, height, planes, components):
    """A complete baseline JPEG file.

    `planes` is a list of one flat row-major byte string per component; every
    component has the same dimensions, so sampling is 1x1 throughout.
    """
    blocks_wide = (width + 7) // 8
    blocks_high = (height + 7) // 8

    writer = BitWriter()
    previous = [0] * len(planes)
    for block_y in range(blocks_high):
        for block_x in range(blocks_wide):
            for index, plane in enumerate(planes):
                samples = []
                for row in range(8):
                    for column in range(8):
                        x = min(block_x * 8 + column, width - 1)
                        y = min(block_y * 8 + row, height - 1)
                        samples.append(plane[y * width + x])
                dc_table = DC_LUMA if index == 0 else DC_CHROMA
                ac_table = AC_LUMA if index == 0 else AC_CHROMA
                previous[index] = encode_block(writer, samples, previous[index], dc_table, ac_table)

    out = bytearray()
    out += bytes([0xFF, 0xD8])  # SOI
    out += build_app0()
    for table_id in sorted({table for _, table in components}):
        out += build_dqt(table_id)
    out += build_sof0(width, height, components)
    out += build_dht(0x00, DC_LUMA_BITS, DC_LUMA_VALS)
    out += build_dht(0x10, AC_LUMA_BITS, AC_LUMA_VALS)
    out += build_dht(0x01, DC_CHROMA_BITS, DC_CHROMA_VALS)
    out += build_dht(0x11, AC_CHROMA_BITS, AC_CHROMA_VALS)
    out += build_sos(components)
    out += writer.flush()
    out += bytes([0xFF, 0xD9])  # EOI
    return bytes(out)


def flat_plane(width, height, value):
    return bytes([value]) * (width * height)


def rgb_to_ycbcr_planes(width, height, pixels):
    """JFIF full-range YCbCr with the fixed-point constants of T.81 table 12.

    `FIX(x) = round(x * 2^16)`, and the three luma constants sum to exactly
    2^16, so a grey pixel `R = G = B = v` yields exactly `Y = v` and
    `Cb = Cr = 128`. Only grey pixels are used by the fixture table, and the
    assertion that follows from this is stated there.
    """
    luma_r, luma_g, luma_b = 19595, 38470, 7471
    cb_r, cb_g, cb_b = -11059, -21710, 32768
    cr_r, cr_g, cr_b = 32768, -27440, -5328
    y_plane = bytearray()
    cb_plane = bytearray()
    cr_plane = bytearray()
    for index in range(width * height):
        r, g, b = pixels[index]
        y = (luma_r * r + luma_g * g + luma_b * b + 32768) >> 16
        cb = (cb_r * r + cb_g * g + cb_b * b + (128 << 16) + 32768) >> 16
        cr = (cr_r * r + cr_g * g + cr_b * b + (128 << 16) + 32768) >> 16
        y_plane.append(y)
        cb_plane.append(cb)
        cr_plane.append(cr)
    return bytes(y_plane), bytes(cb_plane), bytes(cr_plane)


FIXTURES = [
    {
        "name": "grey8x8-200.jpg",
        "width": 8,
        "height": 8,
        "components": [(1, 0)],
        "planes": [flat_plane(8, 8, 200)],
    },
    {
        "name": "grey16x16-halves.jpg",
        "width": 16,
        "height": 16,
        "components": [(1, 0)],
        # Rows 0..7 are 0 and rows 8..15 are 255. The decoded image is exactly
        # that: the two blocks differ only in their DC coefficients.
        "planes": [flat_plane(16, 8, 0) + flat_plane(16, 8, 255)],
    },
    {
        "name": "rgb8x8-grey64.jpg",
        "width": 8,
        "height": 8,
        "components": [(1, 0), (2, 1), (3, 1)],
        "pixels": [(64, 64, 64)] * 64,
    },
    {
        "name": "rgb8x8-grey200.jpg",
        "width": 8,
        "height": 8,
        "components": [(1, 0), (2, 1), (3, 1)],
        "pixels": [(200, 200, 200)] * 64,
    },
]


def main():
    if len(sys.argv) != 2:
        sys.stderr.write("usage: make-fixtures.py <output-directory>\n")
        return 2
    out_dir = sys.argv[1]
    os.makedirs(out_dir, exist_ok=True)
    for fixture in FIXTURES:
        if "pixels" in fixture:
            planes = list(
                rgb_to_ycbcr_planes(fixture["width"], fixture["height"], fixture["pixels"])
            )
        else:
            planes = fixture["planes"]
        data = encode(fixture["width"], fixture["height"], planes, fixture["components"])
        path = os.path.join(out_dir, fixture["name"])
        with open(path, "wb") as handle:
            handle.write(data)
        print("%-24s %6d bytes" % (fixture["name"], len(data)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
