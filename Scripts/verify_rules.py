#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
取件码规则回归验证。

Swift 端的 PickupParser 无法在 Windows 上编译，所以这里用 Python 等价实现
同一套正则和同样的判定顺序跑真实样本。正则语义（ICU vs re）在本次用到的
语法范围内一致：\\d \\s 大小写忽略、定宽 lookbehind、负向前瞻 都通用。

用途：改规则库之前先跑这个，通过率掉下来就说明改坏了。
    python Scripts/verify_rules.py
"""

import re
import sys

# ---------------------------------------------------------------- 规则库镜像

# 取件点品牌：用户实际要去的地方
STATION_BRANDS = [
    ("菜鸟驿站", ["菜鸟驿站", "菜鸟裹裹", "菜鸟"]),
    ("丰巢", ["丰巢", "蜂巢", "hive box"]),
    ("妈妈驿站", ["妈妈驿站"]),
    ("兔喜生活", ["兔喜"]),
    ("快宝驿站", ["快宝"]),
    ("熊猫快收", ["熊猫快收"]),
    ("速递易", ["速递易"]),
]

# 快递公司：包裹是谁承运的
COURIERS = [
    ("京东", ["京东物流", "京喜", "京东快递", "京东"]),
    ("顺丰", ["顺丰", "sf express", "sf-express"]),
    ("中通", ["中通"]),
    ("圆通", ["圆通"]),
    ("申通", ["申通"]),
    ("韵达", ["韵达"]),
    ("极兔", ["极兔", "j&t", "jnt"]),
    ("德邦", ["德邦"]),
    ("百世", ["百世"]),
    ("邮政", ["中国邮政", "邮政ems", "ems"]),
]

NOTICE_KEYWORDS = [
    "取件码", "提货码", "取货码", "取物码", "取件凭证", "取件号",
    "开箱码", "取件密码", "凭码取件", "已到驿站", "已存放至",
]

WEAK_KEYWORDS = ["驿站", "快递柜", "智能柜", "丰巢", "自提柜", "代收点"]

CODE_PATTERNS = [
    ("分区码",
     r"(?:取件码|提货码|取货码|取物码|取件凭证|取件号|开箱码|取件密码|密码)\s*[:：]?\s*(\d{1,3}\s*[-－—–]\s*\d{1,3}(?:\s*[-－—–]\s*\d{1,4})?)"),
    ("前缀短码",
     r"(?:取件码|提货码|取货码|取物码|取件凭证|取件号|开箱码|取件密码)\s*(?:是|为)?\s*[:：]?\s*([0-9A-Za-z]{4,10})(?![0-9A-Za-z])"),
    ("裸分区码",
     r"(?<![0-9])(\d{1,3}\s*[-－—–]\s*\d{1,3}\s*[-－—–]\s*\d{1,4})(?![0-9])"),
    ("码字兜底",
     r"(?:码|code)\s*[:：]?\s*(\d{4,8})(?![0-9])"),
]

ADDRESS_PATTERNS = [
    r"(?:取件地址|存放地址|地址|网点地址|存放位置|柜机位置)\s*[:：]\s*([^\n，,。；;！!]{4,60})",
    r"(?:已存放至|已放至|已投递至|已送达|已送到|寄存于|暂存于|放在)\s*([^\n，,。；;！!]{4,40}?)(?:[，,。；;！!\n]|$)",
    r"(?:请|可)\s*(?:到|至|前往)\s*([^\n，,。；;！!]{4,40}?)(?:取件|领取|自取|凭)",
]

STATION_PATTERNS = [
    r"(?:已到|已存放至|已放至|已投递至|已存入|已放入|存放至|投递至|存入|放入|寄存在|暂存于|在)\s*([^，,。；;！!\n]{1,25}?(?:驿站|快递柜|智能柜|自提柜|服务点|代收点|快递超市))",
    r"【([^】]*?(?:驿站|快递柜|智能柜|自提柜|服务点|代收点|快递超市)[^】]*?)】",
    r"(?<![至入在到])([\u4e00-\u9fa5A-Za-z0-9（）()·]{2,20}?(?:驿站|快递柜|智能柜|自提柜|服务点|代收点|快递超市))",
]

PHONE_TAIL_PATTERNS = [
    r"(?:手机|电话)?\s*尾号\s*[:：]?\s*(\d{4})",
    r"(?:后四位|末四位|后4位)\s*[:：]?\s*(\d{4})",
    r"(\d{4})\s*号?\s*尾号",
]

TRACKING_PATTERNS = [
    r"(?:运单号|快递单号|运单编号|物流单号|单号)\s*[:：]?\s*([A-Za-z0-9]{8,24})",
]

LOCATION_PATTERNS = [
    r"(?:柜机号|柜号|柜机|货架号|货架|层号|格口|箱门)\s*[:：]?\s*([0-9A-Za-z\-]{1,12})",
]

HOLD_PATTERNS = [
    (r"(?:免费)?保管\s*(\d+)\s*(?:个)?小时", 1),
    (r"(?:免费)?保管\s*(\d+)\s*天", 24),
    (r"请在\s*(\d+)\s*小时内", 1),
    (r"(\d+)\s*小时内\s*(?:免费)?取件", 1),
    (r"超过\s*(\d+)\s*小时", 1),
]


# ---------------------------------------------------------------- 解析实现

def normalize(text: str) -> str:
    out = []
    for ch in text:
        cp = ord(ch)
        if 0xFF01 <= cp <= 0xFF5E:
            out.append(chr(cp - 0xFEE0))
        elif cp == 0x3000:
            out.append(" ")
        else:
            out.append(ch)
    return "".join(out)


def first(pattern, text, group=1):
    m = re.search(pattern, text, re.IGNORECASE)
    if not m:
        return None
    try:
        v = m.group(group)
    except IndexError:
        return None
    v = (v or "").strip()
    return v or None


def looks_like_notice(text: str) -> bool:
    low = text.lower()
    if any(k.lower() in low for k in NOTICE_KEYWORDS):
        return True
    if any(k.lower() in low for k in WEAK_KEYWORDS) and re.search(r"\d{4,}", text):
        return True
    return False


def sanitize_code(raw: str):
    s = raw.strip().replace("－", "-").replace("—", "-").replace("–", "-").replace(" ", "")
    s = s.replace("\u00a0", "")
    if not s:
        return None
    if "-" in s:
        parts = s.split("-")
        if not (2 <= len(parts) <= 3):
            return None
        if not all(p and len(p) <= 4 and p.isdigit() for p in parts):
            return None
        return s
    digits = "".join(c for c in s if c.isdigit())
    if len(digits) >= 12:
        return None
    if len(digits) == 11 and s.startswith("1"):
        return None
    if len(digits) < 4:
        return None
    if len(digits) == 8:
        year, month, day = digits[:4], digits[4:6], digits[6:8]
        if year.isdigit() and 2015 <= int(year) <= 2035:
            if 1 <= int(month) <= 12 and 1 <= int(day) <= 31:
                return None
    return s


def extract_code(text: str):
    for name, pattern in CODE_PATTERNS:
        raw = first(pattern, text)
        if raw is None:
            continue
        cleaned = sanitize_code(raw)
        if cleaned:
            return cleaned, name
    return None, None


def detect(brands, text: str):
    low = text.lower()
    for name, kws in brands:
        for kw in kws:
            if kw.lower() in low:
                return name
    return None


def detect_station(text: str):
    for pattern in STATION_PATTERNS:
        v = first(pattern, text)
        if v and len(v) >= 3:
            return v
    return None


def detect_address(text: str):
    for pattern in ADDRESS_PATTERNS:
        v = first(pattern, text)
        if v and len(v) >= 4:
            return v
    return None


def first_of(patterns, text):
    for p in patterns:
        v = first(p, text)
        if v:
            return v
    return None


def compute_hold_hours(text: str):
    for pattern, unit in HOLD_PATTERNS:
        v = first(pattern, text)
        if v and v.isdigit():
            return int(v) * unit
    return None


def parse_block(block: str):
    if not looks_like_notice(block):
        return None
    code, matched_by = extract_code(block)
    if not code:
        return None

    station_brand = detect(STATION_BRANDS, block)
    courier = detect(COURIERS, block)
    merchant = station_brand or courier or "未知快递"

    station = detect_station(block)
    if station and station.replace(" ", "") == merchant:
        station = None

    return {
        "code": code,
        "matched_by": matched_by,
        "merchant": merchant,
        "courier": courier,
        "station": station,
        "address": detect_address(block),
        "phoneTail": first_of(PHONE_TAIL_PATTERNS, block),
        "tracking": first_of(TRACKING_PATTERNS, block),
        "location": first_of(LOCATION_PATTERNS, block),
        "holdHours": compute_hold_hours(block),
    }


def parse(text: str):
    normalized = normalize(text)
    lines = [l.strip() for l in normalized.splitlines() if l.strip()]
    notice_lines = [l for l in lines if looks_like_notice(l)]
    if len(notice_lines) >= 2:
        items = [parse_block(l) for l in notice_lines]
        items = [i for i in items if i]
        if items:
            return items
    single = parse_block(normalized)
    return [single] if single else []


# ---------------------------------------------------------------- 样本

# (说明, 原文, 期望取件码 None=应拒绝, 期望取件点, 期望快递公司)
CASES = [
    ("菜鸟分区码",
     "【菜鸟驿站】您的包裹已到杭州西湖文三路店，请凭取件码8-2-3021于20:00前到店取件，地址：文三路478号。免费保管3天。",
     "8-2-3021", "菜鸟驿站", None),

    ("丰巢8位",
     "【丰巢】您的快递已放入丰巢智能柜，取件码：87654321，柜机位置：A栋1楼大堂，请24小时内取件。",
     "87654321", "丰巢", None),

    ("京东营业部",
     "【京东】您的订单已到达京东快递杭州文三营业部，取件码：3-2-1024，取件时间09:00-21:00，地址：文三路100号。",
     "3-2-1024", "京东", "京东"),

    ("顺丰驿站",
     "【顺丰速运】您的快件已存放至顺丰驿站，取件码 5-1-2088，请凭码取件。地址：杭州市西湖区文三路200号。",
     "5-1-2088", "顺丰", "顺丰"),

    ("兔喜5位",
     "【兔喜生活】您的包裹已到兔喜生活超市，取件码：12345，地址：西湖区文二路50号，营业时间8:00-22:00。",
     "12345", "兔喜生活", None),

    ("妈妈驿站",
     "【妈妈驿站】您的圆通快递已到店，取件码 2-2-2018，请及时取件，地址：文一路12号。",
     "2-2-2018", "妈妈驿站", "圆通"),

    ("中通带尾号",
     "【中通快递】您好，您的快件已到杭州西湖驿站，取件码：6-3-1105，手机尾号8823，请凭取件码取件。",
     "6-3-1105", "中通", "中通"),

    ("速递易柜机",
     "【速递易】您的包裹已存入速递易柜机，取件码 35792468，柜号 B-12，请在48小时内取件。",
     "35792468", "速递易", None),

    ("全角字符",
     "【菜鸟驿站】您的包裹已到，取件码：８－２－３０２１，请及时取件。",
     "8-2-3021", "菜鸟驿站", None),

    ("无冒号",
     "您的快递已到菜鸟驿站文三路店，取件码8-2-3021，请尽快取件",
     "8-2-3021", "菜鸟驿站", None),

    ("运单号干扰",
     "【菜鸟驿站】您的包裹已到店，取件码：2-1-3021，运单号：75312345678901，手机尾号1234。",
     "2-1-3021", "菜鸟驿站", None),

    ("手机号干扰",
     "【菜鸟驿站】取件码：1-1-1001，如有疑问请联系13812345678。",
     "1-1-1001", "菜鸟驿站", None),

    ("地址含门牌数字",
     "【菜鸟驿站】取件码：2-2-2018，地址：文三路478号3幢102室，营业至21点。",
     "2-2-2018", "菜鸟驿站", None),

    ("韵达入丰巢",
     "【韵达】您的快件已投递至丰巢智能柜，取件码是658921，请及时取件。",
     "658921", "丰巢", "韵达"),

    ("极兔入快宝",
     "【极兔速递】您的包裹已在快宝驿站暂存，取件码：7-1-4022，地址：文三路88号。",
     "7-1-4022", "快宝驿站", "极兔"),

    ("邮政ems",
     "【中国邮政】您的EMS快件已到杭州西湖服务点，提货码：4521，请携带身份证取件。",
     "4521", "邮政", "邮政"),

    # ---- 以下应当拒绝 ----
    ("银行验证码应拒绝",
     "【某银行】您的验证码是382910，5分钟内有效，请勿泄露。",
     None, None, None),

    ("营销短信应拒绝",
     "【淘宝】双11大促全场5折起，点击领取优惠券，退订回T。",
     None, None, None),

    ("物流在途应拒绝",
     "【中通】您的快递单号78912345678901已发出，预计明天送达。",
     None, None, None),

    ("已签收应拒绝",
     "【顺丰】您的快件已签收，感谢使用顺丰速运。",
     None, None, None),
]


# ---------------------------------------------------------------- 执行

def main():
    passed = 0
    failed = []
    print("=" * 78)
    print("取件码规则回归验证")
    print("=" * 78)

    for desc, text, expect_code, expect_merchant, expect_courier in CASES:
        items = parse(text)
        if expect_code is None:
            ok = len(items) == 0
            got = "拒绝" if not items else f"误提取 {items[0]['code']}"
        else:
            ok = len(items) > 0 and items[0]["code"] == expect_code
            if items:
                it = items[0]
                got = it["code"]
                if it["merchant"] != (expect_merchant or "未知快递"):
                    ok = False
                    got += f" / 取件点={it['merchant']}(期望{expect_merchant})"
                if it["courier"] != expect_courier:
                    ok = False
                    got += f" / 快递={it['courier']}(期望{expect_courier})"
            else:
                got = "未提取到"

        mark = "PASS" if ok else "FAIL"
        if ok:
            passed += 1
        else:
            failed.append((desc, text, got))

        print(f"[{mark}] {desc:14s} -> {got}")
        if ok and items:
            it = items[0]
            extra = []
            if it["station"]:
                extra.append(f"网点={it['station']}")
            if it["address"]:
                extra.append(f"地址={it['address']}")
            if it["phoneTail"]:
                extra.append(f"尾号={it['phoneTail']}")
            if it["tracking"]:
                extra.append(f"运单={it['tracking']}")
            if it["location"]:
                extra.append(f"柜位={it['location']}")
            if it["holdHours"]:
                extra.append(f"保管={it['holdHours']}h")
            if extra:
                print(f"             {' | '.join(extra)}")

    total = len(CASES)
    print("-" * 78)
    print(f"通过 {passed}/{total}  通过率 {passed / total * 100:.1f}%")

    if failed:
        print("\n失败明细：")
        for desc, text, got in failed:
            print(f"  - {desc}\n      原文: {text}\n      实际: {got}")

    return 0 if passed == total else 1


if __name__ == "__main__":
    sys.exit(main())
