import QtQuick
import Quickshell
import Quickshell.Io
import "runtime" as Runtime

// No windows: exercise the native bridge with the real reservation helper and
// a controlled capture object. All files remain inside the runner's temp dir.
ShellRoot {
    id: test
    property string directory: Quickshell.env("TERRARIUM_POSTCARD_DIRECTORY")
    property string scenario: Quickshell.env("TERRARIUM_POSTCARD_SCENARIO") || "normal"
    property var cases: ["exit-first", "output-first", "refused", "failed", "cancel-before", "cancel-reserve", "cancel-capture", "success", "failed-after-write", "capture-timeout"]
    property int caseIndex: -1
    property string caseName: ""
    property bool failed: false
    property bool resultReady: false
    property bool inspectionReady: false
    property bool inspectionExited: false
    property bool inspectionFinished: false
    property int inspectionExit: -1
    property string inspectionText: ""
    property bool cancelOnStart: false
    property bool lateBlocked: false
    property var lateCallback: null
    property int completionCount: 0
    property int fakeGeneration: 0
    property int captureGeneration: 0
    property var pendingCallback: null
    property string pendingPath: ""
    property string captureMode: "refused"
    property ElapsedTimer elapsed: ElapsedTimer {}

    function fail(message) {
        if (failed) return;
        failed = true;
        console.error("POSTCARD_FAIL: " + message);
        try { writer.cancel(); } catch (error) {}
        Qt.exit(1);
    }
    function check(condition, message) { if (!condition) fail(caseName + ": " + message); return condition; }
    function inspect() {
        inspectionReady = false; inspectionExited = false; inspectionFinished = false; inspectionText = "";
        inspector.command = ["python3", "-c", "import json,pathlib,sys; p=pathlib.Path(sys.argv[1]); f=list(p.glob('*.png')); print(json.dumps({'files':len(f),'nonempty':sum(x.stat().st_size>0 for x in f)}))", directory];
        inspector.running = true;
    }
    function joinInspection() {
        if (!inspectionExited || !inspectionFinished || inspector.running || failed) return;
        var result;
        try { result = JSON.parse(inspectionText); } catch (error) { fail("inspection output"); return; }
        var expected = caseName === "success" ? 1 : (caseName === "failed-after-write" || caseName === "capture-timeout") ? 2 : 0;
        if (!check(inspectionExit === 0 && result.files === expected && result.nonempty === expected, "reservation cleanup or completed-file preservation")) return;
        inspectionReady = true;
    }
    function nextCase() {
        caseIndex++;
        if (caseIndex >= cases.length) {
            check(!writer.busy && !writer.worker.running && !writer.helperSpawned, "writer left a helper running");
            if (!failed) { console.log("POSTCARD_PASS: signal ordering, reservation cleanup, cancellation, timeout, and completed-file preservation"); Qt.quit(); }
            return;
        }
        caseName = cases[caseIndex];
        resultReady = false; inspectionReady = false; lateBlocked = false;
        writer.outputDirectory = directory;
        if (caseName === "exit-first" || caseName === "output-first") {
            // Deliberately reverse the two independent Quickshell signals.
            writer.phase = "reserving"; writer.helperMode = "reserve";
            writer.helperExited = false; writer.helperFinished = false;
            writer.helperTimedOut = false; writer.helperBadOutput = false;
            writer.failureStatus = "";
            if (caseName === "exit-first") {
                writer.receiveExit(1); writer.joinHelper();
                check(writer.busy, "exit was consumed before stdout finished");
                writer.receiveOutput('{"ok":false,"code":"fixture_failure"}');
            } else {
                writer.receiveOutput('{"ok":false,"code":"fixture_failure"}'); writer.joinHelper();
                check(writer.busy, "stdout was consumed before helper exited");
                writer.receiveExit(1);
            }
            return;
        }
        captureMode = caseName === "success" || caseName === "failed-after-write" ? "write"
            : caseName === "refused" ? "refused"
            : caseName === "capture-timeout" ? "hang"
            : caseName === "cancel-capture" ? "hold" : "failed";
        cancelOnStart = caseName === "cancel-reserve";
        if (!check(writer.save(fakeCard), "save was not accepted")) return;
        check(!writer.save(fakeCard), "overlapping save was accepted");
        if (caseName === "cancel-before") writer.cancel();
        if (caseName === "failed") writer.outputDirectory = directory + "/changed-during-save";
    }
    Runtime.PostcardWriter {
        id: writer
        outputDirectory: test.directory
        onCompleted: function(ok, path) {
            if (test.failed) return;
            if (!test.check(!test.resultReady, "completion was emitted twice")) return;
            test.resultReady = true; test.completionCount++;
            if (!test.check(!busy && !worker.running && !helperSpawned, "completion preceded helper exit")) return;
            if (test.scenario !== "normal") {
                if (!test.check(!ok && path === "" && status.length > 0, "helper fault was not reported")) return;
                if (test.scenario === "helper-timeout" && !test.check(test.elapsed.elapsedMs() >= 11000, "stalled helper was not exercised")) return;
                console.log("POSTCARD_PASS: " + test.scenario);
                Qt.quit();
                return;
            }
            var expectedSuccess = test.caseName === "success";
            if (!test.check(ok === expectedSuccess && (ok ? path.length > 0 && savedPath === path : path === "" && savedPath === ""), "incorrect completion result")) return;
            if (test.caseName === "failed-after-write") test.check(status.indexOf("existing file was kept") >= 0, "nonempty-file refusal was not explained");
            if (ok) cancel(); // Completed PNGs must remain untouched.
            Qt.callLater(test.inspect);
        }
    }
    QtObject {
        id: fakeCard
        function capture(path, callback) {
            if (!test.check(path.slice(0, path.lastIndexOf("/")) === test.directory, "save destination changed during the operation")) return false;
            test.fakeGeneration++;
            test.captureGeneration = test.fakeGeneration;
            test.pendingCallback = callback; test.pendingPath = path;
            if (test.captureMode === "refused") return false;
            if (test.captureMode === "write") {
                fileWriter.command = ["python3", "-c", "import pathlib,sys; pathlib.Path(sys.argv[1]).write_bytes(bytes([137,80,78,71,13,10,26,10])+b'synthetic fixture')", path];
                fileWriter.running = true;
            } else if (test.captureMode === "failed") {
                Qt.callLater(function() { callback({ok:false,cancelled:false}); });
            } else if (test.captureMode === "hold") {
                test.lateCallback = callback;
                Qt.callLater(function() { writer.cancel(); lateProbe.start(); });
            }
            return true;
        }
        function cancelCapture() {
            test.fakeGeneration++;
            var callback = test.pendingCallback;
            test.pendingCallback = null;
            if (callback) callback({ok:false,cancelled:true});
        }
    }
    Connections {
        target: writer.worker
        function onStarted() {
            if (test.cancelOnStart && writer.helperMode === "reserve") {
                test.cancelOnStart = false;
                writer.cancel();
            }
        }
    }
    Process {
        id: fileWriter
        stdout: StdioCollector {}
        stderr: StdioCollector {}
        onExited: function(code) {
            if (code !== 0) { test.fail("fixture file write failed"); return; }
            var callback = test.pendingCallback;
            test.pendingCallback = null;
            if (callback) callback({ok:test.caseName === "success",cancelled:false});
        }
    }
    Process {
        id: inspector
        stdout: StdioCollector { onStreamFinished: { test.inspectionText = text; test.inspectionFinished = true; Qt.callLater(test.joinInspection); } }
        stderr: StdioCollector {}
        onRunningChanged: Qt.callLater(test.joinInspection)
        onExited: function(code) { test.inspectionExit = code; test.inspectionExited = true; Qt.callLater(test.joinInspection); }
    }
    Timer {
        id: lateProbe; interval: 300
        onTriggered: {
            if (!test.check(test.fakeGeneration !== test.captureGeneration, "capture cancellation was not invalidated")) return;
            test.lateBlocked = true;
            if (test.lateCallback) test.lateCallback({ok:true,cancelled:false});
            test.lateCallback = null;
        }
    }
    Timer {
        interval: 50; running: !test.failed; repeat: true
        onTriggered: {
            if (test.elapsed.elapsedMs() > 32000) { test.fail("test deadline exceeded"); return; }
            if (test.scenario === "normal" && test.resultReady && test.inspectionReady
                    && (test.caseName !== "cancel-capture" || test.lateBlocked)) test.nextCase();
        }
    }
    Component.onCompleted: {
        elapsed.restart();
        if (!check(directory.indexOf("/") === 0, "test directory missing")) return;
        writer.outputDirectory = "";
        if (!check(!writer.save(fakeCard) && !writer.busy && writer.status.length > 0, "unavailable Pictures folder did not fail safely")) return;
        writer.outputDirectory = directory;
        if (scenario !== "normal") {
            caseName = scenario;
            check(writer.save(fakeCard), "fault case was not accepted");
        } else nextCase();
    }
}
