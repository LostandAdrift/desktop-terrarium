pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Ui as Ui
import "Model.js" as Model
import "Placement.js" as Placement
import "runtime" as Local

Ui.Panel {
    id:root
    moduleName:"io.github.lostandadrift.terrarium"
    ipcTarget:moduleName
    manageIpc:false
    implicitWidth:button.implicitWidth
    implicitHeight:button.implicitHeight

    readonly property var liveSnapshot:Local.Habitat.snapshot
    readonly property var liveGarden:Local.Habitat.garden
    property var demoGarden:Model.newGarden()
    property int demoStep:0
    property bool demoMode:false
    readonly property real now:localClock.date.getTime()
    readonly property bool reducedMotion:setting("reducedMotion",false)===true
    readonly property bool ambientEnabled:setting("ambient",false)===true
    readonly property string ambientDisplay:Placement.normalizeDisplay(setting("ambientDisplay",""))
    readonly property string ambientCorner:Placement.normalizeCorner(setting("ambientCorner","bottom-right"))
    readonly property string ambientSize:Placement.normalizeSize(setting("ambientSize","medium"))
    readonly property var ambientTarget:Placement.chooseScreen(Quickshell.screens,ambientDisplay)
    readonly property var ambientGeometry:Placement.geometry(ambientTarget.screen,ambientSize,ambientCorner)
    readonly property var displayChoices:{
        var choices=[];
        for(var i=0;i<Quickshell.screens.length;i++){
            var output=Quickshell.screens[i];
            choices.push({name:output.name,label:output.name});
        }
        return choices;
    }
    readonly property bool hasScreen:{
        var panelWindow=button.QsWindow.window;
        if(panelWindow===null || panelWindow.screen===null)return false;
        for(var i=0;i<Quickshell.screens.length;i++)if(Quickshell.screens[i]===panelWindow.screen)return true;
        return false;
    }
    readonly property bool ambientHost:hasScreen && button.QsWindow.window.screen === Quickshell.screens[0]
    readonly property var lockService:root.bar && root.bar.shell && typeof root.bar.shell.serviceFor==="function" ? root.bar.shell.serviceFor("omarchy.lock") : null
    readonly property bool sessionLocked:lockService !== null && lockService.locked === true
    readonly property bool observing:observation.observing
    readonly property string paletteName:String(setting("palette","auto"))
    readonly property bool stale:!demoMode && Local.Habitat.stale
    readonly property var displaySnapshot:demoMode?Model.demoSnapshot(demoStep):liveSnapshot
    readonly property var displayGarden:demoMode?demoGarden:liveGarden

    Local.ObserverLease {
        id:observation
        opened:root.opened;demo:root.demoMode;ambient:root.ambientEnabled
        host:root.ambientHost;locked:root.sessionLocked;hasScreen:root.hasScreen
    }
    Local.PostcardWriter { id:postcardWriter }
    SystemClock {
        id:localClock
        precision:SystemClock.Minutes
        enabled:root.hasScreen && !root.sessionLocked && (root.opened || (root.ambientEnabled && root.ambientHost))
    }
    onSessionLockedChanged:if(sessionLocked){postcardWriter.cancel();root.close();}
    onHasScreenChanged:if(!hasScreen){postcardWriter.cancel();root.close();}
    onOpenedChanged:if(!opened)postcardWriter.cancel()

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
            collectorRunning:Local.Habitat.collectorRunning,collectorPid:Local.Habitat.collectorPid,
            watching:root.observing,liveSamples:root.liveGarden.samples,watcherCount:Object.keys(Local.Habitat.watches).length,
            ambientVisible:ambientWindow.visible,
            samples:root.displayGarden.samples,residents:root.displayGarden.residents.length,
            reducedMotion:root.reducedMotion,palette:root.paletteName,section:view.section,locked:root.sessionLocked,
            clockRunning:localClock.enabled,animationRunning:view.sceneAnimating,
            ambientDisplay:root.ambientDisplay,ambientCorner:root.ambientCorner,ambientSize:root.ambientSize,
            ambientActualDisplay:root.ambientTarget.display,ambientFallback:root.ambientTarget.fallback,
            ambientWidth:ambientWindow.width,ambientHeight:ambientWindow.height,
            screenName:root.hasScreen?button.QsWindow.window.screen.name:"",
            availableDisplays:root.displayChoices.map(function(output){return output.name;}),
            exportBusy:postcardWriter.busy,exportStatus:postcardWriter.status,exportPath:postcardWriter.savedPath,
            postcardReady:view.postcardReady};
    }
    function showSection(name) {if(["garden","journal","guide","options","art"].indexOf(name)>=0)view.showSection(name);}
    function place(key,value) {
        if(key==="ambientDisplay")persist(key,Placement.normalizeDisplay(value));
        else if(key==="ambientCorner")persist(key,Placement.normalizeCorner(value));
        else if(key==="ambientSize")persist(key,Placement.normalizeSize(value));
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
            demoStep=35;
        }
    }
    function retry() {Local.Habitat.retry();}

    Timer {
        interval:2000;running:root.opened && root.hasScreen && root.demoMode && !root.sessionLocked;repeat:true
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
            active:root.opened && root.hasScreen && !root.sessionLocked;demo:root.demoMode;stale:root.stale
            ambient:root.ambientEnabled
            displays:root.displayChoices;ambientDisplay:root.ambientDisplay
            ambientCorner:root.ambientCorner;ambientSize:root.ambientSize
            postcardAvailable:true
            exportBusy:postcardWriter.busy;exportStatus:postcardWriter.status;exportPath:postcardWriter.savedPath
            hour:{var date=new Date(root.now);return date.getHours()+date.getMinutes()/60;}
            status:root.stale?(Local.Habitat.status || "Waiting for the local observer…"):Local.Habitat.status
            onCloseRequested:root.close()
            onDemoRequested:root.toggleDemo()
            onMotionRequested:root.persist("reducedMotion",!root.reducedMotion)
            onPaletteRequested:root.cyclePalette()
            onRetryRequested:root.retry()
            onAmbientRequested:root.persist("ambient",!root.ambientEnabled)
            onPlacementRequested:function(key,value){root.place(key,value);}
            onPostcardRequested:{postcardWriter.status="";postcardWriter.savedPath="";}
            onExportRequested:function(cardItem){postcardWriter.save(cardItem);}
            onExportCancelRequested:postcardWriter.cancel()
        }
    }
    PanelWindow {
        id:ambientWindow
        visible:root.ambientEnabled && root.ambientHost && root.ambientGeometry.visible && !root.opened && !root.sessionLocked
        screen:root.ambientTarget.screen
        anchors {
            top:root.ambientGeometry.anchors.top;bottom:root.ambientGeometry.anchors.bottom
            left:root.ambientGeometry.anchors.left;right:root.ambientGeometry.anchors.right
        }
        margins {
            top:root.ambientGeometry.margins.top;bottom:root.ambientGeometry.margins.bottom
            left:root.ambientGeometry.margins.left;right:root.ambientGeometry.margins.right
        }
        implicitWidth:root.ambientGeometry.width
        implicitHeight:root.ambientGeometry.height
        color:"transparent"
        exclusionMode:ExclusionMode.Normal
        exclusiveZone:0
        WlrLayershell.layer:WlrLayer.Bottom
        WlrLayershell.namespace:"desktop-terrarium"
        WlrLayershell.keyboardFocus:WlrKeyboardFocus.None
        mask:Region {}
        GardenScene {
            anchors.fill:parent
            hour:{var date=new Date(root.now);return date.getHours()+date.getMinutes()/60;}
            colors:Model.palette(root.paletteName,new Date(root.now).getHours())
            residents:root.liveGarden.residents;weather:Model.weather(root.liveSnapshot)
            animate:ambientWindow.visible && !root.reducedMotion && !Local.Habitat.stale
            enabled:false
            artworkOnly:true
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
        function placement(key:string,value:string):void {root.place(key,value);}
    }
}
