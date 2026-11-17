# Hotaru 预设与游戏内置数据库联动规范（v1.0）

> 定位：配套 [【Hotaru预设】v1.0.json](file:///F:/sigil-circuit/preset/%E3%80%90Hotaru%E9%A2%84%E8%AE%BE%E8%AE%BE%E3%80%91v1.0.json)（V8）的**独立程序数据库设计基准与上下文拼装合同**。  
> 用途：明确“游戏内置数据库记什么、如何从预设小总结 `<sumUp>` 自动入库、以及单独对话（看板/舰桥）如何按数据库＋相关世界书精准拼包、不发全量聊天历史”。

---

## 一、三方职责边界（避免双头记账）

| 模块 | 管什么 | 不管什么 | 现状 |
| :--- | :--- | :--- | :--- |
| **Hotaru 预设**（主线模式） | 生成正文 + `<sumUp>`（7 项历时同步字段）+ `<pose>` + `<choices>`；或可选 `<UpdateVariable>` | 不直接操作 SQLite，不管理跨存档读写 | 已对齐（`66` 条，`21` 条正则，默认开启 `41` 条） |
| **Hotaru 预设**（单人模式：`🗣️ 联动-角色单独对话模式`） | 生成 `120～450` 字贴身口语对白 + 轻量 `<dbNote>` | 不写 1500 字四层大章，不越权读取未提供的他人秘密 | 已内置在预设 `#60` 位（默认关，单人对话请求时由程序或用户开启） |
| **游戏数据库引擎**（独立应用端，推荐 SQLite） | **唯一进度真源**：校验写入 7 张表、按消息 ID 幂等覆写/回滚、按角色过滤知情边界、为单人对话拼装精简上下文 | 不让 AI 直接写 SQL 或任意篡改库存/任务结算 | **设计定稿于本文**；待后续游戏桌面后端落地接入 |

**双写冲突硬规定（必须遵守）**：
- 若游戏某张卡同时启用原卡 MVU（如《艾瑟拉》现有的 `/主角组`、`/角色组`、`/剧情事件`），必须明确归属：**MVU 管数值与物品清单**（魔力、好感度、物品、魔法、讨伐数、事件列表），**`<sumUp>` 专管历时事件流与在场知情表**（时间、地点、在场人员、可见度、核心何事、伏笔线索），`【变动】` 仅在无 MVU 字段覆盖时作为文本补充记录，禁止两套同时改写同一数值。

---

## 二、游戏内置数据库表结构（7 张表 · SQLite DDL 草案）

```sql
-- 数据库版本与元数据
CREATE TABLE IF NOT EXISTS db_meta (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL
);
-- 固定写入: schema_version = '1'

-- 1. 存档分支与主角实时锚点表（对应现有 /主角组）
CREATE TABLE IF NOT EXISTS player_state (
  branch_id TEXT PRIMARY KEY,                -- 存档/分支唯一标识（隔离周目与读档分支）
  origin_key TEXT NOT NULL,                  -- 出身开局 key
  player_name TEXT NOT NULL,
  player_bio TEXT DEFAULT '',                -- ≤20字当前简述
  current_time TEXT NOT NULL,                -- 如 '1015年2月1日 18:30'（随最新 sumUp 同步）
  current_location TEXT NOT NULL,            -- 国家·地点，如 '塞蕾特公国·中央学院'
  mana_current INTEGER DEFAULT 0,
  mana_max INTEGER DEFAULT 0,
  party_present_json TEXT DEFAULT '[]',      -- 主线此刻身边同行角色 ID 数组
  last_synced_msg_id INTEGER DEFAULT -1,     -- 已入库的最新主线消息 ID
  updated_at TEXT NOT NULL
);

-- 2. 主线时间线与 <sumUp> 同步纪要表（核心联动表）
CREATE TABLE IF NOT EXISTS timeline_summaries (
  entry_id INTEGER PRIMARY KEY AUTOINCREMENT,
  branch_id TEXT NOT NULL,
  source_msg_id INTEGER NOT NULL,            -- 主线消息 ID（重roll/删楼回档幂等清理键）
  swipe_index INTEGER NOT NULL DEFAULT 0,    -- 对应候选序号
  seq_order INTEGER NOT NULL,                -- 递增顺序号
  story_date TEXT NOT NULL,                  -- 来自 <sumUp> 【时间】 如 '1015年2月1日 傍晚'
  location TEXT NOT NULL,                    -- 来自 <sumUp> 【地点】 如 '塞蕾特公国·中央学院旧校场'
  participants_json TEXT NOT NULL,           -- 由 【角色】 映射为标准 character_id 数组，如 '["merlin","rin"]'
  visibility TEXT NOT NULL CHECK(visibility IN ('scene_only','world_public')),
                                             -- 来自 <sumUp> 【可见】：'在场私密'->scene_only, '公开传闻'->world_public
  summary_text TEXT NOT NULL,                -- 来自 <sumUp> 【何事】
  clues_text TEXT DEFAULT '',                -- 来自 <sumUp> 【线索】
  changes_text TEXT DEFAULT '',              -- 来自 <sumUp> 【变动】
  archive_tier TEXT NOT NULL DEFAULT 'active' CHECK(archive_tier IN ('active','compressed')),
  created_at TEXT NOT NULL,
  UNIQUE(branch_id, source_msg_id)
);
CREATE INDEX IF NOT EXISTS idx_timeline_branch_seq ON timeline_summaries(branch_id, seq_order);

-- 3. 角色档案与关系动态表（一人一行、切人严格隔离；对应现有 /角色组）
CREATE TABLE IF NOT EXISTS character_states (
  branch_id TEXT NOT NULL,
  character_id TEXT NOT NULL,                -- 规范英文 ID，如 'merlin'（映射 character_profiles.json）
  display_name TEXT NOT NULL,                -- 如 '梅林'
  is_met INTEGER NOT NULL DEFAULT 0,         -- 0=未正式结识，1=已结识
  last_seen_date TEXT DEFAULT '',
  last_known_location TEXT DEFAULT '',       -- 最后已知所在地，防“跨大陆瞬间贴脸”
  affection INTEGER NOT NULL DEFAULT 0 CHECK(affection BETWEEN 0 AND 100),
  erotic_val INTEGER NOT NULL DEFAULT 0 CHECK(erotic_val BETWEEN 0 AND 100),
  current_form TEXT NOT NULL DEFAULT '日常', -- '日常' / '解放'
  relationship_stance TEXT DEFAULT '',       -- 一句话关系与心结定调（单人对话定调语气核心！）
  dynamic_bio TEXT DEFAULT '',               -- 重大经历后修订的一句话现状
  active_promises TEXT DEFAULT '',           -- 眼下和主角的待办约定
  unlocked_traits_json TEXT DEFAULT '[]',
  PRIMARY KEY (branch_id, character_id)
);

-- 4. 角色私有记忆与知情边界表（彻底解决“隔空读心”与“切人串记忆”）
CREATE TABLE IF NOT EXISTS character_knowledge_facts (
  fact_id INTEGER PRIMARY KEY AUTOINCREMENT,
  branch_id TEXT NOT NULL,
  character_id TEXT NOT NULL,                -- 归属该角色的私有记忆
  source_type TEXT NOT NULL CHECK(source_type IN ('main_witness','bridge_private','secret_known')),
  source_ref TEXT DEFAULT '',                -- 对应 source_msg_id 或 bridge chat_id 区间
  fact_date TEXT DEFAULT '',                 -- 发生时间，如 '1015年2月1日'
  fact_text TEXT NOT NULL,                   -- ≤40字客观事实
  is_shared_to_main INTEGER NOT NULL DEFAULT 0, -- 私聊产生的约定/事实是否同步回主线可见
  importance TEXT NOT NULL DEFAULT 'recent' CHECK(importance IN ('core','recent','resolved'))
);
CREATE INDEX IF NOT EXISTS idx_facts_char ON character_knowledge_facts(branch_id, character_id, importance);

-- 5. 游戏内看板/单独对话流水表（替代 talk_screen.gd 内存临时数组）
CREATE TABLE IF NOT EXISTS bridge_dialogues (
  chat_id INTEGER PRIMARY KEY AUTOINCREMENT,
  branch_id TEXT NOT NULL,
  character_id TEXT NOT NULL,                -- 按角色严格分区
  speaker TEXT NOT NULL CHECK(speaker IN ('me','them')),
  content TEXT NOT NULL,
  note_attitude TEXT DEFAULT '',             -- 从 <dbNote> 【态度】 提取
  note_memory TEXT DEFAULT '',               -- 从 <dbNote> 【记忆】 提取
  compressed_fact_id INTEGER DEFAULT NULL,   -- 超过最近窗口后压缩为一条私有记忆并标此字段
  created_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_bridge_char_id ON bridge_dialogues(branch_id, character_id, chat_id);

-- 6. 重要物品、信物与刻印/魔法表
CREATE TABLE IF NOT EXISTS inventory_and_sigils (
  record_id INTEGER PRIMARY KEY AUTOINCREMENT,
  branch_id TEXT NOT NULL,
  item_key TEXT NOT NULL,
  item_name TEXT NOT NULL,
  category TEXT NOT NULL CHECK(category IN ('key_item','sigil_artifact','material','magic')),
  quantity INTEGER NOT NULL DEFAULT 1,
  holder_scope TEXT NOT NULL DEFAULT 'hero', -- 'hero' | 'gifted:<character_id>' | 'consumed'
  meta_json TEXT DEFAULT '{}',               -- 如魔法的 {载体, 效果, 耗用} 或物品来源说明
  UNIQUE(branch_id, item_key, holder_scope)
);

-- 7. 剧情事件与全局公开局势表（对应现有 /剧情事件 与公共世界动态）
CREATE TABLE IF NOT EXISTS plot_events_and_world_flags (
  branch_id TEXT NOT NULL,
  flag_key TEXT NOT NULL,
  kind TEXT NOT NULL CHECK(kind IN ('plot_event','world_flag')),
  title TEXT NOT NULL,
  status TEXT NOT NULL CHECK(status IN ('active','completed','locked')),
  summary_short TEXT DEFAULT '',             -- ≤30字现况
  reward_settled INTEGER NOT NULL DEFAULT 0, -- 防事件重播重复发奖/加好感锁
  PRIMARY KEY (branch_id, flag_key)
);
```

---

## 三、预设 `<sumUp>...</sumUp>` 入库解析与回滚契约

### 1. 主线输出映射关系（预设 `#55` / `#56`）

每轮主线正文结束后的 `<sumUp>` 固定包含这 7 行（均已通过前端美化正则 `R6` 兼容校验）：

| `<sumUp>` 行标签 | 示例值 | 入库目标表与字段 |
| :--- | :--- | :--- |
| `【时间】` | `1015年2月1日 傍晚` | `timeline_summaries.story_date` + `player_state.current_time` |
| `【地点】` | `塞蕾特公国·中央学院旧校场` | `timeline_summaries.location` + `player_state.current_location` + 参演角色 `last_known_location` |
| `【角色】` | `梅林，凛零` | 解析别名映射为 ID 数组存入 `timeline_summaries.participants_json`，置各人 `is_met=1`、`last_seen_date` |
| `【可见】` | `在场私密` / `公开传闻` | `scene_only` / `world_public`；为 `scene_only` 时，仅允许 `participants_json` 内角色在单独对话检索到本条 |
| `【何事】` | `梅林调试过热的铳枪冷却阀，凛零递来热咖啡。` | `timeline_summaries.summary_text` |
| `【线索】` | `天光输出偏高导致回填刻印片损耗加剧` | `timeline_summaries.clues_text` |
| `【变动】` | `约定明早核对账册；主角获得临时通行证×1` | `timeline_summaries.changes_text`（供确定性规则提炼或人工/脚本审核后更新约定与物品） |

### 2. 防重复 / 切分支 / 删楼规则
- **重新生成 / 切换 Swipe**：同一 `source_msg_id` 写入时直接按 `UNIQUE(branch_id, source_msg_id)` 事务级覆写旧行，再重算 `player_state` 最新指针，绝不连加两遍。
- **回档（`rewind_to(id)`）**：事务执行 `DELETE FROM timeline_summaries WHERE branch_id=? AND source_msg_id > ?`，关联清理 `source_ref > ?` 的 `character_knowledge_facts`。
- **分叉（`branch_from(id)`）**：整库按 `branch_id` 浅拷贝截止至该消息 `id` 的切片到新 `branch_id`，父子分支互不覆盖。

---

## 四、单独对话（看板/舰桥 `talk_screen.gd`）精准拼包流程

当玩家点开**某一名角色（设为 `target_char_id`，如 `merlin`）**发起单人对话时，程序端**不发送全量主线 `chatHistory`**，只按如下 4 步组装本次请求上下文：

1. **开启预设单人模式**：激活 [【Hotaru预设】v1.0.json](file:///F:/sigil-circuit/preset/%E3%80%90Hotaru%E9%A2%84%E8%AE%BE%E8%AE%BE%E3%80%91v1.0.json) 内置条目 **`🗣️ 联动-角色单独对话模式`**（`hotaru_opt_bridge_chat`）。篇幅约束自动切换为 `120～450 字` 生动口语交互，尾标由 `<sumUp><pose><choices>` 切换为轻量 `<dbNote>...</dbNote>`。
2. **筛选对应的世界书（最小必要集合）**：
   - 只注入 `target_char_id` 本人设定 + 其所属国家/当前所在地区条目 + 基础叙述规约；
   - **过滤门禁**：凡世界书中标记为高阶机密（如《艾瑟拉》里的七罪、七十二柱、龙种隐秘）而该角色 `character_knowledge_facts` 未持有的条目，**绝不带入该角色上下文**。
3. **从数据库抽取「仅属于这一幕」的结构化记忆（JSON/紧凑摘要块注入 `worldInfoAfter` 或对话前导）**：
   - **当前锚点**：`player_state` 的 `current_time`、`current_location`、`player_bio`；
   - **公开局势**：`plot_events_and_world_flags` 中 `status='active'` 或公开完结条；
   - **该角色现状**：`character_states` 中 `(branch_id, target_char_id)` 的 `affection`、`relationship_stance`、`active_promises`、`last_known_location`；
   - **经过过滤的主线记忆**：
     ```sql
     SELECT story_date, location, summary_text, clues_text
     FROM timeline_summaries
     WHERE branch_id = ?
       AND (visibility = 'world_public' OR participants_json LIKE '%"' || ? || '"%')
     ORDER BY seq_order DESC
     LIMIT 12;
     ```
   - **该角色私有记忆与持有关联物**：`character_knowledge_facts WHERE character_id = ?`（全部 `core` + 最近 `recent`）+ `inventory_and_sigils WHERE holder_scope IN ('hero', 'gifted:' || ?)`。
4. **附带近期单独对话窗口**：
   - 从 `bridge_dialogues WHERE branch_id=? AND character_id=?` 仅取**最近 `6～10` 条对话原文**。
   - 若某角色私聊超过窗口（例如 `12` 轮以上），将更早几句异步总结成一条 `source_type = 'bridge_private'` 写入 `character_knowledge_facts`，把原句子标上 `compressed_fact_id` 后移出实时发包窗口。
5. **对话回写与主线反馈**：
   - 收到回复后，游戏解析器抽取正文更新对话气泡，抽取 `<dbNote>` 中的 `【态度】` 与 `【记忆】` 更新该角色的 `relationship_stance` / 写入一条 `bridge_private` 记忆。只有当双方真正立下影响主线的明确契约、转赠物品或约定地点时，才将 `is_shared_to_main = 1` 暴露给主线推演。

---

## 五、当前工程落地差距清单（未来接入游戏时核对用）

1. [reply_protocol.json](file:///F:/sigil-circuit/rolecard-rpg/data/reply_protocol.json) 目前 `hidden_tags` 尚未列入 `sumUp`、`pose`、`choices`、`dbNote` —— 未来需要把这四个标签配进剥离/解析清单，以免游戏正文气泡露出原始 XML 标签。
2. [reply_parser.gd](file:///F:/sigil-circuit/rolecard-rpg/scripts/game/reply_parser.gd) 目前只解析 `<场景>/<在场>/<选项>/<插画>/<UpdateVariable>` —— 未来需新增 `<sumUp>` 与 `<dbNote>` 键值对抽取器并交给桌面后端写库。
3. [talk_screen.gd](file:///F:/sigil-circuit/rolecard-rpg/scripts/ui/screens/talk_screen.gd) 目前使用内存数组 `logs` 暂存私聊、右上角好感度读自 `Game.known()` —— 未来需改为读取 `bridge_dialogues` 与 `character_states` 快照。
