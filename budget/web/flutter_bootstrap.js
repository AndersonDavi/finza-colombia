{{flutter_js}}
{{flutter_build_config}}

// Starts the app. If something fails, or it takes too long, the loading
// screen says so and shows the last messages instead of spinning forever,
// so a screenshot from the phone tells what went wrong
(function () {
  var loading = document.querySelector('#loading');
  var problem = document.querySelector('#load-problem');
  var started = Date.now();
  var lines = [];
  var finished = false;

  function remember(kind, args) {
    try {
      var text = Array.prototype.map.call(args, function (a) {
        if (a instanceof Error) return a.message;
        return typeof a === 'string' ? a : JSON.stringify(a);
      }).join(' ');
      lines.push(((Date.now() - started) / 1000).toFixed(1) + 's ' + kind + ': ' + text.slice(0, 300));
      if (lines.length > 14) lines.shift();
    } catch (e) {}
  }
  ['log', 'warn', 'error'].forEach(function (kind) {
    var original = console[kind];
    console[kind] = function () {
      remember(kind, arguments);
      return original.apply(console, arguments);
    };
  });
  window.addEventListener('error', function (e) {
    remember('error', [e.message + (e.filename ? ' (' + e.filename.split('/').pop() + ':' + e.lineno + ')' : '')]);
  });
  window.addEventListener('unhandledrejection', function (e) {
    remember('rejection', [e.reason && e.reason.message ? e.reason.message : String(e.reason)]);
  });

  function checks() {
    var webgl2 = false;
    try { webgl2 = !!document.createElement('canvas').getContext('webgl2'); } catch (e) {}
    return 'WebGL2 ' + (webgl2 ? 'si' : 'no') +
      ' · WebAssembly ' + (typeof WebAssembly === 'object' ? 'si' : 'no') +
      ' · IndexedDB ' + (window.indexedDB ? 'si' : 'no') +
      ' · ' + navigator.userAgent.replace(/^Mozilla\/5\.0 /, '');
  }

  function showProblem(title, error) {
    if (finished || !problem) return;
    if (error) remember('error', [error]);
    problem.querySelector('.title').textContent = title;
    problem.querySelector('.details').textContent = lines.join('\n') + '\n\n' + checks();
    problem.style.display = 'block';
  }

  setTimeout(function () {
    showProblem('Está tardando más de lo normal');
  }, 25000);

  _flutter.loader.load({
    config: {
      // CanvasKit from this same site instead of gstatic.com, one less host
      // that can be slow or blocked on the phone's network
      useLocalCanvasKit: true,
    },
    onEntrypointLoaded: async function (engineInitializer) {
      try {
        loading.classList.add('main_done');
        var appRunner = await engineInitializer.initializeEngine({
          useColorEmoji: true,
        });
        loading.classList.add('init_done');
        await appRunner.runApp();
        finished = true;
        if (problem) problem.remove();
        // A few milliseconds so the fade can be seen before removing it
        setTimeout(function () { loading.remove(); }, 200);
        // Block the edge swipe that navigates back in iOS Safari
        // https://github.com/flutter/flutter/issues/55913#issuecomment-1248816491
        var flutterRoot = document.querySelector('flutter-view, flt-glass-pane');
        if (flutterRoot) {
          flutterRoot.addEventListener('touchstart', function (e) {
            if (e.pageX > 24 && e.pageX < window.innerWidth - 24) return;
            e.preventDefault();
          });
        }
      } catch (error) {
        showProblem('No se pudo abrir Finza', error && error.message ? error.message : String(error));
      }
    },
  }).catch(function (error) {
    showProblem('No se pudo descargar Finza', error && error.message ? error.message : String(error));
  });

  // No offline service worker: it kept serving the previous build after an
  // update. Remove the one an older build may have installed
  if ('serviceWorker' in navigator) {
    navigator.serviceWorker.getRegistrations().then(function (registrations) {
      registrations.forEach(function (registration) { registration.unregister(); });
    });
  }
  if (window.caches) {
    caches.keys().then(function (keys) {
      keys.forEach(function (key) { caches.delete(key); });
    });
  }
})();
