#!/usr/bin/env python3
"""Validate a built Release, not just the flags requested from Xcode."""
import argparse
import plistlib
import re
import subprocess


def signature_problems(metadata, entitlements, developer_id=False):
    problems = []
    if entitlements.get("com.apple.security.get-task-allow"):
        problems.append("Release 带有 get-task-allow 调试权限")
    if developer_id:
        if not re.search(r"^Authority=Developer ID Application: .+$", metadata, re.M):
            problems.append("不是 Developer ID Application 签名")
        flags = re.search(r"\bflags=0x([0-9a-fA-F]+)", metadata)
        if not flags or not int(flags[1], 16) & 0x10000:
            problems.append("Hardened Runtime 未启用")
        if not re.search(r"^Timestamp=.+$", metadata, re.M):
            problems.append("缺少安全时间戳")
        if not re.search(r"^TeamIdentifier=[A-Z0-9]{10}$", metadata, re.M):
            problems.append("缺少有效 TeamIdentifier")
    return problems


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app")
    parser.add_argument("--developer-id", action="store_true")
    args = parser.parse_args()
    subprocess.run(["codesign", "--verify", "--deep", "--strict", args.app], check=True)
    for architecture in ("arm64", "x86_64"):
        display = subprocess.run(["codesign", "--display", "--verbose=4", "--arch", architecture, args.app],
                                 check=True, capture_output=True, text=True)
        rights = subprocess.run(["codesign", "--display", "--entitlements", "-", "--xml",
                                 "--arch", architecture, args.app], check=True, capture_output=True)
        entitlements = plistlib.loads(rights.stdout) if rights.stdout.strip() else {}
        problems = signature_problems(display.stderr, entitlements, args.developer_id)
        if problems:
            raise SystemExit("FAIL：" + architecture + "：" + "；".join(problems))
    print("PASS：两种架构的 Release 签名与调试权限检查通过" +
          ("；Developer ID、Hardened Runtime、安全时间戳已验证" if args.developer_id else "（未证明已公证）"))


if __name__ == "__main__":
    main()
