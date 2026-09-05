import QtQuick
import QtQuick.Window
import ".."
import "../Model.js" as Model

// Offscreen release-preview harness. Synthetic data only; not loaded by the
// installed plugin. Create the output directory before running this file.
Window {
    id:window
    width:1120;height:720;visible:true;color:"#111b20"
    property string output:"/tmp/terrarium-frames"
    property int frame:0
    property int frames:200
    property bool capturing:false
    TerrariumView {
        id:view;anchors.fill:parent;demo:true;paletteName:"dusk";active:true;status:""
        snapshot:Model.demoSnapshot(40+Math.floor(window.frame/40))
        garden:{var s=Model.newGarden();for(var i=0;i<40;i++)s=Model.updateGarden(s,Model.demoSnapshot(i),1700000000000+i*2000);return s;}
    }
    Timer {
        interval:500;running:true
        onTriggered:recorder.start()
    }
    Timer {
        id:recorder;interval:50;repeat:true
        onTriggered:{
            if(window.capturing)return;
            window.capturing=true;
            view.grabToImage(function(result){
                var path=window.output+"/frame-"+String(window.frame).padStart(4,"0")+".png";
                if(!result.saveToFile(path)){console.error("Frame could not be written");Qt.exit(1);return;}
                window.frame++;
                window.capturing=false;
                if(window.frame>=window.frames){recorder.stop();Qt.quit();}
            });
        }
    }
    Component.onCompleted:{
        var args=Qt.application.arguments;
        for(var i=0;i<args.length;i++){
            if(args[i]==="--output" && args[i+1])output=args[++i];
            else if(args[i]==="--frames" && args[i+1])frames=Math.max(1,Math.min(600,Number(args[++i])||200));
        }
    }
}
