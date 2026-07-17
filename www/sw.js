// Minimal service worker for the nursery monitor.
// Android Chrome only shows notifications via ServiceWorkerRegistration.showNotification(),
// so this worker must be registered before popups can work there.
self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', e => e.waitUntil(self.clients.claim()));

self.addEventListener('notificationclick', e => {
  e.notification.close();
  e.waitUntil(
    self.clients.matchAll({ type: 'window', includeUncontrolled: true }).then(list => {
      for (const c of list) if ('focus' in c) return c.focus();
      return self.clients.openWindow('/monitor');
    })
  );
});
