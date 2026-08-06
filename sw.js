const CACHE_NAME = 'pejuang-devisa-v3'; // dinaikkan dari v1 supaya cache lama (yang mungkin sudah
                                          // terlanjur berisi respons API Supabase yang basi) ikut dibuang
const PRECACHE = [
  './',
  './index.html',
  './manifest.json',
  './icon-192.png',
  './icon-512.png',
  './apple-touch-icon.png'
];

self.addEventListener('install', (e) => {
  e.waitUntil(
    caches.open(CACHE_NAME).then((cache) => cache.addAll(PRECACHE)).catch(() => {})
  );
  self.skipWaiting();
});

self.addEventListener('activate', (e) => {
  e.waitUntil(
    caches.keys().then((keys) =>
      Promise.all(keys.filter((k) => k !== CACHE_NAME).map((k) => caches.delete(k)))
    )
  );
  self.clients.claim();
});

self.addEventListener('fetch', (e) => {
  const req = e.request;
  if (req.method !== 'GET') return;

  const url = new URL(req.url);

  // PENTING: jangan pernah campur tangan request ke luar origin situs ini (Supabase REST,
  // Storage, Auth, dll). Data peserta/dokumen harus selalu diambil langsung dari server,
  // tidak boleh disajikan dari cache — kalau tidak, upload/perubahan terbaru bisa "hilang"
  // dari tampilan karena Service Worker menyajikan respons API yang sudah basi.
  if (url.origin !== self.location.origin) return;

  const isHTML = req.mode === 'navigate' || (req.headers.get('accept') || '').includes('text/html');

  if (isHTML) {
    // network-first untuk HTML, biar update selalu kepakai duluan
    e.respondWith(
      fetch(req)
        .then((res) => {
          const copy = res.clone();
          caches.open(CACHE_NAME).then((c) => c.put(req, copy));
          return res;
        })
        .catch(() => caches.match(req).then((r) => r || caches.match('./index.html')))
    );
    return;
  }

  // cache-first HANYA untuk aset statis situs sendiri (ikon, manifest, dll)
  e.respondWith(
    caches.match(req).then((cached) => {
      if (cached) return cached;
      return fetch(req).then((res) => {
        const copy = res.clone();
        caches.open(CACHE_NAME).then((c) => c.put(req, copy));
        return res;
      }).catch(() => cached);
    })
  );
});

self.addEventListener('message', (e) => {
  if (e.data === 'skipWaiting') self.skipWaiting();
});
