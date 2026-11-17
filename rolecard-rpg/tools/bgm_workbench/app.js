(() => {
  "use strict";

  const appState = {
    data: null,
    statusFilter: "all",
    categoryFilter: "all",
    searchText: "",
    poolCollapsed: false,
    uploadTargetSlotId: "__POOL__",
    activeAudioUrl: "",
    activeAudioTitle: "",
    activeAudioSub: "",
    activeAudioBadge: "",
  };

  const els = {
    statMatched: document.getElementById("statMatched"),
    statBatch1: document.getElementById("statBatch1"),
    statFallback: document.getElementById("statFallback"),
    statMissing: document.getElementById("statMissing"),
    progressMatched: document.getElementById("progressMatched"),
    progressFallback: document.getElementById("progressFallback"),
    saveIndicator: document.getElementById("saveIndicator"),
    poolCount: document.getElementById("poolCount"),
    poolDropzone: document.getElementById("poolDropzone"),
    poolList: document.getElementById("poolList"),
    poolFileInput: document.getElementById("poolFileInput"),
    slotFileInput: document.getElementById("slotFileInput"),
    btnTogglePool: document.getElementById("btnTogglePool"),
    searchInput: document.getElementById("searchInput"),
    categoryTabs: document.getElementById("categoryTabs"),
    slotsGrid: document.getElementById("slotsGrid"),
    playerBar: document.getElementById("playerBar"),
    playerPlayBtn: document.getElementById("playerPlayBtn"),
    playerBadge: document.getElementById("playerBadge"),
    playerTitle: document.getElementById("playerTitle"),
    playerSub: document.getElementById("playerSub"),
    playerCurTime: document.getElementById("playerCurTime"),
    playerDurTime: document.getElementById("playerDurTime"),
    playerSeek: document.getElementById("playerSeek"),
    playerLoopBtn: document.getElementById("playerLoopBtn"),
    playerVol: document.getElementById("playerVol"),
    audioEl: document.getElementById("audioEl"),
    modalBackdrop: document.getElementById("modalBackdrop"),
    modalTitle: document.getElementById("modalTitle"),
    modalBody: document.getElementById("modalBody"),
    modalClose: document.getElementById("modalClose"),
    btnAddSlot: document.getElementById("btnAddSlot"),
    btnOriginals: document.getElementById("btnOriginals"),
    btnExport: document.getElementById("btnExport"),
    btnOpenInbox: document.getElementById("btnOpenInbox"),
    btnStopServer: document.getElementById("btnStopServer"),
    btnTheme: document.getElementById("btnTheme"),
    toast: document.getElementById("toast"),
  };

  let toastTimer = null;

  function escapeHtml(value) {
    return String(value ?? "")
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;")
      .replace(/'/g, "&#39;");
  }

  function showToast(msg, durationMs = 2800) {
    els.toast.textContent = msg;
    els.toast.classList.remove("hidden");
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => els.toast.classList.add("hidden"), durationMs);
  }

  function setSavingState(text, ok = true) {
    els.saveIndicator.textContent = text;
    els.saveIndicator.style.color = ok ? "var(--good)" : "var(--warn)";
  }

  function formatBytes(bytes) {
    if (!Number.isFinite(bytes) || bytes <= 0) return "";
    if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(0)} KB`;
    return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
  }

  function formatTime(sec) {
    if (!Number.isFinite(sec) || sec < 0) return "--:--";
    const total = Math.floor(sec);
    const mins = Math.floor(total / 60);
    const secs = total % 60;
    return `${String(mins).padStart(2, "0")}:${String(secs).padStart(2, "0")}`;
  }

  function getOriginalMap() {
    const map = {};
    for (const item of appState.data?.original_tracks || []) {
      map[item.id] = item;
    }
    return map;
  }

  function getAllSlots() {
    const base = appState.data?.slots || [];
    const custom = appState.data?.custom_slots || [];
    return [...base, ...custom];
  }

  function getSlotEffectiveMode(slot) {
    const st = appState.data?.slot_states?.[slot.id] || {};
    const files = appState.data?.files || {};
    const validIds = (st.file_ids || []).filter((fid) => files[fid]);
    if (st.mode === "matched" && validIds.length > 0) return "matched";
    if (st.mode === "fallback_original" && st.fallback_original_id) return "fallback_original";
    if (st.mode === "skipped") return "skipped";
    return "missing";
  }

  async function apiGetState() {
    const resp = await fetch("/api/state", { cache: "no-store" });
    const json = await resp.json();
    if (!resp.ok || !json.ok) throw new Error(json.error || "加载状态失败");
    appState.data = json.state;
    renderAll();
  }

  async function apiMutate(payload) {
    setSavingState("保存中...", false);
    const resp = await fetch("/api/mutate", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(payload),
    });
    const json = await resp.json();
    if (!resp.ok || !json.ok) {
      setSavingState("保存失败", false);
      throw new Error(json.error || "操作失败");
    }
    appState.data = json.state;
    setSavingState("已自动保存到硬盘", true);
    renderAll();
    return json;
  }

  async function uploadFilesToSlot(fileList, slotId) {
    const files = Array.from(fileList || []).filter((f) => f && f.size > 0);
    if (!files.length) return;
    let uploaded = 0;
    for (const file of files) {
      uploaded += 1;
      setSavingState(`正在导入 ${uploaded}/${files.length}...`, false);
      const url = `/api/upload?slot_id=${encodeURIComponent(slotId)}&filename=${encodeURIComponent(file.name)}`;
      const resp = await fetch(url, {
        method: "POST",
        headers: { "X-File-Name": encodeURIComponent(file.name) },
        body: file,
      });
      const json = await resp.json();
      if (!resp.ok || !json.ok) {
        setSavingState("导入失败", false);
        showToast(`${file.name} 导入失败：${json.error || "未知错误"}`, 4200);
        return;
      }
      appState.data = json.state;
    }
    setSavingState("已自动保存到硬盘", true);
    renderAll();
    const targetLabel = slotId === "__POOL__" ? "音频暂存池" : `板块 ${slotId}`;
    showToast(`已成功匹配 ${uploaded} 首音频到 ${targetLabel}`);
  }

  function renderStats() {
    const stats = appState.data?.stats;
    if (!stats) return;
    els.statMatched.textContent = `${stats.matched_slots} / ${stats.total_slots}`;
    els.statBatch1.textContent = `${stats.batch1_done} / ${stats.batch1_total}`;
    els.statFallback.textContent = String(stats.fallback_slots);
    els.statMissing.textContent = String(stats.missing_slots);

    const total = Math.max(1, stats.total_slots);
    els.progressMatched.style.width = `${(stats.matched_slots / total) * 100}%`;
    els.progressFallback.style.width = `${(stats.fallback_slots / total) * 100}%`;
  }

  function getFileSlotUsageMap() {
    const usage = {};
    for (const slot of getAllSlots()) {
      const st = appState.data?.slot_states?.[slot.id];
      if (!st) continue;
      for (const fid of st.file_ids || []) {
        (usage[fid] ||= []).push(slot.id);
      }
    }
    return usage;
  }

  function renderPool() {
    const files = Object.values(appState.data?.files || {});
    const usage = getFileSlotUsageMap();
    els.poolCount.textContent = String(files.length);
    els.poolDropzone.classList.toggle("collapsed", appState.poolCollapsed);

    if (!files.length) {
      els.poolList.innerHTML = `<div class="pool-empty">还没有拖入本地音频 —— 把下载好的 .mp3 / .ogg / .wav / .flac 直接拖到这里，或拖到下方任意板块卡片上</div>`;
      return;
    }

    const sorted = [...files].sort((a, b) => {
      const ua = (usage[a.file_id] || []).length;
      const ub = (usage[b.file_id] || []).length;
      if ((ua === 0) !== (ub === 0)) return ua === 0 ? -1 : 1;
      return (b.uploaded_at || "").localeCompare(a.uploaded_at || "");
    });

    els.poolList.innerHTML = sorted
      .map((meta) => {
        const usedIn = usage[meta.file_id] || [];
        const isUnassigned = usedIn.length === 0;
        const isPlaying = appState.activeAudioUrl === meta.audio_url && !els.audioEl.paused;
        const usedText = isUnassigned ? "未分配 · 可拖走" : `已配 ${usedIn.join(", ")}`;
        const title = meta.display_title || meta.original_filename;
        return `
          <div class="pool-chip ${isUnassigned ? "unassigned" : ""}" draggable="true" data-pool-file-id="${escapeHtml(meta.file_id)}" title="按住拖到下方任意板块卡片即可绑定；点击▶可试听">
            <button type="button" class="play-btn ${isPlaying ? "playing" : ""}" data-play-url="${escapeHtml(meta.audio_url)}" data-play-title="${escapeHtml(title)}" data-play-sub="${escapeHtml(meta.original_filename)}" data-play-badge="已上传">${isPlaying ? "❚❚" : "▶"}</button>
            <span class="pool-chip-title">${escapeHtml(title)}</span>
            <span class="pool-chip-used">${escapeHtml(usedText)}</span>
            <button type="button" class="btn btn-sm btn-ghost btn-danger-text" data-delete-file="${escapeHtml(meta.file_id)}" title="从工作台与本地接收目录中删除此文件">✕</button>
          </div>
        `;
      })
      .join("");
  }

  function renderCategoryTabs() {
    const cats = appState.data?.categories || [];
    const customSlots = appState.data?.custom_slots || [];
    const allSlots = getAllSlots();

    const countMissing = (catId) =>
      allSlots.filter((s) => (catId === "all" || s.category === catId) && getSlotEffectiveMode(s) === "missing").length;

    const tabs = [
      { id: "all", label: `全部分类 (${allSlots.length} · 缺 ${countMissing("all")})` },
      ...cats.map((c) => ({
        id: c.id,
        label: `${c.short_name} (${c.count} · 缺 ${countMissing(c.id)})`,
      })),
    ];
    if (customSlots.length > 0) {
      tabs.push({ id: "CUSTOM", label: `自定义补充 (${customSlots.length})` });
    }

    els.categoryTabs.innerHTML = tabs
      .map(
        (t) => `<button class="chip ${appState.categoryFilter === t.id ? "active" : ""}" data-cat="${escapeHtml(t.id)}" type="button">${escapeHtml(t.label)}</button>`
      )
      .join("");
  }

  function matchesFilter(slot) {
    if (appState.categoryFilter !== "all" && slot.category !== appState.categoryFilter) {
      return false;
    }
    const mode = getSlotEffectiveMode(slot);
    if (appState.statusFilter === "missing" && mode !== "missing") return false;
    if (appState.statusFilter === "batch1" && !slot.batch1) return false;
    if (appState.statusFilter === "matched" && mode !== "matched") return false;
    if (appState.statusFilter === "fallback" && mode !== "fallback_original") return false;

    const q = appState.searchText.trim().toLowerCase();
    if (!q) return true;

    const st = appState.data?.slot_states?.[slot.id] || {};
    const files = appState.data?.files || {};
    const trackNames = (st.file_ids || [])
      .map((fid) => files[fid])
      .filter(Boolean)
      .map((m) => `${m.display_title} ${m.original_filename} ${m.source_credit}`)
      .join(" ");

    const haystack = `${slot.id} ${slot.name} ${slot.scene_desc} ${slot.style_hint} ${slot.priority} ${st.slot_note || ""} ${trackNames}`.toLowerCase();
    return haystack.includes(q);
  }

  function renderSlotTracksHtml(slot, st) {
    const files = appState.data?.files || {};
    const fileIds = (st.file_ids || []).filter((fid) => files[fid]);
    if (!fileIds.length) return "";
    const primaryId = st.primary_file_id || fileIds[0];

    return `<div class="tracks-list">${fileIds
      .map((fid) => {
        const meta = files[fid];
        const isPrimary = fid === primaryId;
        const isPlaying = appState.activeAudioUrl === meta.audio_url && !els.audioEl.paused;
        const durText = meta.duration_seconds ? formatTime(meta.duration_seconds) : "";
        const infoParts = [meta.original_filename, meta.ext.replace(".", "").toUpperCase(), durText, formatBytes(meta.bytes)].filter(Boolean);
        return `
          <div class="track-box ${isPrimary ? "is-primary" : ""}">
            <div class="track-head">
              <button type="button" class="play-btn ${isPlaying ? "playing" : ""}" data-play-url="${escapeHtml(meta.audio_url)}" data-play-title="${escapeHtml(meta.display_title || meta.original_filename)}" data-play-sub="${escapeHtml(slot.id + " · " + slot.name)}" data-play-badge="已配新曲">${isPlaying ? "❚❚" : "▶"}</button>
              <div class="track-name-wrap">
                <div class="track-file-sub">${escapeHtml(infoParts.join(" · "))}</div>
              </div>
              ${isPrimary ? `<span class="mini-badge good">首选</span>` : `<button type="button" class="btn btn-sm btn-ghost" data-set-primary="${escapeHtml(slot.id)}" data-file-id="${escapeHtml(fid)}">设为主用</button>`}
              <button type="button" class="btn btn-sm btn-ghost btn-danger-text" data-unassign-slot="${escapeHtml(slot.id)}" data-file-id="${escapeHtml(fid)}">移出</button>
            </div>
            <div class="track-inputs">
              <input class="inline-input" type="text" value="${escapeHtml(meta.display_title || "")}" placeholder="曲目显示名称" data-file-meta="${escapeHtml(fid)}" data-field="display_title" />
              <input class="inline-input" type="text" value="${escapeHtml(meta.source_credit || "")}" placeholder="出处 / 作者 / 版权备注（可选）" data-file-meta="${escapeHtml(fid)}" data-field="source_credit" />
            </div>
          </div>
        `;
      })
      .join("")}</div>`;
  }

  function renderSlots() {
    const originals = getOriginalMap();
    const visible = getAllSlots().filter(matchesFilter);

    if (!visible.length) {
      els.slotsGrid.innerHTML = `<div class="empty-state">当前筛选条件下没有匹配到板块，试试切换“全部”或清空搜索词。</div>`;
      return;
    }

    els.slotsGrid.innerHTML = visible
      .map((slot) => {
        const mode = getSlotEffectiveMode(slot);
        const st = appState.data?.slot_states?.[slot.id] || {};
        const cardClass =
          mode === "matched"
            ? "is-matched"
            : mode === "fallback_original"
            ? "is-fallback"
            : mode === "skipped"
            ? "is-skipped"
            : "";

        let statusBadge = `<span class="mini-badge">待寻找</span>`;
        if (mode === "matched") {
          const cnt = (st.file_ids || []).filter((id) => appState.data?.files?.[id]).length;
          statusBadge = `<span class="mini-badge good">已配 ${cnt} 首</span>`;
        } else if (mode === "fallback_original") {
          statusBadge = `<span class="mini-badge warn">暂用原卡</span>`;
        } else if (mode === "skipped") {
          statusBadge = `<span class="mini-badge">暂跳过</span>`;
        }

        let fallbackBanner = "";
        if (mode === "fallback_original") {
          const orig = originals[st.fallback_original_id];
          const label = orig ? `${orig.title}（${orig.id}）` : st.fallback_original_id;
          fallbackBanner = `
            <div class="fallback-banner">
              <span>暂用原卡：<strong>${escapeHtml(label)}</strong></span>
              <div class="drop-actions">
                ${orig?.audio_url ? `<button type="button" class="btn btn-sm btn-ghost" data-play-url="${escapeHtml(orig.audio_url)}" data-play-title="${escapeHtml(orig.title)}" data-play-sub="${escapeHtml(orig.role)}" data-play-badge="原卡">试听</button>` : ""}
                <button type="button" class="btn btn-sm btn-ghost" data-clear-mode="${escapeHtml(slot.id)}">改回待找</button>
              </div>
            </div>
          `;
        }

        return `
          <article class="slot-card ${cardClass}" data-slot-id="${escapeHtml(slot.id)}">
            <div class="slot-top">
              <div class="slot-badges">
                <span class="slot-id">${escapeHtml(slot.id)}</span>
                ${slot.batch1 ? `<span class="mini-badge batch1">第一批重点</span>` : ""}
                <span class="mini-badge">${escapeHtml(slot.priority || "")}</span>
                ${statusBadge}
              </div>
              ${slot.category === "CUSTOM" ? `<button type="button" class="btn btn-sm btn-ghost btn-danger-text" data-del-custom="${escapeHtml(slot.id)}">删板块</button>` : ""}
            </div>

            <h3 class="slot-title">${escapeHtml(slot.name)}</h3>

            <div class="slot-meta">
              <div><strong>用途：</strong>${escapeHtml(slot.scene_desc)}</div>
              <div><strong>曲风建议：</strong>${escapeHtml(slot.style_hint)}</div>
              <div><strong>循环要求：</strong>${escapeHtml(slot.loop_req)}</div>
            </div>

            ${renderSlotTracksHtml(slot, st)}
            ${fallbackBanner}

            <div class="drop-hint">
              <span>把音乐拖到本卡片任意位置即可配对</span>
              <div class="drop-actions">
                <button type="button" class="btn btn-sm" data-pick-file="${escapeHtml(slot.id)}">选本地文件</button>
                <button type="button" class="btn btn-sm btn-ghost" data-pick-pool="${escapeHtml(slot.id)}">从已传池选</button>
                <button type="button" class="btn btn-sm btn-ghost" data-pick-orig="${escapeHtml(slot.id)}">暂用原卡</button>
                ${
                  mode === "skipped"
                    ? `<button type="button" class="btn btn-sm btn-ghost" data-clear-mode="${escapeHtml(slot.id)}">恢复待找</button>`
                    : mode === "missing"
                    ? `<button type="button" class="btn btn-sm btn-ghost" data-skip-slot="${escapeHtml(slot.id)}">暂跳过</button>`
                    : ""
                }
              </div>
            </div>

            <input class="inline-input" type="text" value="${escapeHtml(st.slot_note || "")}" placeholder="给 AI / 自己的备注（如：前奏 8 秒后才进高潮、需要裁剪循环等）" data-slot-note="${escapeHtml(slot.id)}" />
          </article>
        `;
      })
      .join("");
  }

  function renderAll() {
    renderStats();
    renderPool();
    renderCategoryTabs();
    renderSlots();
    syncPlayButtonsUi();
  }

  function playTrack(url, title, sub, badge) {
    if (!url) return;
    if (appState.activeAudioUrl === url) {
      if (els.audioEl.paused) {
        els.audioEl.play().catch(() => {});
      } else {
        els.audioEl.pause();
      }
      return;
    }
    appState.activeAudioUrl = url;
    appState.activeAudioTitle = title || "未命名音频";
    appState.activeAudioSub = sub || "";
    appState.activeAudioBadge = badge || "BGM";

    els.playerBar.classList.remove("hidden");
    els.playerBadge.textContent = appState.activeAudioBadge;
    els.playerTitle.textContent = appState.activeAudioTitle;
    els.playerSub.textContent = appState.activeAudioSub;
    els.playerSeek.value = "0";
    els.playerCurTime.textContent = "00:00";
    els.playerDurTime.textContent = "--:--";

    els.audioEl.src = url;
    els.audioEl.play().catch((err) => {
      showToast(`无法直接播放此格式，可能需要先转码：${err?.message || ""}`, 3500);
    });
    syncPlayButtonsUi();
  }

  function syncPlayButtonsUi() {
    const playingUrl = els.audioEl.paused ? "" : appState.activeAudioUrl;
    els.playerPlayBtn.textContent = els.audioEl.paused ? "▶" : "❚❚";
    document.querySelectorAll("[data-play-url]").forEach((btn) => {
      const match = playingUrl && btn.getAttribute("data-play-url") === playingUrl;
      btn.classList.toggle("playing", match);
      if (btn.classList.contains("play-btn")) {
        btn.textContent = match ? "❚❚" : "▶";
      }
    });
  }

  function openModal(title, html) {
    els.modalTitle.textContent = title;
    els.modalBody.innerHTML = html;
    els.modalBackdrop.classList.remove("hidden");
  }

  function closeModal() {
    els.modalBackdrop.classList.add("hidden");
    els.modalBody.innerHTML = "";
  }

  function openPoolPickerModal(slotId) {
    const files = Object.values(appState.data?.files || {});
    if (!files.length) {
      showToast("暂存池还没有文件，先拖几首音乐进来吧！");
      return;
    }
    const usage = getFileSlotUsageMap();
    const rows = files
      .map((meta) => {
        const used = (usage[meta.file_id] || []).join(", ") || "尚未分配";
        const title = meta.display_title || meta.original_filename;
        return `
          <div class="list-row">
            <div>
              <strong>${escapeHtml(title)}</strong>
              <div class="track-file-sub">${escapeHtml(meta.original_filename)} · 已分配：${escapeHtml(used)}</div>
            </div>
            <div class="drop-actions">
              <button type="button" class="btn btn-sm btn-ghost" data-play-url="${escapeHtml(meta.audio_url)}" data-play-title="${escapeHtml(title)}" data-play-sub="${escapeHtml(meta.original_filename)}" data-play-badge="已上传">试听</button>
              <button type="button" class="btn btn-sm btn-accent" data-modal-assign-slot="${escapeHtml(slotId)}" data-modal-file-id="${escapeHtml(meta.file_id)}">绑到此板块</button>
            </div>
          </div>
        `;
      })
      .join("");
    openModal(`从已上传音频池分配到 ${slotId}`, rows);
  }

  function openOriginalsModal(targetSlotId = "") {
    const originals = appState.data?.original_tracks || [];
    const slot = getAllSlots().find((s) => s.id === targetSlotId);
    const recId = slot?.recommended_original_fallback || "";

    const trackRows = originals
      .map((orig) => {
        const isRec = recId && orig.id === recId;
        return `
          <div class="list-row" style="${isRec ? "border-color: var(--border-strong);" : ""}">
            <div>
              <strong>${escapeHtml(orig.title)}</strong>
              ${isRec ? `<span class="mini-badge batch1">文档推荐暂代</span>` : ""}
              <div class="track-file-sub">${escapeHtml(orig.artist)} · ${escapeHtml(orig.role)} · ${formatTime(orig.duration_seconds)}</div>
            </div>
            <div class="drop-actions">
              ${orig.audio_url ? `<button type="button" class="btn btn-sm btn-ghost" data-play-url="${escapeHtml(orig.audio_url)}" data-play-title="${escapeHtml(orig.title)}" data-play-sub="${escapeHtml(orig.role)}" data-play-badge="原卡">试听</button>` : ""}
              ${targetSlotId ? `<button type="button" class="btn btn-sm btn-accent" data-modal-fallback-slot="${escapeHtml(targetSlotId)}" data-modal-orig-id="${escapeHtml(orig.id)}">设为暂用</button>` : ""}
            </div>
          </div>
        `;
      })
      .join("");

    let extraHtml = "";
    if (!targetSlotId) {
      const c2 = appState.data?.covered_events_c2 || [];
      extraHtml = `
        <h4 style="margin: 12px 0 4px;">现有曲库可良好承接的代表事件（无需重复寻曲，直接复用原卡/地区曲）</h4>
        ${c2
          .map(
            (row) => `<div class="list-row"><span>${escapeHtml(row.event)}</span><code>${escapeHtml(row.track_title)}</code></div>`
          )
          .join("")}
      `;
    }

    openModal(
      targetSlotId ? `为 ${targetSlotId} 选择暂用原卡曲目` : "原卡已有 14 首 BGM 试听与复用范围",
      trackRows + extraHtml
    );
  }

  async function openExportModal() {
    const resp = await fetch("/api/export-md", { cache: "no-store" });
    const json = await resp.json();
    const md = json.markdown || "";
    const state = appState.data || {};
    openModal(
      "已匹配清单总览（AI 直接读取这些路径）",
      `
        <div class="slot-meta">
          <div><strong>JSON 权威索引：</strong><code>${escapeHtml(state.assignments_path_rel || "")}</code></div>
          <div><strong>音频文件仓库：</strong><code>${escapeHtml(state.inbox_dir_rel || "")}/files/</code></div>
        </div>
        <textarea id="exportTextarea" class="export-pre" readonly>${escapeHtml(md)}</textarea>
        <div class="drop-actions" style="justify-content:flex-end;">
          <button id="btnCopyExport" type="button" class="btn btn-accent">一键复制全部清单</button>
        </div>
      `
    );
  }

  function openAddSlotModal() {
    openModal(
      "新增自定义音乐板块",
      `
        <label>板块名称（必填）
          <input id="newSlotName" class="inline-input" type="text" placeholder="例：开场手书（2:19） / 某隐藏Boss" />
        </label>
        <label>场景说明
          <input id="newSlotDesc" class="inline-input" type="text" placeholder="说明什么时候播这首" />
        </label>
        <label>风格 / 乐器建议
          <input id="newSlotHint" class="inline-input" type="text" placeholder="例：弦乐、空灵女声、节奏渐快" />
        </label>
        <div class="drop-actions" style="justify-content:flex-end; margin-top:6px;">
          <button id="btnConfirmAddSlot" type="button" class="btn btn-accent">确认创建</button>
        </div>
      `
    );
  }

  function bindGlobalEvents() {
    // Prevent accidental tab navigation when dropping outside dropzones.
    window.addEventListener("dragover", (e) => e.preventDefault());
    window.addEventListener("drop", (e) => e.preventDefault());

    // Pool dropzone events
    els.poolDropzone.addEventListener("dragover", (e) => {
      e.preventDefault();
      els.poolDropzone.classList.add("drag-over");
    });
    els.poolDropzone.addEventListener("dragleave", () => {
      els.poolDropzone.classList.remove("drag-over");
    });
    els.poolDropzone.addEventListener("drop", (e) => {
      e.preventDefault();
      els.poolDropzone.classList.remove("drag-over");
      if (e.dataTransfer?.files?.length) {
        uploadFilesToSlot(e.dataTransfer.files, "__POOL__");
      }
    });

    // Drag start on pool chips
    document.addEventListener("dragstart", (e) => {
      const chip = e.target.closest("[data-pool-file-id]");
      if (!chip) return;
      e.dataTransfer.setData("application/x-aethera-file-id", chip.getAttribute("data-pool-file-id"));
      e.dataTransfer.effectAllowed = "copyLink";
    });

    // Slot card dropzone events (delegated)
    els.slotsGrid.addEventListener("dragover", (e) => {
      const card = e.target.closest(".slot-card[data-slot-id]");
      if (!card) return;
      e.preventDefault();
      card.classList.add("drag-over");
    });
    els.slotsGrid.addEventListener("dragleave", (e) => {
      const card = e.target.closest(".slot-card[data-slot-id]");
      if (!card || card.contains(e.relatedTarget)) return;
      card.classList.remove("drag-over");
    });
    els.slotsGrid.addEventListener("drop", async (e) => {
      const card = e.target.closest(".slot-card[data-slot-id]");
      if (!card) return;
      e.preventDefault();
      card.classList.remove("drag-over");
      const slotId = card.getAttribute("data-slot-id");
      const poolFileId = e.dataTransfer?.getData("application/x-aethera-file-id");
      if (poolFileId) {
        try {
          await apiMutate({ action: "assign", slot_id: slotId, file_id: poolFileId, make_primary: true });
          showToast(`已将曲目分配到 ${slotId}`);
        } catch (err) {
          showToast(err.message);
        }
        return;
      }
      if (e.dataTransfer?.files?.length) {
        await uploadFilesToSlot(e.dataTransfer.files, slotId);
      }
    });

    // Global click delegation
    document.addEventListener("click", async (e) => {
      const target = e.target.closest("button");
      if (!target) return;

      if (target.dataset.status) {
        appState.statusFilter = target.dataset.status;
        document.querySelectorAll("[data-status]").forEach((btn) =>
          btn.classList.toggle("active", btn.dataset.status === appState.statusFilter)
        );
        renderSlots();
        return;
      }

      if (target.dataset.cat) {
        appState.categoryFilter = target.dataset.cat;
        renderCategoryTabs();
        renderSlots();
        return;
      }

      if (target.dataset.playUrl) {
        playTrack(
          target.dataset.playUrl,
          target.dataset.playTitle,
          target.dataset.playSub,
          target.dataset.playBadge
        );
        return;
      }

      if (target.dataset.pickFile) {
        appState.uploadTargetSlotId = target.dataset.pickFile;
        els.slotFileInput.value = "";
        els.slotFileInput.click();
        return;
      }

      if (target.dataset.pickPool) {
        openPoolPickerModal(target.dataset.pickPool);
        return;
      }

      if (target.dataset.pickOrig) {
        openOriginalsModal(target.dataset.pickOrig);
        return;
      }

      if (target.dataset.setPrimary) {
        await apiMutate({
          action: "set_primary",
          slot_id: target.dataset.setPrimary,
          file_id: target.dataset.fileId,
        });
        return;
      }

      if (target.dataset.unassignSlot) {
        await apiMutate({
          action: "unassign",
          slot_id: target.dataset.unassignSlot,
          file_id: target.dataset.fileId,
        });
        return;
      }

      if (target.dataset.skipSlot) {
        await apiMutate({ action: "set_slot_mode", slot_id: target.dataset.skipSlot, mode: "skipped" });
        return;
      }

      if (target.dataset.clearMode) {
        await apiMutate({ action: "set_slot_mode", slot_id: target.dataset.clearMode, mode: "missing" });
        return;
      }

      if (target.dataset.deleteFile) {
        if (confirm("确定彻底删除这个已上传的音频文件吗？（已绑定它的板块也会同步解除）")) {
          await apiMutate({ action: "delete_file", file_id: target.dataset.deleteFile });
          showToast("已删除音频文件");
        }
        return;
      }

      if (target.dataset.delCustom) {
        if (confirm(`确定删除自定义板块 ${target.dataset.delCustom} 吗？`)) {
          await apiMutate({ action: "delete_custom_slot", slot_id: target.dataset.delCustom });
        }
        return;
      }

      if (target.dataset.modalAssignSlot) {
        await apiMutate({
          action: "assign",
          slot_id: target.dataset.modalAssignSlot,
          file_id: target.dataset.modalFileId,
          make_primary: true,
        });
        closeModal();
        showToast(`已分配到 ${target.dataset.modalAssignSlot}`);
        return;
      }

      if (target.dataset.modalFallbackSlot) {
        await apiMutate({
          action: "set_slot_mode",
          slot_id: target.dataset.modalFallbackSlot,
          mode: "fallback_original",
          fallback_original_id: target.dataset.modalOrigId,
        });
        closeModal();
        showToast(`已设为暂用原卡曲目`);
        return;
      }

      if (target.id === "btnCopyExport") {
        const area = document.getElementById("exportTextarea");
        try {
          await navigator.clipboard.writeText(area.value);
          showToast("已复制清单到剪贴板");
        } catch {
          area.select();
          document.execCommand("copy");
          showToast("已复制清单");
        }
        return;
      }

      if (target.id === "btnConfirmAddSlot") {
        const name = document.getElementById("newSlotName").value.trim();
        const scene_desc = document.getElementById("newSlotDesc").value.trim();
        const style_hint = document.getElementById("newSlotHint").value.trim();
        if (!name) {
          showToast("请先填板块名称");
          return;
        }
        await apiMutate({ action: "add_custom_slot", name, scene_desc, style_hint });
        closeModal();
        showToast(`已新增板块：${name}`);
      }
    });

    // Save edited fields cleanly on change (blur / Enter)
    document.addEventListener("change", async (e) => {
      const el = e.target;
      if (el.dataset.fileMeta) {
        await apiMutate({
          action: "update_file_meta",
          file_id: el.dataset.fileMeta,
          [el.dataset.field]: el.value,
        });
      } else if (el.dataset.slotNote) {
        await apiMutate({
          action: "update_slot_note",
          slot_id: el.dataset.slotNote,
          slot_note: el.value,
        });
      }
    });

    els.poolFileInput.addEventListener("change", (e) => {
      uploadFilesToSlot(e.target.files, "__POOL__");
      e.target.value = "";
    });
    els.slotFileInput.addEventListener("change", (e) => {
      uploadFilesToSlot(e.target.files, appState.uploadTargetSlotId || "__POOL__");
      e.target.value = "";
    });

    els.btnTogglePool.addEventListener("click", () => {
      appState.poolCollapsed = !appState.poolCollapsed;
      els.poolDropzone.classList.toggle("collapsed", appState.poolCollapsed);
    });

    els.searchInput.addEventListener("input", () => {
      appState.searchText = els.searchInput.value;
      renderSlots();
    });

    els.btnAddSlot.addEventListener("click", openAddSlotModal);
    els.btnOriginals.addEventListener("click", () => openOriginalsModal(""));
    els.btnExport.addEventListener("click", openExportModal);
    els.btnOpenInbox.addEventListener("click", async () => {
      const resp = await fetch("/api/open-inbox", { method: "POST" });
      const json = await resp.json();
      showToast(`目录：${json.inbox_dir_abs || ""}`, 3500);
    });
    els.btnStopServer.addEventListener("click", async () => {
      if (!confirm("停止本地后台服务？已经自动保存的文件不受影响，下次双击桌面图标即可重新打开。")) {
        return;
      }
      try {
        await fetch("/api/shutdown", { method: "POST" });
      } catch {}
      setSavingState("后台服务已停止", false);
      showToast("后台服务已安全停止；下次用桌面快捷图标随时再开。", 6000);
    });

    els.modalClose.addEventListener("click", closeModal);
    els.modalBackdrop.addEventListener("click", (e) => {
      if (e.target === els.modalBackdrop) closeModal();
    });

    // Theme toggle
    const savedTheme = localStorage.getItem("aethera-bgm-theme") || "night";
    document.documentElement.setAttribute("data-theme", savedTheme);
    els.btnTheme.textContent = savedTheme === "night" ? "☀" : "☾";
    els.btnTheme.addEventListener("click", () => {
      const next = document.documentElement.getAttribute("data-theme") === "night" ? "day" : "night";
      document.documentElement.setAttribute("data-theme", next);
      localStorage.setItem("aethera-bgm-theme", next);
      els.btnTheme.textContent = next === "night" ? "☀" : "☾";
    });

    // Audio player wiring
    els.audioEl.loop = true;
    els.audioEl.volume = Number(els.playerVol.value);

    els.playerPlayBtn.addEventListener("click", () => {
      if (!els.audioEl.src) return;
      if (els.audioEl.paused) {
        els.audioEl.play().catch(() => {});
      } else {
        els.audioEl.pause();
      }
    });

    els.playerLoopBtn.addEventListener("click", () => {
      els.audioEl.loop = !els.audioEl.loop;
      els.playerLoopBtn.textContent = `循环: ${els.audioEl.loop ? "开" : "关"}`;
      els.playerLoopBtn.classList.toggle("active", els.audioEl.loop);
    });

    els.playerVol.addEventListener("input", () => {
      els.audioEl.volume = Number(els.playerVol.value);
    });

    els.playerSeek.addEventListener("input", () => {
      if (Number.isFinite(els.audioEl.duration) && els.audioEl.duration > 0) {
        els.audioEl.currentTime = (Number(els.playerSeek.value) / 1000) * els.audioEl.duration;
      }
    });

    els.audioEl.addEventListener("play", syncPlayButtonsUi);
    els.audioEl.addEventListener("pause", syncPlayButtonsUi);
    els.audioEl.addEventListener("ended", syncPlayButtonsUi);
    els.audioEl.addEventListener("loadedmetadata", () => {
      els.playerDurTime.textContent = formatTime(els.audioEl.duration);
    });
    els.audioEl.addEventListener("timeupdate", () => {
      els.playerCurTime.textContent = formatTime(els.audioEl.currentTime);
      if (Number.isFinite(els.audioEl.duration) && els.audioEl.duration > 0) {
        els.playerSeek.value = String(Math.round((els.audioEl.currentTime / els.audioEl.duration) * 1000));
      }
    });
  }

  bindGlobalEvents();
  apiGetState().catch((err) => {
    setSavingState("连接工作台失败", false);
    showToast(err.message, 5000);
  });
})();
