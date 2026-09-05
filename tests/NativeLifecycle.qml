import QtQuick
import Quickshell
import "runtime" as Runtime

// Actual production leases/store with simulated display membership and lock
// service inputs. No windows, compositor commands, or real session locking.
ShellRoot {
    id:test
    property int phase:0
    property int cycles:0
    property int pid:0
    property int samples:0
    property real began:Date.now()
    property real heldAt:0
    property var replacement:null
    property bool finished:false
    Runtime.ObserverLease { id:first;ambient:true;host:true }
    Runtime.ObserverLease { id:second;ambient:true;host:false }
    Component { id:leaseComponent;Runtime.ObserverLease {ambient:true;host:true} }
    function fail(reason){
        if(finished)return;
        finished=true;
        try {
            if(Runtime.Habitat.collectorRunning)Runtime.Habitat.collector.signal(18);
            first.hasScreen=false;second.hasScreen=false;
            if(replacement)replacement.hasScreen=false;
        } catch(error) {}
        console.error("LIFECYCLE_FAIL: "+reason);Qt.exit(1);
    }
    Timer {
        interval:50;running:!test.finished;repeat:true
        onTriggered:{
            var store=Runtime.Habitat;
            if(Date.now()-test.began>65000){test.fail("timeout in phase "+test.phase);return;}
            if(test.phase===0 && store.garden.samples>=2 && store.collectorPid>0){
                test.pid=store.collectorPid;
                // A new screen can arrive before the old root is destroyed.
                test.replacement=leaseComponent.createObject(test);
                if(Object.keys(store.watches).length!==2 || store.collectorPid!==test.pid){test.fail("replacement duplicated the collector");return;}
                first.hasScreen=false;
                if(Object.keys(store.watches).length!==1){test.fail("removed display retained its lease");return;}
                test.replacement.locked=true;second.locked=true;test.phase=1;
            } else if(test.phase===1 && !store.collectorRunning){
                if(Object.keys(store.watches).length!==0){test.fail("lock retained observation");return;}
                test.samples=store.garden.samples;
                test.replacement.locked=false;second.locked=false;test.phase=2;
            } else if(test.phase===2 && store.collectorRunning && store.garden.samples>test.samples){
                if(store.collectorPid===test.pid || Object.keys(store.watches).length!==1){test.fail("unlock did not restore a single fresh observer");return;}
                test.replacement.hasScreen=false;second.hasScreen=false;test.phase=3;
            } else if(test.phase===3 && !store.collectorRunning){
                test.replacement.destroy();test.replacement=null;
                second.hasScreen=true;second.host=true;test.phase=4;
            } else if(test.phase===4 && store.collectorPid>0 && !store.stale){
                test.phase=5;
            } else if(test.phase===5 && test.cycles<200){
                // Burst reopen/retry transitions reproduce changing ownership
                // while a real child is still starting or shutting down.
                second.host=false;second.opened=true;
                store.retry();second.opened=false;second.host=true;
                test.cycles++;
            } else if(test.phase===5){
                test.samples=store.garden.samples;test.phase=6;
            } else if(test.phase===6 && store.collectorRunning && !store.stale && store.garden.samples>test.samples){
                test.pid=store.collectorPid;
                store.wallClock=function(){return Date.now()+3600000;};
                test.heldAt=Date.now();test.phase=7;
            } else if(test.phase===7 && Date.now()-test.heldAt>1500){
                if(store.stale){test.fail("forward calendar change made fresh data stale");return;}
                store.collector.signal(19);
                store.wallClock=function(){return Date.now()-3600000;};
                test.heldAt=Date.now();test.phase=8;
            } else if(test.phase===8 && Date.now()-test.heldAt>11000){
                if(!store.stale || store.collectorPid!==test.pid){test.fail("backward calendar change hid stalled data");return;}
                store.collector.signal(18);
                store.wallClock=function(){return Date.now();};
                test.samples=store.garden.samples;test.phase=9;
            } else if(test.phase===9 && !store.stale && store.garden.samples>test.samples){
                second.hasScreen=false;test.phase=10;
            } else if(test.phase===10 && !store.collectorRunning){
                if(Object.keys(store.watches).length!==0){test.fail("final watcher leak");return;}
                test.finished=true;
                console.log("LIFECYCLE_PASS: lock/unlock, display replacement, zero screens, 200 rapid transitions, calendar jumps, and final cleanup");
                Qt.quit();
            }
        }
    }
}
