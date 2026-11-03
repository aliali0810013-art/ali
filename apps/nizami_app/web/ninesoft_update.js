/* NineSoft web shell update. Never touch localStorage, IndexedDB, or offline
 * accounting queues: users may have unposted invoices in those stores. */
(() => {
  'use strict';
  const button = document.getElementById('ninesoft-update-btn');
  const status = document.getElementById('ninesoft-update-status');
  if (!button || !status) return;
  let running = false;
  const show = (message) => { status.textContent = message; status.hidden = false; };
  const isFlutterAssetCache = (name) =>
    name === 'flutter-app-cache' || name === 'flutter-temp-cache' ||
    name === 'flutter-app-manifest' || name.startsWith('flutter-app-cache-');

  button.addEventListener('click', async () => {
    if (running) return;
    running = true;
    button.disabled = true;
    show('جارٍ البحث عن أحدث إصدار…');
    try {
      // Never discard a pending business operation merely because an API or
      // cache refresh failed. The user can retry without losing local drafts.
      if (!navigator.onLine) throw new Error('لا يوجد اتصال بالإنترنت.');
      const shell = new URL('index.html', document.baseURI);
      shell.searchParams.set('_ninesoft_check', String(Date.now()));
      const response = await fetch(shell.toString(), {cache: 'no-store', credentials: 'same-origin'});
      if (!response.ok) throw new Error('تعذر الوصول إلى الإصدار الجديد.');
      show('تم التحقق. جارٍ تنظيف ملفات الواجهة وإعادة التشغيل…');
      if (navigator.serviceWorker) {
        const regs = await navigator.serviceWorker.getRegistrations();
        const base = new URL(document.baseURI).pathname;
        for (const reg of regs) {
          const scope = new URL(reg.scope);
          if (scope.origin === location.origin && scope.pathname === base) {
            await reg.unregister();
          }
        }
      }
      // Do not delete generic Workbox caches: another app at the same
      // origin might own them. Removing this app's service worker and its
      // Flutter-specific caches is sufficient for the next navigation.
      if ('caches' in window) {
        const names = await caches.keys();
        for (const name of names) if (isFlutterAssetCache(name)) await caches.delete(name);
      }
      // Force the browser to revalidate the HTML document and Flutter bundle.
      // No financial data or offline outbox is cleared by this operation.
      const target = new URL(location.href);
      target.searchParams.set('ninesoft_refresh', String(Date.now()));
      location.replace(target.toString());
    } catch (error) {
      show(error && error.message ? error.message : 'تعذر تحديث الواجهة؛ حاول مجددًا.');
      button.disabled = false;
      running = false;
    }
  });
})();
