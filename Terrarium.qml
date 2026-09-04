pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Ui as Ui
import "Model.js" as Model

Ui.Panel {
    id:root
    moduleName:"io.github.lostandadrift.terrarium"
    ipcTarget:moduleName
    manageIpc:false
    implicitWidth:button.implicitWidth
    implicitHeight:button.implicitHeight

    property var liveSnapshot:Model.emptySnapshot()
    property var liveGarden:Model.newGarden()
    property var demoGarden:Model.newGarden()
    property int demoStep:0
    property bool demoMode:false
    property bool collectorFailed:false
    property bool collectorRestarting:false
    property string collectorStatus:"Connecting to your desktop…"
    property real openedAt:0
    property real lastSample:0
    property real now:Date.now()
    readonly property bool reducedMotion:setting("reducedMotion",false)===true
    readonly property bool ambientEnabled:setting("ambient",false)===true
    readonly property bool ambientHost:button.QsWindow.window !== null && button.QsWindow.window.screen === Quickshell.screens[0]
    readonly property bool observing:opened || (ambientEnabled && ambientHost)
    readonly property string paletteName:String(setting("palette","auto"))
    readonly property bool stale:observing && !demoMode && (collectorFailed || now-Math.max(openedAt,lastSample)>9000)
    readonly property var displaySnapshot:demoMode?Model.demoSnapshot(demoStep):liveSnapshot
    readonly property var displayGarden:demoMode?demoGarden:liveGarden

    function acceptSample(data) {
        if(data.length>131072)return;
        try {
            var sample=Model.normalize(JSON.parse(data));
            liveSnapshot=sample;
            lastSample=Date.now();now=lastSample;
            liveGarden=Model.updateGarden(liveGarden,sample,lastSample);
            collectorStatus=sample.errors.length?"Some observations are unavailable.":"";
        } catch(error) { collectorStatus="An observation could not be read."; }
    }
    function instances() {
        return root.bar && typeof root.bar.moduleWidgets==="function" ? root.bar.moduleWidgets(root.moduleName) : [root];
    }
    function activeInstance() {
        var all=instances();
        for(var i=0;i<all.length;i++) if(all[i].opened)return all[i];
        return root;
    }
    function runtimeState() {
        return {opened:root.opened,demo:root.demoMode,stale:root.stale,ambient:root.ambientEnabled,ambientHost:root.ambientHost,
            collectorRunning:collector.running,collectorPid:collector.processId,
            samples:root.displayGarden.samples,residents:root.displayGarden.residents.length,
            reducedMotion:root.reducedMotion,palette:root.paletteName,section:view.section};
    }
    function showSection(name) {if(["garden","journal","guide"].indexOf(name)>=0)view.section=name;}
    function open() {
        openedAt=Date.now();now=openedAt;collectorFailed=false;
        root.controller.show();
    }
    function persist(key,value) {
        var entry={id:root.moduleName};
        for(var k in root.settings) if(k!=="id") entry[k]=root.settings[k];
        entry[key]=value;root.settings=entry;
        if(root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline==="function")
            root.bar.shell.updateEntryInline(root.moduleName,entry);
    }
    function cyclePalette() {
        var options=["auto","dusk","dawn","moss"];
        persist("palette",options[(options.indexOf(paletteName)+1)%options.length]);
    }
    function toggleDemo() {
        demoMode=!demoMode;
        if(demoMode && demoGarden.samples===0) {
            var g=Model.newGarden();
            for(var i=0;i<35;i++)g=Model.updateGarden(g,Model.demoSnapshot(i),Date.now()-(35-i)*2000);
            demoGarden=g;
        }
        if(!demoMode){openedAt=Date.now();collectorFailed=false;}
    }
    function retry() {
        collectorRestarting=true;collectorFailed=false;openedAt=Date.now();now=openedAt;
        Qt.callLater(function(){root.collectorRestarting=false;});
    }

    Process {
        id:collector
        command:["python3","-u",decodeURIComponent(Qt.resolvedUrl("scripts/collect.py").toString().replace(/^file:\/\//,"")),"--interval","2"]
        running:root.observing && !root.demoMode && !root.collectorFailed && !root.collectorRestarting
        stdout:SplitParser { onRead:function(data){root.acceptSample(data);} }
        stderr:SplitParser { onRead:function(data){ if(root.observing && !root.demoMode)root.collectorStatus="The local observer reported an error."; } }
        onExited:function(exitCode) {
            if(root.observing && !root.demoMode && !root.collectorRestarting) {
                root.collectorFailed=true;root.collectorStatus="The local observer stopped. You can try again.";
            }
        }
    }
    Timer {
        interval:1000;running:root.observing;repeat:true
        onTriggered:root.now=Date.now()
    }
    Timer {
        interval:2000;running:root.opened && root.demoMode;repeat:true
        onTriggered:{root.demoStep++;root.demoGarden=Model.updateGarden(root.demoGarden,Model.demoSnapshot(root.demoStep),Date.now());}
    }

    Ui.BarIconButton {
        id:button;anchors.fill:parent;bar:root.bar
        tooltipText:"Desktop Terrarium"
        onPressed:function(b){root.toggle();}
        iconComponent:Component {
            Canvas {
                id:iconCanvas
                onPaint:{
                    var c=getContext("2d"),s=width/24;c.reset();c.scale(s,s);
                    c.strokeStyle=button.foreground;c.lineWidth=1.45;c.lineCap="round";
                    c.beginPath();c.moveTo(5,18);c.lineTo(5,10);c.bezierCurveTo(5,1,19,1,19,10);c.lineTo(19,18);c.stroke();
                    c.beginPath();c.ellipse(4,16,16,5);c.stroke();
                    c.beginPath();c.moveTo(12,18);c.lineTo(12,10);c.moveTo(12,14);c.bezierCurveTo(7,13,8,8,12,12);c.moveTo(12,12);c.bezierCurveTo(16,11,17,6,13,9);c.stroke();
                }
                Connections { target:button;function onForegroundChanged(){iconCanvas.requestPaint();} }
            }
        }
    }
    Ui.KeyboardPanel {
        id:panel
        anchorItem:button;owner:root;bar:root.bar;open:root.opened
        focusTarget:view
        padding:0
        centerOnBar:true
        contentWidth:panel.fittedContentWidth(1120)
        contentHeight:panel.fittedContentHeight(720)

        TerrariumView {
            id:view;anchors.fill:parent
            snapshot:root.displaySnapshot;garden:root.displayGarden
            paletteName:root.paletteName;reducedMotion:root.reducedMotion
            active:root.opened;demo:root.demoMode;stale:root.stale
            ambient:root.ambientEnabled
            hour:new Date(root.now).getHours()
            status:root.stale?(root.collectorStatus || "Waiting for the local observer…"):root.collectorStatus
            onCloseRequested:root.close()
            onDemoRequested:root.toggleDemo()
            onMotionRequested:root.persist("reducedMotion",!root.reducedMotion)
            onPaletteRequested:root.cyclePalette()
            onRetryRequested:root.retry()
            onAmbientRequested:root.persist("ambient",!root.ambientEnabled)
        }
    }
    PanelWindow {
        id:ambientWindow
        visible:root.ambientEnabled && root.ambientHost && !root.opened
        screen:Quickshell.screens[0] || null
        anchors { bottom:true;right:true }
        margins { bottom:36;right:36 }
        implicitWidth:Math.min(680,screen?screen.width*.4:680)
        implicitHeight:implicitWidth*550/900
        color:"transparent"
        exclusionMode:ExclusionMode.Ignore
        WlrLayershell.layer:WlrLayer.Bottom
        WlrLayershell.namespace:"desktop-terrarium"
        WlrLayershell.keyboardFocus:WlrKeyboardFocus.None
        mask:Region {}
        GardenScene {
            anchors.fill:parent
            palette:Model.palette(root.paletteName,new Date(root.now).getHours())
            residents:root.liveGarden.residents;weather:Model.weather(root.liveSnapshot)
            animate:ambientWindow.visible && !root.reducedMotion && !root.stale
            enabled:false
        }
    }
    // Introspection and ordinary actions for CLI/keyboard users and native
    // lifecycle tests. This interface cannot execute arbitrary commands.
    IpcHandler {
        target:"terrarium"
        enabled:root.ambientHost
        function state():string {
            return JSON.stringify(root.activeInstance().runtimeState());
        }
        function allStates():string {return JSON.stringify(root.instances().map(function(item){return item.runtimeState();}));}
        function demo():void {root.activeInstance().toggleDemo();}
        function motion():void {root.activeInstance().persist("reducedMotion",!root.reducedMotion);}
        function palette():void {root.cyclePalette();}
        function ambient():void {root.persist("ambient",!root.ambientEnabled);}
        function retry():void {root.activeInstance().retry();}
        function section(name:string):void {root.activeInstance().showSection(name);}
    }
}
