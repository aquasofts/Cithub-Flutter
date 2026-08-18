/**
 * Cloudflare Worker：RSS 聚合 + 图片/GIF 按需反代 + 10 小时缓存
 *
 * 用户只访问：
 *   https://cloudflare-rss-hub-pages.pages.dev
 *
 * 必需绑定：
 *   KV：RSS_CACHE
 *   Secret：ADMIN_TOKEN
 *
 * 可选变量：
 *   UPSTREAM_RSS_URL       上游总订阅 RSS 地址
 *   FETCH_TIMEOUT_MS       默认 20000
 *   MAX_TOTAL_ITEMS        默认 200
 *   CACHE_MAX_AGE_SECONDS  默认 4500
 */

const PUBLIC_BASE_URL =
  "https://cloudflare-rss-hub-pages.pages.dev";

/**
 * 没配置 UPSTREAM_RSS_URL 环境变量时，
 * 使用这里填写的 RSS 地址。
 */
const FALLBACK_UPSTREAM_RSS_URL =
  "请替换为完整的总订阅RSS地址";

const FEEDS = [
  {
    id: "wechat-all",
    name: "校园公众号合集",
    enabled: true,
  },
];

/**
 * 图片、GIF 等媒体缓存 10 小时。
 */
const MEDIA_CACHE_SECONDS =
  10 * 60 * 60;

/**
 * 只允许反代可信图片域名，
 * 避免接口成为任意代理。
 */
const MEDIA_ALLOWED_HOSTS = [
  "wechatrss.waytomaster.com",
  ".qpic.cn",
  ".qlogo.cn",
  "res.wx.qq.com",
];

const AGGREGATE_KEY =
  "rss:aggregate:lazy-media:v1";

const SOURCE_KEY_PREFIX =
  "rss:source:lazy-media:v1:";

const DEFAULT_FETCH_TIMEOUT_MS = 20000;
const DEFAULT_MAX_TOTAL_ITEMS = 200;
const DEFAULT_CACHE_MAX_AGE_SECONDS = 4500;

export default {
  async fetch(request, env, ctx) {
    return handleRequest(
      request,
      env,
      ctx,
    );
  },

  async scheduled(
    _controller,
    env,
    ctx,
  ) {
    ctx.waitUntil(
      refreshAllFeeds(env),
    );
  },
};

async function handleRequest(
  request,
  env,
  ctx,
) {
  const url =
    new URL(request.url);

  const publicHost =
    new URL(
      PUBLIC_BASE_URL,
    ).hostname;

  /**
   * 只允许 Pages 域名作为公开入口。
   *
   * 用户直接访问 Worker 的 workers.dev
   * 地址会返回 404。
   */
  if (url.hostname !== publicHost) {
    return new Response(
      "Not Found",
      {
        status: 404,
        headers: {
          "cache-control":
            "no-store",
        },
      },
    );
  }

  if (
    request.method === "OPTIONS"
  ) {
    return new Response(
      null,
      {
        status: 204,
        headers: corsHeaders(),
      },
    );
  }

  /**
   * 图片和 GIF 按需反代。
   *
   * 只有浏览器或 RSS 阅读器真正访问
   * /api/media 时才会拉取上游图片。
   */
  if (
    url.pathname === "/api/media"
  ) {
    return handleMediaProxy(
      request,
      ctx,
    );
  }

  if (!env.RSS_CACHE) {
    return jsonResponse(
      {
        error:
          "RSS_CACHE KV 尚未绑定",
      },
      500,
      noStoreHeaders(),
    );
  }

  if (
    url.pathname === "/" ||
    url.pathname === "/api"
  ) {
    return jsonResponse({
      name:
        "校园公众号 RSS 聚合",
      publicBaseUrl:
        PUBLIC_BASE_URL,
      mediaMode: "lazy",
      mediaCacheSeconds:
        MEDIA_CACHE_SECONDS,
      endpoints: {
        rss: "/api/rss.xml",
        feeds: "/api/feeds",
        sources: "/api/sources",
        health: "/api/health",
        refresh:
          "POST /api/admin/refresh",
      },
    });
  }

  if (
    url.pathname ===
    "/api/admin/refresh"
  ) {
    if (
      request.method !== "POST"
    ) {
      return jsonResponse(
        {
          error:
            "Method not allowed",
        },
        405,
        {
          ...noStoreHeaders(),
          allow: "POST",
        },
      );
    }

    if (
      !isAuthorized(
        request,
        env,
      )
    ) {
      return jsonResponse(
        {
          error: "Unauthorized",
        },
        401,
        noStoreHeaders(),
      );
    }

    const snapshot =
      await refreshAllFeeds(env);

    return jsonResponse(
      snapshotSummary(snapshot),
      200,
      noStoreHeaders(),
    );
  }

  const snapshot =
    await env.RSS_CACHE.get(
      AGGREGATE_KEY,
      "json",
    );

  if (
    url.pathname ===
    "/api/health"
  ) {
    return jsonResponse(
      {
        ok: Boolean(snapshot),
        cached: Boolean(snapshot),

        generatedAt:
          snapshot?.generatedAt ??
          null,

        stale: snapshot
          ? Boolean(
              snapshot.stale,
            ) ||
            isSnapshotExpired(
              snapshot,
              env,
            )
          : true,

        configuredSources:
          FEEDS.filter(
            (feed) =>
              feed.enabled !== false,
          ).length,

        totalItems:
          snapshot?.totalItems ?? 0,

        mediaCacheSeconds:
          MEDIA_CACHE_SECONDS,
      },
      snapshot ? 200 : 503,
      noStoreHeaders(),
    );
  }

  if (!snapshot) {
    return jsonResponse(
      {
        error:
          "RSS cache is empty",

        message:
          "请先调用 POST /api/admin/refresh，或等待 Cron 首次执行。",
      },
      503,
      noStoreHeaders(),
    );
  }

  if (
    url.pathname ===
    "/api/sources"
  ) {
    return jsonResponse({
      generatedAt:
        snapshot.generatedAt,

      stale:
        Boolean(
          snapshot.stale,
        ) ||
        isSnapshotExpired(
          snapshot,
          env,
        ),

      sources:
        snapshot.sources,
    });
  }

  if (
    url.pathname ===
      "/api/feeds" ||
    url.pathname ===
      "/api/feeds.json"
  ) {
    const filtered =
      filterSnapshot(
        snapshot,
        url.searchParams,
        env,
      );

    return jsonResponse({
      ...filtered,

      stale:
        Boolean(
          snapshot.stale,
        ) ||
        isSnapshotExpired(
          snapshot,
          env,
        ),
    });
  }

  if (
    url.pathname ===
    "/api/rss.xml"
  ) {
    const filtered =
      filterSnapshot(
        snapshot,
        url.searchParams,
        env,
      );

    return new Response(
      toMergedRss(filtered),
      {
        status: 200,
        headers: {
          ...corsHeaders(),

          "content-type":
            "application/rss+xml; charset=utf-8",

          "cache-control":
            "public, max-age=300",

          "x-content-type-options":
            "nosniff",
        },
      },
    );
  }

  return jsonResponse(
    {
      error: "Not found",
    },
    404,
    noStoreHeaders(),
  );
}

async function refreshAllFeeds(
  env,
) {
  const enabledFeeds =
    FEEDS.filter(
      (feed) =>
        feed.enabled !== false,
    );

  const results =
    await Promise.all(
      enabledFeeds.map(
        (feed) =>
          refreshSingleFeed(
            feed,
            env,
          ),
      ),
    );

  const maxTotal =
    readNumber(
      env.MAX_TOTAL_ITEMS,
      DEFAULT_MAX_TOTAL_ITEMS,
      1,
      1000,
    );

  const items =
    dedupeItems(
      results.flatMap(
        (source) =>
          source.items,
      ),
    )
      .sort(compareItems)
      .slice(0, maxTotal);

  const snapshot = {
    version: 1,

    mode:
      "raw-rss-with-lazy-media",

    generatedAt:
      new Date().toISOString(),

    stale:
      results.some(
        (source) =>
          source.stale,
      ),

    sourceCount:
      results.length,

    successfulSourceCount:
      results.filter(
        (source) =>
          !source.error,
      ).length,

    failedSourceCount:
      results.filter(
        (source) =>
          Boolean(
            source.error,
          ),
      ).length,

    totalItems:
      items.length,

    sources:
      results.map(
        ({
          items: _items,
          ...source
        }) => source,
      ),

    items,
  };

  await env.RSS_CACHE.put(
    AGGREGATE_KEY,
    JSON.stringify(snapshot),
    {
      expirationTtl:
        60 * 60 * 24 * 7,
    },
  );

  return snapshot;
}

async function refreshSingleFeed(
  feed,
  env,
) {
  const cacheKey =
    `${SOURCE_KEY_PREFIX}${feed.id}`;

  const previous =
    await env.RSS_CACHE.get(
      cacheKey,
      "json",
    );

  try {
    const upstreamUrl =
      resolveUpstreamRssUrl(
        env,
      );

    if (!upstreamUrl) {
      throw new Error(
        "尚未配置上游 RSS 地址。请设置 UPSTREAM_RSS_URL，或修改 FALLBACK_UPSTREAM_RSS_URL。",
      );
    }

    const timeoutMs =
      readNumber(
        env.FETCH_TIMEOUT_MS,
        DEFAULT_FETCH_TIMEOUT_MS,
        1000,
        60000,
      );

    const response =
      await fetchWithTimeout(
        upstreamUrl,
        timeoutMs,
        {
          headers: {
            accept:
              "application/rss+xml, application/xml, text/xml, */*;q=0.5",

            "user-agent":
              "Mozilla/5.0 (compatible; CampusRSSAggregator/1.0)",
          },

          redirect: "follow",
        },
      );

    if (!response.ok) {
      throw new Error(
        `上游 RSS 返回 HTTP ${response.status} ${response.statusText}`,
      );
    }

    const xml =
      await response.text();

    if (
      !/<rss\b/i.test(xml) ||
      !/<item\b/i.test(xml)
    ) {
      throw new Error(
        "上游内容不是包含 item 的 RSS 2.0 文档",
      );
    }

    const items =
      parseAndTransformRssItems(
        xml,
        feed,
      );

    const source = {
      id: feed.id,
      name: feed.name,

      publicUrl:
        `${PUBLIC_BASE_URL}/api/rss.xml`,

      fetchedAt:
        new Date().toISOString(),

      stale: false,
      error: null,

      itemCount:
        items.length,

      items,
    };

    await env.RSS_CACHE.put(
      cacheKey,
      JSON.stringify(source),
      {
        expirationTtl:
          60 * 60 * 24 * 7,
      },
    );

    return source;
  } catch (error) {
    const message =
      error instanceof Error
        ? error.message
        : String(error);

    if (previous) {
      return {
        ...previous,

        fetchedAt:
          new Date().toISOString(),

        stale: true,
        error: message,
      };
    }

    return {
      id: feed.id,
      name: feed.name,

      publicUrl:
        `${PUBLIC_BASE_URL}/api/rss.xml`,

      fetchedAt:
        new Date().toISOString(),

      stale: true,
      error: message,

      itemCount: 0,
      items: [],
    };
  }
}

function resolveUpstreamRssUrl(
  env,
) {
  const value =
    String(
      env.UPSTREAM_RSS_URL ||
        FALLBACK_UPSTREAM_RSS_URL ||
        "",
    ).trim();

  if (
    !value ||
    value.includes("请替换") ||
    value.includes(
      "example.com",
    )
  ) {
    return "";
  }

  try {
    const url =
      new URL(value);

    if (
      url.protocol !== "https:" &&
      url.protocol !== "http:"
    ) {
      return "";
    }

    return url.toString();
  } catch {
    return "";
  }
}

function parseAndTransformRssItems(
  xml,
  feed,
) {
  const rawItems =
    extractRawElements(
      xml,
      "item",
    );

  return rawItems
    .map(
      (rawItem) =>
        transformRawItem(
          rawItem,
          feed,
        ),
    )
    .filter(
      (item) =>
        Boolean(item.link),
    );
}

function transformRawItem(
  rawItem,
  feed,
) {
  const title =
    elementText(
      rawItem,
      "title",
    ) || "无标题";

  const link =
    firstNonEmpty(
      elementText(
        rawItem,
        "link",
      ),

      elementText(
        rawItem,
        "guid",
      ),
    );

  const guid =
    elementText(
      rawItem,
      "guid",
    ) || link;

  const publishedAt =
    normalizeDate(
      firstNonEmpty(
        elementText(
          rawItem,
          "pubDate",
        ),

        elementText(
          rawItem,
          "dc:date",
        ),

        elementText(
          rawItem,
          "date",
        ),
      ),
    );

  /**
   * 从标题前缀提取公众号名称。
   *
   * 例如：
   * [团聚长工程] 文章标题
   */
  const titlePublisher =
    extractPublisherFromTitle(
      title,
    );

  const existingPublisher =
    normalizePublisherName(
      firstNonEmpty(
        elementText(
          rawItem,
          "dc:creator",
        ),

        elementText(
          rawItem,
          "author",
        ),
      ),
    );

  const publisherNickname =
    titlePublisher ||
    existingPublisher ||
    "未知发布者";

  let transformed =
    rawItem;

  /**
   * 删除上游作者和 source。
   *
   * 防止上游总订阅账户名、
   * 私有订阅地址或 Token
   * 出现在最终 RSS。
   */
  transformed =
    removeElement(
      transformed,
      "dc:creator",
    );

  transformed =
    removeElement(
      transformed,
      "author",
    );

  transformed =
    removeElement(
      transformed,
      "source",
    );

  /**
   * 这里只改写资源地址。
   *
   * 此时不会访问任何图片，
   * 所以刷新 RSS 不会触发
   * 图片或 GIF 拉取。
   */
  transformed =
    rewriteMediaUrlsInMarkup(
      transformed,
      link ||
        PUBLIC_BASE_URL,
    );

  /**
   * 写入正确公众号昵称。
   */
  const metadata = [
    `  <dc:creator><![CDATA[${safeCdata(
      publisherNickname,
    )}]]></dc:creator>`,

    `  <source url="${escapeXmlAttribute(
      `${PUBLIC_BASE_URL}/api/rss.xml`,
    )}"><![CDATA[${safeCdata(
      publisherNickname,
    )}]]></source>`,
  ].join("\n");

  transformed =
    transformed.replace(
      /<\/item>\s*$/i,
      `${metadata}\n</item>`,
    );

  const rawContent =
    firstNonEmptyRaw(
      elementInnerRaw(
        transformed,
        "content:encoded",
      ),

      elementInnerRaw(
        transformed,
        "description",
      ),

      elementInnerRaw(
        transformed,
        "summary",
      ),
    );

  const contentHtml =
    unwrapCdataOnly(
      rawContent,
    );

  const image =
    firstProxyImageFromMarkup(
      transformed,
    );

  return {
    id: hashString(
      `${feed.id}|${link || guid || title}`,
    ),

    sourceId: feed.id,

    sourceName:
      publisherNickname,

    sourceFeedUrl:
      `${PUBLIC_BASE_URL}/api/rss.xml`,

    title,
    link,
    guid,
    publishedAt,

    author:
      publisherNickname,

    publisherNickname,

    summary:
      makePlainSummary(
        contentHtml,
      ),

    contentHtml,
    image,

    /**
     * 保存基本原样的 item XML。
     *
     * 只改：
     * - 图片资源地址
     * - 发布者字段
     * - source 字段
     */
    rawXml:
      transformed,
  };
}

function filterSnapshot(
  snapshot,
  params,
  env,
) {
  const source =
    (
      params.get("source") ||
      ""
    ).trim();

  const query =
    (
      params.get("q") ||
      ""
    )
      .trim()
      .toLowerCase();

  const limit =
    readNumber(
      params.get("limit"),

      readNumber(
        env.MAX_TOTAL_ITEMS,
        DEFAULT_MAX_TOTAL_ITEMS,
        1,
        1000,
      ),

      1,
      1000,
    );

  let items =
    snapshot.items;

  if (source) {
    items =
      items.filter(
        (item) =>
          item.sourceId ===
            source ||
          item.publisherNickname ===
            source,
      );
  }

  if (query) {
    items =
      items.filter(
        (item) =>
          [
            item.title,
            item.summary,
            item.publisherNickname,
          ]
            .filter(Boolean)
            .join(" ")
            .toLowerCase()
            .includes(query),
      );
  }

  items =
    items.slice(
      0,
      limit,
    );

  return {
    generatedAt:
      snapshot.generatedAt,

    sourceCount:
      snapshot.sourceCount,

    successfulSourceCount:
      snapshot.successfulSourceCount,

    failedSourceCount:
      snapshot.failedSourceCount,

    totalItems:
      items.length,

    sources:
      snapshot.sources,

    items,
  };
}

function toMergedRss(
  snapshot,
) {
  const itemsXml =
    snapshot.items
      .map(
        (item) =>
          item.rawXml,
      )
      .join("\n");

  return `<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0"
  xmlns:atom="http://www.w3.org/2005/Atom"
  xmlns:dc="http://purl.org/dc/elements/1.1/"
  xmlns:content="http://purl.org/rss/1.0/modules/content/"
  xmlns:media="http://search.yahoo.com/mrss/"
  xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd">
  <channel>
    <title>校园公众号合集</title>
    <link>${escapeXml(
      PUBLIC_BASE_URL,
    )}</link>
    <description>校园微信公众号原始内容聚合订阅</description>
    <language>zh-CN</language>
    <generator>Campus RSS Aggregator</generator>
    <lastBuildDate>${new Date(
      snapshot.generatedAt,
    ).toUTCString()}</lastBuildDate>
    <atom:link href="${escapeXmlAttribute(
      `${PUBLIC_BASE_URL}/api/rss.xml`,
    )}" rel="self" type="application/rss+xml" />
${itemsXml}
  </channel>
</rss>`;
}

async function handleMediaProxy(
  request,
  ctx,
) {
  if (
    request.method !== "GET" &&
    request.method !== "HEAD"
  ) {
    return new Response(
      "Method not allowed",
      {
        status: 405,

        headers: {
          allow: "GET, HEAD",

          "cache-control":
            "no-store",
        },
      },
    );
  }

  const requestUrl =
    new URL(request.url);

  const encodedSource =
    requestUrl.searchParams.get(
      "u",
    );

  if (!encodedSource) {
    return new Response(
      "缺少媒体地址",
      {
        status: 400,

        headers:
          noStoreHeaders(),
      },
    );
  }

  let sourceUrl;

  try {
    sourceUrl =
      new URL(
        decodeBase64Url(
          encodedSource,
        ),
      );
  } catch {
    return new Response(
      "媒体地址无效",
      {
        status: 400,

        headers:
          noStoreHeaders(),
      },
    );
  }

  if (
    !isAllowedMediaUrl(
      sourceUrl,
    )
  ) {
    return new Response(
      "不允许代理该媒体来源",
      {
        status: 403,

        headers:
          noStoreHeaders(),
      },
    );
  }

  /**
   * 固定使用 Pages 地址作为缓存键。
   */
  const canonicalUrl =
    `${PUBLIC_BASE_URL}/api/media?u=${encodeURIComponent(
      encodedSource,
    )}`;

  const cacheKey =
    new Request(
      canonicalUrl,
      {
        method: "GET",
      },
    );

  const cache =
    caches.default;

  /**
   * 先查缓存。
   *
   * 命中时不会请求上游图片。
   */
  const cached =
    await cache.match(
      cacheKey,
    );

  if (cached) {
    return mediaResponseForClient(
      cached,
      "HIT",
      request.method === "HEAD",
    );
  }

  /**
   * 缓存没有时，
   * 才真正请求上游图片。
   */
  let upstream;

  try {
    upstream =
      await fetchMediaFollowingSafeRedirects(
        sourceUrl,
      );
  } catch (error) {
    return new Response(
      `获取媒体失败：${
        error instanceof Error
          ? error.message
          : String(error)
      }`,
      {
        status: 502,

        headers:
          noStoreHeaders(),
      },
    );
  }

  if (!upstream.ok) {
    return new Response(
      `上游媒体返回 HTTP ${upstream.status}`,
      {
        status:
          upstream.status,

        headers:
          noStoreHeaders(),
      },
    );
  }

  const contentType =
    (
      upstream.headers.get(
        "content-type",
      ) || ""
    )
      .split(";")[0]
      .trim()
      .toLowerCase();

  /**
   * 只接受 image/*。
   *
   * 包括：
   * - image/jpeg
   * - image/png
   * - image/gif
   * - image/webp
   * - image/avif
   */
  if (
    !contentType.startsWith(
      "image/",
    )
  ) {
    return new Response(
      `上游资源不是图片：${
        contentType ||
        "未知类型"
      }`,
      {
        status: 415,

        headers:
          noStoreHeaders(),
      },
    );
  }

  const headers =
    new Headers();

  headers.set(
    "content-type",
    contentType,
  );

  /**
   * 浏览器缓存和 Cloudflare 边缘缓存
   * 都设置为 10 小时。
   */
  headers.set(
    "cache-control",
    `public, max-age=${MEDIA_CACHE_SECONDS}, s-maxage=${MEDIA_CACHE_SECONDS}`,
  );

  headers.set(
    "expires",

    new Date(
      Date.now() +
        MEDIA_CACHE_SECONDS *
          1000,
    ).toUTCString(),
  );

  headers.set(
    "access-control-allow-origin",
    "*",
  );

  headers.set(
    "cross-origin-resource-policy",
    "cross-origin",
  );

  headers.set(
    "x-content-type-options",
    "nosniff",
  );

  headers.set(
    "content-disposition",
    "inline",
  );

  copyHeaderIfPresent(
    upstream.headers,
    headers,
    "etag",
  );

  copyHeaderIfPresent(
    upstream.headers,
    headers,
    "last-modified",
  );

  copyHeaderIfPresent(
    upstream.headers,
    headers,
    "content-length",
  );

  const cacheableResponse =
    new Response(
      upstream.body,
      {
        status: 200,
        headers,
      },
    );

  /**
   * 当前请求直接返回图片，
   * 同时在后台写入缓存。
   */
  ctx.waitUntil(
    cache.put(
      cacheKey,
      cacheableResponse.clone(),
    ),
  );

  return mediaResponseForClient(
    cacheableResponse,
    "MISS",
    request.method === "HEAD",
  );
}

async function fetchMediaFollowingSafeRedirects(
  initialUrl,
) {
  let currentUrl =
    new URL(
      initialUrl.toString(),
    );

  for (
    let redirects = 0;
    redirects <= 5;
    redirects += 1
  ) {
    if (
      !isAllowedMediaUrl(
        currentUrl,
      )
    ) {
      throw new Error(
        "媒体地址跳转到了不允许的域名",
      );
    }

    const response =
      await fetch(
        currentUrl.toString(),
        {
          method: "GET",

          redirect: "manual",

          headers: {
            accept:
              "image/avif,image/webp,image/apng,image/gif,image/png,image/jpeg,image/*;q=0.9,*/*;q=0.5",

            "user-agent":
              "Mozilla/5.0 (compatible; CampusRSSMediaProxy/1.0)",

            referer:
              "https://mp.weixin.qq.com/",
          },
        },
      );

    if (
      ![
        301,
        302,
        303,
        307,
        308,
      ].includes(
        response.status,
      )
    ) {
      return response;
    }

    const location =
      response.headers.get(
        "location",
      );

    if (!location) {
      throw new Error(
        "上游返回跳转，但没有 Location",
      );
    }

    currentUrl =
      new URL(
        location,
        currentUrl,
      );
  }

  throw new Error(
    "媒体地址跳转次数过多",
  );
}

function mediaResponseForClient(
  response,
  cacheStatus,
  headOnly,
) {
  const headers =
    new Headers(
      response.headers,
    );

  headers.set(
    "x-media-cache",
    cacheStatus,
  );

  return new Response(
    headOnly
      ? null
      : response.body,
    {
      status:
        response.status,

      statusText:
        response.statusText,

      headers,
    },
  );
}

/**
 * 改写 RSS item 内的图片资源地址。
 *
 * 不会执行 fetch，
 * 只生成 /api/media 链接。
 */
function rewriteMediaUrlsInMarkup(
  markup,
  baseUrl,
) {
  if (!markup) {
    return "";
  }

  return String(
    markup,
  ).replace(
    /<([a-zA-Z][\w:-]*)(?:\s[^<>]*?)?>/g,

    (
      tag,
      rawTagName,
    ) => {
      const tagName =
        rawTagName.toLowerCase();

      let output = tag;

      if (
        tagName === "img"
      ) {
        for (
          const attribute of [
            "src",
            "data-src",
            "data-original",
            "data-lazy-src",
            "data-url",
          ]
        ) {
          output =
            rewriteUrlAttribute(
              output,
              attribute,
              baseUrl,
            );
        }

        for (
          const attribute of [
            "srcset",
            "data-srcset",
          ]
        ) {
          output =
            rewriteSrcsetAttribute(
              output,
              attribute,
              baseUrl,
            );
        }

        /**
         * RSS 阅读器通常不会运行微信懒加载 JS。
         *
         * 因此把 data-src 中的真实图片
         * 提升到 src。
         */
        output =
          promoteLazyImageSource(
            output,
          );
      }

      /**
       * 微信图片链接卡片常用 imgurl。
       */
      if (
        tagName === "a"
      ) {
        output =
          rewriteUrlAttribute(
            output,
            "imgurl",
            baseUrl,
          );
      }

      /**
       * 视频本身不代理，
       * 只代理视频封面和头像。
       */
      if (
        tagName ===
          "mp-common-videosnap" ||
        tagName ===
          "iframe" ||
        tagName ===
          "video"
      ) {
        output =
          rewriteUrlAttribute(
            output,
            "data-cover",
            baseUrl,
          );

        output =
          rewriteUrlAttribute(
            output,
            "data-headimgurl",
            baseUrl,
          );

        output =
          rewriteUrlAttribute(
            output,
            "poster",
            baseUrl,
          );
      }

      if (
        tagName ===
          "media:content" ||
        tagName ===
          "media:thumbnail"
      ) {
        output =
          rewriteUrlAttribute(
            output,
            "url",
            baseUrl,
          );
      }

      if (
        tagName ===
        "enclosure"
      ) {
        const type =
          getAttribute(
            output,
            "type",
          );

        if (
          !type ||
          /^image\//i.test(type)
        ) {
          output =
            rewriteUrlAttribute(
              output,
              "url",
              baseUrl,
            );
        }
      }

      /**
       * 改写 style 中的：
       * background-image:url(...)
       */
      output =
        rewriteStyleUrls(
          output,
          baseUrl,
        );

      return output;
    },
  );
}

function promoteLazyImageSource(
  tag,
) {
  const preferred =
    firstNonEmpty(
      getAttribute(
        tag,
        "data-src",
      ),

      getAttribute(
        tag,
        "data-original",
      ),

      getAttribute(
        tag,
        "data-lazy-src",
      ),
    );

  if (
    !preferred ||
    !preferred.startsWith(
      `${PUBLIC_BASE_URL}/api/media?u=`,
    )
  ) {
    return tag;
  }

  const srcRegex =
    /(\ssrc\s*=\s*)(["'])([\s\S]*?)\2/i;

  if (
    srcRegex.test(tag)
  ) {
    return tag.replace(
      srcRegex,

      (
        _full,
        prefix,
        quote,
      ) =>
        `${prefix}${quote}${preferred}${quote}`,
    );
  }

  return tag.replace(
    /\s*\/?>$/,

    (ending) =>
      ` src="${preferred}"${ending}`,
  );
}

function rewriteUrlAttribute(
  tag,
  attributeName,
  baseUrl,
) {
  const regex =
    new RegExp(
      `(\\s${escapeRegExp(
        attributeName,
      )}\\s*=\\s*)(["'])([\\s\\S]*?)\\2`,

      "i",
    );

  return tag.replace(
    regex,

    (
      full,
      prefix,
      quote,
      value,
    ) => {
      const proxyUrl =
        makeMediaProxyUrl(
          value,
          baseUrl,
        );

      if (!proxyUrl) {
        return full;
      }

      return `${prefix}${quote}${proxyUrl}${quote}`;
    },
  );
}

function rewriteSrcsetAttribute(
  tag,
  attributeName,
  baseUrl,
) {
  const regex =
    new RegExp(
      `(\\s${escapeRegExp(
        attributeName,
      )}\\s*=\\s*)(["'])([\\s\\S]*?)\\2`,

      "i",
    );

  return tag.replace(
    regex,

    (
      full,
      prefix,
      quote,
      value,
    ) => {
      /**
       * data: 图片内部可能包含逗号，
       * 不进行拆分。
       */
      if (
        /\bdata:/i.test(
          value,
        )
      ) {
        return full;
      }

      const rewritten =
        value
          .split(",")
          .map(
            (candidate) => {
              const trimmed =
                candidate.trim();

              if (!trimmed) {
                return "";
              }

              const match =
                trimmed.match(
                  /^(\S+)(\s+.+)?$/,
                );

              if (!match) {
                return trimmed;
              }

              const proxyUrl =
                makeMediaProxyUrl(
                  match[1],
                  baseUrl,
                );

              return `${
                proxyUrl ||
                match[1]
              }${
                match[2] ||
                ""
              }`;
            },
          )
          .filter(Boolean)
          .join(", ");

      return `${prefix}${quote}${rewritten}${quote}`;
    },
  );
}

function rewriteStyleUrls(
  tag,
  baseUrl,
) {
  const styleRegex =
    /(\sstyle\s*=\s*)(["'])([\s\S]*?)\2/i;

  return tag.replace(
    styleRegex,

    (
      _full,
      prefix,
      quote,
      styleText,
    ) => {
      const rewritten =
        styleText.replace(
          /url\(\s*(["']?)(.*?)\1\s*\)/gi,

          (
            urlFull,
            _innerQuote,
            resource,
          ) => {
            const proxyUrl =
              makeMediaProxyUrl(
                resource,
                baseUrl,
              );

            return proxyUrl
              ? `url("${proxyUrl}")`
              : urlFull;
          },
        );

      return `${prefix}${quote}${rewritten}${quote}`;
    },
  );
}

function makeMediaProxyUrl(
  value,
  baseUrl,
) {
  const normalized =
    normalizeMediaSource(
      value,
      baseUrl,
    );

  if (!normalized) {
    return "";
  }

  let sourceUrl;

  try {
    sourceUrl =
      new URL(normalized);
  } catch {
    return "";
  }

  const publicOrigin =
    new URL(
      PUBLIC_BASE_URL,
    ).origin;

  /**
   * 已经是自己的代理地址时，
   * 不再重复套一层。
   */
  if (
    sourceUrl.origin ===
      publicOrigin &&
    sourceUrl.pathname ===
      "/api/media"
  ) {
    return sourceUrl.toString();
  }

  if (
    !isAllowedMediaUrl(
      sourceUrl,
    )
  ) {
    return "";
  }

  return `${PUBLIC_BASE_URL}/api/media?u=${encodeBase64Url(
    sourceUrl.toString(),
  )}`;
}

function normalizeMediaSource(
  value,
  baseUrl,
) {
  let text =
    decodeXmlEntities(
      String(
        value ||
          "",
      ).trim(),
    );

  if (!text) {
    return "";
  }

  if (
    /^(data|javascript|vbscript|blob):/i.test(
      text,
    )
  ) {
    return "";
  }

  /**
   * 微信视频封面有时是：
   * https%3A%2F%2F...
   */
  if (
    /^https?%3a%2f%2f/i.test(
      text,
    )
  ) {
    try {
      text =
        decodeURIComponent(
          text,
        );
    } catch {
      return "";
    }
  }

  if (
    text.startsWith("//")
  ) {
    text =
      `https:${text}`;
  }

  try {
    return new URL(
      text,
      baseUrl ||
        undefined,
    ).toString();
  } catch {
    return "";
  }
}

function isAllowedMediaUrl(
  url,
) {
  if (
    url.protocol !== "https:" &&
    url.protocol !== "http:"
  ) {
    return false;
  }

  if (
    url.username ||
    url.password
  ) {
    return false;
  }

  if (
    url.port &&
    url.port !== "80" &&
    url.port !== "443"
  ) {
    return false;
  }

  const hostname =
    url.hostname.toLowerCase();

  return MEDIA_ALLOWED_HOSTS.some(
    (rule) => {
      const normalizedRule =
        rule.toLowerCase();

      if (
        normalizedRule.startsWith(
          ".",
        )
      ) {
        return hostname.endsWith(
          normalizedRule,
        );
      }

      return (
        hostname ===
        normalizedRule
      );
    },
  );
}

function firstProxyImageFromMarkup(
  markup,
) {
  const text =
    String(markup || "");

  const patterns = [
    /<media:content\b[^>]*\burl=["']([^"']+)["']/i,

    /<media:thumbnail\b[^>]*\burl=["']([^"']+)["']/i,

    /<img\b[^>]*\bsrc=["']([^"']+)["']/i,

    /<img\b[^>]*\bdata-src=["']([^"']+)["']/i,
  ];

  for (
    const pattern of patterns
  ) {
    const match =
      text.match(pattern);

    if (
      match?.[1]?.startsWith(
        `${PUBLIC_BASE_URL}/api/media?u=`,
      )
    ) {
      return match[1];
    }
  }

  return null;
}

function extractPublisherFromTitle(
  title,
) {
  const text =
    String(
      title || "",
    ).trim();

  const match =
    text.match(
      /^\s*(?:\[([^\]]+)\]|【([^】]+)】)\s*/,
    );

  return normalizePublisherName(
    match?.[1] ||
      match?.[2] ||
      "",
  );
}

function normalizePublisherName(
  value,
) {
  const text =
    plainText(value);

  if (!text) {
    return "";
  }

  /**
   * 聚合服务的频道标题
   * 不能当成公众号名称。
   */
  if (
    /^wechat\s*rss\b/i.test(
      text,
    )
  ) {
    return "";
  }

  if (
    /cloudflare\s*rss/i.test(
      text,
    )
  ) {
    return "";
  }

  if (
    /campus\s*rss/i.test(
      text,
    )
  ) {
    return "";
  }

  return text;
}

function extractRawElements(
  xml,
  tagName,
) {
  const escaped =
    escapeRegExp(tagName);

  const regex =
    new RegExp(
      `<${escaped}\\b[^>]*>[\\s\\S]*?<\\/${escaped}>`,

      "gi",
    );

  return (
    String(
      xml || "",
    ).match(regex) || []
  );
}

function elementInnerRaw(
  xml,
  tagName,
) {
  const escaped =
    escapeRegExp(tagName);

  const regex =
    new RegExp(
      `<${escaped}\\b[^>]*>([\\s\\S]*?)<\\/${escaped}>`,

      "i",
    );

  return (
    String(
      xml || "",
    ).match(regex)?.[1] ||
    ""
  );
}

function elementText(
  xml,
  tagName,
) {
  return plainText(
    elementInnerRaw(
      xml,
      tagName,
    ),
  );
}

function removeElement(
  xml,
  tagName,
) {
  const escaped =
    escapeRegExp(tagName);

  const paired =
    new RegExp(
      `\\s*<${escaped}\\b[^>]*>[\\s\\S]*?<\\/${escaped}>`,

      "gi",
    );

  const selfClosing =
    new RegExp(
      `\\s*<${escaped}\\b[^>]*/>`,

      "gi",
    );

  return String(
    xml || "",
  )
    .replace(
      paired,
      "",
    )
    .replace(
      selfClosing,
      "",
    );
}

function getAttribute(
  tag,
  attributeName,
) {
  const regex =
    new RegExp(
      `\\s${escapeRegExp(
        attributeName,
      )}\\s*=\\s*(?:"([^"]*)"|'([^']*)'|([^\\s>]+))`,

      "i",
    );

  const match =
    String(
      tag || "",
    ).match(regex);

  return match
    ? match[1] ??
        match[2] ??
        match[3] ??
        ""
    : "";
}

function plainText(
  value,
) {
  return decodeXmlEntities(
    unwrapCdataOnly(
      String(
        value || "",
      ),
    )
      .replace(
        /<br\s*\/?>/gi,
        "\n",
      )
      .replace(
        /<\/p>/gi,
        "\n",
      )
      .replace(
        /<\/li>/gi,
        "\n",
      )
      .replace(
        /<[^>]+>/g,
        " ",
      ),
  )
    .replace(
      /\u00a0/g,
      " ",
    )
    .replace(
      /[ \t]+/g,
      " ",
    )
    .replace(
      /\s*\n\s*/g,
      "\n",
    )
    .trim();
}

function makePlainSummary(
  html,
) {
  const text =
    plainText(html);

  if (
    text.length <= 500
  ) {
    return text;
  }

  return `${text
    .slice(0, 500)
    .trim()}…`;
}

function unwrapCdataOnly(
  value,
) {
  const text =
    String(value || "");

  const match =
    text.match(
      /^\s*<!\[CDATA\[([\s\S]*?)\]\]>\s*$/,
    );

  return match
    ? match[1]
    : text;
}

function decodeXmlEntities(
  value,
) {
  return String(
    value || "",
  )
    .replace(
      /&#x([0-9a-f]+);/gi,

      (
        _match,
        hex,
      ) =>
        String.fromCodePoint(
          Number.parseInt(
            hex,
            16,
          ),
        ),
    )
    .replace(
      /&#([0-9]+);/g,

      (
        _match,
        decimal,
      ) =>
        String.fromCodePoint(
          Number.parseInt(
            decimal,
            10,
          ),
        ),
    )
    .replace(
      /&nbsp;/gi,
      " ",
    )
    .replace(
      /&lt;/gi,
      "<",
    )
    .replace(
      /&gt;/gi,
      ">",
    )
    .replace(
      /&quot;/gi,
      '"',
    )
    .replace(
      /&apos;/gi,
      "'",
    )
    .replace(
      /&amp;/gi,
      "&",
    );
}

function normalizeDate(
  value,
) {
  if (!value) {
    return null;
  }

  const date =
    new Date(
      String(
        value,
      ).trim(),
    );

  return Number.isNaN(
    date.getTime(),
  )
    ? null
    : date.toISOString();
}

function dedupeItems(
  items,
) {
  const seen =
    new Set();

  const result = [];

  for (
    const item of items
  ) {
    const key =
      item.link ||
      item.guid ||
      `${item.title}|${
        item.publishedAt ||
        ""
      }`;

    if (
      !key ||
      seen.has(key)
    ) {
      continue;
    }

    seen.add(key);
    result.push(item);
  }

  return result;
}

function compareItems(
  a,
  b,
) {
  const aTime =
    a.publishedAt
      ? new Date(
          a.publishedAt,
        ).getTime()
      : 0;

  const bTime =
    b.publishedAt
      ? new Date(
          b.publishedAt,
        ).getTime()
      : 0;

  return bTime - aTime;
}

function snapshotSummary(
  snapshot,
) {
  return {
    version:
      snapshot.version,

    mode:
      snapshot.mode,

    generatedAt:
      snapshot.generatedAt,

    stale:
      snapshot.stale,

    sourceCount:
      snapshot.sourceCount,

    successfulSourceCount:
      snapshot.successfulSourceCount,

    failedSourceCount:
      snapshot.failedSourceCount,

    totalItems:
      snapshot.totalItems,

    sources:
      snapshot.sources,
  };
}

function isSnapshotExpired(
  snapshot,
  env,
) {
  const maxAge =
    readNumber(
      env.CACHE_MAX_AGE_SECONDS,
      DEFAULT_CACHE_MAX_AGE_SECONDS,
      60,
      86400,
    );

  const generatedAt =
    new Date(
      snapshot.generatedAt,
    ).getTime();

  return (
    !Number.isFinite(
      generatedAt,
    ) ||
    Date.now() -
      generatedAt >
      maxAge * 1000
  );
}

function isAuthorized(
  request,
  env,
) {
  if (!env.ADMIN_TOKEN) {
    return false;
  }

  return (
    request.headers.get(
      "authorization",
    ) ===
    `Bearer ${env.ADMIN_TOKEN}`
  );
}

async function fetchWithTimeout(
  url,
  timeoutMs,
  init = {},
) {
  const controller =
    new AbortController();

  const timer =
    setTimeout(
      () =>
        controller.abort(),

      timeoutMs,
    );

  try {
    return await fetch(
      url,
      {
        ...init,

        signal:
          controller.signal,
      },
    );
  } finally {
    clearTimeout(timer);
  }
}

function encodeBase64Url(
  text,
) {
  const bytes =
    new TextEncoder().encode(
      text,
    );

  let binary = "";

  const chunkSize = 32768;

  for (
    let index = 0;
    index < bytes.length;
    index += chunkSize
  ) {
    binary +=
      String.fromCharCode(
        ...bytes.subarray(
          index,
          index + chunkSize,
        ),
      );
  }

  return btoa(binary)
    .replace(
      /\+/g,
      "-",
    )
    .replace(
      /\//g,
      "_",
    )
    .replace(
      /=+$/g,
      "",
    );
}

function decodeBase64Url(
  value,
) {
  const base64 =
    String(value)
      .replace(
        /-/g,
        "+",
      )
      .replace(
        /_/g,
        "/",
      );

  const padded =
    base64 +
    "=".repeat(
      (
        4 -
        (base64.length % 4)
      ) %
        4,
    );

  const binary =
    atob(padded);

  const bytes =
    new Uint8Array(
      binary.length,
    );

  for (
    let index = 0;
    index <
    binary.length;
    index += 1
  ) {
    bytes[index] =
      binary.charCodeAt(
        index,
      );
  }

  return new TextDecoder().decode(
    bytes,
  );
}

function copyHeaderIfPresent(
  from,
  to,
  name,
) {
  const value =
    from.get(name);

  if (value) {
    to.set(
      name,
      value,
    );
  }
}

function hashString(
  value,
) {
  let hash = 2166136261;

  for (
    let index = 0;
    index < value.length;
    index += 1
  ) {
    hash ^=
      value.charCodeAt(
        index,
      );

    hash =
      Math.imul(
        hash,
        16777619,
      );
  }

  return (hash >>> 0)
    .toString(16)
    .padStart(
      8,
      "0",
    );
}

function firstNonEmpty(
  ...values
) {
  for (
    const value of values
  ) {
    if (
      value !== undefined &&
      value !== null &&
      String(
        value,
      ).trim() !== ""
    ) {
      return String(
        value,
      ).trim();
    }
  }

  return "";
}

function firstNonEmptyRaw(
  ...values
) {
  for (
    const value of values
  ) {
    if (
      value !== undefined &&
      value !== null &&
      String(
        value,
      ).trim() !== ""
    ) {
      return String(value);
    }
  }

  return "";
}

function readNumber(
  value,
  fallback,
  min,
  max,
) {
  const parsed =
    Number.parseInt(
      String(
        value ?? "",
      ),
      10,
    );

  if (
    !Number.isFinite(
      parsed,
    )
  ) {
    return fallback;
  }

  return Math.min(
    max,
    Math.max(
      min,
      parsed,
    ),
  );
}

function escapeRegExp(
  value,
) {
  return String(
    value,
  ).replace(
    /[.*+?^${}()|[\]\\]/g,
    "\\$&",
  );
}

function escapeXml(
  value,
) {
  return String(
    value || "",
  )
    .replace(
      /&/g,
      "&amp;",
    )
    .replace(
      /</g,
      "&lt;",
    )
    .replace(
      />/g,
      "&gt;",
    )
    .replace(
      /"/g,
      "&quot;",
    )
    .replace(
      /'/g,
      "&apos;",
    );
}

function escapeXmlAttribute(
  value,
) {
  return escapeXml(value);
}

/**
 * CDATA 内部不能直接出现 ]]>
 */
function safeCdata(
  value,
) {
  return String(
    value || "",
  ).replace(
    /\]\]>/g,
    "]]]]><![CDATA[>",
  );
}

function corsHeaders() {
  return {
    "access-control-allow-origin":
      "*",

    "access-control-allow-methods":
      "GET, HEAD, POST, OPTIONS",

    "access-control-allow-headers":
      "Authorization, Content-Type",
  };
}

function noStoreHeaders() {
  return {
    "cache-control":
      "no-store",
  };
}

function jsonResponse(
  data,
  status = 200,
  extraHeaders = {},
) {
  return new Response(
    JSON.stringify(
      data,
      null,
      2,
    ),
    {
      status,

      headers: {
        ...corsHeaders(),

        "content-type":
          "application/json; charset=utf-8",

        "x-content-type-options":
          "nosniff",

        "cache-control":
          "public, max-age=60",

        ...extraHeaders,
      },
    },
  );
}