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
}
