import QtQuick
import Quickshell
import "runtime" as Runtime

// A real Quickshell Process test without windows or desktop interaction.
ShellRoot {
    id:test
    property int phase:0
    property real began:Date.now()
    property real heldAt:0
    property int heldPid:0
    property int priorSamples:0
    function fail(reason){
        try {
            if(Runtime.Habitat.collectorRunning)Runtime.Habitat.collector.signal(18);
            Runtime.Habitat.unwatch("one");Runtime.Habitat.unwatch("two");
        } catch(error) {}
        console.error("STORE_FAIL: "+reason);
        Qt.exit(1);
    }
    Component.onCompleted:Runtime.Habitat.watch("one",true)
    Timer {
        interval:100;running:true;repeat:true
        onTriggered:{
            var store=Runtime.Habitat;
            if(Date.now()-test.began>35000){test.fail("timeout at phase "+test.phase);return;}
            if(test.phase===0 && store.garden.samples>=2 && store.collectorRunning){
                test.heldPid=store.collectorPid;
                store.watch("two",true);
                store.unwatch("one");
                if(store.collectorPid!==test.heldPid || Object.keys(store.watches).length!==1){test.fail("second watcher did not share the observer");return;}
                store.collector.signal(19); // SIGSTOP, only the test's child.
                store.retry();
                test.heldAt=Date.now();test.phase=1;
            } else if(test.phase===1 && Date.now()-test.heldAt>=10000){
                if(store.collectorPid!==test.heldPid || !store.stale){test.fail("delayed stop lost child ownership or stale state: "+JSON.stringify({pid:store.collectorPid,held:test.heldPid,stale:store.stale,failed:store.failed,restarting:store.restarting,awaiting:store.awaitingExit,ticks:store.retryTicks}));return;}
                test.priorSamples=store.garden.samples;
                store.collector.signal(18); // SIGCONT lets queued SIGTERM run.
                test.phase=2;
            } else if(test.phase===2 && store.collectorRunning && store.collectorPid!==test.heldPid && store.garden.samples>test.priorSamples && !store.stale){
                store.unwatch("two");test.phase=3;
            } else if(test.phase===3 && !store.collectorRunning){
                console.log("STORE_PASS: one shared observer, stalled intentional shutdown, automatic recovery, and final stop");
                Qt.quit();
            }
        }
    }
}
