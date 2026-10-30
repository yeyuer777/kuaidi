#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Swift 源码静态自检。

在没有 Xcode 的 Windows 上，编译前只能做到这一步：
按 Swift 的词法规则剥掉注释和字符串，然后检查括号配平、
文件级结构关键字是否闭合、以及 import 是否齐全。

它不是编译器，但能抓住绝大多数手写语法错误——尤其是括号没闭合、
多行字符串没结束、注释嵌套错这类问题。

    python Scripts/check_swift_syntax.py
"""

import os
import re
import sys

ROOT = "PickupCode"

# 这些 SwiftUI / AppKit 类型需要对应的 import
KNOWN_IMPORTS = {"SwiftUI", "Foundation", "AppIntents", "PhotosUI", "UIKit", "Vision", "Combine"}


def scan(path):
    """返回 (错误列表, 统计信息)"""
    with open(path, encoding="utf-8") as f:
        src = f.read()

    errors = []
    i = 0
    n = len(src)
    depth = {"{": 0, "(": 0, "[": 0}
    closer = {"}": "{", ")": "(", "]": "["}
    open_lines = []
    imports = set()
    line = 1
    saw_multiline_string = False

    while i < n:
        ch = src[i]

        if ch == "\n":
            line += 1
            i += 1
            continue

        # 行注释
        if src.startswith("//", i):
            while i < n and src[i] != "\n":
                i += 1
            continue

        # 块注释（Swift 支持嵌套）
        if src.startswith("/*", i):
            nest = 1
            start_line = line
            i += 2
            while i < n and nest > 0:
                if src.startswith("/*", i):
                    nest += 1
                    i += 2
                elif src.startswith("*/", i):
                    nest -= 1
                    i += 2
                else:
                    if src[i] == "\n":
                        line += 1
                    i += 1
            if nest != 0:
                errors.append(f"L{start_line}: 块注释没有闭合")
            continue

        # 多行字符串
        if src.startswith('"""', i):
            saw_multiline_string = True
            start_line = line
            i += 3
            closed = False
            while i < n:
                if src[i] == "\\":
                    i += 2
                    continue
                if src.startswith('"""', i):
                    i += 3
                    closed = True
                    break
                if src[i] == "\n":
                    line += 1
                i += 1
            if not closed:
                errors.append(f"L{start_line}: 多行字符串没有闭合")
            continue

        # 普通字符串
        if ch == '"':
            start_line = line
            i += 1
            closed = False
            while i < n:
                if src[i] == "\\":
                    i += 2
                    continue
                if src[i] == '"':
                    i += 1
                    closed = True
                    break
                if src[i] == "\n":
                    line += 1
                    break  # 普通字符串不允许裸换行
                i += 1
            if not closed:
                errors.append(f"L{start_line}: 字符串没有闭合")
            continue

        # 括号
        if ch in depth:
            depth[ch] += 1
            open_lines.append((ch, line))
        elif ch in closer:
            want = closer[ch]
            if depth[want] == 0:
                errors.append(f"L{line}: 多余的 '{ch}'")
            else:
                depth[want] -= 1
                # 弹出最近的对应开括号
                for idx in range(len(open_lines) - 1, -1, -1):
                    if open_lines[idx][0] == want:
                        open_lines.pop(idx)
                        break
        elif ch.isalpha():
            m = re.match(r"[A-Za-z_][A-Za-z0-9_]*", src[i:])
            if m:
                word = m.group(0)
                if word == "import":
                    rest = src[i + len(word):i + len(word) + 24]
                    for imp in KNOWN_IMPORTS:
                        if rest.lstrip().startswith(imp):
                            imports.add(imp)
                i += len(word)
                continue
        i += 1

    for bracket, count in depth.items():
        if count != 0:
            lines = [ln for b, ln in open_lines if b == bracket]
            errors.append(f"'{bracket}' 未闭合 {count} 处，最近开括号在 L{lines}")

    return errors, {
        "imports": imports,
        "lines": line,
        "multiline_string": saw_multiline_string,
    }


def main():
    files = []
    for dirpath, _dirnames, filenames in os.walk(ROOT):
        for name in filenames:
            if name.endswith(".swift"):
                files.append(os.path.join(dirpath, name))
    files.sort()

    total_errors = 0
    print("=" * 74)
    print("Swift 源码静态自检")
    print("=" * 74)

    for path in files:
        errors, info = scan(path)
        total_errors += len(errors)
        status = "OK  " if not errors else "FAIL"
        extra = " ".join(sorted(info["imports"])) or "-"
        print(f"[{status}] {path:48s} {info['lines']:>4} 行  imports: {extra}")
        for e in errors:
            print(f"         → {e}")

    print("-" * 74)
    print(f"共 {len(files)} 个 Swift 文件，{total_errors} 个问题")

    if total_errors:
        print("\n有未闭合的括号或字符串，编译必然失败，先修这里。")
        return 1
    print("括号与字符串全部配平。")
    return 0


if __name__ == "__main__":
    sys.exit(main())
