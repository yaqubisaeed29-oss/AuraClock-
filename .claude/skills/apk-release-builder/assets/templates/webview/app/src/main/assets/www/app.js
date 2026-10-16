// Starter logic for the packaged web app. Replace freely - nothing here is
// required by the native host except that index.html exists at this path.

(function () {
  "use strict";

  var bridge = window.AndroidBridge || null;
  var out = document.getElementById("out");

  function log(message) {
    if (out) out.textContent = message;
    console.log(message);
  }

  // ---- clock -------------------------------------------------------------
  var clock = document.getElementById("clock");
  var dateEl = document.getElementById("date");

  function pad(n) { return n < 10 ? "0" + n : String(n); }

  function tick() {
    var now = new Date();
    if (clock) {
      clock.textContent = pad(now.getHours()) + ":" + pad(now.getMinutes()) + ":" + pad(now.getSeconds());
    }
    if (dateEl) {
      dateEl.textContent = now.toLocaleDateString(undefined, {
        weekday: "long", year: "numeric", month: "long", day: "numeric"
      });
    }
  }

  tick();
  setInterval(tick, 1000);

  // ---- bridge wiring -----------------------------------------------------
  if (!bridge) {
    log("window.AndroidBridge missing - you are viewing this outside the app.");
    return;
  }

  function on(id, handler) {
    var el = document.getElementById(id);
    if (el) el.addEventListener("click", handler);
  }

  on("btn-version", function () {
    log("versionName " + bridge.getAppVersion() +
        " / versionCode " + bridge.getVersionCode() +
        " / id " + bridge.getPackageName());
  });

  on("btn-vibrate", function () {
    bridge.vibrate(40);
    log("vibrate(40) sent");
  });

  on("btn-share", function () {
    bridge.share(document.getElementById("title").textContent,
                 "Shared from the packaged app.");
    log("share sheet requested");
  });

  log("AndroidBridge ready - app version " + bridge.getAppVersion());
})();
