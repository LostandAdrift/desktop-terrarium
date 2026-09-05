pragma ComponentBehavior: Bound
import QtQuick
import QtCore
import Quickshell
import Quickshell.Io

QtObject {
    id: root
    property string outputDirectory: picturesDirectory()
    readonly property bool busy: phase !== "idle"
    property string status: ""
    property string savedPath: ""
    signal completed(bool ok, string path)

    // Operation state is intentionally separate from helper signal state.
    property string phase: "idle"
    property int generation: 0
    property var captureItem: null
    property bool cancelled: false
    property string operationDirectory: ""
    property string reservationPath: ""
    property string reservationToken: ""
    property string failureStatus: ""
    property string helperMode: ""
    property bool helperStarted: false
    property bool helperSpawned: false
    property bool helperExited: false
    property bool helperFinished: false
    property bool helperTimedOut: false
    property bool helperKilled: false
    property bool helperBadOutput: false
    property int helperExitCode: -1
    property string helperText: ""
    property bool destroying: false
    property ElapsedTimer stageClock: ElapsedTimer {}

    function picturesDirectory() {
        var location = String(StandardPaths.writableLocation(StandardPaths.PicturesLocation) || "");
        if (!location) return "";
        try {
            if (location.indexOf("file:///") === 0) location = decodeURIComponent(location.slice(7));
        } catch (error) { return ""; }
        return location.indexOf("/") === 0 ? location.replace(/\/+$/, "") + "/Terrarium" : "";
    }
    function validDirectory(value) {
        return typeof value === "string" && value.indexOf("/") === 0 && value.length <= 4096 && !/[\x00\r\n]/.test(value);
    }
    function save(item) {
        if (busy || destroying) return false;
        if (!validDirectory(outputDirectory)) {
            status = "Your Pictures folder is unavailable.";
            return false;
        }
        if (!item || typeof item.capture !== "function" || typeof item.cancelCapture !== "function") {
            status = "The postcard is not ready yet.";
            return false;
        }
        if ("busy" in item && item.busy === true) {
            status = "This postcard is already being saved.";
            return false;
        }
        generation++;
        captureItem = item;
        cancelled = false;
        operationDirectory = outputDirectory.replace(/\/+$/, "") || "/";
        reservationPath = "";
        reservationToken = "";
        failureStatus = "";
        savedPath = "";
        status = "Preparing your postcard…";
        phase = "reserving";
        var operation = generation;
        Qt.callLater(function() {
            if (root.generation === operation && root.phase === "reserving") root.startHelper("reserve");
        });
        return true;
    }
    function cancel() {
        if (!busy || destroying) return;
        cancelled = true;
        failureStatus = "Postcard cancelled.";
        if (phase === "capturing") {
            stopCapture();
            cleanup();
        } else if (phase === "reserving" && helperMode === "") {
            finish(false, "", failureStatus);
        } else {
            // A reserve helper may have created the file but not delivered its
            // receipt yet. Await both output and exit before cleaning it up.
            status = "Cancelling postcard…";
        }
    }
    function stopCapture() {
        phase = "cancelling"; // Invalidate synchronous and late capture callbacks first.
        var item = captureItem;
        captureItem = null;
        if (item && typeof item.cancelCapture === "function") {
            try { item.cancelCapture(); }
            catch (error) { failureStatus = "The postcard could not be finished."; }
        }
    }
    function startHelper(mode) {
        if (destroying || worker.running || helperSpawned || (mode !== "reserve" && mode !== "cancel")) return;
        helperMode = mode;
        helperStarted = false;
        helperSpawned = false;
        helperExited = false;
        helperFinished = false;
        helperTimedOut = false;
        helperKilled = false;
        helperBadOutput = false;
        helperExitCode = -1;
        helperText = "";
        stageClock.restart();
        var script = decodeURIComponent(Qt.resolvedUrl("../scripts/postcard.py").toString().replace("file://", ""));
        var command = ["python3", "-u", script, mode, "--directory", operationDirectory];
        if (mode === "cancel") command = command.concat(["--path", reservationPath, "--token", reservationToken]);
        worker.command = command;
        worker.running = true;
    }
    function receiveOutput(text) {
        if (!helperMode || destroying) return;
        helperFinished = true;
        if (text.length > 16384) helperBadOutput = true;
        else helperText = text;
        Qt.callLater(joinHelper);
    }
    function receiveExit(code) {
        if (!helperMode || destroying) return;
        helperSpawned = false;
        helperExited = true;
        helperExitCode = code;
        Qt.callLater(joinHelper);
    }
    function joinHelper() {
        if (!helperMode || !helperExited || !helperFinished || worker.running || destroying) return;
        var mode = helperMode, response = null;
        helperMode = "";
        try {
            if (!helperBadOutput && helperText.trim()) response = JSON.parse(helperText);
        } catch (error) {}
        helperText = "";
        if (mode === "reserve") {
            var receipt = response && response.ok === true && typeof response.path === "string"
                && validDirectory(response.path) && /\.png$/.test(response.path)
                && typeof response.token === "string" && response.token.length > 0 && response.token.length <= 8192;
            if (receipt) {
                reservationPath = response.path;
                reservationToken = response.token;
            }
            if (!receipt || helperExitCode !== 0 || helperTimedOut) {
                failureStatus = failureStatus || "Your postcard could not be prepared.";
                if (receipt) cleanup();
                else finish(false, "", failureStatus);
                return;
            }
            if (cancelled) { cleanup(); return; }
            phase = "capturing";
            status = "Saving your postcard…";
            stageClock.restart();
            var operation = generation;
            Qt.callLater(function() { root.beginCapture(operation); });
        } else {
            if (response && response.ok === true && helperExitCode === 0 && !helperTimedOut)
                finish(false, "", failureStatus || "Postcard cancelled.");
            else if (response && response.code === "not_empty")
                finish(false, "", "The postcard could not be finished. The existing file was kept.");
            else
                finish(false, "", "The postcard was not saved. The reserved file was kept.");
        }
    }
    function beginCapture(operation) {
        if (destroying || operation !== generation || phase !== "capturing" || cancelled) return;
        var item = captureItem;
        if (!item) { failureStatus = "The postcard is no longer available."; cleanup(); return; }
        var accepted = false, threw = false;
        try {
            accepted = item.capture(reservationPath, function(result) {
                if (root.destroying || root.generation !== operation || root.phase !== "capturing" || root.cancelled) return;
                if (result && result.ok === true && result.cancelled !== true)
                    root.finish(true, root.reservationPath, "Postcard saved.");
                else {
                    root.failureStatus = result && result.cancelled === true ? "Postcard cancelled." : "The postcard could not be saved.";
                    root.stopCapture();
                    root.cleanup();
                }
            });
        } catch (error) { threw = true; }
        if (accepted !== true && generation === operation && phase === "capturing") {
            failureStatus = "The postcard is not ready to save.";
            // A normal refusal has not granted ownership of a capture. Only
            // cancel an uncertain partial start when capture itself threw.
            if (threw) stopCapture();
            cleanup();
        }
    }
    function cleanup() {
        captureItem = null;
        if (!reservationPath || !reservationToken) { finish(false, "", failureStatus || "Postcard cancelled."); return; }
        phase = "cleaning";
        status = "Finishing postcard cleanup…";
        var operation = generation;
        Qt.callLater(function() {
            if (root.generation === operation && root.phase === "cleaning" && root.helperMode === "") root.startHelper("cancel");
        });
    }
    function finish(ok, path, message) {
        captureItem = null;
        reservationPath = "";
        reservationToken = "";
        helperMode = "";
        helperText = "";
        generation++;
        savedPath = ok ? path : "";
        status = message;
        phase = "idle";
        completed(ok, ok ? path : "");
    }
    function helperOutputTooLarge() {
        if (!helperMode || helperBadOutput) return;
        helperBadOutput = true;
        helperTimedOut = true;
        failureStatus = "The postcard helper returned an unreadable response.";
        worker.running = false;
    }

    property Process worker: Process {
        running: false
        stdout: StdioCollector {
            waitForEnd: false
            onTextChanged: if (text.length > 16384) root.helperOutputTooLarge()
            onStreamFinished: root.receiveOutput(text)
        }
        stderr: StdioCollector {
            waitForEnd: false
            onTextChanged: if (text.length > 16384) root.helperOutputTooLarge()
        }
        onStarted: { root.helperStarted = true; root.helperSpawned = true; }
        onRunningChanged: Qt.callLater(root.joinHelper)
        onExited: function(code) { root.receiveExit(code); }
    }
    property Timer watchdog: Timer {
        interval: 250; running: root.busy; repeat: true
        onTriggered: {
            var elapsed = root.stageClock.elapsedMs();
            if (root.phase === "capturing" && elapsed >= 10000) {
                root.failureStatus = "Saving the postcard took too long.";
                root.stopCapture();
                root.cleanup();
                return;
            }
            if (!root.helperMode) return;
            if (elapsed >= 10000 && !root.helperTimedOut) {
                root.helperTimedOut = true;
                root.failureStatus = root.helperStarted ? "The postcard helper took too long." : "The postcard helper could not start.";
                root.status = root.failureStatus;
                worker.running = false;
            }
            if (root.helperTimedOut && elapsed >= 12000 && worker.running && !root.helperKilled) {
                root.helperKilled = true;
                worker.signal(9); // Only this writer's already-owned helper.
            }
            if (root.helperTimedOut && !worker.running && !root.helperSpawned) {
                // Failed starts may emit neither exited nor streamFinished.
                root.helperExited = true;
                root.helperFinished = true;
                root.joinHelper();
            }
        }
    }
    Component.onDestruction: {
        destroying = true;
        generation++;
        if (captureItem && typeof captureItem.cancelCapture === "function") {
            try { captureItem.cancelCapture(); } catch (error) {}
        }
        // Normal close/lock calls cancel() while this object is alive. During
        // shell destruction invalidate capture and stop this owned helper;
        // never start an untracked detached cleanup process.
        if (worker.running) worker.signal(9);
    }
}
