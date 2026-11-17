# -*- coding: utf-8 -*-
"""把生成的预设通过 SillyTavern 官方接口装进运行中的宿主，然后回读校验。

对应宿主代码：
- src/endpoints/presets.js  POST /api/presets/save  body {apiId, name, preset}
- src/endpoints/settings.js POST /api/settings/get 返回 openai_settings / openai_setting_names

跑法：python F:/sigil-circuit/preset/install_to_host.py
报告写 F:/sigil-circuit/preset/_install.log
"""

import json
import os
import urllib.request
import urllib.parse

HERE = os.path.dirname(os.path.abspath(__file__))
REF = os.path.join(os.path.dirname(HERE), "_preset_ref")
PRESET_PATH = os.path.join(HERE, "白描回廊 v1.0.json")
LOG = os.path.join(HERE, "_install.log")

BASE = "http://127.0.0.1:8000"
NAME = "白描回廊 v1.0"


def read_cookie():
    """Netscape 格式的 cookie jar 解析。

    坑：Express 写的 session cookie 行首是 `#HttpOnly_127.0.0.1`，
    用 `startswith('#')` 跳过注释会把真正的 cookie 一起跳掉。
    """
    p = os.path.join(REF, "cj.txt")
    jar = []
    for line in open(p, encoding="utf-8"):
        s = line.rstrip("\n")
        if not s or (s.startswith("#") and not s.startswith("#HttpOnly_")):
            continue
        parts = s.split("\t")
        if len(parts) >= 7:
            jar.append(parts[5] + "=" + parts[6])
    return "; ".join(jar)


def call(path, payload, token, cookie):
    data = json.dumps(payload, ensure_ascii=False).encode("utf-8")
    req = urllib.request.Request(BASE + path, data=data, method="POST")
    req.add_header("Content-Type", "application/json")
    req.add_header("X-CSRF-Token", token)
    req.add_header("Cookie", cookie)
    with urllib.request.urlopen(req, timeout=30) as r:
        return r.status, r.read().decode("utf-8", "replace")


def main():
    out = []
    token = json.load(open(os.path.join(REF, "tok.json"), encoding="utf-8"))["token"]
    cookie = read_cookie()
    out.append("cookie: %s" % ("有" if cookie else "无"))

    preset = json.load(open(PRESET_PATH, encoding="utf-8"))
    out.append("本地预设: %d 条 prompts, %d 组 prompt_order"
               % (len(preset["prompts"]), len(preset["prompt_order"])))

    st, body = call("/api/presets/save",
                    {"apiId": "openai", "name": NAME, "preset": preset}, token, cookie)
    out.append("POST /api/presets/save -> %s %s" % (st, body[:200]))

    st, body = call("/api/settings/get", {}, token, cookie)
    out.append("POST /api/settings/get -> %s" % st)
    if st != 200:
        out.append("回读失败，无法确认宿主是否接受")
        return out

    d = json.loads(body)
    names = d.get("openai_setting_names") or []
    out.append("宿主预设总数: %d" % len(names))
    if NAME not in names:
        out.append("!! 宿主列表里找不到 %r" % NAME)
        return out

    idx = names.index(NAME)
    incoming = d.get("openai_settings") or []
    raw = incoming[idx] if idx < len(incoming) else None
    if raw is None:
        out.append("!! openai_settings 里取不到对应项")
        return out
    # 宿主返回的是原始文件字符串，不是对象（settings.js:106 fileContents.push(file)）
    got = json.loads(raw) if isinstance(raw, str) else raw

    out.append("宿主读到的 %r:" % NAME)
    out.append("  prompts: %d 条" % len(got.get("prompts") or []))
    out.append("  prompt_order 组: %s"
               % [str(g.get("character_id")) for g in (got.get("prompt_order") or [])])
    for g in got.get("prompt_order") or []:
        order = g.get("order") or []
        out.append("    cid=%s -> %d 条, 默认开 %d"
                   % (g.get("character_id"), len(order),
                      len([e for e in order if e.get("enabled")])))
    out.append("  temperature=%r top_p=%r max_context=%r max_tokens=%r"
               % (got.get("temperature"), got.get("top_p"),
                  got.get("openai_max_context"), got.get("openai_max_tokens")))
    out.append("  含连接字段: %s"
               % sorted(set(got) & {"chat_completion_source", "openai_model", "claude_model",
                                    "reverse_proxy", "proxy_password", "custom_url"}))

    # 逐条比对 identifier，确认宿主没吃掉自定义条目
    local_ids = [p["identifier"] for p in preset["prompts"]]
    host_ids = [p.get("identifier") for p in (got.get("prompts") or [])]
    out.append("  identifier 完全一致: %s" % (local_ids == host_ids))
    if local_ids != host_ids:
        out.append("    本地有而宿主无: %s" % [i for i in local_ids if i not in host_ids])
        out.append("    宿主有而本地无: %s" % [i for i in host_ids if i not in local_ids])

    main_c = [p for p in got["prompts"] if p.get("identifier") == "main"][0].get("content", "")
    out.append("  main 正文长度: %d（截断检查：%s）" % (len(main_c), "完整" if len(main_c) > 300 else "可疑"))
    return out


if __name__ == "__main__":
    lines = main()
    open(LOG, "w", encoding="utf-8").write("\n".join(lines) + "\n")
    print("install done, see _install.log")
