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
    signal residentSelected(string key)
    readonly property real drawingScale: Math.min(width / 900, height / 550)
    readonly property string compositionKey: JSON.stringify(residents.map(function(p) {
        return [p.key,p.category,p.slot,Math.round(p.growth*10),p.missing>0];
    })) + palette.name + Math.round(weather.water * 10)

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
        anchors.centerIn: parent
        scale: root.drawingScale

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
                required property var modelData
                readonly property var pos: Model.positions[modelData.slot]
                readonly property bool selected: root.selectedKey === modelData.key
                x: pos.x-38; y: pos.y-114
                width:76; height:135
                Rectangle {
                    anchors.bottom:parent.bottom; anchors.horizontalCenter:parent.horizontalCenter
                    width:60;height:16;radius:30
                    color:"transparent";border.color:root.palette.gold;border.width:1
                    opacity:parent.selected? .8 : hit.containsMouse ? .45 : 0
                }
                Rectangle {
                    visible:parent.selected || hit.containsMouse
                    anchors.horizontalCenter:parent.horizontalCenter
                    y:138;width:Math.min(label.implicitWidth+18,220);height:24;radius:4
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
