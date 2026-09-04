.pragma library

// Pure state transitions shared by the native view and the test harness.
function clamp(n, lo, hi) { return Math.max(lo, Math.min(hi, n)); }
function finite(n, fallback) { return typeof n === "number" && isFinite(n) ? n : fallback; }
function percent(n) { return typeof n === "number" && isFinite(n) ? clamp(n, 0, 100) : null; }
function cleanName(value) { return String(value || "unknown").replace(/[\x00-\x1f\x7f-\x9f]/g, "").slice(0, 64); }
function hash(text) {
    var h = 2166136261;
    for (var i = 0; i < text.length; i++) { h ^= text.charCodeAt(i); h = Math.imul(h, 16777619); }
    return h >>> 0;
}
function random(seed) { var s = seed >>> 0; return function() { s = (Math.imul(s, 1664525) + 1013904223) >>> 0; return s / 4294967296; }; }

var categories = ["browser", "editor", "terminal", "agent", "media", "system", "other"];
var speciesNames = { browser: "Canopy tree", editor: "Ink fern", terminal: "Copper fern", agent: "Lantern bloom", media: "Bellflower", system: "Moss colony", other: "Wild sprout" };
var positions = [{x:305,y:342}, {x:582,y:356}, {x:438,y:381}, {x:229,y:408}, {x:667,y:411}, {x:365,y:445}, {x:550,y:450}];

function emptySnapshot() {
    return { version: 1, timestamp: 0, interval: 0, cpu: null,
        memory: { usedBytes: 0, totalBytes: 0, percent: null },
        network: { rxBytesPerSec: null, txBytesPerSec: null, interfaces: [] },
        processes: [], processCount: 0, uptimeSeconds: 0, errors: [] };
}

function normalize(raw) {
    if (!raw || raw.version !== 1 || !raw.memory || !raw.network || !Array.isArray(raw.processes))
        throw new Error("Unsupported telemetry format");
    var out = emptySnapshot();
    out.timestamp = Math.max(0, finite(raw.timestamp, 0));
    out.interval = clamp(finite(raw.interval, 0), 0, 120);
    out.cpu = percent(raw.cpu);
    out.memory.totalBytes = Math.max(0, finite(raw.memory.totalBytes, 0));
    out.memory.usedBytes = clamp(finite(raw.memory.usedBytes, 0), 0, out.memory.totalBytes);
    out.memory.percent = out.memory.totalBytes > 0 ? percent(raw.memory.percent) : null;
    ["rxBytesPerSec", "txBytesPerSec"].forEach(function(k) {
        out.network[k] = typeof raw.network[k] === "number" && isFinite(raw.network[k]) ? Math.max(0, raw.network[k]) : null;
    });
    out.network.interfaces = Array.isArray(raw.network.interfaces) ? raw.network.interfaces.slice(0, 32).map(cleanName) : [];
    var seen = Object.create(null);
    raw.processes.slice(0, 32).forEach(function(p) {
        if (!p || typeof p !== "object") return;
        var key = cleanName(p.key || p.name);
        if (seen[key] || out.processes.length >= 7) return;
        seen[key] = true;
        out.processes.push({ key: key, name: cleanName(p.name), count: Math.round(clamp(finite(p.count, 1), 1, 100000)),
            cpu: percent(p.cpu), memoryBytes: Math.max(0, finite(p.memoryBytes, 0)),
            category: categories.indexOf(p.category) >= 0 ? p.category : "other" });
    });
    out.processCount = Math.max(0, Math.round(finite(raw.processCount, 0)));
    out.uptimeSeconds = Math.max(0, finite(raw.uptimeSeconds, 0));
    out.errors = Array.isArray(raw.errors) ? raw.errors.slice(0, 6).map(cleanName) : [];
    return out;
}

function newGarden() { return { residents: [], notes: [], observedSeconds: 0, samples: 0, nextNote: 1 }; }
function updateGarden(previous, snapshot, now) {
    var state = previous || newGarden();
    var seconds = clamp(finite(snapshot.interval, 0), 0, 10);
    var residents = [], taken = {}, notes = state.notes.slice(), nextNote = state.nextNote;
    var byKey = Object.create(null);
    snapshot.processes.forEach(function(p) { byKey[p.key] = p; });
    // Keep each resident's position, even when the telemetry ranking changes.
    state.residents.forEach(function(old) {
        var p = byKey[old.key];
        if (p) {
            residents.push({ key: p.key, name: p.name, count: p.count, cpu: p.cpu, memoryBytes: p.memoryBytes,
                category: p.category, slot: old.slot, age: old.age + seconds, missing: 0,
                growth: Math.min(1, old.growth + seconds / 180) });
            taken[old.slot] = true; delete byKey[old.key];
        } else if (old.missing + seconds < 18) {
            residents.push({ key: old.key, name: old.name, count: old.count, cpu: null, memoryBytes: old.memoryBytes,
                category: old.category, slot: old.slot, age: old.age, growth: old.growth, missing: old.missing + seconds });
            taken[old.slot] = true;
        } else {
            notes.unshift({ id: nextNote++, time: now, text: old.name + " left the observed group.", kind: "departed" });
        }
    });
    snapshot.processes.forEach(function(p) {
        if (!byKey[p.key] || residents.length >= 7) return;
        var slot = 0; while (taken[slot] && slot < 7) slot++;
        if (slot >= 7) return;
        taken[slot] = true;
        residents.push({ key: p.key, name: p.name, count: p.count, cpu: p.cpu, memoryBytes: p.memoryBytes,
            category: p.category, slot: slot, age: 0, missing: 0, growth: 0.35 });
        if (state.samples > 0) notes.unshift({ id: nextNote++, time: now, text: p.name + " took root.", kind: "arrival" });
    });
    return { residents: residents, notes: notes.slice(0, 24), observedSeconds: state.observedSeconds + seconds,
        samples: state.samples + 1, nextNote: nextNote };
}

function weather(snapshot) {
    var rx = finite(snapshot.network.rxBytesPerSec, 0);
    var rain = clamp(Math.log(1 + rx / 4096) / Math.log(2049), 0, 1);
    var activity = clamp(finite(snapshot.cpu, 0) / 100, 0, 1);
    return { rain: rain, activity: activity, water: clamp(finite(snapshot.memory.percent, 0) / 100, 0, 1),
        particles: Math.round(5 + activity * 19) };
}

function formatBytes(bytes, decimals) {
    if (bytes === null || bytes === undefined || !isFinite(bytes)) return "—";
    var units = ["B", "KiB", "MiB", "GiB", "TiB"], n = Math.max(0, bytes), u = 0;
    while (n >= 1024 && u < 4) { n /= 1024; u++; }
    return n.toFixed(decimals === undefined ? (u > 0 && n < 10 ? 1 : 0) : decimals) + " " + units[u];
}
function formatRate(bytes) { return bytes === null || bytes === undefined ? "—" : formatBytes(bytes) + "/s"; }
function formatPercent(value) { return value === null || value === undefined ? "—" : Math.round(value) + "%"; }
function duration(seconds) {
    var n = Math.max(0, Math.floor(seconds));
    if (n < 60) return "just now";
    if (n < 3600) return Math.floor(n / 60) + "m";
    if (n < 86400) return Math.floor(n / 3600) + "h " + Math.floor(n % 3600 / 60) + "m";
    return Math.floor(n / 86400) + "d " + Math.floor(n % 86400 / 3600) + "h";
}
function narrative(snapshot) {
    var w = weather(snapshot);
    if (snapshot.timestamp === 0) return "Every little world begins with a moment of quiet.";
    if (snapshot.errors.length) return "A little of the outside world is out of view.";
    if (w.rain > 0.6) return "A passing shower. Plenty of life beneath the glass.";
    if (w.activity > 0.65) return "The lanterns are busy tonight.";
    if (w.rain > 0.2) return "A little rain is finding its way home.";
    return "A small world, quietly getting on with things.";
}
function palette(name, hour) {
    if (name === "auto") name = hour >= 7 && hour < 17 ? "moss" : hour >= 5 && hour < 7 ? "dawn" : "dusk";
    var all = {
        dusk: { name:"dusk", label:"Dusk garden", bg:"#111b20", panel:"#162329", surface:"#1c2b30", line:"#304247", ink:"#e6e8d8", muted:"#9cacaa", gold:"#dfbc7b", leaf:"#77ad8d", leafLight:"#b0ceb0", leafDark:"#315b50", flower:"#eeb589", sky:"#213b42", water:"#468d94", soil:"#2b302b", rock:"#63776c" },
        dawn: { name:"dawn", label:"Dawn garden", bg:"#282124", panel:"#30272b", surface:"#3a3032", line:"#594248", ink:"#f5e5d5", muted:"#c3aaa6", gold:"#f1c085", leaf:"#b1b584", leafLight:"#ddd4a7", leafDark:"#667552", flower:"#eaa3a0", sky:"#684951", water:"#91a6ad", soil:"#42332e", rock:"#938276" },
        moss: { name:"moss", label:"Moss garden", bg:"#17211d", panel:"#1d2a23", surface:"#27382c", line:"#3c5040", ink:"#e7edd8", muted:"#a3b49c", gold:"#dbcc8b", leaf:"#85b273", leafLight:"#c2d697", leafDark:"#3d6546", flower:"#e9b18e", sky:"#354d3d", water:"#609888", soil:"#303a2c", rock:"#718572" }
    };
    return all[name] || all.dusk;
}

function demoSnapshot(step) {
    var t = step || 0;
    return normalize({ version:1, timestamp:1700000000 + t * 2, interval:2, cpu:23 + Math.sin(t / 7) * 12,
        memory:{ usedBytes:7301444403, totalBytes:17179869184, percent:42.5 },
        network:{ rxBytesPerSec:262144 * (1.3 + Math.sin(t / 9)), txBytesPerSec:18432, interfaces:["demo"] },
        processes:[
            {key:"firefox", name:"Firefox", count:8, cpu:8.2, memoryBytes:1430257664, category:"browser"},
            {key:"codex", name:"Codex", count:3, cpu:6.1, memoryBytes:754974720, category:"agent"},
            {key:"neovim", name:"Neovim", count:1, cpu:2.4, memoryBytes:115343360, category:"editor"},
            {key:"ghostty", name:"Ghostty", count:2, cpu:0.9, memoryBytes:178257920, category:"terminal"},
            {key:"music", name:"Music", count:1, cpu:1.3, memoryBytes:293601280, category:"media"},
            {key:"files", name:"Files", count:1, cpu:0.2, memoryBytes:73400320, category:"other"}
        ], processCount:84, uptimeSeconds:20432, errors:[] });
}
