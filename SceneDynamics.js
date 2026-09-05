.pragma library

// Rendering state only. These functions never retain telemetry or wall-clock history.
function finite(value, fallback) { return typeof value === "number" && isFinite(value) ? value : fallback; }
function clamp(value, low, high) { return Math.max(low, Math.min(high, value)); }
function smooth(from, to, seconds, response) {
    return from + (to - from) * (1 - Math.exp(-clamp(finite(seconds, 0), 0, .1) / response));
}
function smoothstep(low, high, value) {
    var t = clamp((value - low) / (high - low), 0, 1);
    return t * t * (3 - 2 * t);
}
function hash(text) {
    var value = 2166136261;
    for (var i = 0; i < text.length; i++) value = Math.imul(value ^ text.charCodeAt(i), 16777619);
    return value >>> 0;
}

function skyAt(hour) {
    var h = ((finite(hour, 20) % 24) + 24) % 24;
    var day = smoothstep(5.5, 7.5, h) * (1 - smoothstep(16.5, 18.5, h));
    var arc = clamp((h - 6) / 12, 0, 1);
    // Sun and moon never share the glass: a short empty window is a horizon
    // glow, not a second celestial body.
    var sun = smoothstep(5.6, 7.2, h) * (1 - smoothstep(16.8, 18.4, h));
    var moon = h < 12 ? (1 - smoothstep(4.0, 5.4, h)) : smoothstep(18.6, 20.0, h);
    var horizon = Math.max(
        smoothstep(4.5, 5.7, h) * (1 - smoothstep(5.7, 7.2, h)),
        smoothstep(16.7, 18.2, h) * (1 - smoothstep(18.2, 19.6, h))
    );
    var interior = day;
    return { hour:h, daylight:day, night:1-day,
        warmth:4 * day * (1-day), sunX:620-115*arc, sunY:197-89*Math.sin(arc*Math.PI),
        opening:.32+.68*day, sun:sun, moon:moon, stars:moon, interior:interior, horizon:horizon };
}

function slotsFor(residents) {
    var slots = [null, null, null, null, null, null, null];
    // The model already bounds and normalizes residents. Keep the renderer safe
    // when used independently by offscreen fixtures or another QML consumer.
    var list = Array.isArray(residents) ? residents : [];
    for (var i = 0; i < Math.min(list.length, 32); i++) {
        var r = list[i];
        if (r && Number.isInteger(r.slot) && r.slot >= 0 && r.slot < 7 && !slots[r.slot]) slots[r.slot] = r;
    }
    return slots;
}

function targetEnergy(resident) { return clamp(finite(resident ? resident.cpu : 0, 0) / 100, 0, 1); }
function growth(resident) { return clamp(finite(resident ? resident.growth : 0, .35), 0, 1); }

function pose(category, key, phase, energy, impulse) {
    var shapes = {
        browser:[.72, .63, .6, .002], editor:[1.75, .93, .9, .003],
        terminal:[1.32, .78, .75, .003], agent:[1.12, .8, .8, .004],
        media:[1.65, 1.03, .85, .004], system:[.22, .49, .3, .012], other:[1.65, .89, .8, .004]
    };
    var s = Object.prototype.hasOwnProperty.call(shapes,category) ? shapes[category] : shapes.other;
    var offset = hash(String(key)) / 4294967296 * Math.PI * 2;
    var t = finite(phase, 0), e = clamp(finite(energy, 0), 0, 1);
    return {
        angle:clamp(Math.sin(t*s[1]+offset)*(s[0]+e*s[2]) + Math.sin(t*.31+offset)*.23 + finite(impulse, 0), -7, 7),
        stretch:1+Math.sin(t*s[1]*.73+offset)*(s[3]+e*.003),
        glow:clamp(.1+e*.7+(Math.sin(t*1.5+offset)+1)*.045, 0, 1)
    };
}

function addTouch(previous, x, y, kind) {
    var result = previous.slice(-3);
    result.push({ x:clamp(finite(x, 450), 154, 746), y:clamp(finite(y, 400), 60, 461), kind:kind, age:0 });
    return result;
}
function ageTouches(previous, seconds) {
    var result = [], dt = clamp(finite(seconds, 0), 0, .1);
    previous.forEach(function(touch) {
        var age = touch.age + dt;
        if (age < 3.2) result.push({x:touch.x,y:touch.y,kind:touch.kind,age:age});
    });
    return result;
}
function impulseAt(touches, x, y) {
    var result = 0;
    touches.forEach(function(touch) {
        var dx = x-touch.x, dy = y-touch.y;
        var distance = Math.sqrt(dx*dx+dy*dy);
        var reach = Math.max(0, 1-distance/310);
        result += Math.sin(touch.age*9.5) * Math.exp(-touch.age*1.85) * 4.8 * reach * (dx < -8 ? -1 : 1);
    });
    return clamp(result, -5.5, 5.5);
}
function inPond(x, y) { return Math.pow((x-566)/82, 2)+Math.pow((y-415)/23, 2) <= 1; }
function inGlass(x, y) {
    if (y < 47 || y > 461 || x < 144 || x > 756) return false;
    if (y < 235) return Math.pow((x-450)/305, 2)+Math.pow((y-235)/190, 2) <= 1;
    if (y > 410) return Math.pow((x-450)/310, 2)+Math.pow((y-410)/77, 2) <= 1;
    return true;
}
