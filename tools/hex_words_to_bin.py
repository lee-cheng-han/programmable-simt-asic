#!/usr/bin/env python3
import argparse
import pathlib
import struct


def convert(source: pathlib.Path, destination: pathlib.Path) -> int:
    words = []
    for line_number, raw in enumerate(source.read_text().splitlines(), 1):
        text = raw.split("#", 1)[0].strip()
        if not text:
            continue
        try:
            value = int(text, 16)
        except ValueError as error:
            raise ValueError(f"{source}:{line_number}: invalid hexadecimal word") from error
        if value < 0 or value > 0xFFFFFFFF:
            raise ValueError(f"{source}:{line_number}: word does not fit in 32 bits")
        words.append(value)
    if not words:
        raise ValueError(f"{source}: no words found")
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_bytes(struct.pack(f"<{len(words)}I", *words))
    return len(words)


def main() -> None:
    parser = argparse.ArgumentParser(description="Convert one hexadecimal word per line to a little-endian binary")
    parser.add_argument("source", type=pathlib.Path)
    parser.add_argument("destination", type=pathlib.Path)
    args = parser.parse_args()
    count = convert(args.source, args.destination)
    print(f"wrote {count} words to {args.destination}")


if __name__ == "__main__":
    main()
