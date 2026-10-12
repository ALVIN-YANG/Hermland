#!/usr/bin/env python3
"""Conservative SSH compatibility gate; never changes the server configuration.

Only global settings and Hermland's two managed group blocks are supported.
Arbitrary Match/Include combinations cannot be proven safe by checking one
source IP. Refuse them, rather than weakening or rearranging another policy.
"""
import argparse
import glob
from pathlib import Path
import shlex
import sys


class PolicyError(Exception):
    pass


MARKERS = {
    "# Hermland device access (managed)": "hermland-devices",
    "# Hermland relay access (managed)": "hermland-relay",
}


def check_config(config=Path("/etc/ssh/sshd_config"), include_base=Path("/etc/ssh")):
    expected_group = None
    seen_groups = set()
    visiting = set()

    def visit(path, depth=0):
        nonlocal expected_group
        path = path.resolve()
        if path in visiting or depth > 16:
            raise PolicyError("SSH Include 存在循环或嵌套过深，停止操作")
        visiting.add(path)
        try:
            lines = path.read_text().splitlines()
            for number, line in enumerate(lines, 1):
                stripped = line.strip()
                if stripped in MARKERS:
                    if expected_group is not None:
                        raise PolicyError("Hermland 管理标记不完整，停止操作")
                    expected_group = MARKERS[stripped]
                    continue
                parts = shlex.split(line, comments=True)
                if not parts:
                    continue
                keyword, separator, value = parts[0].partition("=")
                args = ([value] if separator and value else []) + parts[1:]
                keyword = keyword.lower()
                if keyword == "match":
                    valid = (expected_group is not None and len(args) == 2
                             and args[0].lower() == "group" and args[1] == expected_group
                             and expected_group not in seen_groups)
                    if not valid:
                        raise PolicyError(f"{path.name}:{number} 有不受支持的 SSH Match 规则。"
                                          "本版本不自动改写其他账户策略；请管理员评估后使用兼容配置")
                    seen_groups.add(expected_group)
                    expected_group = None
                elif expected_group is not None:
                    raise PolicyError("Hermland 管理标记后不是预期的 Match Group，停止操作")
                elif keyword == "include":
                    if not args:
                        raise PolicyError("SSH Include 路径缺失")
                    for pattern in args:
                        if "$" in pattern or "%" in pattern:
                            raise PolicyError("SSH Include 使用了无法验证的动态路径，停止操作")
                        absolute = pattern if Path(pattern).is_absolute() else str(include_base / pattern)
                        for included in sorted(glob.glob(absolute)):
                            visit(Path(included), depth + 1)
        except (OSError, ValueError) as error:
            raise PolicyError(f"无法完整检查 SSH 配置 {path.name}，停止操作") from error
        finally:
            visiting.remove(path)

    visit(Path(config))
    if expected_group is not None:
        raise PolicyError("Hermland 管理标记缺少 Match Group，停止操作")


def main():
    parser = argparse.ArgumentParser(description="只读检查 SSH 条件规则，不改配置或授权")
    parser.add_argument("--config", type=Path, default=Path("/etc/ssh/sshd_config"))
    args = parser.parse_args()
    try:
        check_config(args.config)
    except PolicyError as error:
        print(f"FAIL：{error}", file=sys.stderr)
        return 1
    print("PASS：没有无法验证的条件 SSH 策略；继续核对实际账户限制")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
