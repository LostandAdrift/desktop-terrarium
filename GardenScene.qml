pragma ComponentBehavior: Bound
import QtQuick
import "Model.js" as Model
import "ScenePainter.js" as Painter

Item {
    id: root
    property var palette: Model.palette("dusk", 20)
    property var residents: []
    property var weather: ({ rain:0, activity:0, water:0, particles:5 })
    property bool animate: true
    property string selectedKey: ""
    property real phase: 0
    property bool fitVessel: false
    signal residentSelected(string key)
    // Painted glass, brass loop, and plinth occupy this crop of the 900x550 plate.
    readonly property real vesselX: 140
    readonly property real vesselY: 12
    readonly property real vesselW: 620
    readonly property real vesselH: 528
    readonly property real drawingScale: root.fitVessel
        ? Math.min(width / vesselW, height / vesselH)
        : Math.min(width / 900, height / 550)
    readonly property string compositionKey: JSON.stringify(residents.map(function(p) {
        return [p.key,p.category,p.slot,Math.round(p.growth*10),p.missing>0];
    })) + palette.name + Math.round(weather.water * 10)

    clip: root.fitVessel
    onCompositionKeyChanged: backdrop.requestPaint()
    onVisibleChanged: if (visible) backdrop.requestPaint()

    Timer {
        interval: 50
        running: root.animate && root.visible
        repeat: true
        onTriggered: root.phase = (root.phase + 0.05) % 3600
    }

    Item {
        id: drawing
        width: 900; height: 550
        transformOrigin: Item.TopLeft
        scale: root.drawingScale
        x: root.fitVessel
            ? (root.width - root.vesselW * scale) / 2 - root.vesselX * scale
            : (root.width - 900 * scale) / 2
        y: root.fitVessel
            ? (root.height - root.vesselH * scale) / 2 - root.vesselY * scale
            : (root.height - 550 * scale) / 2

        Canvas {
            id: backdrop
            anchors.fill: parent
            renderStrategy: Canvas.Threaded
            onPaint: Painter.paint(getContext("2d"), root.palette, root.residents, root.weather.water)
            Component.onCompleted: requestPaint()
        }

        // Drifting light represents aggregate CPU activity. Rain represents
        // received network traffic, not actual meteorological weather.
        Repeater {
            model: root.weather.particles
            Item {
                required property int index
                readonly property real t: root.phase * (.17 + index % 4 * .02) + index * 2.399
                x: 280 + (index * 83 % 350) + Math.sin(t) * 42
                y: 180 + (index * 47 % 195) + Math.cos(t * .7) * 20
                width: 22; height: 22
                opacity: .35 + (Math.sin(t * 2) + 1) * .28
                Rectangle { anchors.centerIn: parent; width:14; height:14; radius:7; color:root.palette.gold; opacity:.045 }
                Rectangle { anchors.centerIn: parent; width:7; height:7; radius:4; color:root.palette.gold; opacity:.1 }
                Rectangle { anchors.centerIn: parent; width:2.5; height:2.5; radius:2; color:root.palette.gold }
            }
        }
        Repeater {
            model: Math.round(root.weather.rain * 54)
            Rectangle {
                required property int index
                readonly property real travel: (root.phase * 115 + index * 29) % 268
                x: 227 + (index * 97 % 440) + travel * .06
                y: 115 + travel
                width: .8; height: 5 + index % 4
                radius:1
                rotation: -4
                color: root.palette.water
                opacity: .12 + (index % 4) * .06
            }
        }
        // Ripples use cheap geometry; the illustration is not repainted.
        Repeater {
            model: 3
            Rectangle {
                required property int index
                readonly property real travel: (root.phase * .23 + index / 3) % 1
                x: 549 - width / 2 + index * 15
                y: 414 - height / 2 + index * 3
                width: 10 + travel * 40
                height: width * .2
                radius: width
                color: "transparent"
                border.color: root.palette.leafLight
                border.width: 1
                opacity: (1 - travel) * (.1 + root.weather.rain * .3)
            }
        }
        Repeater {
            model: root.residents
            Item {
                id: plantHit
                required property var modelData
                readonly property var pos: Model.positions[modelData.slot]
                readonly property bool selected: root.selectedKey === modelData.key
                readonly property bool tallFoliage: modelData.category === "browser" || modelData.category === "agent"
                objectName: "plant-" + modelData.key
                x: pos.x - width / 2
                y: pos.y - (tallFoliage ? 228 : 118)
                width: tallFoliage ? 130 : 80
                height: tallFoliage ? 250 : 140
                Rectangle {
                    anchors.bottom:parent.bottom; anchors.horizontalCenter:parent.horizontalCenter
                    width:60;height:16;radius:30
                    color:"transparent";border.color:root.palette.gold;border.width:1
                    opacity:parent.selected? .8 : hit.containsMouse ? .45 : 0
                }
                Rectangle {
                    visible:parent.selected || hit.containsMouse
                    anchors.horizontalCenter:parent.horizontalCenter
                    anchors.top:parent.bottom;anchors.topMargin:4
                    width:Math.min(label.implicitWidth+18,220);height:24;radius:4
                    color:root.palette.panel;border.color:root.palette.line
                    Text {
                        id:label;anchors.centerIn:parent;width:parent.width-18;text:modelData.name;elide:Text.ElideRight
                        textFormat:Text.PlainText;color:root.palette.ink;font.pixelSize:11
                    }
                }
                MouseArea {
                    id:hit;anchors.fill:parent;hoverEnabled:true;cursorShape:Qt.PointingHandCursor
                    onClicked:root.residentSelected(modelData.key)
                    Accessible.role: Accessible.Button
                    Accessible.name: "Inspect " + modelData.name
                }
            }
        }
    }
}
