{{flutter_js}}
{{flutter_build_config}}

// NineSoft is a live business application. Always load the current deployed
// shell instead of pinning an older release behind Flutter's legacy PWA cache.
if ('serviceWorker' in navigator) {
  navigator.serviceWorker.getRegistrations().then((registrations) => {
    for (const registration of registrations) registration.unregister();
  });
}

_flutter.loader.load();
