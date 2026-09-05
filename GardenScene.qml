pragma ComponentBehavior: Bound
import QtQuick
import "Model.js" as Model
import "ScenePainter.js" as Painter
import "SceneDynamics.js" as Dynamics

Item {
    id: root
    property var colors: Model.palette("dusk", 20)
    property var residents: []
    property var weather: ({ rain:0, activity:0, water:0, particles:5 })
    property bool animate: true
    property string selectedKey: ""
    property real phase: 0
    property real hour: 20
    property bool fitVessel: false
    property bool artworkOnly: false
    property real rasterScale: 1
    readonly property real textureScale: Math.max(1,Math.min(2,isFinite(rasterScale)?rasterScale:1))
    property real rain: 0
    property real activity: 0
    property real water: 0
    property var touches: []
    property var staticTouch: null
    property bool sceneReady: false
    property string pointerKey: ""
    readonly property bool animationRunning: root.animate && root.visible
    readonly property int transientCount: touches.length
    readonly property var slots: Dynamics.slotsFor(residents)
    readonly property int residentTextureCount: slots.filter(function(r){return r!==null;}).length
    readonly property real skyMinute: Math.floor(Dynamics.skyAt(hour).hour*60)/60
    readonly property var sky: Dynamics.skyAt(skyMinute)
    readonly property string groundKey: JSON.stringify(colors)+":"+skyMinute+":"+Math.round(water*10)
    readonly property bool artReady: {
        if (!sceneReady || !ground.artReady || !bridge.artReady || !glass.artReady) return false;
        for (var i=0;i<plants.count;i++) {
            var plant=plants.itemAt(i);
            if (root.slots[i]!==null && (!plant || !plant.artReady)) return false;
        }
        return true;
    }
    readonly property real vesselX: 140
    readonly property real vesselY: 12
    readonly property real vesselW: 620
    readonly property real vesselH: 528
    readonly property real drawingScale: root.fitVessel
        ? Math.min(width / vesselW, height / vesselH)
        : Math.min(width / 900, height / 550)
    signal residentSelected(string key)

    clip: root.fitVessel
    onVisibleChanged: if (visible) { ground.requestArt(); bridge.requestArt(); glass.requestArt(); } else pointerKey=""
    onWeatherChanged: if (!animationRunning) settleWeather()
    onAnimationRunningChanged: {
        if (!animationRunning) { settleWeather(); touches=[]; }
        staticTouch=null;
    }
    onEnabledChanged: if (!enabled) { touches=[]; staticTouch=null; pointerKey=""; }
    onArtworkOnlyChanged: if (artworkOnly) { touches=[]; staticTouch=null; pointerKey=""; }
    Component.onCompleted: { settleWeather(); sceneReady=true; }

    function settleWeather() {
        rain=Dynamics.clamp(Dynamics.finite(weather.rain,0),0,1);
        activity=Dynamics.clamp(Dynamics.finite(weather.activity,0),0,1);
        water=Dynamics.clamp(Dynamics.finite(weather.water,0),0,1);
    }
    function botanicalPaintCount() {
        var result=0;
        for(var i=0;i<plants.count;i++) { var plant=plants.itemAt(i); if(plant)result+=plant.paintCount; }
        return result;
    }
    function touchAt(x,y,key) {
        if (!root.enabled || !root.visible || root.artworkOnly || !Dynamics.inGlass(x,y)) return false;
        var kind=Dynamics.inPond(x,y)?"pond":"glass";
        if (root.animationRunning) {
            touches=Dynamics.addTouch(touches,x,y,kind); staticTouch=null;
        } else {
            // Reduced motion acknowledges a touch without starting a clock.
            staticTouch={x:x,y:y,kind:kind,key:key||""};
        }
        return true;
    }
    function interactSelected() {
        if (!root.enabled || !root.visible || root.artworkOnly) return false;
        for(var i=0;i<root.slots.length;i++) {
            var resident=root.slots[i];
            if(resident && resident.key===root.selectedKey) {
                var pos=Model.positions[i];
                return touchAt(pos.x,pos.y-48,resident.key);
            }
        }
        return false;
    }
    function residentAt(x,y) {
        if (!root.enabled || !root.visible || root.artworkOnly || !Dynamics.inGlass(x,y))return null;
        // Basal targets have priority even where another canopy crosses them.
        // Their minimum screen size remains useful in the compact garden.
        var radius=Math.max(12,13/Math.max(.1,root.drawingScale));
        var closest=null,distance=radius*radius;
        for(var i=0;i<7;i++)if(root.slots[i]) {
            var position=Model.positions[i],dx=x-position.x,dy=y-position.y;
            var d=dx*dx+dy*dy;
            if(d<=distance){closest=root.slots[i];distance=d;}
        }
        if(closest)return closest;
        // The remaining hit regions follow the same cached botanical form as
        // the painter. Clear spaces between leaves stay available to the glass.
        for(i=6;i>=0;i--) {
            var plant=plants.itemAt(i);
            if(!plant || !plant.resident)continue;
            var point=plant.mapFromItem(drawing,x,y);
            if(plant.containsBotanical(point.x,point.y))return plant.resident;
        }
        return null;
    }

    // One clock advances rendering state. Cached Canvases never follow phase.
    Timer {
        interval:50; running:root.animationRunning; repeat:true
        onTriggered: {
            root.phase+=.05;
            root.rain=Dynamics.smooth(root.rain,Dynamics.clamp(Dynamics.finite(root.weather.rain,0),0,1),.05,1.2);
            root.activity=Dynamics.smooth(root.activity,Dynamics.clamp(Dynamics.finite(root.weather.activity,0),0,1),.05,1.2);
            root.water=Dynamics.smooth(root.water,Dynamics.clamp(Dynamics.finite(root.weather.water,0),0,1),.05,1.4);
            if(root.touches.length)root.touches=Dynamics.ageTouches(root.touches,.05);
            for(var i=0;i<plants.count;i++) { var plant=plants.itemAt(i); if(plant && plant.visible)plant.advance(.05); }
        }
    }

    Item {
        id:drawing
        objectName:"scenePlate"
        width:900; height:550
        transformOrigin:Item.TopLeft
        scale:root.drawingScale
        x:root.fitVessel ? (root.width-root.vesselW*scale)/2-root.vesselX*scale : (root.width-900*scale)/2
        y:root.fitVessel ? (root.height-root.vesselH*scale)/2-root.vesselY*scale : (root.height-550*scale)/2

        CachedPlate {
            id:ground; rasterScale:root.textureScale
            contentKey:root.groundKey
            paintContent:function(context){Painter.paintGround(context,root.colors,Math.round(root.water*10)/10,root.sky,root.textureScale);}
        }

        // Fixed slots survive replacement telemetry arrays: no texture rebuilds,
        // lost interpolation, or lost keyboard focus on ordinary samples.
        Repeater {
            id:plants
            model:7
            PlantSprite {
                required property int index
                readonly property var pos:Model.positions[index]
                resident:root.slots[index]
                colors:root.colors
                rasterScale:root.textureScale
                enabled:!root.artworkOnly
                ornaments:!root.artworkOnly
                pointerHovered:resident!==null && root.pointerKey===resident.key
                opening:root.sky.opening
                phase:root.phase
                moving:root.animationRunning
                selected:resident!==null && root.selectedKey===resident.key
                acknowledged:root.staticTouch!==null && resident!==null && root.staticTouch.key===resident.key
                impulse:Dynamics.impulseAt(root.touches,pos.x,pos.y-65)
                x:pos.x-rootX; y:pos.y-rootY; z:pos.y
                onActivated:function(localX,localY) {
                    if(!resident)return;
                    root.residentSelected(resident.key);
                    root.touchAt(x+localX,y+localY,resident.key);
                }
            }
        }
        CachedPlate {
            id:bridge; rasterScale:root.textureScale; z:395
            contentKey:JSON.stringify(root.colors)
            paintContent:function(context){Painter.paintBridge(context,root.colors,root.textureScale);}
        }

        // Fixed geometry pools fade smoothly as the readings change.
        Repeater {
            model:24
            Item {
                required property int index
                readonly property real t:root.phase*(.17+index%4*.02)+index*2.399
                readonly property real baseX:280+(index*83%350)
                readonly property real baseY:180+(index*47%195)
                readonly property real touch:Dynamics.impulseAt(root.touches,baseX,baseY)
                x:baseX+Math.sin(t)*42+touch*2.5; y:baseY+Math.cos(t*.7)*20+touch; z:790
                width:22; height:22
                opacity:Dynamics.clamp(5+root.activity*19-index,0,1)*(.35+(Math.sin(t*2)+1)*.28)*(.65+root.sky.night*.35)
                Rectangle { anchors.centerIn:parent;width:14;height:14;radius:7;color:root.colors.gold;opacity:.045 }
                Rectangle { anchors.centerIn:parent;width:7;height:7;radius:4;color:root.colors.gold;opacity:.1 }
                Rectangle { anchors.centerIn:parent;width:2.5;height:2.5;radius:2;color:root.colors.gold }
            }
        }
        Repeater {
            model:54
            Rectangle {
                required property int index
                readonly property real travel:(root.phase*115+index*29)%268
                x:227+(index*97%440)+travel*.06; y:115+travel; z:800
                width:.8; height:5+index%4; radius:1; rotation:-4; color:root.colors.water
                opacity:Dynamics.clamp(root.rain*54-index,0,1)*(.12+(index%4)*.06)
            }
        }
        Repeater {
            model:3
            Rectangle {
                required property int index
                readonly property real travel:(root.phase*.23+index/3)%1
                x:549-width/2+index*15; y:414-height/2+index*3; z:404
                width:10+travel*40; height:width*.2; radius:width
                color:"transparent"; border.color:root.colors.leafLight; border.width:1
                opacity:(1-travel)*(.1+root.rain*.3)
            }
        }
        Repeater {
            model:4
            Rectangle {
                required property int index
                readonly property var touch:index<root.touches.length?root.touches[index]:null
                readonly property bool pond:touch!==null && touch.kind==="pond"
                readonly property real age:touch?touch.age:0
                visible:!root.artworkOnly && touch!==null
                x:(touch?touch.x:0)-width/2; y:(touch?touch.y:0)-height/2; z:pond?405:810
                width:pond?12+age*27:8+age*13; height:width*(pond?.25:1); radius:width/2
                color:"transparent"; border.color:root.colors.gold; border.width:1
                opacity:Math.max(0,1-age/2.3)*(pond?.65:.35)
            }
        }
        Rectangle {
            visible:!root.artworkOnly && root.staticTouch!==null
            x:(root.staticTouch?root.staticTouch.x:0)-width/2; y:(root.staticTouch?root.staticTouch.y:0)-height/2
            z:810
            width:root.staticTouch && root.staticTouch.kind==="pond"?35:15
            height:root.staticTouch && root.staticTouch.kind==="pond"?9:15
            radius:width/2; color:"transparent"; border.color:root.colors.gold; border.width:1; opacity:.65
        }
        CachedPlate {
            id:glass; rasterScale:root.textureScale; z:1000
            contentKey:JSON.stringify(root.colors)
            paintContent:function(context){Painter.paintGlass(context,root.colors,root.textureScale);}
        }
        MouseArea {
            anchors.fill:parent; z:1050
            enabled:!root.artworkOnly
            hoverEnabled:true
            cursorShape:root.pointerKey!==""?Qt.PointingHandCursor:Qt.ArrowCursor
            onPositionChanged:function(mouse){var resident=root.residentAt(mouse.x,mouse.y);root.pointerKey=resident?resident.key:"";}
            onExited:root.pointerKey=""
            onClicked:function(mouse) {
                var resident=root.residentAt(mouse.x,mouse.y);
                if(resident)root.residentSelected(resident.key);
                root.touchAt(mouse.x,mouse.y,resident?resident.key:"");
            }
        }

        // Names are hover/focus discovery hints, not permanent scene stickers.
        Repeater {
            model:7
            Rectangle {
                required property int index
                readonly property var plant:root.sceneReady?plants.itemAt(index):null
                readonly property var resident:root.slots[index]
                readonly property var pos:Model.positions[index]
                objectName:resident?"plant-label-"+resident.key:""
                visible:!root.artworkOnly && resident!==null && plant!==null && plant.hovered
                x:Math.max(155,Math.min(745-width,pos.x-width/2)); y:pos.y+18
                width:Math.min(label.implicitWidth+18,220); height:24; radius:4; z:1100
                color:root.colors.panel; border.color:root.colors.line
                Text {
                    id:label
                    anchors.centerIn:parent; width:parent.width-18
                    text:parent.resident && typeof parent.resident.name==="string"?parent.resident.name:""; elide:Text.ElideRight
                    textFormat:Text.PlainText; color:root.colors.ink; font.pixelSize:11
                }
            }
        }
    }

    // Acknowledgements describe the exact submitted content, not merely an
    // issued paint command. Serializing submissions prevents a late old painted
    // signal from declaring a changed palette or resident texture ready.
    component CachedPlate: Canvas {
        id:cache
        property string contentKey:""
        property var paintContent
        property real rasterScale:1
        property bool inFlight:false
        property string issuedKey:""
        property string completedKey:""
        readonly property string renderKey:contentKey+":"+width+":"+height+":"+canvasSize.width+":"+canvasSize.height
        readonly property bool artReady:completedKey!=="" && completedKey===renderKey
        width:parent?parent.width*rasterScale:900
        height:parent?parent.height*rasterScale:550
        scale:1/rasterScale
        transformOrigin:Item.TopLeft
        renderStrategy:Canvas.Threaded
        function requestArt() { if (!inFlight) requestPaint(); }
        onRenderKeyChanged:requestArt()
        onAvailableChanged:if(available)requestArt()
        onPaint:{
            if(inFlight || typeof paintContent!=="function")return;
            issuedKey=renderKey; inFlight=true;
            paintContent(getContext("2d"));
        }
        onPainted:{
            if(!inFlight)return;
            completedKey=issuedKey; inFlight=false;
            if(!artReady)requestArt();
        }
        Component.onCompleted:requestArt()
    }
}
