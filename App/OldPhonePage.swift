/// The page an old phone keeps open. It has to run on very old browsers, so there is no
/// modern syntax in here and everything it needs is in this one string. The Windows app
/// serves the same page.
enum OldPhonePage {
    static let html = #"""
<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no">
<meta name="apple-mobile-web-app-capable" content="yes">
<meta name="apple-mobile-web-app-status-bar-style" content="black">
<meta name="format-detection" content="telephone=no">
<title>Clawdmeter</title>
<style>
html, body {
  margin: 0;
  padding: 0;
  height: 100%;
  background: #1d1917;
  color: #fff;
  font-family: "Helvetica Neue", Helvetica, Arial, sans-serif;
  overflow: hidden;
  -webkit-text-size-adjust: none;
  -webkit-user-select: none;
}
#stage {
  position: absolute;
  left: 0;
  top: 0;
  background: #2a2320;
  background-image: -webkit-linear-gradient(top, #342b27, #1d1917);
  overflow: hidden;
  -webkit-transform-origin: 0 0;
}
#plan {
  position: absolute;
  left: 22px;
  top: 16px;
  font-size: 12px;
  letter-spacing: 2px;
  color: #a3908a;
}
#live {
  position: absolute;
  right: 22px;
  top: 18px;
  width: 9px;
  height: 9px;
  border-radius: 5px;
  background: #4a403c;
}
#live.on {
  background: #ec9676;
  -webkit-animation: pulse 1.6s infinite;
}
@-webkit-keyframes pulse {
  0% { opacity: 1; }
  50% { opacity: 0.25; }
  100% { opacity: 1; }
}
#value {
  position: absolute;
  left: 20px;
  top: 30px;
  font-size: 112px;
  font-weight: 200;
  letter-spacing: -4px;
  color: #ec9676;
}
#title {
  position: absolute;
  left: 24px;
  top: 150px;
  font-size: 17px;
  color: #efe4e0;
}
#detail {
  position: absolute;
  left: 24px;
  top: 174px;
  font-size: 13px;
  color: #a3908a;
}
.track {
  position: absolute;
  left: 22px;
  height: 10px;
  border-radius: 5px;
  background: #3b3029;
  overflow: hidden;
}
.fill {
  height: 10px;
  width: 0;
  border-radius: 5px;
  background: #d77757;
  background-image: -webkit-linear-gradient(left, #be5c3e, #ec9676);
}
#bar1 { top: 200px; }
#bar2 { top: 226px; height: 6px; }
#bar2 .fill { height: 6px; }
#second {
  position: absolute;
  right: 22px;
  top: 220px;
  font-size: 12px;
  color: #a3908a;
}
#today {
  position: absolute;
  right: 22px;
  bottom: 14px;
  font-size: 13px;
  color: #a3908a;
  text-align: right;
}
#ground {
  position: absolute;
  left: 0;
  right: 0;
  bottom: 34px;
  height: 1px;
  background: #3b3029;
}
#clawd {
  position: absolute;
  bottom: 35px;
  left: 0;
  width: 48px;
  height: 30px;
}
.px { position: absolute; background: #d77757; }
.eye { background: #17120f; }
.leg { background: #be5c3e; }
#clawd.tired .px, #clawd.sleeping .px { background: #c06a4c; }
#z {
  position: absolute;
  left: 58px;
  top: 0;
  font-size: 15px;
  color: #a3908a;
  display: none;
}
#clawd.sleeping #z { display: block; }
#ask {
  position: absolute;
  right: 20px;
  top: 46px;
  font-size: 84px;
  font-weight: 200;
  color: #f5b24c;
  display: none;
}
#ask.on {
  display: block;
  -webkit-animation: pulse 1.4s infinite;
}
#offline {
  position: absolute;
  left: 22px;
  bottom: 14px;
  font-size: 13px;
  color: #d77757;
  display: none;
}
</style>
</head>
<body>
<div id="stage">
  <div id="plan">CLAWDMETER</div>
  <div id="live"></div>
  <div id="value">0%</div>
  <div id="title">Waiting for the computer</div>
  <div id="detail"></div>
  <div class="track" id="bar1"><div class="fill" id="fill1"></div></div>
  <div class="track" id="bar2"><div class="fill" id="fill2"></div></div>
  <div id="second"></div>
  <div id="ground"></div>
  <div id="clawd">
    <div id="z">z z</div>
  </div>
  <div id="today"></div>
  <div id="ask">!</div>
  <div id="offline">No answer from the computer</div>
</div>
<script>
var WIDE = 480;
var TALL = 320;
var UNIT = 3;
var state = { fraction: 0, seconds: 0, walking: 1, x: 10, step: 1, mood: "idle" };

function el(id) { return document.getElementById(id); }

function layout() {
  var stage = el("stage");
  var w = window.innerWidth;
  var h = window.innerHeight;
  stage.style.width = WIDE + "px";
  stage.style.height = TALL + "px";
  el("bar1").style.width = (WIDE - 44) + "px";
  el("bar2").style.width = (WIDE - 150) + "px";

  if (h > w) {
    // The phone is upright, so the page lies down instead.
    var scale = Math.min(h / WIDE, w / TALL);
    stage.style.webkitTransform = "translateX(" + w + "px) rotate(90deg) scale(" + scale + ")";
  } else {
    var flat = Math.min(w / WIDE, h / TALL);
    stage.style.webkitTransform = "scale(" + flat + ")";
  }
}

function pixel(parent, x, y, w, h, kind) {
  var box = document.createElement("div");
  box.className = "px" + (kind ? " " + kind : "");
  box.style.left = (x * UNIT) + "px";
  box.style.top = (y * UNIT) + "px";
  box.style.width = (w * UNIT) + "px";
  box.style.height = (h * UNIT) + "px";
  parent.appendChild(box);
  return box;
}

var legsA = [];
var legsB = [];

function buildClawd() {
  var clawd = el("clawd");
  pixel(clawd, 2, 0, 12, 8);
  pixel(clawd, 0, 4, 2, 2);
  pixel(clawd, 14, 4, 2, 2);
  pixel(clawd, 4, 2, 1, 2, "eye");
  pixel(clawd, 11, 2, 1, 2, "eye");
  legsA.push(pixel(clawd, 3, 7, 1, 3, "leg"));
  legsA.push(pixel(clawd, 10, 7, 1, 3, "leg"));
  legsB.push(pixel(clawd, 5, 7, 1, 3, "leg"));
  legsB.push(pixel(clawd, 12, 7, 1, 3, "leg"));
}

function show(list, on) {
  for (var i = 0; i < list.length; i++) { list[i].style.opacity = on ? 1 : 0.25; }
}

var frame = 0;
function walk() {
  frame++;
  var clawd = el("clawd");
  if (state.mood === "sleeping") {
    clawd.style.left = (WIDE - 90) + "px";
    show(legsA, true);
    show(legsB, true);
    clawd.style.bottom = "35px";
    return;
  }
  var speed = state.mood === "busy" ? 2.4 : 1.2;
  state.x += state.step * speed;
  if (state.x > WIDE - 60) { state.step = -1; }
  if (state.x < 6) { state.step = 1; }
  clawd.style.left = Math.round(state.x) + "px";
  var swap = Math.floor(frame / 6) % 2 === 0;
  show(legsA, swap);
  show(legsB, !swap);
  clawd.style.bottom = (35 + (Math.floor(frame / 6) % 2)) + "px";
}

function countdown() {
  if (state.seconds > 0) {
    state.seconds--;
    el("detail").innerHTML = "Resets in " + clock(state.seconds);
  }
}

function clock(total) {
  var minutes = Math.ceil(total / 60);
  if (minutes < 60) { return minutes + "m"; }
  var hours = Math.floor(minutes / 60);
  var rest = minutes % 60;
  if (hours < 24) { return rest === 0 ? hours + "h" : hours + "h " + rest + "m"; }
  var days = Math.floor(hours / 24);
  return days + "d " + (hours % 24) + "h";
}

function paint(data) {
  el("plan").innerHTML = (data.plan || "Clawdmeter").toUpperCase();
  el("value").innerHTML = data.value || "0%";
  el("title").innerHTML = data.title || "";
  el("detail").innerHTML = data.note || data.detail || "";
  el("fill1").style.width = Math.round((data.fraction || 0) * (WIDE - 44)) + "px";
  el("value").style.color = tint(data.severity);
  el("fill1").style.backgroundImage = "-webkit-linear-gradient(left, " + deep(data.severity) + ", " + tint(data.severity) + ")";

  if (data.second) {
    el("bar2").style.display = "block";
      el("fill2").style.width = Math.round((data.second.fraction || 0) * (WIDE - 150)) + "px";
    el("second").innerHTML = data.second.title + "  " + data.second.value;
  } else {
    el("bar2").style.display = "none";
    el("second").innerHTML = "";
  }

  el("today").innerHTML = data.today ? data.today + " tokens today<br>" + data.requests + " requests" : "";
  el("live").className = data.working ? "on" : "";
  el("ask").className = data.asking ? "on" : "";
  el("clawd").className = data.mood || "idle";
  state.mood = data.mood || "idle";
  state.seconds = data.resetSeconds || 0;
  el("offline").style.display = "none";
}

function tint(severity) {
  if (severity === "critical") { return "#ff695e"; }
  if (severity === "warning") { return "#f5b24c"; }
  return "#ec9676";
}

function deep(severity) {
  if (severity === "critical") { return "#e23e3a"; }
  if (severity === "warning") { return "#de8c2c"; }
  return "#be5c3e";
}

function key() {
  var mark = window.location.search.indexOf("k=");
  return mark < 0 ? "" : window.location.search.substring(mark + 2);
}

function refresh() {
  var request = new XMLHttpRequest();
  request.open("GET", "/usage?k=" + key(), true);
  request.onreadystatechange = function () {
    if (request.readyState !== 4) { return; }
    if (request.status === 200) {
      try {
        paint(JSON.parse(request.responseText));
      } catch (error) {
        el("offline").style.display = "block";
      }
    } else {
      el("offline").style.display = "block";
    }
  };
  request.onerror = function () { el("offline").style.display = "block"; };
  request.send();
}

buildClawd();
layout();
refresh();
window.onresize = layout;
window.onorientationchange = function () { window.setTimeout(layout, 300); };
window.setInterval(refresh, 15000);
window.setInterval(countdown, 1000);
window.setInterval(walk, 60);
</script>
</body>
</html>
"""#
}
