package com.pufy.app.ui.miniapp

// iOS ControlSpot.pageScript (MiniAppView.swift) — yüzen düğmenin altında dokunulabilir öğe varsa boş köşeyi bildirir
object ControlSpotScript {
    const val SOURCE = """
(function(){
if (window.__pufyFreeSpot) return;
var probe = null;
function insets(){
if (!probe) {
probe = document.createElement('div');
probe.style.cssText = 'position:fixed;left:0;top:0;width:0;height:0;visibility:hidden;pointer-events:none;' +
'padding:env(safe-area-inset-top) env(safe-area-inset-right) env(safe-area-inset-bottom) env(safe-area-inset-left)';
(document.body || document.documentElement).appendChild(probe);
}
var s = getComputedStyle(probe);
return { t: parseFloat(s.paddingTop) || 0, r: parseFloat(s.paddingRight) || 0, b: parseFloat(s.paddingBottom) || 0, l: parseFloat(s.paddingLeft) || 0 };
}
function spots(){
var W = innerWidth, H = innerHeight, i = insets(), size = 46;
var bottom = H - i.b - 4 - 34 - 6, top = i.t + 8 - 6, mid = H * 0.5 - 23;
var right = W - i.r - 14 - 34 - 6, left = i.l + 14 - 6;
return [[right, bottom], [left, bottom], [right, mid], [left, mid], [right, top], [left, top]]
.map(function(p){ return { x: p[0], y: p[1], w: size, h: size }; });
}
var SEL = 'button,a[href],input:not([type=hidden]),select,textarea,label,summary,[role=button],[role=tab],[role=switch],' +
'[role=checkbox],[role=link],[onclick],[tabindex]:not([tabindex="-1"]),.p-btn,.p-chip,.p-icon-btn';
function scrollsAway(el){
var doc = document.scrollingElement || document.documentElement;
var docScrolls = doc.scrollHeight > innerHeight + 4;
for (var e = el; e && e !== document.body && e !== document.documentElement; e = e.parentElement) {
var cs = getComputedStyle(e);
if (cs.position === 'fixed' || cs.position === 'sticky') return false;
if (/(auto|scroll)/.test(cs.overflowY) && e.scrollHeight > e.clientHeight + 4) return true;
}
return docScrolls;
}
function blocked(r){
var els = document.querySelectorAll(SEL);
for (var k = 0; k < els.length; k++) {
var el = els[k], b = el.getBoundingClientRect();
if (b.width < 2 || b.height < 2) continue;
if (b.right < r.x || b.left > r.x + r.w || b.bottom < r.y || b.top > r.y + r.h) continue;
var cs = getComputedStyle(el);
if (cs.visibility === 'hidden' || cs.pointerEvents === 'none' || parseFloat(cs.opacity) < 0.05) continue;
if (scrollsAway(el)) continue;
var cx = Math.min(Math.max(r.x + r.w / 2, b.left + 1), b.right - 1);
var cy = Math.min(Math.max(r.y + r.h / 2, b.top + 1), b.bottom - 1);
var hit = document.elementFromPoint(cx, cy);
if (hit && (hit === el || el.contains(hit) || hit.contains(el))) return true;
}
return false;
}
window.__pufyFreeSpot = function(){
var s = spots();
for (var i = 0; i < s.length; i++) { if (!blocked(s[i])) return i; }
return 0;
};
var last = -1, timer = null, lastRun = 0;
function check(){
timer = null; lastRun = Date.now();
var i = window.__pufyFreeSpot();
if (i !== last) { last = i; try { PufyNative.layout(i); } catch (e) {} }
}
function soon(){ if (!timer) timer = setTimeout(check, Math.max(400, 1000 - (Date.now() - lastRun))); }
new MutationObserver(soon).observe(document.documentElement, { subtree: true, childList: true, attributes: true, attributeFilter: ['class', 'hidden', 'style'] });
addEventListener('resize', soon); addEventListener('load', soon); document.addEventListener('scroll', soon, true);
setTimeout(check, 300); setTimeout(check, 1500);
})();
"""
}
