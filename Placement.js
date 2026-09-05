.pragma library

// Pure placement policy. Dimensions are logical screen coordinates; callers
// keep coordinator ownership and saved preferences separate from this choice.
var corners = ["top-left", "top-right", "bottom-left", "bottom-right"];
var sizes = ["small", "medium", "large"];
var targetWidths = { small: 440, medium: 600, large: 760 };

function normalizeDisplay(value) {
    return typeof value === "string"
        ? value.replace(/[\x00-\x1f\x7f-\x9f]/g, "").trim().slice(0, 256) : "";
}
function normalizeCorner(value) {
    var name = typeof value === "string" ? value.trim().toLowerCase() : "";
    return corners.indexOf(name) >= 0 ? name : "bottom-right";
}
function normalizeSize(value) {
    var name = typeof value === "string" ? value.trim().toLowerCase() : "";
    return sizes.indexOf(name) >= 0 ? name : "medium";
}
function normalizeOptions(value) {
    var options = value && typeof value === "object" ? value : {};
    return { display: normalizeDisplay(options.display), corner: normalizeCorner(options.corner), size: normalizeSize(options.size) };
}
function logicalExtent(value) {
    return typeof value === "number" && isFinite(value) && value >= 1 ? value : 0;
}

// `screens` may be a QML list wrapper rather than a JavaScript Array. The
// returned screen is the original object, suitable for PanelWindow.screen.
function chooseScreen(screens, savedDisplay) {
    var requested = normalizeDisplay(savedDisplay), first = null, firstIndex = -1;
    var count = screens && typeof screens.length === "number" && isFinite(screens.length)
        ? Math.min(64, Math.max(0, Math.floor(screens.length))) : 0;
    for (var i = 0; i < count; i++) {
        var screen = screens[i];
        if (!screen || !logicalExtent(screen.width) || !logicalExtent(screen.height)) continue;
        var name = normalizeDisplay(screen.name);
        if (first === null) { first = screen; firstIndex = i; }
        if (requested && name === requested)
            return { screen: screen, index: i, display: name, requestedDisplay: requested, fallback: false };
    }
    return { screen: first, index: firstIndex, display: first ? normalizeDisplay(first.name) : "",
        requestedDisplay: requested, fallback: first !== null && requested !== "" };
}

function geometry(screen, size, corner) {
    var w = logicalExtent(screen ? screen.width : 0), h = logicalExtent(screen ? screen.height : 0);
    var name = normalizeCorner(corner);
    var anchors = { top: name.indexOf("top-") === 0, bottom: name.indexOf("bottom-") === 0,
        left: name.slice(-5) === "-left", right: name.slice(-6) === "-right" };
    // Keep the normal 36-pixel inset on ordinary screens. On tiny screens,
    // reserve at most one eighth of the short edge on each side for breathing
    // room rather than allowing the margins to consume the whole destination.
    var margin = w && h ? Math.min(36, Math.floor(Math.min(w, h) / 8)) : 0;
    var availableW = Math.max(0, w - margin * 2), availableH = Math.max(0, h - margin * 2);
    var width = w && h ? Math.min(targetWidths[normalizeSize(size)], availableW, availableH * 900 / 550) : 0;
    var height = width * 550 / 900;
    return { width: width, height: height, margin: margin, visible: width > 0 && height > 0,
        anchors: anchors,
        margins: { top: anchors.top ? margin : 0, bottom: anchors.bottom ? margin : 0,
            left: anchors.left ? margin : 0, right: anchors.right ? margin : 0 } };
}
