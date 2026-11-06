"""Bounded encoding for the small settings plists used by AirPort ACP."""
from __future__ import annotations


def encode(value: object) -> bytes:
    size = 0
    nodes = 0

    def pack(item: object, depth: int = 0) -> bytes:
        nonlocal size, nodes
        nodes += 1
        if depth > 16 or nodes > 8192:
            raise ValueError("The settings are too large.")
        if item is None:
            result = b"\0"
        elif type(item) is bool:
            result = b"\x09" if item else b"\x08"
        elif type(item) is int and 0 <= item < 2**64:
            length = next(n for n in (1, 2, 4, 8) if item < 2**(8*n))
            result = bytes([0x10 + (length.bit_length()-1)]) + item.to_bytes(length, "big")
        elif isinstance(item, str) and "\0" not in item:
            result = b"\x70" + item.encode("utf-8") + b"\0"
        elif isinstance(item, bytes):
            result = (bytes([0x40 + len(item)]) if len(item) < 15 else b"\x4f" + pack(len(item), depth+1)) + item
        elif isinstance(item, list):
            if any(child is None for child in item):
                raise ValueError("The settings contain an unsupported value.")
            result = b"\xa0" + b"".join(pack(child, depth+1) for child in item) + b"\0"
        elif isinstance(item, dict) and all(isinstance(key, str) for key in item):
            result = b"\xd0" + b"".join(pack(key, depth+1) + pack(child, depth+1) for key, child in item.items()) + b"\0"
        else:
            raise ValueError("The settings contain an unsupported value.")
        size += len(result)
        if size > 1_048_576:
            raise ValueError("The settings are too large.")
        return result

    return b"CFB0" + pack(value) + b"END!"
