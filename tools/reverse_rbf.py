#!/usr/bin/env python3
"""Convert a Quartus .rbf into an Analogue Pocket .rev bitstream.

The Pocket loads bitstreams with the bit order of every byte reversed
(MSB<->LSB). This matches helpers/package.py:reverse_bitstream() from
agg23/pocketpublish. Usage: reverse_rbf.py <input.rbf> <output.rev>
"""
import sys


def reverse_bits(data: bytearray) -> bytearray:
    for i in range(len(data)):
        b = data[i]
        data[i] = (
            ((b & 0x01) << 7)
            | ((b & 0x02) << 5)
            | ((b & 0x04) << 3)
            | ((b & 0x08) << 1)
            | ((b & 0x10) >> 1)
            | ((b & 0x20) >> 3)
            | ((b & 0x40) >> 5)
            | ((b & 0x80) >> 7)
        )
    return data


def main() -> None:
    if len(sys.argv) != 3:
        sys.exit("Usage: reverse_rbf.py <input.rbf> <output.rev>")
    with open(sys.argv[1], "rb") as f:
        data = bytearray(f.read())
    reverse_bits(data)
    with open(sys.argv[2], "wb") as f:
        f.write(data)
    print(f"Wrote {sys.argv[2]} ({len(data)} bytes)")


if __name__ == "__main__":
    main()
