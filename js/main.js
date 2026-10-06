// Stalactite — canvas renderer and viewport helper.
//
// Elm owns the model and produces a pure scene description; this file walks
// that description and issues the canvas calls. Nothing here decides what the
// picture means.

(function () {
  "use strict";

  function fillStyle(ctx, f) {
    if (!f) return null;
    if (f.k === "flat") return f.c;
    if (f.k === "linear") {
      var g = ctx.createLinearGradient(f.x0, f.y0, f.x1, f.y1);
      f.stops.forEach(function (s) {
        g.addColorStop(Math.min(1, Math.max(0, s[0])), s[1]);
      });
      return g;
    }
    if (f.k === "radial") {
      var r = ctx.createRadialGradient(f.x0, f.y0, Math.max(0, f.r0), f.x1, f.y1, Math.max(0.01, f.r1));
      f.stops.forEach(function (s) {
        r.addColorStop(Math.min(1, Math.max(0, s[0])), s[1]);
      });
      return r;
    }
    return null;
  }

  function applyStroke(ctx, s) {
    ctx.strokeStyle = s.c;
    ctx.lineWidth = s.w;
    ctx.lineCap = s.cap || "round";
    ctx.lineJoin = "round";
    ctx.setLineDash(s.dash || []);
  }

  function tracePath(ctx, pts, closed) {
    ctx.beginPath();
    for (var i = 0; i < pts.length; i++) {
      var p = pts[i];
      if (i === 0) ctx.moveTo(p[0], p[1]);
      else ctx.lineTo(p[0], p[1]);
    }
    if (closed) ctx.closePath();
  }

  function drawShape(ctx, s) {
    switch (s.t) {
      case "rect": {
        var f = fillStyle(ctx, s.f);
        if (f) {
          ctx.fillStyle = f;
          ctx.fillRect(s.x, s.y, s.w, s.h);
        }
        break;
      }
      case "circle": {
        ctx.beginPath();
        ctx.arc(s.x, s.y, Math.max(0.01, s.r), 0, Math.PI * 2);
        var cf = fillStyle(ctx, s.f);
        if (cf) {
          ctx.fillStyle = cf;
          ctx.fill();
        }
        if (s.s) {
          applyStroke(ctx, s.s);
          ctx.stroke();
        }
        break;
      }
      case "ellipse": {
        ctx.beginPath();
        ctx.ellipse(s.x, s.y, Math.max(0.01, s.rx), Math.max(0.01, s.ry), 0, 0, Math.PI * 2);
        var ef = fillStyle(ctx, s.f);
        if (ef) {
          ctx.fillStyle = ef;
          ctx.fill();
        }
        if (s.s) {
          applyStroke(ctx, s.s);
          ctx.stroke();
        }
        break;
      }
      case "poly": {
        if (!s.p || s.p.length < 2) break;
        tracePath(ctx, s.p, !!s.closed);
        var pf = fillStyle(ctx, s.f);
        if (pf) {
          ctx.fillStyle = pf;
          ctx.fill();
        }
        if (s.s) {
          applyStroke(ctx, s.s);
          ctx.stroke();
        }
        // reset the dash so it never leaks into the next shape
        ctx.setLineDash([]);
        break;
      }
      case "seg": {
        applyStroke(ctx, s.s);
        ctx.beginPath();
        ctx.moveTo(s.x0, s.y0);
        ctx.lineTo(s.x1, s.y1);
        ctx.stroke();
        ctx.setLineDash([]);
        break;
      }
      case "label": {
        ctx.font = s.font;
        ctx.fillStyle = s.c;
        ctx.textAlign = s.align || "left";
        ctx.textBaseline = "alphabetic";
        ctx.fillText(s.v, s.x, s.y);
        break;
      }
      case "group": {
        (s.shapes || []).forEach(function (inner) {
          drawShape(ctx, inner);
        });
        break;
      }
      default:
        break;
    }
  }

  // Elm's outgoing port has already turned the scene into a plain object by the
  // time it arrives here, so this accepts either an object or a JSON string.
  function render(payload) {
    var el = document.getElementById("stage");
    if (!el) return;

    var scene = payload;
    if (typeof payload === "string") {
      try {
        scene = JSON.parse(payload);
      } catch (e) {
        return;
      }
    }
    if (!scene || !scene.shapes) return;

    // Match the backing store to the CSS box times the device pixel ratio so
    // the drawing is crisp on high-density displays. The scene is authored in
    // CSS pixels, so we scale the context instead of the geometry.
    var dpr = Math.min(window.devicePixelRatio || 1, 2);
    var box = el.getBoundingClientRect();
    var cssW = Math.max(240, Math.round(box.width || scene.w));
    var cssH = Math.round(cssW * (scene.h / scene.w));

    var bw = Math.round(cssW * dpr);
    var bh = Math.round(cssH * dpr);
    if (el.width !== bw || el.height !== bh) {
      el.width = bw;
      el.height = bh;
    }
    el.style.height = cssH + "px";

    var ctx = el.getContext("2d");
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    ctx.clearRect(0, 0, cssW, cssH);

    // the scene was authored at scene.w; scale to the actual CSS width
    var k = cssW / scene.w;
    ctx.save();
    ctx.scale(k, k);
    ctx.fillStyle = scene.bg;
    ctx.fillRect(0, 0, scene.w, scene.h);
    (scene.shapes || []).forEach(function (s) {
      drawShape(ctx, s);
    });
    ctx.restore();
    ctx.setLineDash([]);
  }

  // ---- ports -------------------------------------------------------------

  var app = Elm.Main.init({ node: document.getElementById("root") });

  app.ports.renderScene.subscribe(render);

  var raf = null;
  function notify() {
    if (raf) cancelAnimationFrame(raf);
    raf = requestAnimationFrame(function () {
      var el = document.getElementById("stage");
      if (el) app.ports.canvasResized.send(Math.round(el.getBoundingClientRect().width));
    });
  }
  window.addEventListener("resize", notify);
  window.addEventListener("orientationchange", notify);
  notify();
})();
