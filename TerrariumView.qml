pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Window
import "Model.js" as Model
import "PostcardModel.js" as PostcardModel

FocusScope {
    id: root
    property var snapshot: Model.emptySnapshot()
    property var garden: Model.newGarden()
    property string paletteName: "auto"
    property real hour: new Date().getHours()+new Date().getMinutes()/60
    property bool motionPaused: false
    property bool reducedMotion: false
    property bool demo: false
    property bool ambient: false
    property var displays: []
    property string ambientDisplay: ""
    property string ambientCorner: "bottom-right"
    property string ambientSize: "medium"
    property bool postcardAvailable: false
    property bool exportBusy: false
    property string exportStatus: ""
    property string exportPath: ""
    property bool postcardPathCopied: false
    property bool active: true
    property string status: "Connecting to your desktop…"
    property bool stale: false
    property string section: "garden"
    property string selectedKey: ""
    property Item artReturnFocus: null
    property string artReturnSection: "garden"
    property Item postcardReturnFocus: null
    property string postcardReturnSection: "garden"
    property var postcardSnapshot: null
    property string postcardSource: ""
    property bool postcardLoaded: false
    readonly property bool artMode: section === "art"
    readonly property bool postcardMode: section === "postcard"
    readonly property bool postcardReady: postcardLoaded && postcardLoader.item!==null && postcardLoader.item.ready
    readonly property bool postcardSaving: exportBusy || (postcardLoader.item!==null && postcardLoader.item.busy)
    readonly property bool gardenVisible: section === "garden" || artMode
    readonly property var displayChoices: {
        var result=[], seen=Object.create(null);
        var available=Array.isArray(displays)?displays:[];
        for(var i=0;i<Math.min(available.length,32);i++) {
            var display=available[i];
            if(!display || typeof display.name!=="string" || !display.name.length || seen[display.name])continue;
            seen[display.name]=true;
            result.push({name:display.name,label:typeof display.label==="string" && display.label.length?display.label:display.name});
        }
        return result;
    }
    readonly property bool displayMissing: {
        if(!ambientDisplay.length)return false;
        for(var i=0;i<displayChoices.length;i++)if(displayChoices[i].name===ambientDisplay)return false;
        return true;
    }
    readonly property bool compact: width < 850 || height < 640
    readonly property bool tight: width < 700
    readonly property bool sceneAnimating:scene.animationRunning
    readonly property int headerBand: artMode ? 0 : compact ? (tight ? 46 : 62) : 92
    readonly property int footerBand: artMode || postcardMode ? 0 : compact ? 34 : 45
    readonly property int bodyY: artMode ? 12 : compact ? (tight ? 54 : 70) : 111
    readonly property int readingsHeight: compact ? 28 : 83
    readonly property var colors: Model.palette(paletteName, hour)
    readonly property var atmosphere: Model.weather(snapshot)
    readonly property var selected: {
        for (var i=0;i<garden.residents.length;i++) if (garden.residents[i].key===selectedKey) return garden.residents[i];
        return null;
    }
    readonly property string habitatBadge: {
        if (root.demo) return "DEMONSTRATION";
        if (root.stale) return "OBSERVATION PAUSED";
        if (!root.snapshot || root.snapshot.timestamp === 0) return "CONNECTING";
        return "LIVE HABITAT";
    }
    readonly property color habitatDot: root.demo ? root.colors.gold : root.stale ? root.colors.flower : (!root.snapshot || root.snapshot.timestamp === 0 ? root.colors.muted : root.colors.leaf)
    signal closeRequested()
    signal demoRequested()
    signal motionRequested()
    signal paletteRequested()
    signal retryRequested()
    signal ambientRequested()
    signal placementRequested(string key, string value)
    signal postcardRequested()
    signal exportRequested(var cardItem)
    signal exportCancelRequested()

    function showSection(name) {
        if(name==="postcard") {root.requestPostcard();return;}
        if(["garden","journal","guide","options","art"].indexOf(name)<0)return;
        var from=root.postcardMode?root.postcardReturnSection:root.section;
        var focus=root.postcardMode?root.postcardReturnFocus:root.Window.window?root.Window.window.activeFocusItem:null;
        if(root.postcardLoaded)root.discardPostcard();
        if(name==="art" && !root.artMode && from!=="art") {
            root.artReturnSection=from;
            root.artReturnFocus=focus;
        }
        root.section=name;
    }
    function leaveArt() {
        var target=root.artReturnFocus;
        root.section=root.artReturnSection==="art"?"garden":root.artReturnSection;
        Qt.callLater(function(){
            if(!root.active || !root.visible)return;
            if(target && target.visible && target.enabled)target.forceActiveFocus();
            else root.forceActiveFocus();
        });
    }
    function capturePostcardSnapshot() {
        root.postcardSnapshot=PostcardModel.create({residents:root.garden.residents,colors:root.colors,hour:root.hour,weather:root.atmosphere});
        root.postcardSource=root.demo?"Demonstration snapshot":root.stale?"Paused observation snapshot":!root.snapshot.timestamp?"Before the first observation":"Live garden snapshot";
    }
    function requestPostcard() {
        if(!root.postcardAvailable || !root.active || !root.visible)return false;
        if(root.postcardMode && root.postcardLoaded)return true;
        root.postcardReturnSection=root.section==="postcard"?"garden":root.section;
        root.postcardReturnFocus=root.Window.window?root.Window.window.activeFocusItem:null;
        root.capturePostcardSnapshot();
        root.postcardLoaded=true;
        root.section="postcard";
        root.postcardRequested();
        return true;
    }
    function savePostcard() {
        if(!root.postcardMode || !root.active || !root.visible || !root.postcardReady || root.postcardSaving)return false;
        root.exportRequested(postcardLoader.item);
        return true;
    }
    function copyPostcardPath() {
        if(!root.postcardMode || !root.active || !root.visible || !root.exportPath.length)return false;
        postcardPathClipboard.selectAll();
        postcardPathClipboard.copy();
        postcardPathClipboard.deselect();
        root.postcardPathCopied=true;
        return true;
    }
    function cancelPostcardCapture() {
        root.exportCancelRequested();
        if(postcardLoader.item!==null)postcardLoader.item.cancelCapture();
    }
    function discardPostcard() {
        if(!root.postcardLoaded && root.postcardSnapshot===null)return;
        // The native writer sees cancellation while its item still exists.
        root.cancelPostcardCapture();
        root.postcardLoaded=false;
        root.postcardSnapshot=null;
        root.postcardSource="";
        root.postcardPathCopied=false;
    }
    function refreshPostcard() {
        if(!root.postcardMode || !root.active || !root.visible || root.postcardSaving)return false;
        root.cancelPostcardCapture();
        root.capturePostcardSnapshot();
        root.postcardRequested();
        return true;
    }
    function leavePostcard() {
        var target=root.postcardReturnFocus;
        var previous=root.postcardReturnSection;
        root.discardPostcard();
        root.section=previous==="postcard"?"garden":previous;
        Qt.callLater(function(){
            if(!root.active || !root.visible)return;
            if(target && target.visible && target.enabled)target.forceActiveFocus();
            else root.forceActiveFocus();
        });
    }
    function abandonPostcard() {
        if(!root.postcardLoaded)return;
        var previous=root.postcardReturnSection;
        root.discardPostcard();
        root.section=previous==="postcard"?"garden":previous;
    }
    function requestClose() {
        root.abandonPostcard();
        root.closeRequested();
    }
    function revealOption(control) {
        if(root.section!=="options" || !control)return;
        var top=control.mapToItem(optionsScroll.contentItem,0,0).y;
        var end=Math.max(0,optionsScroll.contentHeight-optionsScroll.height);
        var offset=optionsScroll.contentY;
        if(top<offset)offset=top;
        else if(top+control.height>offset+optionsScroll.height)offset=top+control.height-optionsScroll.height;
        optionsScroll.contentY=Math.max(0,Math.min(end,offset));
    }
    function revealFocusedOption() {
        var focused=root.Window.window?root.Window.window.activeFocusItem:null;
        var parent=focused;
        while(parent && parent!==optionsScroll.contentItem)parent=parent.parent;
        if(parent)root.revealOption(focused);
    }

    function busiestKey() {
        var best="", score=-1;
        for (var i=0;i<root.garden.residents.length;i++) {
            var r=root.garden.residents[i];
            var s=(r.cpu===null||r.cpu===undefined)?-1:r.cpu;
            if (best==="" || s>score) { best=r.key; score=s; }
        }
        return best;
    }
    function syncSelection() {
        if (!root.garden.residents || !root.garden.residents.length) {
            if (root.selectedKey!=="") root.selectedKey="";
            return;
        }
        var present=false;
        for (var i=0;i<root.garden.residents.length;i++) if (root.garden.residents[i].key===root.selectedKey) { present=true; break; }
        if (!present) root.selectedKey=root.busiestKey();
    }
    function moveSelection(direction) {
        if (!garden.residents.length) return;
        var index = -1;
        for (var i=0;i<garden.residents.length;i++) if(garden.residents[i].key===selectedKey) index=i;
        index=index<0?(direction>0?0:garden.residents.length-1):(index+direction+garden.residents.length)%garden.residents.length;
        selectedKey=garden.residents[index].key;
    }
    function revealResident(row) {
        var top=row.mapToItem(residentList,0,0).y;
        var end=Math.max(0,residentScroll.contentHeight-residentScroll.height);
        var offset=residentScroll.contentY;
        if(top<offset)offset=top;
        else if(top+row.height>offset+residentScroll.height)offset=top+row.height-residentScroll.height;
        residentScroll.contentY=Math.max(0,Math.min(end,offset));
    }
    function scrollSection(key) {
        var target=section==="guide"?guideScroll:section==="journal"?journalScroll:section==="options"?optionsScroll:null;
        if(!target)return false;
        var end=Math.max(0,target.contentHeight-target.height),offset=target.contentY;
        if(key===Qt.Key_Home)offset=0;
        else if(key===Qt.Key_End)offset=end;
        else if(key===Qt.Key_Down)offset+=40;
        else if(key===Qt.Key_Up)offset-=40;
        else if(key===Qt.Key_PageDown)offset+=target.height*.8;
        else if(key===Qt.Key_PageUp)offset-=target.height*.8;
        else return false;
        target.contentY=Math.max(0,Math.min(end,offset));
        return true;
    }
    onGardenChanged: syncSelection()
    onSelectedKeyChanged: Qt.callLater(syncSelection)
    onSectionChanged: {
        if(root.section!=="postcard")root.discardPostcard();
        Qt.callLater(function(){
            if(!root.active || !root.visible)return;
            if(root.artMode)artBack.forceActiveFocus();
            else if(root.postcardMode)postcardPane.forceActiveFocus();
            else if(root.section==="options") {
                optionsScroll.contentY=0;
                optionsScroll.forceActiveFocus();
            }
            else root.forceActiveFocus();
        });
    }
    onActiveChanged:if(!root.active)root.abandonPostcard()
    onVisibleChanged:if(!root.visible)root.abandonPostcard()
    onPostcardAvailableChanged:if(!root.postcardAvailable)root.abandonPostcard()
    onExportPathChanged:root.postcardPathCopied=false
    Component.onCompleted: syncSelection()
    Component.onDestruction:if(root.postcardLoaded)root.cancelPostcardCapture()
    Keys.onPressed: function(event) {
        if(event.key===Qt.Key_Escape) { if(root.postcardMode)root.leavePostcard();else if(root.artMode)root.leaveArt();else if(section!=="garden")root.showSection("garden");else root.requestClose(); }
        else if(event.key===Qt.Key_G) root.showSection("garden");
        else if(event.key===Qt.Key_J) root.showSection("journal");
        else if(event.key===Qt.Key_H || event.key===Qt.Key_Question) root.showSection("guide");
        else if(event.key===Qt.Key_O) root.showSection("options");
        else if(event.key===Qt.Key_F) { if(root.artMode)root.leaveArt();else root.showSection("art"); }
        else if(event.key===Qt.Key_S && (event.modifiers & Qt.ControlModifier) && root.postcardAvailable) {
            if(root.postcardMode)root.savePostcard();else root.requestPostcard();
        }
        else if(event.key===Qt.Key_P) root.motionRequested();
        else if(event.key===Qt.Key_D) root.demoRequested();
        else if(event.key===Qt.Key_C) root.paletteRequested();
        else if(event.key===Qt.Key_A) root.ambientRequested();
        else if(event.key===Qt.Key_Space && root.gardenVisible) scene.interactSelected();
        else if(root.scrollSection(event.key)) {}
        else if(root.gardenVisible && (event.key===Qt.Key_Right || event.key===Qt.Key_Down)) root.moveSelection(1);
        else if(root.gardenVisible && (event.key===Qt.Key_Left || event.key===Qt.Key_Up)) root.moveSelection(-1);
        else return;
        event.accepted=true;
    }

    Rectangle { anchors.fill:parent;color:root.colors.bg;radius:12;border.color:root.colors.line;border.width:1 }
    Rectangle { visible:!root.artMode;x:1;y:1;width:parent.width-2;height:root.headerBand;radius:12;color:root.colors.panel }
    Rectangle { visible:!root.artMode;x:1;y:root.headerBand-20;width:parent.width-2;height:21;color:root.colors.panel }
    Rectangle { visible:!root.artMode;x:24;y:root.headerBand;width:parent.width-48;height:1;color:root.colors.line }

    Column {
        id: titleBlock
        visible:!root.artMode
        x:24;y:root.compact?(root.tight?14:12):20;spacing:4
        width: Math.max(80, parent.width - 48 - navRow.width)
        Text { text:"TERRARIUM / NO. 001";font.pixelSize:10;font.letterSpacing:2;color:root.colors.gold }
        Text {
            objectName:"titleText"
            visible:!root.tight
            width:parent.width
            text:"A little world of your own."
            font.family:"serif";font.pixelSize:root.compact?18:29;color:root.colors.ink
            elide:Text.ElideRight
        }
    }
    Row {
        id: navRow
        visible:!root.artMode
        objectName:"navRow"
        anchors.right:parent.right;anchors.rightMargin:24;y:root.compact?(root.tight?8:16):31;spacing:6
        Control { text:root.compact?"G":"Garden";selected:root.section==="garden";onClicked:root.showSection("garden");hint:"Garden (G)" }
        Control { text:root.compact?"J":"Journal";selected:root.section==="journal";onClicked:root.showSection("journal");hint:"Observation journal (J)" }
        Control { id:optionsButton;objectName:"optionsButton";text:root.compact?"O":"Options";selected:root.section==="options";onClicked:root.showSection("options");hint:"Terrarium options (O)" }
        Control { objectName:"guideButton";text:"?";selected:root.section==="guide";onClicked:root.showSection(root.section==="guide"?"garden":"guide");hint:"Field guide (H)" }
        Control { objectName:"closeButton";text:"×";onClicked:root.requestClose();hint:"Close terrarium (Escape)" }
    }

    Row {
        id:body;x:root.artMode?12:24;y:root.bodyY;width:parent.width-x*2;height:root.height-root.bodyY-root.footerBand-(root.artMode?12:root.compact?4:13);spacing:24
        Item {
            id: mainArea
            width: body.width-(sidebar.visible?276:0)
            height:body.height

            Item {
                id: habitatBand
                visible:!root.artMode && root.section!=="options" && !root.postcardMode
                width: parent.width
                height: !visible ? 0 : root.compact && root.section==="garden" && root.selected!==null ? 38 : 18
                Row {
                    id:habitatLabel;spacing:8
                    Rectangle { width:5;height:5;radius:3;y:4;color:root.habitatDot }
                    Text { objectName:"habitatStatus";text:root.habitatBadge;font.pixelSize:10;font.letterSpacing:1.6;color:root.colors.muted }
                }
                Text {
                    id: compactCaption
                    objectName: "compactCaption"
                    visible: root.compact && root.section==="garden" && root.selected!==null
                    y: 18
                    width: parent.width
                    elide: Text.ElideRight
                    text: root.selected ? root.selected.name+" · "+Model.speciesNames[root.selected.category]+(root.selected.unavailable?" · readings unavailable":" · "+Model.formatPercent(root.selected.cpu)+" CPU · "+Model.formatBytes(root.selected.memoryBytes)) : ""
                    textFormat: Text.PlainText
                    color: root.colors.ink
                    font.pixelSize: 12
                }
            }

            Item {
                id: stage
                objectName: "gardenWell"
                width: parent.width
                anchors.top: habitatBand.bottom
                anchors.bottom: readings.top
                anchors.topMargin: root.artMode ? 0 : 6
                anchors.bottomMargin: root.artMode || root.section==="options" || root.postcardMode ? 0 : root.compact ? 6 : 18

                GardenScene {
                    id:scene
                    objectName:"gardenScene"
                    anchors.fill:parent
                    visible:root.gardenVisible || root.section==="journal"
                    opacity:root.section==="journal" ? 0.55 : 1
                    enabled:root.gardenVisible
                    fitVessel:root.compact || root.artMode
                    hour:root.hour
                    colors:root.colors;residents:root.garden.residents;weather:root.atmosphere
                    animate:root.active && root.gardenVisible && !root.motionPaused && !root.reducedMotion && !root.stale
                    selectedKey:root.selectedKey
                    onResidentSelected:function(key){root.selectedKey=key;}
                }

                Item {
                    id: noticeBox
                    objectName: "noticeBox"
                    visible:root.section==="garden" && !root.demo && (root.snapshot.timestamp===0 || root.stale || root.status.length>0)
                    width:Math.min(parent.width-24,440);height:noticeContent.implicitHeight+20
                    anchors.horizontalCenter:parent.horizontalCenter
                    anchors.top:parent.top
                    anchors.topMargin:10
                    Rectangle { anchors.fill:parent;radius:6;color:root.colors.panel;border.color:root.colors.line }
                    Column {
                        id:noticeContent;x:10;y:10;width:parent.width-20;spacing:8
                        Text { width:parent.width;text:root.status;textFormat:Text.PlainText;horizontalAlignment:Text.AlignHCenter;wrapMode:Text.WordWrap;color:root.colors.ink;font.pixelSize:12 }
                        Control { visible:root.stale;anchors.horizontalCenter:parent.horizontalCenter;text:"Try again";onClicked:root.retryRequested() }
                    }
                }

                Item {
                    visible:root.section==="journal"
                    anchors.fill:parent
                    Rectangle {
                        id: journalPanel
                        x: 8; y: 8
                        width: (root.compact && root.width < 880) ? parent.width-16 : Math.min(440, parent.width*0.56)
                        height: Math.min(parent.height-16, root.garden.notes.length===0 ? (root.compact?168:188) : (root.compact?70:90) + Math.max(52, root.garden.notes.length*32) + 12)
                        radius: 8
                        color: root.colors.panel
                        opacity: 0.92
                        border.color: root.colors.line
                    }
                    Item {
                        x: journalPanel.x+14; y: journalPanel.y+12
                        width: journalPanel.width-28; height: journalPanel.height-24
                        Text { text:"Field notes";font.family:"serif";font.pixelSize:root.compact?22:29;color:root.colors.ink }
                        Text { y:root.compact?30:42;width:parent.width;text:"Small arrivals and departures, observed this session.";color:root.colors.muted;font.pixelSize:12;wrapMode:Text.WordWrap }
                        ListView {
                            id:journalScroll;objectName:"journalScroll"
                            y:root.compact?62:82;width:parent.width;height:parent.height-(root.compact?62:82);clip:true;spacing:14
                            model:root.garden.notes
                            boundsBehavior:Flickable.StopAtBounds
                            delegate:Row {
                                required property var modelData
                                width:ListView.view.width;spacing:14
                                Text { width:43;text:Qt.formatTime(new Date(modelData.time),"HH:mm");color:root.colors.gold;font.pixelSize:11 }
                                Text { width:parent.width-57;text:modelData.text;textFormat:Text.PlainText;color:root.colors.ink;font.pixelSize:12;wrapMode:Text.WordWrap }
                            }
                        }
                        Text {
                            visible:root.garden.notes.length===0;y:root.compact?86:106;width:parent.width
                            text:"Nothing to hurry.\nNew observations will find their way here.";color:root.colors.muted;font.pixelSize:14;lineHeight:1.5
                        }
                    }
                }

                Flickable {
                    id:guideScroll;objectName:"guideScroll"
                    visible:root.section==="guide"
                    anchors.fill:parent
                    anchors.bottomMargin: 22
                    contentWidth:Math.max(40,width-14);contentHeight:guide.implicitHeight+8;clip:true;boundsBehavior:Flickable.StopAtBounds
                    Column {
                        id:guide;width:guideScroll.contentWidth;spacing:14
                        Text { text:"Reading your little world";font.family:"serif";font.pixelSize:root.compact?22:26;color:root.colors.ink }
                        Text { width:parent.width;text:"A living illustration of your computer, with a little room for imagination.";color:root.colors.muted;font.pixelSize:12;wrapMode:Text.WordWrap;lineHeight:1.4 }
                        Text { text:"Private by nature";color:root.colors.gold;font.pixelSize:13 }
                        Text { width:parent.width;wrapMode:Text.WordWrap;lineHeight:1.35;color:root.colors.muted;font.pixelSize:12;text:"No accounts, network requests, or saved activity history. Only process names and numeric counters are observed. Disappearance does not mean a task succeeded." }
                        Text { text:"Numbers and weather";color:root.colors.gold;font.pixelSize:13 }
                        Text { width:parent.width;wrapMode:Text.WordWrap;lineHeight:1.35;color:root.colors.muted;font.pixelSize:12;text:"The readings are your computer. Lanterns, rain, and the pond illustrate those numbers. They are not a forecast, and rain is not weather outside." }
                        Text { text:"Keys";color:root.colors.gold;font.pixelSize:13 }
                        Text { width:parent.width;wrapMode:Text.WordWrap;lineHeight:1.35;color:root.colors.muted;font.pixelSize:12;text:"G garden · J journal · H or ? guide · O options · F art mode · arrows inspect plants · Space gently touch the selected plant · Page Up/Down scroll · P pause · C palette · D demo · A pin to desktop · Esc return or close." }
                        Repeater {
                            model:[
                                {name:"Plants · applications",body:"A few of your busiest process groups take root. They keep their places as activity changes, and grow while observed. Select a plant to see its actual usage."},
                                {name:"Lantern light · CPU",body:"More activity brings more drifting lights. The number below is your computer’s aggregate CPU usage, not a forecast."},
                                {name:"Rain · network",body:"Received network traffic brings a passing shower. Upload traffic appears in the reading below. This is your network, not the weather outside."},
                                {name:"The pond · memory",body:"The water reflects memory in use. Your garden stays healthy at every level; it does not need feeding or attention."},
                                {name:"Time & quiet",body:"The sky follows local time in every palette. Auto also changes the colors through the day. Touch a plant or the pond for a small response; nothing needs feeding or attention. Press P to pause motion, C to choose colors, or D to explore a clearly labeled demonstration."}
                            ]
                            Column {
                                required property var modelData
                                width:guide.width;spacing:5
                                Text { text:modelData.name;color:root.colors.gold;font.pixelSize:13 }
                                Text { width:parent.width;text:modelData.body;color:root.colors.muted;font.pixelSize:12;wrapMode:Text.WordWrap;lineHeight:1.35 }
                            }
                        }
                    }
                }
                Rectangle {
                    objectName:"guideScrollTrack"
                    visible:root.section==="guide" && guideScroll.contentHeight>guideScroll.height+2
                    anchors.right:stage.right;anchors.rightMargin:2
                    anchors.top:stage.top;anchors.bottom:stage.bottom;anchors.topMargin:4;anchors.bottomMargin:4
                    width:5;radius:2;color:root.colors.line
                    Rectangle {
                        objectName:"guideScrollThumb"
                        width:5;radius:2;color:root.colors.gold
                        x:0
                        height: Math.max(18, (stage.height-8) * Math.min(1, guideScroll.height / Math.max(1, guideScroll.contentHeight)))
                        y: (stage.height-8-height) * (guideScroll.contentY / Math.max(1, guideScroll.contentHeight-guideScroll.height))
                    }
                }
                Rectangle {
                    objectName:"guideScrollHint"
                    visible:root.section==="guide" && guideScroll.contentHeight>guideScroll.height+2 && guideScroll.contentY+guideScroll.height<guideScroll.contentHeight-8
                    anchors.bottom:stage.bottom;anchors.horizontalCenter:stage.horizontalCenter;anchors.bottomMargin:4
                    width: hintLabel.implicitWidth+16; height: hintLabel.implicitHeight+8
                    radius: 4
                    color: root.colors.panel
                    border.color: root.colors.line
                    z: 6
                    Text {
                        id: hintLabel
                        anchors.centerIn: parent
                        text:"↓  Page Down · End"
                        color:root.colors.gold;font.pixelSize:11
                    }
                }

                Flickable {
                    id:optionsScroll
                    objectName:"optionsScroll"
                    visible:root.section==="options"
                    anchors.fill:parent
                    anchors.bottomMargin:8
                    contentWidth:Math.max(40,width-14)
                    contentHeight:optionsColumn.implicitHeight+12
                    boundsBehavior:Flickable.StopAtBounds
                    clip:true
                    onHeightChanged:Qt.callLater(root.revealFocusedOption)
                    Keys.onTabPressed:function(event){
                        if(optionsScroll.activeFocus)pinOption.forceActiveFocus();
                        else event.accepted=false;
                    }
                    Keys.onBacktabPressed:function(event){
                        if(optionsScroll.activeFocus)optionsButton.forceActiveFocus();
                        else event.accepted=false;
                    }
                    Column {
                        id:optionsColumn
                        width:Math.min(740,optionsScroll.contentWidth)
                        x:(optionsScroll.contentWidth-width)/2
                        spacing:18
                        onPositioningComplete:Qt.callLater(root.revealFocusedOption)
                        Column {
                            width:parent.width;spacing:7
                            Text { text:"Make yourself at home";font.family:"serif";font.pixelSize:root.compact?24:29;color:root.colors.ink }
                            Text { width:parent.width;wrapMode:Text.WordWrap;text:"A place on your desktop, a little quiet, or just the art.";font.pixelSize:12;color:root.colors.muted }
                        }
                        Column {
                            width:parent.width;spacing:10
                            OptionHeading { text:"ON YOUR DESKTOP" }
                            Flow {
                                width:parent.width;spacing:8
                                OptionButton {
                                    id:pinOption
                                    objectName:"pinOption"
                                    text:root.ambient?"Unpin from desktop":"Pin to desktop"
                                    selected:root.ambient
                                    hint:"Toggle the live desktop garden (A)"
                                    onClicked:root.ambientRequested()
                                }
                                OptionButton {
                                    objectName:"artOption"
                                    text:"Enjoy the art"
                                    hint:"Expand the garden and hide its readings (F)"
                                    onClicked:root.showSection("art")
                                }
                                OptionButton {
                                    objectName:"postcardOption"
                                    visible:root.postcardAvailable
                                    text:"Make a postcard"
                                    hint:"Preview and save a postcard (Ctrl+S)"
                                    onClicked:root.requestPostcard()
                                }
                            }
                            Text {
                                width:parent.width;wrapMode:Text.WordWrap;lineHeight:1.35
                                text:"The pinned garden sits behind your windows. Clicks pass through it, and it never takes keyboard focus."
                                font.pixelSize:12;color:root.colors.muted
                            }
                        }
                        Column {
                            width:parent.width;spacing:8
                            Text { text:"Display";font.pixelSize:13;color:root.colors.ink }
                            OptionChoice {
                                objectName:"display-automatic"
                                width:parent.width
                                text:"Automatic"
                                detail:root.displayChoices.length?"First available display":"Waiting for a connected display"
                                selected:root.ambientDisplay===""
                                onClicked:root.placementRequested("ambientDisplay","")
                            }
                            Repeater {
                                model:root.displayChoices
                                OptionChoice {
                                    required property var modelData
                                    required property int index
                                    objectName:"display-"+index
                                    width:optionsColumn.width
                                    text:modelData.label
                                    detail:modelData.label===modelData.name?"":modelData.name
                                    selected:root.ambientDisplay===modelData.name
                                    onClicked:root.placementRequested("ambientDisplay",modelData.name)
                                }
                            }
                            Text {
                                objectName:"displayFallbackNotice"
                                visible:root.displayMissing
                                width:parent.width
                                text:root.displayChoices.length
                                    ? "Saved display "+root.ambientDisplay+" is disconnected. The first available display is used until it returns."
                                    : "Saved display "+root.ambientDisplay+" is disconnected. The pinned garden will return when a display is available."
                                textFormat:Text.PlainText;wrapMode:Text.WrapAnywhere;lineHeight:1.35
                                font.pixelSize:12;color:root.colors.gold
                            }
                        }
                        Column {
                            width:parent.width;spacing:8
                            Text { text:"Corner";font.pixelSize:13;color:root.colors.ink }
                            Flow {
                                width:parent.width;spacing:8
                                Repeater {
                                    model:[{value:"top-left",label:"Top left"},{value:"top-right",label:"Top right"},{value:"bottom-left",label:"Bottom left"},{value:"bottom-right",label:"Bottom right"}]
                                    OptionButton {
                                        required property var modelData
                                        objectName:"corner-"+modelData.value
                                        text:modelData.label
                                        selected:root.ambientCorner===modelData.value
                                        hint:"Place the garden in the "+modelData.label.toLowerCase()+" corner"
                                        onClicked:root.placementRequested("ambientCorner",modelData.value)
                                    }
                                }
                            }
                        }
                        Column {
                            width:parent.width;spacing:8
                            Text { text:"Size";font.pixelSize:13;color:root.colors.ink }
                            Flow {
                                width:parent.width;spacing:8
                                Repeater {
                                    model:[{value:"small",label:"Small"},{value:"medium",label:"Medium"},{value:"large",label:"Large"}]
                                    OptionButton {
                                        required property var modelData
                                        objectName:"size-"+modelData.value
                                        text:modelData.label
                                        selected:root.ambientSize===modelData.value
                                        hint:modelData.label+" desktop garden"
                                        onClicked:root.placementRequested("ambientSize",modelData.value)
                                    }
                                }
                            }
                            Text { width:parent.width;wrapMode:Text.WordWrap;text:"Every size stays inside the available display area.";font.pixelSize:12;color:root.colors.muted }
                        }
                        Rectangle { width:parent.width;height:1;color:root.colors.line }
                        Column {
                            width:parent.width;spacing:10
                            OptionHeading { text:"COLOR, MOTION & CURIOSITY" }
                            Flow {
                                width:parent.width;spacing:8
                                OptionButton { objectName:"paletteOption";text:"Palette: "+root.paletteName;hint:"Change palette (C)";onClicked:root.paletteRequested() }
                                OptionButton { objectName:"motionOption";text:root.motionPaused || root.reducedMotion?"Resume motion":"Pause motion";selected:root.motionPaused || root.reducedMotion;hint:"Toggle motion (P)";onClicked:root.motionRequested() }
                                OptionButton { objectName:"demoOption";text:root.demo?"Return to live":"Explore demo";selected:root.demo;hint:"Toggle demonstration (D)";onClicked:root.demoRequested() }
                            }
                            Text {
                                width:parent.width;wrapMode:Text.WordWrap;lineHeight:1.35
                                text:"Auto follows the time of day. Pausing motion keeps the garden still while readings continue. The demonstration uses invented applications and activity."
                                font.pixelSize:12;color:root.colors.muted
                            }
                            Text {
                                visible:root.ambient && root.demo
                                width:parent.width;wrapMode:Text.WordWrap;lineHeight:1.35
                                text:"Your desktop garden stays live while you explore the demonstration here."
                                font.pixelSize:12;color:root.colors.gold
                            }
                        }
                    }
                }
                Rectangle {
                    objectName:"optionsScrollTrack"
                    visible:root.section==="options" && optionsScroll.contentHeight>optionsScroll.height+2
                    anchors.right:parent.right;anchors.rightMargin:2
                    anchors.top:parent.top;anchors.bottom:parent.bottom;anchors.bottomMargin:8
                    width:5;radius:2;color:root.colors.line
                    Rectangle {
                        width:parent.width;radius:2;color:root.colors.gold
                        height:Math.max(18,parent.height*Math.min(1,optionsScroll.height/Math.max(1,optionsScroll.contentHeight)))
                        y:(parent.height-height)*optionsScroll.contentY/Math.max(1,optionsScroll.contentHeight-optionsScroll.height)
                    }
                }

                Item {
                    id:postcardPane
                    objectName:"postcardPane"
                    visible:root.postcardMode
                    anchors.fill:parent
                    Keys.onTabPressed:function(event){
                        if(postcardPane.activeFocus) {
                            if(postcardSave.enabled)postcardSave.forceActiveFocus();
                            else if(postcardRefresh.enabled)postcardRefresh.forceActiveFocus();
                            else postcardBack.forceActiveFocus();
                        } else event.accepted=false;
                    }
                    Column {
                        id:postcardHeading
                        width:parent.width;spacing:6
                        Text { text:"A moment to keep";font.family:"serif";font.pixelSize:root.compact?23:29;color:root.colors.ink }
                        Text {
                            objectName:"postcardSource"
                            text:root.postcardSource;textFormat:Text.PlainText
                            font.pixelSize:10;font.letterSpacing:1.1;color:root.colors.gold
                        }
                        Text {
                            width:parent.width;wrapMode:Text.WordWrap
                            text:"Only the art is saved. Application names and numeric readings stay out."
                            font.pixelSize:12;color:root.colors.muted
                        }
                    }
                    Item {
                        id:postcardWell
                        objectName:"postcardWell"
                        width:parent.width
                        anchors.top:postcardHeading.bottom;anchors.topMargin:12
                        anchors.bottom:postcardActions.top;anchors.bottomMargin:12
                        Rectangle {
                            anchors.centerIn:parent
                            width:postcardLoader.width+2;height:postcardLoader.height+2
                            color:root.colors.panel;border.color:root.colors.line
                        }
                        Loader {
                            id:postcardLoader
                            objectName:"postcardLoader"
                            // Unload only through discardPostcard(), after cancellation.
                            active:root.postcardLoaded
                            anchors.centerIn:parent
                            width:Math.max(1,Math.min(parent.width,parent.height*18/11))
                            height:width*11/18
                            sourceComponent:Component {
                                Postcard { card:root.postcardSnapshot }
                            }
                        }
                        Text {
                            visible:postcardLoader.status===Loader.Error
                            anchors.centerIn:parent
                            width:parent.width;wrapMode:Text.WordWrap;horizontalAlignment:Text.AlignHCenter
                            text:"The postcard preview could not be loaded. Return to the garden and try again."
                            font.pixelSize:12;color:root.colors.flower
                        }
                    }
                    Column {
                        id:postcardActions
                        objectName:"postcardActions"
                        width:parent.width
                        anchors.bottom:parent.bottom
                        spacing:8
                        Flow {
                            width:parent.width;spacing:8
                            Control {
                                id:postcardSave
                                objectName:"postcardSave"
                                text:root.postcardSaving?"Saving…":root.postcardReady?"Save PNG":"Preparing…"
                                enabled:root.postcardReady && !root.postcardSaving && root.active
                                opacity:enabled?1:.5
                                hintAbove:true;hint:"Save this postcard on your computer (Ctrl+S)"
                                onClicked:root.savePostcard()
                            }
                            Control {
                                id:postcardRefresh
                                objectName:"postcardRefresh"
                                text:"Refresh snapshot"
                                enabled:!root.postcardSaving && root.active
                                opacity:enabled?1:.5
                                hintAbove:true;hint:"Take a new snapshot of the current garden"
                                onClicked:root.refreshPostcard()
                            }
                            Control {
                                id:postcardBack
                                objectName:"postcardBack"
                                text:root.postcardSaving?"Cancel & back":"Back"
                                hintAbove:true;hint:"Return from the postcard preview (Escape)"
                                onClicked:root.leavePostcard()
                            }
                        }
                        Text {
                            objectName:"postcardExportStatus"
                            width:parent.width
                            text:root.exportStatus.length?root.exportStatus:root.postcardSaving?"Saving your postcard…":"High-resolution PNG · saves to this computer"
                            textFormat:Text.PlainText;wrapMode:Text.WordWrap;maximumLineCount:2;elide:Text.ElideRight
                            font.pixelSize:12;color:root.colors.muted
                        }
                        Item {
                            visible:root.exportPath.length>0
                            width:parent.width
                            height:visible?postcardCopyPath.height:0
                            Text {
                                objectName:"postcardExportPath"
                                anchors.left:parent.left;anchors.right:postcardCopyPath.left;anchors.rightMargin:10
                                anchors.verticalCenter:parent.verticalCenter
                                text:root.exportPath;textFormat:Text.PlainText;elide:Text.ElideMiddle
                                font.family:"monospace";font.pixelSize:11;color:root.colors.gold
                                Accessible.role:Accessible.StaticText
                                Accessible.name:"Saved location: "+root.exportPath
                            }
                            Control {
                                id:postcardCopyPath
                                objectName:"postcardCopyPath"
                                anchors.right:parent.right
                                width:96
                                text:root.postcardPathCopied?"Copied":"Copy path"
                                hintAbove:true
                                hint:root.postcardPathCopied?"Full path copied":"Copy the complete saved path"
                                Accessible.description:root.exportPath
                                onClicked:root.copyPostcardPath()
                            }
                        }
                    }
                }
            }

            Item {
                id: readings
                objectName:"readings"
                visible:!root.artMode && root.section!=="options" && !root.postcardMode
                width: parent.width
                height: visible ? root.readingsHeight : 0
                anchors.bottom: parent.bottom
                Row {
                    visible: !root.compact
                    width: parent.width
                    spacing: 10
                    height: 83
                    Reading {
                        width:(parent.width-20)/3
                        heading:"LANTERNS";value:Model.formatPercent(root.snapshot.cpu);detail:"CPU activity"
                        points:root.atmosphere.activity
                        accessibleName:"Lanterns CPU activity "+Model.formatPercent(root.snapshot.cpu)
                    }
                    Reading {
                        width:(parent.width-20)/3
                        heading:"THE POND";value:Model.formatPercent(root.snapshot.memory.percent)
                        detail:root.snapshot.memory.percent===null?"Memory unavailable":Model.formatBytes(root.snapshot.memory.usedBytes)+" memory";points:root.atmosphere.water
                        accessibleName:"Pond memory "+(root.snapshot.memory.percent===null?"unavailable":Model.formatPercent(root.snapshot.memory.percent)+" "+Model.formatBytes(root.snapshot.memory.usedBytes))
                    }
                    Reading {
                        width:(parent.width-20)/3
                        heading:"PASSING RAIN";value:Model.formatRate(root.snapshot.network.rxBytesPerSec)
                        detail:"↑ "+Model.formatRate(root.snapshot.network.txBytesPerSec);points:root.atmosphere.rain
                        accessibleName:"Passing rain received "+Model.formatRate(root.snapshot.network.rxBytesPerSec)+" sent "+Model.formatRate(root.snapshot.network.txBytesPerSec)
                    }
                }
                Row {
                    objectName: "compactReadings"
                    visible: root.compact
                    width: parent.width
                    height: 28
                    spacing: 10
                    StripReading {
                        width: Math.max(0, (parent.width-20)/3)
                        heading: "Lanterns"
                        value: Model.formatPercent(root.snapshot.cpu)
                        detail: "CPU"
                        points: root.atmosphere.activity
                        accessibleName: "Lanterns CPU activity "+Model.formatPercent(root.snapshot.cpu)
                    }
                    StripReading {
                        width: Math.max(0, (parent.width-20)/3)
                        heading: "Pond"
                        value: Model.formatPercent(root.snapshot.memory.percent)
                        detail: root.snapshot.memory.percent===null ? "unavailable" : Model.formatBytes(root.snapshot.memory.usedBytes)
                        points: root.atmosphere.water
                        accessibleName: "Pond memory "+(root.snapshot.memory.percent===null?"unavailable":Model.formatPercent(root.snapshot.memory.percent)+" "+Model.formatBytes(root.snapshot.memory.usedBytes))
                    }
                    StripReading {
                        width: Math.max(0, (parent.width-20)/3)
                        heading: "Rain"
                        value: Model.formatRate(root.snapshot.network.rxBytesPerSec)
                        detail: "↑ "+Model.formatRate(root.snapshot.network.txBytesPerSec)
                        points: root.atmosphere.rain
                        accessibleName: "Passing rain received "+Model.formatRate(root.snapshot.network.rxBytesPerSec)+" sent "+Model.formatRate(root.snapshot.network.txBytesPerSec)
                    }
                }
            }
        }

        Column {
            id:sidebar;objectName:"residentSidebar";visible:!root.compact && !root.artMode && root.section!=="options" && !root.postcardMode;width:252;height:body.height;spacing:13
            Row {
                id:gardenCount
                width:parent.width
                Text { width:parent.width-45;text:"IN THE GARDEN";font.pixelSize:10;font.letterSpacing:1.6;color:root.colors.muted }
                Text { width:45;text:String(root.garden.residents.length).padStart(2,"0");horizontalAlignment:Text.AlignRight;font.family:"monospace";font.pixelSize:11;color:root.colors.gold }
            }
            Text {
                id:speciesLabel
                width:parent.width;text:root.selected?Model.speciesNames[root.selected.category]:"Every process leaves a little trace."
                font.family:"serif";font.pixelSize:21;color:root.colors.ink;wrapMode:Text.WordWrap
            }
            Flickable {
                id:residentScroll;objectName:"residentScroll"
                width:parent.width
                height:Math.min(contentHeight,Math.max(88,sidebar.height-gardenCount.implicitHeight-speciesLabel.implicitHeight-specimenNotes.implicitHeight-1-sidebar.spacing*4))
                contentWidth:width;contentHeight:residentList.implicitHeight
                clip:true;boundsBehavior:Flickable.StopAtBounds
                onHeightChanged:Qt.callLater(residentList.revealSelection)
                Column {
                    id:residentList;width:parent.width;spacing:3
                    function revealSelection(){
                        for(var i=0;i<children.length;i++)
                            if(children[i].objectName.indexOf("resident-")===0 && children[i].selected)
                                root.revealResident(children[i]);
                    }
                    onPositioningComplete:revealSelection()
                Repeater {
                    model:root.garden.residents
                    Rectangle {
                        id:residentRow
                        required property var modelData
                        readonly property bool selected:root.selectedKey===modelData.key
                        objectName:"resident-"+modelData.key
                        width:sidebar.width;height:44;radius:5
                        color:selected || residentMouse.containsMouse || activeFocus?root.colors.surface:"transparent"
                        border.color:activeFocus?root.colors.gold:root.colors.line;border.width:selected||activeFocus?1:0
                        activeFocusOnTab:true
                        onActiveFocusChanged:if(activeFocus)root.revealResident(residentRow)
                        onSelectedChanged:if(selected)Qt.callLater(function(){root.revealResident(residentRow);})
                        Accessible.role:Accessible.Button;Accessible.name:"Inspect "+modelData.name
                        Accessible.onPressAction:root.selectedKey=modelData.key
                        Keys.onReturnPressed:root.selectedKey=modelData.key
                        Keys.onEnterPressed:root.selectedKey=modelData.key
                        Keys.onSpacePressed:root.selectedKey=modelData.key
                        Row {
                            x:9;anchors.verticalCenter:parent.verticalCenter;spacing:10
                            Rectangle {
                                width:5;height:5;radius:3;anchors.verticalCenter:parent.verticalCenter
                                color:modelData.missing>0 || modelData.unavailable?root.colors.muted:root.colors.leaf
                            }
                            Column {
                                width:144;spacing:3
                                Text { width:parent.width;text:modelData.name;textFormat:Text.PlainText;elide:Text.ElideRight;font.pixelSize:12;color:root.colors.ink }
                                Text { text:Model.speciesNames[modelData.category];font.pixelSize:10;color:root.colors.muted }
                            }
                            Text { width:58;anchors.verticalCenter:parent.verticalCenter;text:Model.formatBytes(modelData.memoryBytes);font.pixelSize:10;horizontalAlignment:Text.AlignRight;color:root.colors.muted }
                        }
                        MouseArea { id:residentMouse;anchors.fill:parent;hoverEnabled:true;cursorShape:Qt.PointingHandCursor;onClicked:root.selectedKey=modelData.key }
                    }
                }
                }
                Rectangle {
                    parent:residentScroll.contentItem
                    visible:residentScroll.contentHeight>residentScroll.height+1
                    x:residentScroll.width-3;y:residentScroll.contentY+(residentScroll.height-height)*residentScroll.contentY/Math.max(1,residentScroll.contentHeight-residentScroll.height)
                    width:3;height:Math.max(18,residentScroll.height*residentScroll.height/Math.max(1,residentScroll.contentHeight))
                    radius:2;color:root.colors.gold;opacity:0.6
                }
            }
            Rectangle { width:parent.width;height:1;color:root.colors.line }
            Column {
                id:specimenNotes;objectName:"specimenNotes"
                width:parent.width;spacing:8
                Text {
                    text:root.selected?"SPECIMEN NOTES":"A MOMENT HERE"
                    color:root.colors.gold;font.pixelSize:10;font.letterSpacing:1.5
                }
                Text {
                    objectName:"specimenBody"
                    width:parent.width
                    text:root.selected?
                        root.selected.unavailable ? "Application readings unavailable.\nHeld in place until observations return." :
                        Model.formatPercent(root.selected.cpu)+" CPU · "+root.selected.count+" process"+(root.selected.count===1?"":"es")+"\nObserved "+Model.duration(root.selected.age)+(root.selected.missing>0?" · outside the current sample":""):
                        Model.narrative(root.snapshot)
                    textFormat:Text.PlainText;wrapMode:Text.WordWrap;color:root.colors.muted;font.pixelSize:12;lineHeight:1.45
                }
                Text {
                    objectName:"processSummary"
                    text:root.snapshot.processCount+" processes"+(root.snapshot.uptimeSeconds>0?" · uptime "+Model.duration(root.snapshot.uptimeSeconds):"")
                    visible:!root.selected && root.snapshot.timestamp>0 && root.snapshot.processesAvailable!==false
                    color:root.colors.muted;font.pixelSize:10
                }
            }
        }
    }

    TextEdit {
        id:postcardPathClipboard
        visible:false;readOnly:true;activeFocusOnTab:false
        text:root.exportPath;textFormat:TextEdit.PlainText
        Accessible.ignored:true
    }
    Rectangle { visible:!root.artMode && !root.postcardMode;x:24;y:parent.height-root.footerBand;width:parent.width-48;height:1;color:root.colors.line }
    Row {
        visible:!root.artMode && root.section!=="options" && !root.postcardMode
        x:24;anchors.bottom:parent.bottom;anchors.bottomMargin:root.compact?4:7;spacing:6
        Control { text:root.motionPaused || root.reducedMotion?"Motion paused":"Pause motion";quiet:true;hintAbove:true;onClicked:root.motionRequested();hint:"Toggle motion (P)" }
        Control { text:root.paletteName==="auto"?"Palette: auto":"Palette: "+root.paletteName;quiet:true;hintAbove:true;onClicked:root.paletteRequested();hint:"Change palette (C)" }
        Control { objectName:"artButton";text:"Enjoy the art";quiet:true;hintAbove:true;onClicked:root.showSection("art");hint:"Expand the garden and hide its readings (F)" }
    }
    Control {
        visible:root.section==="options"
        x:24;anchors.bottom:parent.bottom;anchors.bottomMargin:root.compact?4:7
        text:"Back to garden";quiet:true;hintAbove:true;hint:"Return to the garden (G or Escape)"
        onClicked:root.showSection("garden")
    }
    Text {
        visible:!root.artMode && !root.postcardMode && (root.width>1040 || (root.ambient && root.section!=="options"))
        anchors.right:parent.right;anchors.rightMargin:28;anchors.bottom:parent.bottom;anchors.bottomMargin:18
        text:root.section==="options"?"PAGE UP / DOWN TO SCROLL":root.ambient?(root.tight?"PINNED · A TO UNPIN":"PINNED TO YOUR DESKTOP"):"LOCAL BY NATURE";font.pixelSize:9;font.letterSpacing:1.6;color:root.colors.muted
    }
    Control {
        id:artBack
        objectName:"artBack"
        visible:root.artMode
        x:20;y:20
        text:"‹ Back"
        Accessible.name:"Return from art mode (F or Escape)"
        onClicked:root.leaveArt()
    }
    Control {
        id:artPostcard
        objectName:"artPostcard"
        visible:root.artMode && root.postcardAvailable
        x:artBack.x+artBack.width+8;y:20
        text:"Postcard";hint:"Preview and save a postcard (Ctrl+S)"
        onClicked:root.requestPostcard()
    }
    Text {
        objectName:"artStatus"
        visible:root.artMode && (root.demo || root.stale || !root.snapshot.timestamp)
        anchors.right:parent.right;anchors.rightMargin:24;y:32
        width:Math.max(0,root.width-(artPostcard.visible?artPostcard.x+artPostcard.width:artBack.x+artBack.width)-56)
        horizontalAlignment:Text.AlignRight;elide:Text.ElideRight
        text:root.habitatBadge;font.pixelSize:10;font.letterSpacing:1.2;color:root.habitatDot
    }
    Text {
        visible:root.artMode
        anchors.horizontalCenter:parent.horizontalCenter;anchors.bottom:parent.bottom;anchors.bottomMargin:17
        text:"Touch a plant · F or Esc to return";font.pixelSize:11;color:root.colors.muted
    }
    Item { id:hintOverlay;anchors.fill:parent;z:100 }

    component Control: TerrariumControl {
        hintLayer:hintOverlay
        ink:root.colors.ink;muted:root.colors.muted;surface:root.colors.surface;line:root.colors.line;accent:root.colors.gold
    }
    component OptionButton: Control {
        id:optionButton
        onActiveFocusChanged:if(activeFocus)root.revealOption(optionButton)
    }
    component OptionHeading: Text {
        color:root.colors.gold;font.pixelSize:10;font.letterSpacing:1.4
    }
    component OptionChoice: Rectangle {
        id:choice
        property string text:""
        property string detail:""
        property bool selected:false
        signal clicked()
        implicitHeight:detail.length?58:40
        radius:6
        color:choice.selected || choiceMouse.containsMouse || choice.activeFocus?root.colors.surface:"transparent"
        border.color:choice.activeFocus?root.colors.gold:root.colors.line
        activeFocusOnTab:true
        Accessible.role:Accessible.Button
        Accessible.name:(choice.selected?"Selected display: ":"Use display: ")+choice.text+(choice.detail.length?", "+choice.detail:"")
        Accessible.onPressAction:choice.clicked()
        Keys.onReturnPressed:choice.clicked()
        Keys.onEnterPressed:choice.clicked()
        Keys.onSpacePressed:choice.clicked()
        onActiveFocusChanged:if(activeFocus)root.revealOption(choice)
        Rectangle {
            x:13;anchors.verticalCenter:parent.verticalCenter
            width:11;height:11;radius:6;color:"transparent"
            border.color:choice.selected?root.colors.gold:root.colors.muted
            Rectangle { visible:choice.selected;anchors.centerIn:parent;width:5;height:5;radius:3;color:root.colors.gold }
        }
        Column {
            x:36;anchors.verticalCenter:parent.verticalCenter;width:parent.width-49;spacing:5
            Text { width:parent.width;text:choice.text;textFormat:Text.PlainText;elide:Text.ElideRight;font.pixelSize:12;color:root.colors.ink }
            Text { visible:choice.detail.length>0;width:parent.width;text:choice.detail;textFormat:Text.PlainText;elide:Text.ElideRight;font.pixelSize:11;color:root.colors.muted }
        }
        MouseArea { id:choiceMouse;anchors.fill:parent;hoverEnabled:true;cursorShape:Qt.PointingHandCursor;onClicked:choice.clicked() }
    }
    component Reading: Rectangle {
        property string heading:""
        property string value:""
        property string detail:""
        property real points:0
        property string accessibleName:""
        height:83;radius:7;color:root.colors.panel;border.color:root.colors.line
        Accessible.role: Accessible.StaticText
        Accessible.name: accessibleName.length ? accessibleName : heading+" "+value+" "+detail
        Text { x:12;y:11;text:parent.heading;color:root.colors.muted;font.pixelSize:9;font.letterSpacing:1.2 }
        Text { x:12;y:27;text:parent.value;color:root.colors.ink;font.pixelSize:22;font.family:"serif" }
        Text { x:12;y:58;text:parent.detail;color:root.colors.muted;font.pixelSize:10 }
        Rectangle { anchors.right:parent.right;anchors.rightMargin:12;y:32;width:3;height:30;radius:2;color:root.colors.line
            Rectangle { anchors.bottom:parent.bottom;width:3;height:Math.max(2,parent.height*parent.parent.points);radius:2;color:root.colors.gold }
        }
    }
    component StripReading: Item {
        property string heading:""
        property string value:""
        property string detail:""
        property real points:0
        property string accessibleName:""
        height:28
        Accessible.role: Accessible.StaticText
        Accessible.name: accessibleName.length ? accessibleName : heading+" "+value+" "+detail
        Column {
            anchors.left: parent.left
            anchors.right: tick.left
            anchors.rightMargin: 6
            anchors.verticalCenter: parent.verticalCenter
            spacing: 1
            Text {
                width: parent.width
                text: heading+"  "+value
                elide: Text.ElideRight
                textFormat: Text.PlainText
                color: root.colors.ink
                font.pixelSize: 12
            }
            Text {
                width: parent.width
                text: detail
                elide: Text.ElideRight
                textFormat: Text.PlainText
                color: root.colors.muted
                font.pixelSize: 10
            }
        }
        Rectangle {
            id: tick
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: 3; height: 18; radius: 2; color: root.colors.line
            Rectangle { anchors.bottom: parent.bottom; width: 3; height: Math.max(2, parent.height * parent.parent.points); radius: 2; color: root.colors.gold }
        }
    }
}
