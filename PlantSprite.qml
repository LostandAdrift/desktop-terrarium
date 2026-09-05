pragma ComponentBehavior: Bound
import QtQuick
import "ScenePainter.js" as Painter
import "SceneDynamics.js" as Dynamics

Item {
    id: root
    property var resident: null
    property var colors
    property real opening: 1
    property real phase: 0
    property real impulse: 0
    property bool moving: false
    property bool selected: false
    property bool acknowledged: false
    property bool ornaments: true
    property real rasterScale: 1
    readonly property real textureScale: Math.max(1,Math.min(2,isFinite(rasterScale)?rasterScale:1))
    property real energy: 0
    property real shownGrowth: .35
    property real shownOpacity: 1
    property int paintCount: 0
    property bool paintInFlight: false
    property string issuedPaintKey: ""
    property string completedPaintKey: ""
    readonly property string identity: resident ? resident.key : ""
    readonly property string category: resident ? resident.category : "other"
    readonly property bool hovered: pointer.containsMouse || activeFocus
    readonly property real rootX: 128
    readonly property real rootY: 244
    readonly property bool edgeResident: resident!==null && (resident.slot===3 || resident.slot===4)
    readonly property real edgeScale: edgeResident ? (category==="browser"?.7:(category==="editor" || category==="terminal"?.88:1)) : 1
    readonly property real plantScale: (.57 + shownGrowth * .43) * (resident && resident.slot < 2 ? 1.08 : 1) * edgeScale
    readonly property var freePose: Dynamics.pose(category, identity, moving ? phase : 0, energy, impulse)
    readonly property var pose: ({angle:Dynamics.clamp(freePose.angle,edgeResident?-3.2:-7,edgeResident?3.2:7),stretch:freePose.stretch,glow:freePose.glow})
    readonly property var tips: category === "agent" ? Painter.lanternTips(identity) : []
    readonly property string paintKey: identity + ":" + category + ":" + JSON.stringify(colors)
        + ((category === "agent" || category === "media") ? ":" + Math.round(opening * 16) : "")
    readonly property string renderKey: paintKey+":"+plantCanvas.width+":"+plantCanvas.height+":"+plantCanvas.canvasSize.width+":"+plantCanvas.canvasSize.height
    readonly property bool artReady: completedPaintKey!=="" && completedPaintKey===renderKey
    signal activated(real localX, real localY)

    width: 256; height: 260
    visible: resident !== null
    objectName: "plant-" + identity
    activeFocusOnTab: visible && enabled
    Accessible.role: Accessible.Button
    Accessible.name: ornaments && resident && typeof resident.name==="string" ? "Inspect and touch " + resident.name : "Terrarium plant"
    Accessible.onPressAction: root.activated(rootX, rootY-55)
    Keys.onReturnPressed: root.activated(rootX, rootY-55)
    Keys.onEnterPressed: root.activated(rootX, rootY-55)
    Keys.onSpacePressed: root.activated(rootX, rootY-55)

    function settle() {
        energy = Dynamics.targetEnergy(resident);
        shownGrowth = Dynamics.growth(resident);
        shownOpacity = resident && resident.missing > 0 ? .45 : 1;
    }
    function advance(seconds) {
        energy = Dynamics.smooth(energy, Dynamics.targetEnergy(resident), seconds, 1.25);
        shownGrowth = Dynamics.smooth(shownGrowth, Dynamics.growth(resident), seconds, .7);
        shownOpacity = Dynamics.smooth(shownOpacity, resident && resident.missing > 0 ? .45 : 1, seconds, .65);
    }
    onIdentityChanged: settle()
    onResidentChanged: if (!moving) settle()
    onMovingChanged: if (!moving) settle()
    function requestArt() { if (!paintInFlight) plantCanvas.requestPaint(); }
    onRenderKeyChanged: requestArt()
    Component.onCompleted: { settle(); requestArt(); }

    // Neither this shadow nor the selection ring rotates: the root stays planted.
    Rectangle {
        x:root.rootX-width/2; y:root.rootY-3
        width:50*root.plantScale; height:14*root.plantScale; radius:width/2
        color:"#25352b"; opacity:.65*root.shownOpacity
    }
    Rectangle {
        objectName:"root-ring-"+root.identity
        visible:root.ornaments
        x:root.rootX-width/2; y:root.rootY-height/2+3
        width:60*root.plantScale; height:16*root.plantScale; radius:width/2
        color:"transparent"; border.color:root.colors.gold; border.width:root.acknowledged?2:1
        opacity:root.selected || root.acknowledged || root.activeFocus ? .8 : pointer.containsMouse ? .45 : 0
    }

    Item {
        id: botanical
        objectName:"botanical-"+root.identity
        anchors.fill:parent
        opacity:root.shownOpacity
        transform:[
            Scale { origin.x:root.rootX; origin.y:root.rootY; xScale:root.plantScale; yScale:root.plantScale*root.pose.stretch },
            Rotation { origin.x:root.rootX; origin.y:root.rootY; angle:root.pose.angle }
        ]
        Canvas {
            id:plantCanvas
            width:root.width*root.textureScale
            height:root.height*root.textureScale
            scale:1/root.textureScale
            transformOrigin:Item.TopLeft
            renderStrategy:Canvas.Threaded
            onAvailableChanged: if (available) root.requestArt()
            onPaint: {
                if (!root.colors || root.paintInFlight) return;
                root.issuedPaintKey=root.renderKey;
                root.paintInFlight=true;
                Painter.paintPlant(getContext("2d"), root.colors, root.resident, Math.round(root.opening*16)/16,root.textureScale);
                root.paintCount++;
            }
            onPainted: {
                if (!root.paintInFlight) return;
                root.completedPaintKey=root.issuedPaintKey;
                root.paintInFlight=false;
                if (!root.artReady) root.requestArt();
            }
        }
        Repeater {
            model:root.tips
            Rectangle {
                required property var modelData
                x:modelData.x-width/2; y:modelData.y-height/2
                width:29; height:29; radius:15
                color:root.colors.gold
                opacity:root.pose.glow*.08
                Rectangle {
                    anchors.centerIn:parent; width:11; height:13; radius:6
                    color:root.colors.gold; opacity:.5
                }
            }
        }
    }

    MouseArea {
        id:pointer
        x:root.rootX-width/2
        y:root.rootY-height+7
        width:(root.category==="browser"?194:root.category==="agent"?126:root.category==="system"?124:190)*root.plantScale+8
        height:(root.category==="browser"?222:root.category==="agent"?166:root.category==="system"?74:128)*root.plantScale+8
        hoverEnabled:true
        cursorShape:Qt.PointingHandCursor
        onClicked:function(mouse){root.activated(x+mouse.x,y+mouse.y);}
    }
}
