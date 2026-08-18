# Cithub RSS Worker

This directory is the standalone RSS aggregation and media-proxy worker migrated
from the GPL-3.0 Cithub Android repository. The Flutter application does not need
this directory to compile; deployments use Cloudflare Worker + Pages service
bindings as documented in `Work.js` and `pages/wrangler.jsonc`.

No deployment token, KV data, upstream private feed URL, or administrator secret
is stored here. Configure `RSS_CACHE`, `ADMIN_TOKEN`, `UPSTREAM_RSS_URL`, and the
`RSS_WORKER` service binding in the deployment environment.
