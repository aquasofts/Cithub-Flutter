interface FetcherLike {
  fetch(request: Request): Promise<Response>;
}

interface Env {
  RSS_WORKER: FetcherLike;
}

interface PagesContext {
  request: Request;
  env: Env;
}

/**
 * 浏览器只访问 Pages 域名下的 /api/*。
 * Pages Function 使用 Service Binding 在 Cloudflare 内部调用 Worker，
 * 不经过 workers.dev 公网域名。
 */
export async function onRequest(context: PagesContext): Promise<Response> {
  try {
    const response = await context.env.RSS_WORKER.fetch(context.request);
    const headers = new Headers(response.headers);
    headers.set("x-api-entry", "cloudflare-pages");

    return new Response(response.body, {
      status: response.status,
      statusText: response.statusText,
      headers,
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    return Response.json(
      {
        error: "RSS Worker service unavailable",
        message,
      },
      {
        status: 502,
        headers: {
          "cache-control": "no-store",
          "x-content-type-options": "nosniff",
        },
      },
    );
  }
}
