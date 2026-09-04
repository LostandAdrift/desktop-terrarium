import QtQuick
import QtQuick.Window
import ".."
import "../Model.js" as Model

Window {
    id:window
    width:1120;height:720;visible:true;color:"#111b20"
    property string output: "/tmp/terrarium-render.png"
    property int ticks:0
    TerrariumView {
        id:view;anchors.fill:parent;demo:true;paletteName:"dusk";active:true;status:""
        snapshot:Model.demoSnapshot(40)
        garden:{var s=Model.newGarden();for(var i=0;i<40;i++)s=Model.updateGarden(s,Model.demoSnapshot(i),1700000000000+i*2000);return s;}
        onCloseRequested:Qt.quit()
        onPaletteRequested:paletteName=paletteName==="dusk"?"dawn":paletteName==="dawn"?"moss":"dusk"
        onMotionRequested:motionPaused=!motionPaused
        onDemoRequested:demo=!demo
    }
    Timer {
        interval:1500;running:true;repeat:false
        onTriggered:view.grabToImage(function(result){result.saveToFile(window.output);console.log("RENDER_SAVED");Qt.quit();})
    }
    Component.onCompleted:{
        var args=Qt.application.arguments;
        for(var i=0;i<args.length;i++) {
            if(args[i]==="--output" && args[i+1])output=args[++i];
            else if(args[i]==="--compact"){width=720;height=620;}
            else if(args[i]==="--short"){width=960;height=480;}
            else if(args[i]==="--narrow"){width=640;height=480;}
            else if(args[i]==="--guide")view.section="guide";
            else if(args[i]==="--journal")view.section="journal";
            else if(args[i]==="--error"){view.demo=false;view.stale=true;view.status="The local observer stopped. You can try again.";}
            else if(args[i]==="--empty"){view.demo=false;view.snapshot=Model.emptySnapshot();view.garden=Model.newGarden();view.status="Connecting to your desktop…";}
            else if(args[i]==="--dawn")view.paletteName="dawn";
            else if(args[i]==="--moss")view.paletteName="moss";
        }
    }
}
