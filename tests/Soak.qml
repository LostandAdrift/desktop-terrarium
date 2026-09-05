import QtQuick
import QtQuick.Window
import ".."
import "../Model.js" as Model

// Opt-in synthetic view soak. It never reads native desktop state or saves art.
Window {
    id: root
    width: 1120; height: 720; visible: true; color: "#111b20"
    property int seconds: 30
    property int warmup: 5
    property int teardown: 5
    property int elapsed: 0
    property int step: 0
    property string phaseName: "warmup"
    property var state: Model.newGarden()
    property real previousPhase: -1
    property bool previouslyAnimated: true
    property bool finished: false
    property int phaseSince: 0
    property string frozenPostcard: ""
    property bool postcardBecameReady: false
    property bool postcardReleasePending: false
    property int postcardPhaseUpdates: 0
    property int postcardRequests: 0
    property int postcardReadyCount: 0
    property int postcardReleases: 0
    property int postcardFrozenChecks: 0
    property int postcardLiveUpdates: 0

    function findNamed(item, name) {
        if (!item) return null;
        if (item.objectName === name) return item;
        var children = item.children || [];
        for (var i = 0; i < children.length; i++) {
            var found = findNamed(children[i], name);
            if (found) return found;
        }
        return null;
    }
    function scenesIn(item) {
        if (!item) return [];
        var found = typeof item.botanicalPaintCount === "function" ? [item] : [];
        var children = item.children || [];
        for (var i = 0; i < children.length; i++) found = found.concat(scenesIn(children[i]));
        return found;
    }
    function fail(code) {
        if (finished) return;
        finished = true;
        console.log("SOAK " + JSON.stringify({ type: "error", code: code }));
        Qt.exit(1);
    }
    function sample(index) {
        var s = Model.demoSnapshot(index);
        s.processes = [];
        s.processesAvailable = true;
        for (var i = 0; i < 7; i++) {
            s.processes.push({
                key: "synthetic-" + i + (i === 6 ? "-" + Math.floor((index + 10) / 12) : ""),
                name: "Specimen " + (i + 1), category: Model.categories[i],
                count: i + 1, cpu: (index + i) % 4 === 0 ? 100 : (index * (i + 1)) % 30,
                memoryBytes: (i + 1) * 10485760
            });
        }
        s.cpu = index % 4 < 2 ? 0 : 100;
        s.memory.percent = [0, 50, 100][index % 3];
        s.memory.usedBytes = s.memory.totalBytes * s.memory.percent / 100;
        s.network.rxBytesPerSec = index % 4 < 2 ? 0 : 1073741824;
        s.network.txBytesPerSec = index % 4 < 2 ? 1073741824 : 0;
        if (index % 53 >= 45 && index % 53 <= 47) {
            s.processesAvailable = false;
            s.processes = [];
            s.errors = ["process scan incomplete"];
        }
        return Model.normalize(s);
    }
    function updateSample() {
        if (!viewLoader.item) return;
        var s = sample(step);
        state = Model.updateGarden(state, s, 1700000000000 + step * 2000);
        viewLoader.item.snapshot = s;
        viewLoader.item.garden = state;
        viewLoader.item.hour = step % 24;
        viewLoader.item.paletteName = ["auto", "dusk", "dawn", "moss"][Math.floor(step / 4) % 4];
        if (phaseName === "postcard") {
            postcardPhaseUpdates++;
            postcardLiveUpdates++;
        }
        var scene = findNamed(viewLoader.item, "gardenScene");
        if (scene && scene.visible) {
            // Exercise the bounded native scene response without pointer input.
            for (var t = 0; t < 12; t++) scene.touchAt(t % 2 ? 350 : 560, t % 2 ? 250 : 415, "");
        }
        step++;
    }
    function requestedPhase() {
        if (elapsed >= seconds - teardown) return "teardown";
        if (elapsed < warmup) return "warmup";
        var phases = ["animated", "paused", "hidden", "reduced", "journal", "options", "art", "postcard"];
        // The shortest run still dwells in preview for five seconds, allowing
        // its painted readiness acknowledgement and multiple live updates.
        var regular = seconds >= 240 ? 20 : 2;
        var preview = seconds >= 240 ? 20 : 5;
        var offset = (elapsed - warmup) % (regular * 7 + preview);
        var next = phases[Math.min(7, Math.floor(offset / regular))];
        // Do not begin a new preview that teardown would truncate before its
        // readiness deadline. Earlier complete cycles supply its coverage.
        if (next === "postcard" && phaseName !== "postcard" && seconds - teardown - elapsed < 5)
            return "animated";
        return next;
    }
    function setPhase() {
        var next = requestedPhase();
        if (next === phaseName) return;
        if (phaseName === "postcard") {
            if (!postcardBecameReady || postcardPhaseUpdates < 1) { fail("postcard_coverage_incomplete"); return; }
            postcardReleasePending = true;
        }
        phaseName = next;
        phaseSince = elapsed;
        if (phaseName === "teardown") {
            viewLoader.active = false;
            return;
        }
        var v = viewLoader.item;
        if (!v) { fail("view_missing"); return; }
        v.visible = phaseName !== "hidden";
        v.active = phaseName !== "hidden";
        v.motionPaused = phaseName === "paused";
        v.reducedMotion = phaseName === "reduced";
        if (phaseName === "postcard") {
            if (!v.requestPostcard()) { fail("postcard_request_refused"); return; }
            frozenPostcard = JSON.stringify(v.postcardSnapshot);
            postcardBecameReady = false;
            postcardPhaseUpdates = 0;
            postcardRequests++;
        } else {
            v.showSection(["journal", "options", "art"].indexOf(phaseName) >= 0 ? phaseName : "garden");
            frozenPostcard = "";
        }
    }
    function report() {
        var v = viewLoader.item;
        var scene = findNamed(v, "gardenScene");
        var scenes = scenesIn(v);
        var cardScene = findNamed(v, "postcardScene");
        var card = findNamed(v, "postcardPreview");
        if (viewLoader.item && !scene) { fail("scene_missing"); return; }
        var residents = state.residents, slots = {};
        if (residents.length > 7 || state.notes.length > 24) { fail("state_bound"); return; }
        for (var i = 0; i < residents.length; i++) {
            var r = residents[i];
            if (r.slot < 0 || r.slot >= 7 || slots[r.slot] || !isFinite(r.growth) || r.growth < 0 || r.growth > 1) {
                fail("resident_invariant"); return;
            }
            slots[r.slot] = true;
        }
        var textures = 0, transients = 0, paints = 0, animations = 0;
        for (var s = 0; s < scenes.length; s++) {
            var current = scenes[s];
            if (typeof current.animationRunning !== "boolean") { fail("scene_counters_missing"); return; }
            if (current.residentTextureCount > 7 || current.transientCount > 4) { fail("scene_object_bound"); return; }
            textures += current.residentTextureCount;
            transients += current.transientCount;
            paints += current.botanicalPaintCount();
            animations += current.animationRunning ? 1 : 0;
        }
        if (scenes.length > 2 || textures > 14 || animations > 1 || transients > 4) { fail("aggregate_scene_bound"); return; }
        if (cardScene && (cardScene.animationRunning || cardScene.phase !== 0)) { fail("postcard_animated"); return; }
        if (scene && !previouslyAnimated && previousPhase >= 0 && scene.phase !== previousPhase) {
            fail("paused_scene_advanced"); return;
        }
        if (phaseName === "postcard") {
            if (!v.postcardLoaded) { fail("postcard_unloaded_early"); return; }
            if (JSON.stringify(v.postcardSnapshot) !== frozenPostcard) { fail("postcard_input_mutated"); return; }
            if (v.postcardReady) {
                if (!card || !cardScene || scenes.length !== 2 || JSON.stringify(card.snapshot) !== frozenPostcard) {
                    fail("postcard_snapshot_mismatch"); return;
                }
                if (!postcardBecameReady) { postcardBecameReady = true; postcardReadyCount++; }
                postcardFrozenChecks++;
            } else if (elapsed - phaseSince >= 5) { fail("postcard_readiness_timeout"); return; }
        } else {
            if (card || cardScene || (v && (v.postcardLoaded || v.postcardSnapshot !== null)) || scenes.length > 1) {
                fail("postcard_loader_retained"); return;
            }
            if (postcardReleasePending) { postcardReleases++; postcardReleasePending = false; }
        }
        previousPhase = scene ? scene.phase : -1;
        previouslyAnimated = scene ? scene.animationRunning : false;
        console.log("SOAK " + JSON.stringify({
            type: "metric", second: elapsed, phase: phaseName, samples: state.samples,
            residents: residents.length, notes: state.notes.length, viewLoaded: !!viewLoader.item,
            animationRunning: animations > 0, scenes: scenes.length, animatedScenes: animations,
            postcardLoaded: v ? v.postcardLoaded : false, postcardReady: v ? v.postcardReady : false,
            postcardAnimated: cardScene ? cardScene.animationRunning : false,
            postcardRequests: postcardRequests, postcardReadyCount: postcardReadyCount,
            postcardReleases: postcardReleases, postcardFrozenChecks: postcardFrozenChecks,
            postcardLiveUpdates: postcardLiveUpdates,
            textures: textures, transients: transients, paints: paints
        }));
    }

    Loader {
        id: viewLoader
        anchors.fill: parent
        sourceComponent: Component {
            TerrariumView { demo: true; paletteName: "dusk"; active: true; status: ""; postcardAvailable: true }
        }
    }
    Timer {
        interval: 1000; running: !root.finished; repeat: true
        onTriggered: {
            root.elapsed++;
            // Check animation under the previous phase before changing gates.
            root.report();
            if (root.finished) return;
            if (root.elapsed >= root.seconds) {
                root.finished = true;
                console.log("SOAK " + JSON.stringify({type: "done", second: root.elapsed, viewLoaded: !!viewLoader.item}));
                Qt.quit();
                return;
            }
            root.setPhase();
            if (root.finished) return;
            if (root.elapsed % 2 === 0) root.updateSample();
            var scene = root.findNamed(viewLoader.item, "gardenScene");
            root.previousPhase = scene ? scene.phase : -1;
            root.previouslyAnimated = scene ? scene.animationRunning : false;
        }
    }
    Component.onCompleted: {
        var args = Qt.application.arguments;
        for (var i = 0; i < args.length; i++) {
            if (args[i] === "--seconds" && args[i + 1]) seconds = Number(args[++i]);
            else if (args[i] === "--warmup" && args[i + 1]) warmup = Number(args[++i]);
        }
        if (!isFinite(seconds) || seconds < 30 || seconds > 86400 || warmup < 5 || warmup >= seconds - teardown) {
            fail("invalid_duration"); return;
        }
        updateSample();
        setPhase();
        report();
    }
}
