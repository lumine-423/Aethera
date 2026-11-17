# -*- coding: utf-8 -*-
"""把工作区的 Hotaru 预设同步进正在运行的 SillyTavern。

为什么要动两处：
  ST 的「当前生效预设」存在 data/default-user/settings.json 的 oai_settings 里，
  它不会因为 OpenAI Settings 目录下的文件变了就自动重读。
  所以既要覆盖目录文件（下次在 UI 里切预设时用），也要改 oai_settings（这次立刻生效）。

跑法：python F:/sigil-circuit/preset/sync_to_st.py
"""
import json, os, sys, shutil, datetime, urllib.request, http.cookiejar

sys.stdout.reconfigure(encoding='utf-8')

SRC = r"F:\sigil-circuit\preset\【Hotaru预设】v1.0.json"
ST_USER = r"F:\sillytavern\SillyTavern\data\default-user"
ST_PRESETS = os.path.join(ST_USER, "OpenAI Settings")
ST_FILE = os.path.join(ST_PRESETS, "【Hotaru预设】v1.0.json")
ST_SETTINGS = os.path.join(ST_USER, "settings.json")
BASE = "http://127.0.0.1:8000"
ts = datetime.datetime.now().strftime('%Y%m%d_%H%M%S')


def api_get_settings():
    """服务端回读，确认 ST 真的认了这份内容。"""
    cj = http.cookiejar.CookieJar()
    op = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(cj))
    tok = json.loads(op.open(BASE + "/csrf-token", timeout=5).read())['token']
    req = urllib.request.Request(BASE + "/api/settings/get", data=b'{}', method='POST')
    req.add_header("Content-Type", "application/json")
    req.add_header("X-CSRF-Token", tok)
    d = json.loads(op.open(req, timeout=10).read().decode("utf-8"))
    s = json.loads(d['settings']) if isinstance(d.get('settings'), str) else d
    return s.get('oai_settings') or {}


def main():
    newp = json.load(open(SRC, encoding="utf-8"))
    print(f"源文件: {len(newp['prompts'])} 条 prompts, {os.path.getsize(SRC)} bytes")

    # 1) 覆盖预设目录文件
    if not os.path.isdir(ST_PRESETS):
        print(f"!! 找不到预设目录 {ST_PRESETS}")
        return 1
    if os.path.exists(ST_FILE):
        bak = ST_FILE + ".bak_" + ts
        shutil.copy2(ST_FILE, bak)
        print("旧预设备份 ->", os.path.basename(bak))
    shutil.copy2(SRC, ST_FILE)
    print("已覆盖目录文件 ->", os.path.basename(ST_FILE))

    # 2) 改 settings.json 里的 oai_settings
    bak2 = ST_SETTINGS + ".bak_" + ts
    shutil.copy2(ST_SETTINGS, bak2)
    print("旧 settings 备份 ->", os.path.basename(bak2))

    d = json.load(open(ST_SETTINGS, encoding="utf-8"))
    o = d.get('oai_settings') or {}
    before = len(o.get('prompts') or [])
    o['prompts'] = newp['prompts']
    o['prompt_order'] = newp['prompt_order']
    added = []
    for k, v in newp.items():
        if k not in o:
            o[k] = v
            added.append(k)
    d['oai_settings'] = o

    tmp = ST_SETTINGS + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(d, f, ensure_ascii=False, indent=2)
    os.replace(tmp, ST_SETTINGS)
    print(f"oai_settings: {before} 条 -> {len(o['prompts'])} 条" + (f"（补齐键 {added}）" if added else ""))

    # 3) 服务端回读
    try:
        live = api_get_settings()
        ids = [p.get('identifier') for p in (live.get('prompts') or [])]
        armor = [i for i in ids if 'armor' in (i or '')]
        print(f"服务端回读: {len(ids)} 条 | 破甲 {len(armor)} 条 | 因律神 {'✓' if any('【因律神】' in (p.get('content') or '') for p in live.get('prompts') or []) else '✗'}")
        if len(ids) != len(newp['prompts']):
            print("!! 服务端条数与源文件不一致，可能需要重启 ST")
            return 2
    except Exception as e:
        print("服务端回读跳过（ST 没开？）:", e)

    print("\n完成。浏览器 Ctrl+Shift+R 强制刷新，预设下拉重新点一次【Hotaru预设】v1.0 即可看到。")
    return 0


if __name__ == "__main__":
    sys.exit(main())