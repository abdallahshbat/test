/* ── HUFFAZ PWA SERVICE WORKER ──────────────────────── */
const CACHE_NAME = 'huffaz-v1';
const SUPABASE_HOST = 'aeonokdakdvqgiisfhwv.supabase.co';

/* Assets to pre-cache on install */
const PRECACHE = [
  './dashboard.html',
  './manifest.json',
  'https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2/dist/umd/supabase.min.js'
];

/* Offline fallback HTML */
const OFFLINE_HTML = `<!DOCTYPE html>
<html lang="ar" dir="rtl">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>حفّاظ — غير متصل</title>
<style>
*{box-sizing:border-box;margin:0;padding:0}
body{font-family:'Segoe UI',system-ui,sans-serif;background:#0F1419;color:#E8EDF2;
  min-height:100vh;display:flex;align-items:center;justify-content:center;
  text-align:center;padding:24px;direction:rtl}
.icon{font-size:4rem;margin-bottom:16px}
h1{font-size:1.3rem;font-weight:800;margin-bottom:8px;
  background:linear-gradient(135deg,#C9A84C,#F0D080);
  -webkit-background-clip:text;-webkit-text-fill-color:transparent;background-clip:text}
p{font-size:.88rem;color:#9AB0C2;line-height:1.7;max-width:280px;margin:0 auto 20px}
button{padding:12px 28px;background:linear-gradient(135deg,#C9A84C,#A8872E);
  color:#fff;border:none;border-radius:12px;font-size:.9rem;font-weight:700;
  cursor:pointer;font-family:inherit}
</style>
</head>
<body>
<div>
  <div class="icon">📵</div>
  <h1>لا يوجد اتصال بالإنترنت</h1>
  <p>تحتاج إلى اتصال للوصول إلى بيانات حفّاظ. يرجى التحقق من اتصالك والمحاولة مجدداً.</p>
  <button onclick="location.reload()">إعادة المحاولة</button>
</div>
</body>
</html>`;

/* ── INSTALL: pre-cache assets ───────────────────────── */
self.addEventListener('install', e => {
  e.waitUntil(
    caches.open(CACHE_NAME).then(cache =>
      Promise.allSettled(PRECACHE.map(url => cache.add(url).catch(() => {})))
    ).then(() => self.skipWaiting())
  );
});

/* ── ACTIVATE: clean old caches ─────────────────────── */
self.addEventListener('activate', e => {
  e.waitUntil(
    caches.keys().then(keys =>
      Promise.all(keys.filter(k => k !== CACHE_NAME).map(k => caches.delete(k)))
    ).then(() => self.clients.claim())
  );
});

/* ── FETCH: routing strategy ─────────────────────────── */
self.addEventListener('fetch', e => {
  const url = new URL(e.request.url);

  /* Supabase API → Network-only (never cache auth/data) */
  if (url.hostname === SUPABASE_HOST) {
    e.respondWith(
      fetch(e.request).catch(() =>
        new Response(JSON.stringify({ error: 'offline' }), {
          status: 503,
          headers: { 'Content-Type': 'application/json' }
        })
      )
    );
    return;
  }

  /* CDN scripts → Cache-first, fall back to network */
  if (url.hostname === 'cdn.jsdelivr.net') {
    e.respondWith(
      caches.match(e.request).then(cached => cached || fetch(e.request).then(res => {
        const clone = res.clone();
        caches.open(CACHE_NAME).then(c => c.put(e.request, clone));
        return res;
      }))
    );
    return;
  }

  /* HTML pages → Network-first, fall back to cache, then offline page */
  if (e.request.mode === 'navigate' || e.request.headers.get('accept')?.includes('text/html')) {
    e.respondWith(
      fetch(e.request)
        .then(res => {
          const clone = res.clone();
          caches.open(CACHE_NAME).then(c => c.put(e.request, clone));
          return res;
        })
        .catch(() =>
          caches.match(e.request).then(cached =>
            cached || new Response(OFFLINE_HTML, {
              headers: { 'Content-Type': 'text/html; charset=utf-8' }
            })
          )
        )
    );
    return;
  }

  /* Everything else → Cache-first */
  e.respondWith(
    caches.match(e.request).then(cached => cached || fetch(e.request))
  );
});

/* ── SKIP WAITING (triggered by update banner) ───────── */
self.addEventListener('message', e => {
  if (e.data?.type === 'SKIP_WAITING') self.skipWaiting();
});

/* ── BACKGROUND SYNC (future-ready) ─────────────────── */
self.addEventListener('sync', e => {
  if (e.tag === 'huffaz-sync') {
    /* placeholder for offline queue sync */
  }
});
