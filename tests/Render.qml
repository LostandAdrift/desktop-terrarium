import QtQuick
import QtQuick.Window
import ".."
import "../Model.js" as Model

Window {
    id:window
    width:1120;height:720;visible:true;color:"#111b20"
    property string output: "/tmp/terrarium-render.png"
    property int ticks:0
    property bool capturing:false
    function findScene(item) {
        if(item.objectName==="gardenScene")return item;
        var children=item.children||[];
        for(var i=0;i<children.length;i++){var found=findScene(children[i]);if(found)return found;}
        return null;
    }
    TerrariumView {
        id:view;anchors.fill:parent;demo:true;paletteName:"dusk";hour:20;active:true;status:""
        snapshot:Model.demoSnapshot(40)
        garden:{var s=Model.newGarden();for(var i=0;i<40;i++)s=Model.updateGarden(s,Model.demoSnapshot(i),1700000000000+i*2000);return s;}
        onCloseRequested:Qt.quit()
        onPaletteRequested:paletteName=paletteName==="dusk"?"dawn":paletteName==="dawn"?"moss":"dusk"
        onMotionRequested:motionPaused=!motionPaused
        onDemoRequested:demo=!demo
    }
    Timer {
        interval:50;running:true;repeat:true
        onTriggered:{
            window.ticks++;
            if(window.ticks>200){console.error("Preview did not become ready");Qt.exit(1);return;}
            if(window.capturing || window.ticks<30)return;
            var scene=window.findScene(view);
            if(view.section==="postcard" ? !view.postcardReady : (scene && scene.visible && !scene.artReady))return;
            window.capturing=true;
            if(!view.grabToImage(function(result){
                if(!result.saveToFile(window.output)){console.error("Preview could not be written");Qt.exit(1);return;}
                Qt.quit();
            })){console.error("Preview capture could not start");Qt.exit(1);}
        }
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
            else if(args[i]==="--art")view.showSection("art");
            else if(args[i]==="--options"){
                view.displays=[{name:"DP-1",label:"Desk display"},{name:"HDMI-A-1",label:"Portrait display"}];
                view.showSection("options");
            }
            else if(args[i]==="--postcard"){view.postcardAvailable=true;Qt.callLater(view.requestPostcard);}
            else if(args[i]==="--error"){view.demo=false;view.stale=true;view.status="The local observer stopped. You can try again.";}
            else if(args[i]==="--empty"){view.demo=false;view.snapshot=Model.emptySnapshot();view.garden=Model.newGarden();view.status="Connecting to your desktop…";}
            else if(args[i]==="--dawn")view.paletteName="dawn";
            else if(args[i]==="--moss")view.paletteName="moss";
            else if(args[i]==="--hour" && args[i+1])view.hour=Number(args[++i]);
            else if(args[i]==="--selected" && args[i+1])view.selectedKey=args[++i];
            else if(args[i]==="--age" && args[i+1]){
                var age=Math.max(0,Math.min(86400,Number(args[++i])||0));
                var grown=JSON.parse(JSON.stringify(view.garden));
                grown.residents.forEach(function(resident){resident.age=age;resident.growth=Model.growthForAge(age);});
                view.garden=grown;
            }
            else if(args[i]==="--species" && args[i+1]){
                var species=args[++i];
                if(Model.categories.indexOf(species)<0){console.error("Unknown synthetic species");Qt.exit(1);return;}
                var grouped=JSON.parse(JSON.stringify(view.garden));grouped.residents=[];
                for(var n=0;n<7;n++)grouped.residents.push({key:"specimen-"+n,name:"Specimen "+(n+1),category:species,slot:n,cpu:25,memoryBytes:104857600,count:1,age:21600,growth:Model.growthForAge(21600),missing:0});
                view.garden=grouped;
            }
            else if(args[i]==="--crowded"){
                width=1120;height=640;
                var g=JSON.parse(JSON.stringify(view.garden));
                g.residents.push(Object.assign({},g.residents[0],{key:"services",name:"Services",category:"system",slot:6,cpu:0.3}));
                view.garden=g;
            }
        }
    }
}
