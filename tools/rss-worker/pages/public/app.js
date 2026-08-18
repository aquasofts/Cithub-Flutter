const state = {
  payload: null,
  items: [],
  mode: "loading"
};

const elements = {
  list: document.querySelector("#feedList"),
  template: document.querySelector("#articleTemplate"),
  statusDot: document.querySelector("#statusDot"),
  statusText: document.querySelector("#statusText"),
  metaText: document.querySelector("#metaText"),
  reloadButton: document.querySelector("#reloadButton"),
  searchInput: document.querySelector("#searchInput"),
  sourceSelect: document.querySelector("#sourceSelect"),
  emptyState: document.querySelector("#emptyState")
};

async function loadFeeds() {
  setLoading(true);
  try {
    // 永远只访问当前 Pages 域名，不请求 workers.dev。
    const payload = await fetchJsonWithTimeout("/api/feeds?limit=500", 10000);
    usePayload(payload);
  } catch (error) {
    console.error(error);
    setStatus(
      "error",
      "Pages API 加载失败",
      "请检查 Service Binding，或等待 Worker Cron 生成首次缓存"
    );
    state.items = [];
    render();
  } finally {
    setLoading(false);
  }
}

function usePayload(payload) {
  if (!payload || !Array.isArray(payload.items)) {
    throw new Error("返回的数据格式不正确");
  }

  state.payload = payload;
  state.items = payload.items;
  state.mode = payload.stale ? "stale" : "ready";
  rebuildSourceOptions(payload.sources || [], payload.items);

  const generated = payload.generatedAt
    ? new Date(payload.generatedAt).toLocaleString("zh-CN", { hour12: false })
    : "未知时间";

  if (payload.stale) {
    setStatus(
      "warn",
      "Pages 已读取缓存（部分来源可能过期）",
      `共 ${payload.items.length} 条 · 更新于 ${generated}`
    );
  } else {
    setStatus(
      "ok",
      "Pages 同域 API 在线",
      `共 ${payload.items.length} 条 · 更新于 ${generated}`
    );
  }
  render();
}

function render() {
  const query = elements.searchInput.value.trim().toLowerCase();
  const source = elements.sourceSelect.value;
  const filtered = state.items.filter((item) => {
    if (source && item.sourceId !== source) return false;
    if (!query) return true;
    return `${item.title || ""} ${item.summary || ""} ${item.author || ""}`
      .toLowerCase()
      .includes(query);
  });

  elements.list.replaceChildren();
  elements.emptyState.hidden = filtered.length !== 0;

  for (const item of filtered) {
    const fragment = elements.template.content.cloneNode(true);
    const article = fragment.querySelector("article");
    const title = fragment.querySelector(".title");
    const summary = fragment.querySelector(".summary");
    const sourceNode = fragment.querySelector(".source");
    const time = fragment.querySelector("time");
    const cover = fragment.querySelector(".cover");

    title.textContent = item.title || "无标题";
    title.href = safeHttpUrl(item.link) || "#";
    summary.textContent = item.summary || "暂无摘要";
    sourceNode.textContent = item.sourceName || item.sourceId || "未知来源";

    if (item.publishedAt) {
      const date = new Date(item.publishedAt);
      time.dateTime = date.toISOString();
      time.textContent = date.toLocaleString("zh-CN", { hour12: false });
    } else {
      time.textContent = "时间未知";
    }

    const image = safeHttpUrl(item.image);
    if (image) {
      cover.src = image;
      cover.alt = `${item.title || "文章"}的配图`;
      cover.hidden = false;
      cover.addEventListener("error", () => {
        cover.remove();
        article.classList.add("no-cover");
      });
    }

    elements.list.append(fragment);
  }
}

function rebuildSourceOptions(sources, items) {
  const current = elements.sourceSelect.value;
  const sourceMap = new Map();
  for (const source of sources) sourceMap.set(source.id, source.name);
  for (const item of items) sourceMap.set(item.sourceId, item.sourceName || item.sourceId);

  elements.sourceSelect.replaceChildren(new Option("全部来源", ""));
  for (const [id, name] of sourceMap) {
    elements.sourceSelect.add(new Option(name, id));
  }
  if (sourceMap.has(current)) elements.sourceSelect.value = current;
}

async function fetchJsonWithTimeout(url, timeoutMs) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    const response = await fetch(url, {
      signal: controller.signal,
      headers: { accept: "application/json" },
      cache: "no-store"
    });

    const payload = await response.json().catch(() => null);
    if (!response.ok) {
      const message = payload?.message || payload?.error || `HTTP ${response.status}`;
      throw new Error(message);
    }
    return payload;
  } finally {
    clearTimeout(timer);
  }
}

function safeHttpUrl(value) {
  if (!value) return "";
  try {
    const url = new URL(value, location.href);
    return ["http:", "https:"].includes(url.protocol) ? url.href : "";
  } catch {
    return "";
  }
}

function setStatus(type, title, meta) {
  elements.statusDot.className = `status-dot ${type}`;
  elements.statusText.textContent = title;
  elements.metaText.textContent = meta;
}

function setLoading(loading) {
  elements.reloadButton.disabled = loading;
  elements.reloadButton.textContent = loading ? "加载中…" : "重新加载";
  if (loading) setStatus("", "正在加载…", "从 Pages 同域 /api/feeds 读取");
}

elements.reloadButton.addEventListener("click", loadFeeds);
elements.searchInput.addEventListener("input", render);
elements.sourceSelect.addEventListener("change", render);
loadFeeds();
