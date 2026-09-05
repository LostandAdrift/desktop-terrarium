import QtQuick

// A panel's observation lifetime. Keeping it independent of window APIs lets
// the real ownership behavior be exercised through screen and lock changes.
QtObject {
    id: root
    property bool opened: false
    property bool demo: false
    property bool ambient: false
    property bool host: false
    property bool locked: false
    property bool hasScreen: true
    property bool ready: false
    readonly property string key: "panel-" + Date.now() + "-" + Math.random().toString(16).slice(2)
    readonly property bool observing: hasScreen && !locked && ((opened && !demo) || (ambient && host))
    function sync() { if (ready) Habitat.watch(key, observing); }
    onObservingChanged: sync()
    Component.onCompleted: { ready = true; sync(); }
    Component.onDestruction: Habitat.unwatch(key)
}
