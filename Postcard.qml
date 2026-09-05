pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Window
import "PostcardModel.js" as PostcardModel

Item {
    id:root
    objectName:"postcardPreview"
    property var card:null
    readonly property var snapshot:root.frozenCard
    readonly property bool ready:root.card!==null && root.visible && root.Window.window!==null && root.Window.window.visible && illustration.artReady
    readonly property bool busy:root.captureBusy
    readonly property int pixelWidth:1800
    readonly property int pixelHeight:1100
    // Qt multiplies grabToImage's integer target size by the window DPR. Keep
    // exports near the same pixel dimensions on every output; unusual fractional
    // scales can round one dimension by one pixel (for example 175%).
    readonly property real captureScale: {
        var window=root.Window.window;
        var scale=window && "devicePixelRatio" in window ? window.devicePixelRatio : root.Screen.devicePixelRatio;
        return isFinite(scale) && scale>0 ? scale : 1;
    }
    property var frozenCard:PostcardModel.create({})
    property bool captureBusy:false
    property int generation:0
    property var completion:null
    property bool alive:true

    implicitWidth:900; implicitHeight:550
    width:implicitWidth; height:width*11/18
    Accessible.role:Accessible.Graphic
    Accessible.name:"Terrarium postcard preview"

    onCardChanged: {
        cancelCapture();
        frozenCard=PostcardModel.create(card);
    }
    Component.onDestruction: {
        alive=false;
        // The writer also cleans its reservation if this item is destroyed.
        generation++; captureBusy=false; completion=null;
    }

    function finish(captureGeneration,result) {
        if(!root.alive || !root.captureBusy || captureGeneration!==root.generation)return;
        var callback=root.completion;
        root.captureBusy=false; root.completion=null;
        if(typeof callback==="function")callback(result);
    }
    function cancelCapture() {
        var oldGeneration=root.generation, callback=root.completion, pending=root.captureBusy;
        root.generation++;
        root.captureBusy=false; root.completion=null;
        if(pending && root.alive && typeof callback==="function")
            callback({ok:false,cancelled:true,error:"cancelled",generation:oldGeneration});
        return pending;
    }
    function capture(path,callback) {
        if(!root.alive || root.busy || !root.ready || typeof callback!=="function"
            || typeof path!=="string" || path.length===0 || path.length>4096 || path[0]!=="/"
            || path.indexOf("\0")>=0 || !/\.png$/i.test(path))return false;
        root.generation++;
        var captureGeneration=root.generation;
        var scaleAtCapture=root.captureScale;
        root.captureBusy=true; root.completion=callback;
        var accepted=surface.grabToImage(function(result) {
            // A closed/locked preview may leave an already scheduled native grab
            // behind. Its generation must be checked BEFORE touching the path.
            if(!root || !root.alive || !root.captureBusy || root.generation!==captureGeneration)return;
            if(root.captureScale!==scaleAtCapture) {
                root.finish(captureGeneration,{ok:false,cancelled:false,error:"display_changed",generation:captureGeneration});
                return;
            }
            var saved=false;
            try { saved=result!==null && result.saveToFile(path); }
            catch(error) { saved=false; }
            root.finish(captureGeneration,{ok:saved,cancelled:false,error:saved?"":"save_failed",generation:captureGeneration});
        },Qt.size(Math.max(1,Math.round(root.pixelWidth/scaleAtCapture)),Math.max(1,Math.round(root.pixelHeight/scaleAtCapture))));
        if(!accepted)
            root.finish(captureGeneration,{ok:false,cancelled:false,error:"grab_failed",generation:captureGeneration});
        // The operation was accepted, even if the native grab failed immediately
        // and delivered its failure callback synchronously.
        return true;
    }

    Item {
        id:surface
        objectName:"postcardSurface"
        width:900; height:550
        transformOrigin:Item.TopLeft
        scale:Math.min(root.width/width,root.height/height)
        x:(root.width-width*scale)/2; y:(root.height-height*scale)/2
        Rectangle { anchors.fill:parent; color:root.frozenCard.colors.bg }
        GardenScene {
            id:illustration
            objectName:"postcardScene"
            anchors.fill:parent
            colors:root.frozenCard.colors
            residents:root.frozenCard.residents
            weather:root.frozenCard.weather
            hour:root.frozenCard.hour
            animate:false
            artworkOnly:true
            rasterScale:2
            selectedKey:""
        }
    }
}
