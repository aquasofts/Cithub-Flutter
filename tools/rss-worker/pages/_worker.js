export default {
  async fetch(request, env) {
    const url =
      new URL(request.url);

    /**
     * 所有 /api 请求通过 Service Binding
     * 转发给后台 RSS Worker。
     */
    if (
      url.pathname === "/api" ||
      url.pathname.startsWith(
        "/api/",
      )
    ) {
      if (!env.RSS_WORKER) {
        return Response.json(
          {
            error:
              "RSS_WORKER 服务绑定尚未配置",
          },
          {
            status: 500,

            headers: {
              "cache-control":
                "no-store",
            },
          },
        );
      }

      try {
        return await env.RSS_WORKER.fetch(
          request,
        );
      } catch (error) {
        return Response.json(
          {
            error:
              "后台 RSS Worker 调用失败",

            message:
              error instanceof Error
                ? error.message
                : String(error),
          },
          {
            status: 502,

            headers: {
              "cache-control":
                "no-store",
            },
          },
        );
      }
    }

    /**
     * 其他路径继续读取 Pages 静态文件。
     */
    return env.ASSETS.fetch(
      request,
    );
  },
};