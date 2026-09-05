import QtQuick

Rectangle {
    id: root
    property string text: ""
    property string hint: ""
    property color ink: "#e6e8d8"
    property color muted: "#9cacaa"
    property color surface: "#1c2b30"
    property color line: "#304247"
    property color accent: "#dfbc7b"
    property bool selected: false
    property bool quiet: false
    property bool hintAbove: false
    property Item hintLayer: null
    signal clicked()
    implicitWidth: label.implicitWidth + 24
    implicitHeight: 32
    radius: 5
    color: selected || mouse.containsMouse || activeFocus ? surface : "transparent"
    border.width: selected || activeFocus || !quiet ? 1 : 0
    border.color: activeFocus ? accent : line
    activeFocusOnTab: true
    Accessible.role: Accessible.Button
    Accessible.name: hint || text
    Accessible.onPressAction: root.clicked()
    Text {
        id: label
        anchors.centerIn: parent
        text: root.text
        textFormat: Text.PlainText
        color: root.selected ? root.accent : root.ink
        font.pixelSize: 12
    }
    MouseArea {
        id:mouse;anchors.fill:parent;hoverEnabled:true;cursorShape:Qt.PointingHandCursor
        onClicked: root.clicked()
    }
    Keys.onReturnPressed: clicked()
    Keys.onEnterPressed: clicked()
    Keys.onSpacePressed: clicked()
    Rectangle {
        id: tooltip
        objectName: "hint-" + root.objectName
        parent: root.hintLayer || root
        visible: root.visible && root.hint.length > 0 && (mouse.containsMouse || root.activeFocus)
        // Resolve again when shown or resized; the control may live in a Row.
        readonly property point origin: {
            var geometry = [visible, root.x, root.y, root.width, root.height, parent.width, parent.height];
            return root.mapToItem(parent, 0, 0);
        }
        width: root.hintLayer ? Math.min(hintLabel.implicitWidth + 14, parent.width - 16) : hintLabel.implicitWidth + 14
        height: hintLabel.implicitHeight + 8
        radius: 4
        z: 20
        color: root.surface
        border.color: root.line
        x: root.hintLayer ? Math.max(8, Math.min(parent.width - width - 8, origin.x + (root.width - width) / 2)) : (root.width - width) / 2
        y: {
            var desired = origin.y + (root.hintAbove ? -height - 6 : root.height + 6);
            return root.hintLayer ? Math.max(8, Math.min(parent.height - height - 8, desired)) : desired;
        }
        Text {
            id: hintLabel
            anchors.centerIn: parent
            width: parent.width - 14
            text: root.hint
            textFormat: Text.PlainText
            wrapMode: Text.WordWrap
            color: root.ink
            font.pixelSize: 11
        }
    }
}
