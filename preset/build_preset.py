# -*- coding: utf-8 -*-
"""
白描回廊 v1.0 —— 预设生成器

只做"结构"，文字全在 preset_content.py。
跑法：python F:/sigil-circuit/preset/build_preset.py
产物：F:/sigil-circuit/preset/白描回廊 v1.0.json

结构依据（SillyTavern 1.19.0 源码，均已核对）：
- settingsToUpdate       public/scripts/openai.js:305
- onSettingsPresetChange public/scripts/openai.js:5020
- 装配顺序               public/scripts/openai.js:1181-1345
- Prompt 字段            public/scripts/PromptManager.js:127-195
- prompt_order 真生效组  public/scripts/openai.js:695-700 (dummyId=100001)
"""

import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import preset_content as C

PRESET_NAME = "白描回廊 v1.0"
OUT_PATH = os.path.join(HERE, PRESET_NAME + ".json")

# ---------------------------------------------------------------------------
# 内置 12 条的静态定义（与 Default.json 完全一致的形状）
# marker:true 的条目只写 identifier/name/system_prompt/marker，不带 role/content
# ---------------------------------------------------------------------------

MARKER_IDS = [
    ("dialogueExamples", "Chat Examples"),
    ("chatHistory", "Chat History"),
    ("worldInfoAfter", "World Info (after)"),
    ("worldInfoBefore", "World Info (before)"),
    ("charDescription", "Char Description"),
    ("charPersonality", "Char Personality"),
    ("scenario", "Scenario"),
    ("personaDescription", "Persona Description"),
]


def builtin_prompts():
    """按 Default.json 的原顺序产出 12 条内置条目，其中 4 条被我改写。"""
    return [
        {
            "name": "Main Prompt",
            "system_prompt": True,
            "role": "system",
            "content": C.MAIN_PROMPT,
            "identifier": "main",
        },
        {
            "name": "Auxiliary Prompt",
            "system_prompt": True,
            "role": "system",
            "content": C.NSFW_PROMPT,
            "identifier": "nsfw",
        },
        {"name": "Chat Examples", "system_prompt": True, "marker": True, "identifier": "dialogueExamples"},
        {
            "name": "Post-History Instructions",
            "system_prompt": True,
            "role": "system",
            "content": C.JAILBREAK_PROMPT,
            "identifier": "jailbreak",
        },
        {"name": "Chat History", "system_prompt": True, "marker": True, "identifier": "chatHistory"},
        {"name": "World Info (after)", "system_prompt": True, "marker": True, "identifier": "worldInfoAfter"},
        {"name": "World Info (before)", "system_prompt": True, "marker": True, "identifier": "worldInfoBefore"},
        {
            "name": "Enhance Definitions",
            "system_prompt": True,
            "role": "system",
            "content": C.ENHANCE_DEFINITIONS,
            "identifier": "enhanceDefinitions",
        },
        {"name": "Char Description", "system_prompt": True, "marker": True, "identifier": "charDescription"},
        {"name": "Char Personality", "system_prompt": True, "marker": True, "identifier": "charPersonality"},
        {"name": "Scenario", "system_prompt": True, "marker": True, "identifier": "scenario"},
        {"name": "Persona Description", "system_prompt": True, "marker": True, "identifier": "personaDescription"},
    ]


# ---------------------------------------------------------------------------
# 需要改成"绝对位置注入"(injection_position=1) 的条目
# id -> (injection_position, injection_depth)
# 破限·预填充要贴在最新一条消息之后，所以 depth=0
# ---------------------------------------------------------------------------
POSITION_OVERRIDES = {
    "yz_jb_prefill": (1, 0),
}


def custom_prompts():
    """把 preset_content.CUSTOM_PROMPTS 里的五元组转成 SillyTavern 的 prompt 对象。"""
    out = []
    for identifier, name, role, enabled, content in C.CUSTOM_PROMPTS:
        pos, depth = POSITION_OVERRIDES.get(identifier, (0, 4))
        out.append({
            "identifier": identifier,
            "name": name,
            "enabled": enabled,
            "injection_position": pos,
            "injection_depth": depth,
            "injection_order": 100,
            "role": role,
            "content": content,
            "system_prompt": False,   # 必须是 False，否则会被当成受保护的系统提示词
            "marker": False,
            "forbid_overrides": False,
        })
    return out


# 分区标题（正文为空）也是 CUSTOM_PROMPTS 的一部分，它们不参与 true/false 判断


def build_order():
    """返回一组 prompt_order。

    100000 与 100001 都写全，条目集合完全一致（100001 才是真生效组）。
    顺序沿用 Default.json 的原序，自定义条目统一排在 jailbreak 之后——
    因为装配时 nsfw/jailbreak 会被强制提到最前（openai.js:1232-1239），
    自定义条目之间只保留彼此的相对顺序。
    """
    seq = [
        ("main", True),
        ("worldInfoBefore", True),
        ("personaDescription", True),
        ("charDescription", True),
        ("charPersonality", True),
        ("scenario", True),
        ("enhanceDefinitions", False),
        ("nsfw", True),
        ("worldInfoAfter", True),
        ("dialogueExamples", True),
        ("chatHistory", True),
        ("jailbreak", True),
    ]
    for identifier, _name, _role, enabled, _content in C.CUSTOM_PROMPTS:
        seq.append((identifier, enabled))
    return [{"identifier": i, "enabled": e} for i, e in seq]


def build_settings():
    """顶层设置。只写 isConnection=false 的键；一个连接字段都不带。"""
    return {
        # ---- 采样 ----
        "temperature": 1.0,
        "frequency_penalty": 0,
        "presence_penalty": 0,
        "top_p": 0.95,
        "top_k": 0,
        "top_a": 0,
        "min_p": 0,
        "repetition_penalty": 1,
        # ---- 上下文 ----
        "max_context_unlocked": True,
        "openai_max_context": 128000,
        "openai_max_tokens": 16000,
        # ---- 空回复兜底 ----
        "names_behavior": 0,
        "send_if_empty": "（继续）",
        # ---- 文本格式 ----
        "wi_format": "{0}",
        "scenario_format": "{{scenario}}",
        "personality_format": "{{personality}}",
        # ---- 系统提示词处理 ----
        "use_sysprompt": False,
        "squash_system_messages": True,
        "media_inlining": True,
        "inline_image_quality": "auto",
        # ---- 续写 ----
        "continue_prefill": False,
        "continue_postfix": " ",
        "continue_nudge_prompt": "[Continue your last message without repeating its original content.]",
        "group_nudge_prompt": "[Write the next reply only as {{char}}.]",
        "new_chat_prompt": "[Start a new Chat]",
        "new_group_chat_prompt": "[Start a new group chat. Group members: {{group}}]",
        "new_example_chat_prompt": "[Example Chat]",
        "impersonation_prompt": "[Write your next reply from the point of view of {{user}}, using the chat history so far as a guideline for the writing style of {{user}}. Don't write as {{char}} or system. Don't describe actions of {{char}}.]",
        # ---- 工具/推理 ----
        "function_calling": False,
        "tool_call_recurse_limit": 5,
        "show_thoughts": True,
        "reasoning_effort": "auto",
        "verbosity": "auto",
        "enable_web_search": False,
        # ---- 杂项 ----
        "bias_preset_selected": "Default (none)",
        "stream_openai": True,
        "seed": -1,
        "n": 1,
        "request_images": False,
        "request_image_aspect_ratio": "",
        "request_image_resolution": "",
    }


def main():
    prompts = builtin_prompts() + custom_prompts()
    preset = build_settings()
    preset["prompts"] = prompts
    preset["prompt_order"] = [
        {"character_id": 100000, "order": build_order()},
        {"character_id": 100001, "order": build_order()},
    ]
    preset["assistant_prefill"] = ""
    preset["assistant_impersonation"] = False

    with open(OUT_PATH, "w", encoding="utf-8", newline="\n") as f:
        json.dump(preset, f, ensure_ascii=False, indent=4)
        f.write("\n")

    n_on = sum(1 for p in prompts if p.get("enabled"))
    return "OK %s | prompts=%d (custom=%d) | enabled=%d | bytes=%d" % (
        OUT_PATH, len(prompts), len(prompts) - 12, n_on, os.path.getsize(OUT_PATH))


if __name__ == "__main__":
    with open(os.path.join(HERE, "_build.log"), "w", encoding="utf-8") as f:
        f.write(main() + "\n")
