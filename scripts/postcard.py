#!/usr/bin/env python3
"""Reserve and conservatively cancel local PNG output paths.

    postcard.py reserve --directory /absolute/Pictures/Terrarium
    postcard.py cancel --directory DIR --path PATH --token TOKEN

Every command response is one JSON line. Exit 0 means success (including an
already-removed reservation), 1 is an OS/safety refusal, and 2 is invalid input.
Tokens are bounded identity receipts, not secrets or a same-user security boundary.
No secret, receipt sidecar, or activity history is written to disk.
"""

from __future__ import annotations

import argparse
import base64
from contextlib import contextmanager
import json
import os
from pathlib import Path
import re
import secrets
import stat
import sys
import tempfile
import time

MAX_TOKEN = 8192
GENERATED_NAME = re.compile(r"terrarium-[0-9]{8}-[0-9]{6}-[0-9a-f]{16}-[a-z0-9_]{8}\.png\Z")
RECEIPT_FIELDS = {"v", "directory", "directory_device", "directory_inode", "name", "uid", "device", "inode", "ctime_ns"}


class PostcardError(Exception):
    def __init__(self, code: str, exit_code: int = 1):
        self.code = code
        self.exit_code = exit_code
        super().__init__(code)


class JsonParser(argparse.ArgumentParser):
    def error(self, message):
        raise PostcardError("invalid_arguments", 2)


def identity(info):
    return info.st_uid, info.st_dev, info.st_ino, info.st_ctime_ns


@contextmanager
def directory_handle(value: str, create: bool):
    if not isinstance(value, str) or not value or len(value) > 4096 or "\0" in value or not os.path.isabs(value):
        raise PostcardError("invalid_directory", 2)
    try:
        if create:
            os.makedirs(value, mode=0o755, exist_ok=True)
        canonical = str(Path(value).resolve(strict=True))
        descriptor = os.open(canonical, os.O_RDONLY | os.O_DIRECTORY | os.O_CLOEXEC | os.O_NOFOLLOW)
    except (OSError, ValueError, RuntimeError):
        raise PostcardError("cannot_create_directory" if create else "directory_unavailable") from None
    try:
        info = os.fstat(descriptor)
        if not stat.S_ISDIR(info.st_mode) or info.st_uid != os.getuid():
            raise PostcardError("unsafe_directory")
        yield canonical, descriptor, info
    finally:
        os.close(descriptor)


def encode_receipt(receipt: dict) -> str:
    raw = json.dumps(receipt, separators=(",", ":"), ensure_ascii=True).encode("ascii")
    token = base64.urlsafe_b64encode(raw).rstrip(b"=").decode("ascii")
    if len(token) > MAX_TOKEN:
        raise PostcardError("invalid_directory", 2)
    return token


def decode_receipt(token: str) -> dict:
    if not isinstance(token, str) or not token or len(token) > MAX_TOKEN or not re.fullmatch(r"[A-Za-z0-9_-]+", token):
        raise PostcardError("invalid_token", 2)
    try:
        raw = base64.b64decode(token + "=" * (-len(token) % 4), altchars=b"-_", validate=True)
        receipt = json.loads(raw)
    except (ValueError, UnicodeError, RecursionError):
        raise PostcardError("invalid_token", 2) from None
    if not isinstance(receipt, dict) or set(receipt) != RECEIPT_FIELDS or type(receipt["v"]) is not int or receipt["v"] != 1:
        raise PostcardError("invalid_token", 2)
    if not isinstance(receipt["directory"], str) or not os.path.isabs(receipt["directory"]) or len(receipt["directory"]) > 4096:
        raise PostcardError("invalid_token", 2)
    if not isinstance(receipt["name"], str) or not GENERATED_NAME.fullmatch(receipt["name"]):
        raise PostcardError("invalid_token", 2)
    for field in ("directory_device", "directory_inode", "uid", "device", "inode", "ctime_ns"):
        if type(receipt[field]) is not int or receipt[field] < 0:
            raise PostcardError("invalid_token", 2)
    return receipt


def same_empty_file(descriptor: int, name: str, expected: tuple) -> bool:
    try:
        info = os.stat(name, dir_fd=descriptor, follow_symlinks=False)
    except FileNotFoundError:
        return False
    return stat.S_ISREG(info.st_mode) and info.st_nlink == 1 and info.st_size == 0 and identity(info) == expected


def reserve(directory: str) -> dict:
    with directory_handle(directory, create=True) as (canonical, descriptor, directory_info):
        prefix = "terrarium-" + time.strftime("%Y%m%d-%H%M%S") + "-" + secrets.token_hex(8) + "-"
        output = None
        file_descriptor = None
        expected = None
        handed_off = False
        try:
            file_descriptor, output = tempfile.mkstemp(prefix=prefix, suffix=".png", dir=canonical)
            os.fchmod(file_descriptor, 0o600)
            info = os.fstat(file_descriptor)
            expected = identity(info)
            name = os.path.basename(output)
            if not GENERATED_NAME.fullmatch(name) or not same_empty_file(descriptor, name, expected):
                raise PostcardError("reservation_changed")
            receipt = {"v": 1, "directory": canonical, "directory_device": directory_info.st_dev,
                       "directory_inode": directory_info.st_ino, "name": name, "uid": info.st_uid,
                       "device": info.st_dev, "inode": info.st_ino, "ctime_ns": info.st_ctime_ns}
            result = {"ok": True, "path": output, "token": encode_receipt(receipt)}
            handed_off = True
            return result
        except OSError:
            raise PostcardError("cannot_reserve") from None
        finally:
            if file_descriptor is not None:
                if not handed_off and output is not None:
                    try:
                        expected = identity(os.fstat(file_descriptor))
                        name = os.path.basename(output)
                        if same_empty_file(descriptor, name, expected):
                            os.unlink(name, dir_fd=descriptor)
                    except OSError:
                        pass
                os.close(file_descriptor)


def cancel(directory: str, path: str, token: str) -> dict:
    receipt = decode_receipt(token)
    if not isinstance(path, str) or "\0" in path or path != os.path.join(receipt["directory"], receipt["name"]):
        raise PostcardError("reservation_changed")
    if receipt["uid"] != os.getuid():
        raise PostcardError("reservation_changed")
    with directory_handle(directory, create=False) as (canonical, descriptor, directory_info):
        if (canonical != receipt["directory"] or directory_info.st_dev != receipt["directory_device"]
                or directory_info.st_ino != receipt["directory_inode"]):
            raise PostcardError("reservation_changed")
        name = receipt["name"]
        try:
            info = os.stat(name, dir_fd=descriptor, follow_symlinks=False)
        except FileNotFoundError:
            return {"ok": True, "removed": False, "code": "already_removed"}
        except OSError:
            raise PostcardError("cleanup_failed") from None
        expected = receipt["uid"], receipt["device"], receipt["inode"], receipt["ctime_ns"]
        if not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid() or info.st_nlink != 1:
            raise PostcardError("reservation_changed")
        # A completed or partially written image is always preserved, even if a
        # writer changed its ctime before reporting an error to the UI.
        if info.st_size != 0:
            return {"ok": False, "removed": False, "code": "not_empty"}
        if identity(info) != expected:
            raise PostcardError("reservation_changed")
        try:
            if not same_empty_file(descriptor, name, expected):
                raise PostcardError("reservation_changed")
            os.unlink(name, dir_fd=descriptor)
        except FileNotFoundError:
            return {"ok": True, "removed": False, "code": "already_removed"}
        except OSError:
            raise PostcardError("cleanup_failed") from None
        return {"ok": True, "removed": True, "code": "removed"}


def main(argv=None) -> int:
    try:
        parser = JsonParser(description=__doc__)
        commands = parser.add_subparsers(dest="command", required=True, parser_class=JsonParser)
        reservation = commands.add_parser("reserve")
        reservation.add_argument("--directory", required=True)
        cancellation = commands.add_parser("cancel")
        cancellation.add_argument("--directory", required=True)
        cancellation.add_argument("--path", required=True)
        cancellation.add_argument("--token", required=True)
        args = parser.parse_args(argv)
        result = reserve(args.directory) if args.command == "reserve" else cancel(args.directory, args.path, args.token)
        status = 0 if result["ok"] else 1
    except PostcardError as error:
        result = {"ok": False, "code": error.code, "removed": False}
        status = error.exit_code
    except OSError:
        result = {"ok": False, "code": "filesystem_error", "removed": False}
        status = 1
    print(json.dumps(result, ensure_ascii=True, separators=(",", ":")))
    return status


if __name__ == "__main__":
    sys.exit(main())
