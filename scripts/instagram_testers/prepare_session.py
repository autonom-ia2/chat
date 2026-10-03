#!/usr/bin/env python3
"""Prepare a private session file from one Chrome Copy as cURL capture, offline.

Usage: python3 prepare_session.py --input capture.txt --output /private/path/session.json
The capture is parsed as text only. No commands, referenced files or requests run.
"""

import argparse
import json
import os
from pathlib import Path
import secrets
import shlex
import stat
import sys
from urllib.parse import parse_qsl, urlsplit


MAX_INPUT_BYTES = 262_144
MAX_VALUE_BYTES = 32_768
EXTRA_FORM_KEYS = (
    "__aaid", "__req", "__hs", "dpr", "__ccg", "__rev", "__s", "__hsi",
    "__dyn", "qpl_active_flow_ids",
)
HEADER_NAMES = frozenset((
    "accept", "accept-encoding", "accept-language", "cache-control", "pragma",
    "content-type", "cookie", "user-agent", "origin", "referer", "priority",
    "sec-ch-ua", "sec-ch-ua-mobile", "sec-ch-ua-platform", "sec-fetch-dest",
    "sec-fetch-mode", "sec-fetch-site", "sec-fetch-user", "dnt", "x-asbd-id",
    "x-fb-lsd", "x-fb-friendly-name",
))
VALUE_FLAGS = {
    "--url": "url", "-H": "header", "--header": "header",
    "-b": "cookie", "--cookie": "cookie", "--data-raw": "body",
    "-d": "body", "--data": "body", "-X": "method", "--request": "method",
}


class PreparationError(Exception):
    """A deliberately value-free error: never attach capture text to exceptions."""


def require(condition):
    if not condition:
        raise PreparationError("Invalid capture or unsafe output.")


def safe_value(value):
    return bool(value) and len(value.encode("utf-8")) <= MAX_VALUE_BYTES and all(
        ord(char) >= 32 and ord(char) != 127 for char in value
    )


def numeric_id(value):
    return 1 <= len(value) <= 40 and all("0" <= char <= "9" for char in value)


def curl_tokens(capture):
    # POSIX shlex keeps escaped newlines; remove only shell continuations outside
    # quotes. A newline inside a quoted header/cookie/form must remain detectable.
    characters = []
    quote = None
    index = 0
    while index < len(capture):
        char = capture[index]
        if char == "\\" and quote != "'" and index + 1 < len(capture):
            following = capture[index + 1]
            if following == "\n" and quote is None:
                index += 2
                continue
            characters.extend((char, following))
            index += 2
            continue
        if char in ("'", '"'):
            if quote is None:
                quote = char
            elif quote == char:
                quote = None
        characters.append(char)
        index += 1
    lexer = shlex.shlex("".join(characters).strip(), posix=True, punctuation_chars=";&|<>()\n")
    lexer.whitespace = " \t\r"
    lexer.whitespace_split = True
    lexer.commenters = ""
    try:
        tokens = list(lexer)
    except ValueError:
        raise PreparationError("Invalid capture syntax.") from None
    require(tokens and tokens[0] == "curl")
    return tokens[1:]


def form_fields(body):
    require(safe_value(body))
    # parse_qsl tolerates malformed percent escapes; reject those first.
    index = 0
    while index < len(body):
        if body[index] == "%":
            require(index + 2 < len(body) and all(
                char in "0123456789abcdefABCDEF" for char in body[index + 1:index + 3]
            ))
            index += 3
        else:
            index += 1
    try:
        pairs = parse_qsl(body, keep_blank_values=True, strict_parsing=True,
                          encoding="utf-8", errors="strict", max_num_fields=256)
    except (ValueError, UnicodeError):
        raise PreparationError("Invalid form encoding.") from None
    fields = {}
    for key, value in pairs:
        require(safe_value(key) and key not in fields)
        require(not value or safe_value(value))
        fields[key] = value
    return fields


def validate_route(url, fields, headers):
    require(safe_value(url))
    try:
        route = urlsplit(url)
    except ValueError:
        raise PreparationError("Invalid route.") from None
    require(route.scheme == "https" and route.netloc == "developers.facebook.com" and not route.fragment)
    if route.path == "/roles/instagram/typeahead/user/":
        query = form_fields(route.query)
        require(set(query) == {"value"} and safe_value(query["value"]))
    elif route.path == "/api/graphql/":
        require(not route.query and fields.get("fb_api_req_friendly_name") == "RolesTable_Query")
        require(headers.get("x-fb-friendly-name", "RolesTable_Query") == "RolesTable_Query")
        try:
            variables = json.loads(fields.get("variables", ""), object_pairs_hook=unique_json_object)
        except (ValueError, TypeError):
            raise PreparationError("Invalid query variables.") from None
        require(isinstance(variables, dict) and set(variables) == {"app_id"})
        require(isinstance(variables["app_id"], str) and numeric_id(variables["app_id"]))
    else:
        parts = route.path.split("/")
        require(len(parts) == 8 and parts[:2] == ["", "apps"] and numeric_id(parts[2]))
        require(parts[3:] == ["async", "instagram", "roles", "add", ""] and not route.query)


def unique_json_object(pairs):
    result = {}
    for key, value in pairs:
        require(key not in result)
        result[key] = value
    return result


def parse_capture(capture):
    require(len(capture.encode("utf-8")) <= MAX_INPUT_BYTES)
    tokens = curl_tokens(capture)
    values = {}
    headers = {}
    switches = set()
    index = 0
    while index < len(tokens):
        flag = tokens[index]
        index += 1
        if flag in ("--compressed", "--globoff"):
            require(flag not in switches)
            switches.add(flag)
            continue
        if flag.startswith("https://"):
            kind, value = "url", flag
        else:
            require(flag in VALUE_FLAGS and index < len(tokens))
            kind, value = VALUE_FLAGS[flag], tokens[index]
            index += 1
        require(safe_value(value))
        if kind == "header":
            name, separator, header_value = value.partition(":")
            name = name.lower()
            header_value = header_value.strip(" ")
            require(separator and name in HEADER_NAMES and name not in headers and safe_value(header_value))
            headers[name] = header_value
        else:
            require(kind not in values)
            require(kind != "body" or flag == "--data-raw" or not value.startswith("@"))
            values[kind] = value
    require("url" in values and "body" in values and values.get("method", "POST") == "POST")
    content_type = headers.get("content-type", "application/x-www-form-urlencoded")
    require(content_type.lower().split(";", 1)[0].strip() == "application/x-www-form-urlencoded")
    fields = form_fields(values["body"])
    validate_route(values["url"], fields, headers)
    require(not ("cookie" in values and "cookie" in headers))
    cookie = values.get("cookie", headers.get("cookie", ""))
    require(safe_value(cookie))
    cookies = {}
    for item in cookie.split(";"):
        if not item.strip():
            continue
        key, separator, value = item.strip().partition("=")
        require(separator and key and key not in cookies)
        cookies[key] = value
    user_id = fields.get("__user", "")
    require(numeric_id(user_id) and cookies.get("c_user") == user_id)
    session = {"cookie": cookie, "user_id": user_id, "user_agent": headers.get("user-agent", "")}
    for key in ("fb_dtsg", "lsd", "jazoest"):
        session[key] = fields.get(key, "")
    require(all(safe_value(value) for value in session.values()))
    require(headers.get("x-fb-lsd", session["lsd"]) == session["lsd"])
    session["extra_form"] = {key: fields[key] for key in EXTRA_FORM_KEYS if key in fields}
    require(all(safe_value(value) for value in session["extra_form"].values()))
    return session


def private_directory(output):
    """Walk directory descriptors so neither ancestors nor writes follow links."""
    path = Path(output)
    require(".." not in path.parts)
    path = Path(os.path.abspath(path))
    require(path.name not in ("", ".git"))
    flags = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW
    directory = os.open("/", flags)
    try:
        for part in (*path.parent.parts[1:], None):
            try:
                os.stat(".git", dir_fd=directory, follow_symlinks=False)
            except FileNotFoundError:
                pass
            else:
                raise PreparationError("Output in a Git working tree is forbidden.")
            if part is None:
                break
            try:
                child = os.open(part, flags, dir_fd=directory)
            except FileNotFoundError:
                os.mkdir(part, mode=0o700, dir_fd=directory)
                child = os.open(part, flags, dir_fd=directory)
            os.close(directory)
            directory = child
        info = os.fstat(directory)
        require(info.st_uid == os.getuid() and stat.S_IMODE(info.st_mode) & 0o077 == 0)
        return directory, path.name
    except BaseException:
        os.close(directory)
        raise


def write_session(session, output, replace=False):
    directory, name = private_directory(output)
    temporary = None
    try:
        try:
            info = os.stat(name, dir_fd=directory, follow_symlinks=False)
        except FileNotFoundError:
            pass
        else:
            require(replace and stat.S_ISREG(info.st_mode) and info.st_uid == os.getuid())
        candidate = ".instagram-session-" + secrets.token_hex(16)
        descriptor = os.open(candidate, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW,
                             0o600, dir_fd=directory)
        temporary = candidate
        with os.fdopen(descriptor, "w", encoding="utf-8") as stream:
            os.fchmod(stream.fileno(), 0o600)
            json.dump(session, stream, ensure_ascii=True)
            stream.write("\n")
            stream.flush()
            os.fsync(stream.fileno())
        if replace:
            os.replace(temporary, name, src_dir_fd=directory, dst_dir_fd=directory)
        else:
            # Unlike rename, hard-link publication fails if the destination exists.
            os.link(temporary, name, src_dir_fd=directory, dst_dir_fd=directory, follow_symlinks=False)
        os.fsync(directory)
    finally:
        if temporary is not None:
            try:
                os.unlink(temporary, dir_fd=directory)
            except FileNotFoundError:
                pass
        os.close(directory)


class PrivateArgumentParser(argparse.ArgumentParser):
    def error(self, message):
        raise PreparationError("Invalid command arguments.")


def main(argv=None):
    parser = PrivateArgumentParser(description="Prepare a private Meta session JSON offline.", allow_abbrev=False)
    parser.add_argument("--input", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--replace", action="store_true")
    try:
        arguments = parser.parse_args(argv)
        with open(arguments.input, "rb") as stream:
            capture = stream.read(MAX_INPUT_BYTES + 1)
        require(len(capture) <= MAX_INPUT_BYTES)
        session = parse_capture(capture.decode("utf-8"))
        write_session(session, arguments.output, arguments.replace)
    except (PreparationError, OSError, ValueError, UnicodeError, RecursionError):
        print("Session preparation failed; check the capture and private output path.", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
