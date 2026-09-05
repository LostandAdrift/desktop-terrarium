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
    property bool pointerHovered: false
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
    readonly property int residentSlot: resident ? resident.slot : 0
    readonly property bool hovered: pointerHovered || activeFocus
    readonly property real rootX: 128
    readonly property real rootY: 244
    readonly property bool edgeResident: resident!==null && (residentSlot===3 || residentSlot===4)
    readonly property var stature: Dynamics.stature(category,residentSlot)
    readonly property real plantScale: .57 + shownGrowth * .43
    readonly property int maturity: Dynamics.maturity(resident?resident.growth:.35)
    readonly property var form: Painter.plantForm(identity,category,maturity)
    readonly property var freePose: Dynamics.pose(category, identity, moving ? phase : 0, energy, impulse)
    readonly property var pose: ({angle:Dynamics.clamp(freePose.angle,edgeResident?-3.2:-7,edgeResident?3.2:7),stretch:freePose.stretch,glow:freePose.glow})
    readonly property var tips: category === "agent" ? form.blooms : []
    readonly property string paintKey: identity + ":" + category + ":" + maturity + ":" + JSON.stringify(colors)
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
    function containsBotanical(x,y) {
        var point=botanical.mapFromItem(root,x,y);
        return Painter.containsPlant(root.form,point.x-root.rootX,point.y-root.rootY,2.5);
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
        width:50*root.plantScale*root.stature.x; height:14*root.plantScale; radius:width/2
        color:"#25352b"; opacity:.65*root.shownOpacity
    }
    Rectangle {
        objectName:"root-ring-"+root.identity
        visible:root.ornaments
        x:root.rootX-width/2; y:root.rootY-height/2+3
        width:Math.max(32,60*root.plantScale*root.stature.x); height:16*root.plantScale; radius:width/2
        color:"transparent"; border.color:root.colors.gold; border.width:root.acknowledged?2:1
        opacity:root.selected || root.acknowledged || root.activeFocus ? .8 : root.pointerHovered ? .45 : 0
    }

    Item {
        id: botanical
        objectName:"botanical-"+root.identity
        anchors.fill:parent
        opacity:root.shownOpacity
        transform:[
            Scale { origin.x:root.rootX; origin.y:root.rootY; xScale:root.plantScale*root.stature.x; yScale:root.plantScale*root.stature.y*root.pose.stretch },
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
                Painter.paintPlant(getContext("2d"), root.colors, root.resident, Math.round(root.opening*16)/16,root.textureScale,root.form);
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
                x:root.rootX+modelData.x-width/2; y:root.rootY+modelData.y-height/2
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

}
