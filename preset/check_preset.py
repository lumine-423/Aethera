# -*- coding: utf-8 -*-
"""
预设结构自检。只读，不改文件。
跑法：python F:/sigil-circuit/preset/check_preset.py
报告写 F:/sigil-circuit/preset/_check.log

检查项都对应 SillyTavern 1.19.0 的真实行为，不是我自己想的规矩：
1. JSON 能解析
2. 不能有 isConnection=true 的键（否则导入弹敏感字段框）—— openai.js:305 表第四列
3. prompts 里每条自定义条目字段齐全且 system_prompt=false —— PromptManager.js:127-195
4. marker:true 的条目不能带 content —— Default.json 实测
5. prompt_order 必须有 100001 组 —— openai.js:695-700 dummyId=100001
6. prompt_order 里的 identifier 必须都在 prompts 里存在
7. 每个 identifier 在 prompts 里唯一
8. 正文里用到的 {{getvar}} 必须有对应的 {{setvar}}
9. 顶层数值字段类型正确
"""

import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
PRESET = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, "白描回廊 v1.0.json")
LOG = os.path.join(HERE, "_check.log")

# openai.js:305-409 中第四列为 true 的全部键（写进预设会触发敏感字段弹窗）
CONNECTION_KEYS = {
    "chat_completion_source", "group_models", "sort_models",
    "openai_model", "claude_model", "openrouter_model",
    "openrouter_use_fallback", "openrouter_providers", "openrouter_quantizations",
    "openrouter_allow_fallbacks", "openrouter_middleout",
    "ai21_model", "mistralai_model", "cohere_model", "perplexity_model", "groq_model",
    "chutes_model", "siliconflow_model", "siliconflow_endpoint",
    "minimax_model", "minimax_endpoint", "electronhub_model",
    "nanogpt_model", "nanogpt_provider", "nanogpt_payg_override",
    "deepseek_model", "aimlapi_model", "xai_model",
    "pollinations_model", "pollinations_endpoint",
    "moonshot_model", "fireworks_model", "cometapi_model",
    "custom_model", "custom_url", "custom_include_body", "custom_exclude_body",
    "custom_include_headers", "custom_prompt_post_processing",
    "google_model", "vertexai_model", "zai_model", "zai_endpoint",
    "workers_ai_model", "workers_ai_account_id",
    "reverse_proxy", "proxy_password", "show_external_models", "bypass_status_check",
    "vertexai_auth_mode", "vertexai_region", "vertexai_express_project_id",
    "azure_base_url", "azure_deployment_name", "azure_api_version", "azure_openai_model",
}

CUSTOM_REQUIRED = [
    "identifier", "name", "enabled", "injection_position", "injection_depth",
    "injection_order", "role", "content", "system_prompt", "marker", "forbid_overrides",
]

MARKER_IDS = {"dialogueExamples", "chatHistory", "worldInfoAfter", "worldInfoBefore",
              "charDescription", "charPersonality", "scenario", "personaDescription"}

BUILTIN_IDS = MARKER_IDS | {"main", "nsfw", "jailbreak", "enhanceDefinitions"}

lines = []
err = []
warn = []


def bad(msg):
    err.append(msg)


def caution(msg):
    warn.append(msg)


raw = open(PRESET, encoding="utf-8").read()
try:
    d = json.loads(raw)
except Exception as e:
    bad("JSON 解析失败: %s" % e)
    open(LOG, "w", encoding="utf-8").write("\n".join(["[FAIL] " + m for m in err]))
    raise SystemExit(1)

lines.append("文件: %s (%d bytes, %d 行)" % (PRESET, len(raw.encode("utf-8")), raw.count("\n") + 1))

# 2 连接字段
hit = sorted(set(d) & CONNECTION_KEYS)
if hit:
    bad("含连接类字段（导入会弹敏感字段框）: %s" % ", ".join(hit))
else:
    lines.append("OK 无连接类字段")

# 顶层类型
num_keys = ["temperature", "frequency_penalty", "presence_penalty", "top_p", "top_k",
            "top_a", "min_p", "repetition_penalty", "openai_max_context", "openai_max_tokens",
            "names_behavior", "seed", "n", "tool_call_recurse_limit"]
for k in num_keys:
    if k not in d:
        bad("缺顶层键: %s" % k)
    elif not isinstance(d[k], (int, float)) or isinstance(d[k], bool):
        bad("顶层键类型错: %s = %r" % (k, d[k]))
bool_keys = ["max_context_unlocked", "use_sysprompt", "squash_system_messages", "media_inlining",
             "continue_prefill", "function_calling", "show_thoughts", "enable_web_search",
             "stream_openai", "request_images", "assistant_impersonation"]
for k in bool_keys:
    if k not in d:
        bad("缺顶层键: %s" % k)
    elif not isinstance(d[k], bool):
        bad("顶层布尔类型错: %s = %r" % (k, d[k]))

if d.get("openai_max_context", 0) - d.get("openai_max_tokens", 0) < 1000:
    bad("openai_max_context 减 openai_max_tokens 剩不到 1000，历史预算过低")

if d.get("continue_postfix") not in ("", " ", "\n", "\n\n"):
    bad("continue_postfix 不在枚举内: %r" % (d.get("continue_postfix"),))

if d.get("reasoning_effort") not in ("auto", "min", "low", "medium", "high", "max"):
    bad("reasoning_effort 不在枚举内: %r" % (d.get("reasoning_effort"),))

if d.get("names_behavior") not in (-1, 0, 1, 2):
    bad("names_behavior 不在枚举内: %r" % (d.get("names_behavior"),))

lines.append("OK 顶层键齐全、枚举值合法")

# 3/4 prompts
prompts = d.get("prompts") or []
ids = [p.get("identifier") for p in prompts]
if len(ids) != len(set(ids)):
    dup = [i for i in set(ids) if ids.count(i) > 1]
    bad("prompts 里 identifier 重复: %s" % dup)

for p in prompts:
    ident = p.get("identifier")
    if ident in MARKER_IDS:
        if p.get("content"):
            bad("marker 条目不该有 content: %s" % ident)
        if set(p) - {"identifier", "name", "system_prompt", "marker"}:
            caution("marker 条目带了多余字段: %s -> %s" % (ident, sorted(p)))
        continue
    if ident in ("main", "nsfw", "jailbreak", "enhanceDefinitions"):
        if not p.get("system_prompt"):
            bad("内置条目 system_prompt 应为 true: %s" % ident)
        if not isinstance(p.get("content"), str):
            bad("内置条目缺 content: %s" % ident)
        continue
    # 自定义条目
    miss = [k for k in CUSTOM_REQUIRED if k not in p]
    if miss:
        bad("自定义条目缺字段 %s: %s" % (miss, ident))
    if p.get("system_prompt") is not False:
        bad("自定义条目 system_prompt 必须为 false: %s" % ident)
    if p.get("marker"):
        bad("自定义条目 marker 必须为 false: %s" % ident)
    if p.get("injection_position") not in (0, 1):
        bad("injection_position 非法: %s = %r" % (ident, p.get("injection_position")))
    if p.get("role") not in ("system", "user", "assistant"):
        bad("role 非法: %s = %r" % (ident, p.get("role")))
    if not isinstance(p.get("content"), str):
        bad("content 必须是字符串: %s" % ident)

n_custom = len([i for i in ids if i not in BUILTIN_IDS])
n_empty = len([p for p in prompts if p.get("identifier") not in BUILTIN_IDS and p.get("content") == ""])
lines.append("OK prompts 共 %d 条（内置 %d / 自定义 %d，其中空正文分区标题 %d）"
             % (len(prompts), len(prompts) - n_custom, n_custom, n_empty))

# 5 prompt_order
orders = d.get("prompt_order") or []
by_cid = {}
for grp in orders:
    cid = str(grp.get("character_id"))
    if cid in by_cid:
        bad("prompt_order 里 character_id 重复: %s" % cid)
    by_cid[cid] = grp.get("order") or []

if "100001" not in by_cid:
    bad("缺 character_id=100001 组（这是 ST 1.19.0 真正生效的组）")
if "100000" not in by_cid:
    caution("缺 character_id=100000 组（非必需，但社区多数预设会写）")

for cid, order in sorted(by_cid.items()):
    listed = [e.get("identifier") for e in order]
    ghost = [i for i in listed if i not in ids]
    if ghost:
        bad("character_id=%s 的 order 里有不存在的条目: %s" % (cid, ghost))
    not_listed = [i for i in ids if i not in listed]
    if not_listed:
        bad("character_id=%s 的 order 漏掉了条目: %s" % (cid, not_listed))
    if len(listed) != len(set(listed)):
        bad("character_id=%s 的 order 里有重复: %s" % (cid, [i for i in set(listed) if listed.count(i) > 1]))
    on = [e["identifier"] for e in order if e.get("enabled")]
    lines.append("  分组 %s: %d 条，默认开 %d 条" % (cid, len(order), len(on)))

# 每组默认开的分区之内必须恰好一个（选一分区）
# 破甲两档不在此列：普通档常驻在 main/nsfw/jailbreak 里，严格档与预填充是可叠加的加码，不互斥
SELECT_ONE = ["yz_style_literary", "yz_style_cinema", "yz_style_webnovel", "yz_dialog_style"]
for fam in (["yz_pov_third", "yz_pov_second", "yz_pov_first"],
            ["yz_talk_normal", "yz_talk_less", "yz_talk_never"],
            ["yz_pace_normal", "yz_pace_slow", "yz_pace_fast"],
            ["yz_int_normal", "yz_int_high", "yz_int_dark"],
            ["yz_nsfw_soft", "yz_nsfw_plain", "yz_nsfw_intense"],
            ["yz_len_400", "yz_len_800", "yz_len_2000", "yz_len_free"],
            ["yz_mode_writing", "yz_mode_dialogue"],
            SELECT_ONE):
    for cid, order in by_cid.items():
        n = len([e for e in order if e.get("identifier") in fam and e.get("enabled")])
        if n > 1:
            bad("character_id=%s 的选一分区默认开了 %d 条: %s" % (cid, n, fam))
        elif n == 0:
            caution("character_id=%s 的选一分区一条都没开: %s" % (cid, fam[0]))

# 8 注释宏配对 & setvar/getvar
import re
for p in prompts:
    c = p.get("content") or ""
    if c.count("{{//}}") != c.count("{{///}}"):
        bad("多行注释宏没配平: %s" % p.get("identifier"))
    for m in re.finditer(r"\{\{getvar::([^}:]+)", c):
        key = m.group(1).strip()
        if not any(("{{setvar::" + key) in (q.get("content") or "") for q in prompts):
            bad("getvar 没有对应 setvar: %s（出现在 %s）" % (key, p.get("identifier")))

lines.append("OK 注释宏配平、变量宏配对")

# 10 正文里自建的结构标签必须配对（曾漏过一次闭标签写成 </output_disclosure>）
for p in prompts:
    c = p.get("content") or ""
    stack = []
    broken = []
    for m in re.finditer(r"</?([a-zA-Z_][a-zA-Z0-9_]*)>", c):
        name = m.group(1)
        if m.group(0).startswith("</"):
            if stack and stack[-1] == name:
                stack.pop()
            else:
                broken.append("多余的 </%s>" % name)
        else:
            stack.append(name)
    if stack:
        broken.append("未闭合: %s" % stack)
    if broken:
        bad("标签不配对 %s: %s" % (p.get("identifier"), "、".join(broken)))
if not any("标签不配对" in e for e in err):
    lines.append("OK 正文标签全部配对")

# 9 预填充条目位置
for p in prompts:
    if p.get("identifier") == "yz_jb_prefill":
        if p.get("role") != "assistant":
            bad("预填充条目 role 必须为 assistant")
        if p.get("injection_position") != 1 or p.get("injection_depth") != 0:
            bad("预填充条目应为 injection_position=1 / injection_depth=0，实为 %r/%r"
                % (p.get("injection_position"), p.get("injection_depth")))
        if p.get("enabled"):
            caution("预填充条目默认是开的（设计上应默认关）")

# 正文非空的自定义条目数量统计
sizes = [(p["identifier"], len(p.get("content") or "")) for p in prompts
         if p.get("identifier") not in BUILTIN_IDS and p.get("content")]
sizes.sort(key=lambda x: -x[1])
lines.append("最长的 5 条自定义正文: " + ", ".join("%s=%d" % (i, n) for i, n in sizes[:5]))
lines.append("全部自定义正文合计 %d 字" % sum(n for _i, n in sizes))

# ---- 汇总 ----
out = []
out.append("=" * 60)
out.append("预设结构自检")
out.append("=" * 60)
out += lines
out.append("")
if warn:
    out.append("[WARN] %d 条" % len(warn))
    out += ["  - " + w for w in warn]
    out.append("")
if err:
    out.append("[FAIL] %d 条" % len(err))
    out += ["  - " + e for e in err]
    out.append("")
    out.append("结论：不通过")
else:
    out.append("结论：通过（%d 条警告）" % len(warn))

open(LOG, "w", encoding="utf-8").write("\n".join(out) + "\n")
print("check done: %d FAIL, %d WARN" % (len(err), len(warn)))
