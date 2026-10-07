#!/usr/bin/env python3
"""Static HTTP server with byte-range support for media seeking."""

from __future__ import annotations

import os
import re
import sys
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer


RANGE_RE = re.compile(r"bytes=(\d*)-(\d*)$")


class LimitedReader:
    def __init__(self, file_obj, length: int):
        self.file_obj = file_obj
        self.remaining = length

    def read(self, size: int = -1) -> bytes:
        if self.remaining <= 0:
            return b""
        if size < 0 or size > self.remaining:
            size = self.remaining
        data = self.file_obj.read(size)
        self.remaining -= len(data)
        return data

    def close(self) -> None:
        self.file_obj.close()


class RangeRequestHandler(SimpleHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def send_head(self):
        path = self.translate_path(self.path)
        if os.path.isdir(path):
            return super().send_head()
        if not os.path.isfile(path):
            self.send_error(404, "File not found")
            return None

        try:
            file_obj = open(path, "rb")
        except OSError:
            self.send_error(404, "File not found")
            return None

        stat = os.fstat(file_obj.fileno())
        size = stat.st_size
        content_type = self.guess_type(path)
        range_header = self.headers.get("Range")
        start = 0
        end = size - 1
        partial = False

        if range_header and size:
            match = RANGE_RE.fullmatch(range_header.strip())
            if match:
                start_text, end_text = match.groups()
                if start_text:
                    start = int(start_text)
                    end = int(end_text) if end_text else size - 1
                elif end_text:
                    suffix_length = int(end_text)
                    start = max(0, size - suffix_length)
                else:
                    start = size

                if start >= size:
                    file_obj.close()
                    self.send_response(416)
                    self.send_header("Content-Range", f"bytes */{size}")
                    self.send_header("Content-Length", "0")
                    self.end_headers()
                    return None

                end = min(end, size - 1)
                if end < start:
                    file_obj.close()
                    self.send_error(416, "Requested range not satisfiable")
                    return None
                partial = True

        if partial:
            length = end - start + 1
            file_obj.seek(start)
            self.send_response(206)
            self.send_header("Content-Range", f"bytes {start}-{end}/{size}")
        else:
            length = size
            self.send_response(200)

        self.send_header("Content-Type", content_type)
        self.send_header("Accept-Ranges", "bytes")
        self.send_header("Content-Length", str(length))
        self.send_header("Last-Modified", self.date_time_string(stat.st_mtime))
        self.end_headers()
        return LimitedReader(file_obj, length) if partial else file_obj


def main() -> None:
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8080
    server = ThreadingHTTPServer(("0.0.0.0", port), RangeRequestHandler)
    print(f"Serving HTTP on 0.0.0.0 port {port} with byte-range support...", flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
