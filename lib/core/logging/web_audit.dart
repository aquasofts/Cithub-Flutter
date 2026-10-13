import 'package:webview_flutter/webview_flutter.dart';

import 'runtime_log.dart';

Future<void> configureWebAudit(WebViewController controller, String source) =>
    controller.addJavaScriptChannel(
      'CithubAudit',
      onMessageReceived: (message) {
        RuntimeLog.write(source, message.message);
      },
    );

// Installed for each document. Resource Timing also reports earlier resource
// loads; browser-managed navigations/subresources expose metadata, not bodies.
const webAuditScript = r'''
(() => {
  if (window.__cithubAudit) return;
  window.__cithubAudit = true;
  const log = (action, data) => CithubAudit.postMessage(JSON.stringify({action, url: location.href, data}));
  const body = async (value) => {
    const bytes = new Uint8Array(await (value instanceof Response ? value : new Response(value)).arrayBuffer());
    let raw = ''; for (let i = 0; i < bytes.length; i += 8192) raw += String.fromCharCode(...bytes.subarray(i, i + 8192));
    return btoa(raw);
  };
  let seq = 0;
  const originalFetch = window.fetch;
  window.fetch = async function(input, init) {
    const id = ++seq;
    const request = new Request(input, init);
    const copy = request.clone();
    body(copy).then(bytes => log('fetch-request', {id, method: request.method, url: request.url, headers: [...request.headers], bodyBase64: bytes})).catch(error => log('fetch-request-error', {id, error: String(error)}));
    try {
      const response = await originalFetch.call(this, input, init);
      log('fetch-response', {id, url: response.url, status: response.status, headers: [...response.headers]});
      body(response.clone()).then(bytes => log('fetch-body', {id, bodyBase64: bytes})).catch(error => log('fetch-body-error', {id, error: String(error)}));
      return response;
    } catch (error) { log('fetch-error', {id, error: String(error)}); throw error; }
  };
  const open = XMLHttpRequest.prototype.open;
  const send = XMLHttpRequest.prototype.send;
  const header = XMLHttpRequest.prototype.setRequestHeader;
  XMLHttpRequest.prototype.open = function(method, url, ...rest) {
    this.__audit = {id: ++seq, method, url, headers: []};
    return open.call(this, method, url, ...rest);
  };
  XMLHttpRequest.prototype.setRequestHeader = function(key, value) {
    this.__audit?.headers.push([key, value]); return header.call(this, key, value);
  };
  XMLHttpRequest.prototype.send = function(value) {
    const info = this.__audit;
    body(value ?? '').then(bytes => log('xhr-request', {...info, bodyBase64: bytes}));
    this.addEventListener('loadend', () => {
      log('xhr-response', {...info, status: this.status, headers: this.getAllResponseHeaders()});
      let value = this.response;
      if (this.responseType === 'json') value = JSON.stringify(value);
      if (this.responseType === 'document') value = this.responseXML?.documentElement.outerHTML ?? '';
      body(value ?? '').then(bytes => log('xhr-body', {id: info.id, bodyBase64: bytes}));
    });
    this.addEventListener('error', () => log('xhr-error', info));
    this.addEventListener('abort', () => log('xhr-abort', info));
    return send.call(this, value);
  };
  for (const type of ['click', 'input', 'change', 'submit']) {
    document.addEventListener(type, e => log('interaction', {type, tag: e.target.tagName, id: e.target.id, name: e.target.name, value: e.target.value, text: e.target.innerText}), true);
  }
  const resources = entries => entries.forEach(e => log('resource', e.toJSON()));
  resources(performance.getEntriesByType('resource'));
  new PerformanceObserver(list => resources(list.getEntries())).observe({entryTypes: ['resource']});
  log('document', {title: document.title, cookie: document.cookie, html: document.documentElement.outerHTML});
})();
''';
