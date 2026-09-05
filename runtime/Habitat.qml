pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import "../Model.js" as Model

// Shared read-only telemetry store. QtObject has no default child list, so
// Process and Timer are named properties. Process.running stays a binding;
// restart waits until the prior child has actually stopped.
QtObject {
    id: root

    property var snapshot: Model.emptySnapshot()
    property var garden: Model.newGarden()
    property var watches: Object.create(null)
    property string status: ""
    property real now: 0
    property real lastSample: 0
    property real observedAt: 0
    property bool failed: false
    property bool restarting: false
    property bool awaitingExit: false
    property bool spawned: false
    property int retryTicks: 0
    property real sampleAgeMs: 0
    property var wallClock: function() { return Date.now(); }
    property ElapsedTimer freshness: ElapsedTimer {}

    readonly property bool observing: Object.keys(watches).length > 0
    readonly property bool collectorRunning: collector.running
    readonly property int collectorPid: collector.running && collector.processId > 0 ? collector.processId : 0
    readonly property bool stale: observing && (failed || (restarting && retryTicks >= 8) || sampleAgeMs > 9000)

    function watch(key, enabled) {
        if (enabled === false) {
            unwatch(key);
            return;
        }
        var name = String(key);
        var current = root.watches && typeof root.watches === "object" ? root.watches : Object.create(null);
        if (Object.prototype.hasOwnProperty.call(current, name))
            return;
        var keys = Object.keys(current);
        if (keys.length >= 64)
            return;
        var next = Object.create(null);
        for (var i = 0; i < keys.length; i++)
            next[keys[i]] = true;
        next[name] = true;
        var first = keys.length === 0;
        if (first)
            beginObservation();
        root.watches = next;
    }

    function unwatch(key) {
        var name = String(key);
        var current = root.watches && typeof root.watches === "object" ? root.watches : Object.create(null);
        if (!Object.prototype.hasOwnProperty.call(current, name))
            return;
        var keys = Object.keys(current);
        var next = Object.create(null);
        for (var i = 0; i < keys.length; i++) {
            if (keys[i] !== name)
                next[keys[i]] = true;
        }
        var last = keys.length === 1;
        if (last)
            endObservation();
        root.watches = next;
    }

    function retry() {
        // Block a new start before changing failure flags. Process shutdown is
        // asynchronous; keep its eventual exit distinct from a real failure.
        if (root.spawned || root.collector.running)
            root.awaitingExit = true;
        root.restarting = true;
        root.failed = false;
        root.observedAt = root.wallClock();
        root.now = root.observedAt;
        root.freshness.restart();
        root.sampleAgeMs = 0;
        root.status = "Connecting to your desktop…";
        root.retryTicks = 0;
        Qt.callLater(root.syncCollector);
    }

    function acceptSample(data) {
        if (!root.observing || root.restarting || root.failed || data === undefined || data === null)
            return;
        var line = String(data);
        if (!line.length || line.length > 131072)
            return;
        try {
            var sample = Model.normalize(JSON.parse(line));
            var stamp = root.wallClock();
            root.snapshot = sample;
            root.lastSample = stamp;
            root.now = stamp;
            root.freshness.restart();
            root.sampleAgeMs = 0;
            root.garden = Model.updateGarden(root.garden, sample, stamp);
            root.status = !sample.processesAvailable ? "Application observations are unavailable. Your garden is held in place." : sample.errors.length ? "Some observations are unavailable." : "";
        } catch (error) {
            root.status = "An observation could not be read.";
        }
    }

    function beginObservation() {
        root.observedAt = root.wallClock();
        root.now = root.observedAt;
        root.freshness.restart();
        root.sampleAgeMs = 0;
        root.failed = false;
        root.retryTicks = 0;
        root.status = "Connecting to your desktop…";
        root.restarting = root.collector.running || root.awaitingExit || root.spawned;
    }

    function endObservation() {
        if (root.spawned || root.collector.running)
            root.awaitingExit = true;
        root.restarting = true;
        root.retryTicks = 0;
    }

    function syncCollector() {
        if (!root.restarting)
            return;
        if (!root.observing || root.failed) {
            root.restarting = false;
            root.retryTicks = 0;
            return;
        }
        if (root.collector.running || root.awaitingExit)
            return;
        root.restarting = false;
        root.retryTicks = 0;
    }

    property Process collector: Process {
        command: ["python3", "-u", decodeURIComponent(Qt.resolvedUrl("../scripts/collect.py").toString().replace("file://", "")), "--interval", "2"]
        running: root.observing && !root.failed && !root.restarting
        stdout: SplitParser {
            onRead: function(data) { root.acceptSample(data); }
        }
        stderr: SplitParser {
            onRead: function(data) {
                if (root.observing && !root.restarting && !root.failed)
                    root.status = "The local observer reported an error.";
            }
        }
        onStarted: {
            root.spawned = true;
            if (!root.observing || root.restarting)
                root.awaitingExit = true;
        }
        onRunningChanged: Qt.callLater(root.syncCollector)
        onExited: function(exitCode) {
            root.spawned = false;
            if (root.awaitingExit) {
                root.awaitingExit = false;
                Qt.callLater(root.syncCollector);
                return;
            }
            if (root.observing && !root.restarting) {
                root.failed = true;
                root.status = "The local observer stopped. You can try again.";
            }
        }
    }

    property Timer watchdog: Timer {
        interval: 1000
        running: root.observing
        repeat: true
        onTriggered: {
            root.now = root.wallClock();
            root.sampleAgeMs = root.freshness.elapsedMs();
            if (!root.restarting)
                return;
            root.retryTicks = Math.min(8, root.retryTicks + 1);
            if (root.retryTicks >= 8) {
                if (!root.collector.running && !root.spawned) {
                    // A failed start may have no exit signal. A child that
                    // actually started retains ownership until onExited.
                    root.awaitingExit = false;
                    root.syncCollector();
                } else {
                    root.status = "Waiting for the previous observer to stop…";
                }
                return;
            }
            root.syncCollector();
        }
    }

    Component.onDestruction: {
        root.watches = Object.create(null);
        root.restarting = false;
    }
}
