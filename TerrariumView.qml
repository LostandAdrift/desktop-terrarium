pragma ComponentBehavior: Bound
import QtQuick
import "Model.js" as Model

FocusScope {
    id: root
    property var snapshot: Model.emptySnapshot()
    property var garden: Model.newGarden()
    property string paletteName: "auto"
    property int hour: new Date().getHours()
    property bool motionPaused: false
    property bool reducedMotion: false
    property bool demo: false
    property bool ambient: false
    property bool active: true
    property string status: "Connecting to your desktop…"
    property bool stale: false
    property string section: "garden"
    property string selectedKey: ""
    readonly property bool compact: width < 850 || height < 640
    readonly property bool tight: width < 700
    readonly property int headerBand: compact ? (tight ? 46 : 62) : 92
    readonly property int footerBand: compact ? 34 : 45
    readonly property int bodyY: compact ? (tight ? 54 : 70) : 111
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
        var target=section==="guide"?guideScroll:section==="journal"?journalScroll:null;
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
    Component.onCompleted: syncSelection()
    Keys.onPressed: function(event) {
        if(event.key===Qt.Key_Escape) { if(section!=="garden")section="garden";else root.closeRequested(); }
        else if(event.key===Qt.Key_G) section="garden";
        else if(event.key===Qt.Key_J) section="journal";
        else if(event.key===Qt.Key_H || event.key===Qt.Key_Question) section="guide";
        else if(event.key===Qt.Key_P) root.motionRequested();
        else if(event.key===Qt.Key_D) root.demoRequested();
        else if(event.key===Qt.Key_C) root.paletteRequested();
        else if(event.key===Qt.Key_A) root.ambientRequested();
        else if(root.scrollSection(event.key)) {}
        else if(event.key===Qt.Key_Right || event.key===Qt.Key_Down) root.moveSelection(1);
        else if(event.key===Qt.Key_Left || event.key===Qt.Key_Up) root.moveSelection(-1);
        else return;
        event.accepted=true;
    }

    Rectangle { anchors.fill:parent;color:root.colors.bg;radius:12;border.color:root.colors.line;border.width:1 }
    Rectangle { x:1;y:1;width:parent.width-2;height:root.headerBand;radius:12;color:root.colors.panel }
    Rectangle { x:1;y:root.headerBand-20;width:parent.width-2;height:21;color:root.colors.panel }
    Rectangle { x:24;y:root.headerBand;width:parent.width-48;height:1;color:root.colors.line }

    Column {
        id: titleBlock
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
        objectName:"navRow"
        anchors.right:parent.right;anchors.rightMargin:24;y:root.compact?(root.tight?8:16):31;spacing:6
        Control { text:root.compact?"G":"Garden";selected:root.section==="garden";onClicked:root.section="garden";hint:"Garden (G)" }
        Control { text:root.compact?"J":"Journal";selected:root.section==="journal";onClicked:root.section="journal";hint:"Observation journal (J)" }
        Control { objectName:"guideButton";text:"?";selected:root.section==="guide";onClicked:root.section=root.section==="guide"?"garden":"guide";hint:"Field guide (H)" }
        Control { objectName:"closeButton";text:"×";onClicked:root.closeRequested();hint:"Close terrarium (Escape)" }
    }

    Row {
        id:body;x:24;y:root.bodyY;width:parent.width-48;height:root.height-root.bodyY-root.footerBand-(root.compact?4:13);spacing:24
        Item {
            id: mainArea
            width: body.width-(root.compact?0:276)
            height:body.height

            Item {
                id: habitatBand
                width: parent.width
                height: root.compact && root.section==="garden" && root.selected!==null ? 38 : 18
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
                    text: root.selected ? root.selected.name+" · "+Model.speciesNames[root.selected.category]+" · "+Model.formatPercent(root.selected.cpu)+" CPU · "+Model.formatBytes(root.selected.memoryBytes) : ""
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
                anchors.topMargin: 6
                anchors.bottomMargin: root.compact ? 6 : 18

                GardenScene {
                    id:scene
                    objectName:"gardenScene"
                    anchors.fill:parent
                    visible:root.section==="garden" || root.section==="journal"
                    opacity:root.section==="journal" ? 0.55 : 1
                    enabled:root.section==="garden"
                    fitVessel:root.compact
                    palette:root.colors;residents:root.garden.residents;weather:root.atmosphere
                    animate:root.active && root.section==="garden" && !root.motionPaused && !root.reducedMotion && !root.stale
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
                        Text { width:parent.width;wrapMode:Text.WordWrap;lineHeight:1.35;color:root.colors.muted;font.pixelSize:12;text:"G garden · J journal · H or ? guide · arrows inspect plants · Page Up/Down scroll · P pause · C palette · D demo · A pin to desktop · Esc close." }
                        Repeater {
                            model:[
                                {name:"Plants · applications",body:"A few of your busiest process groups take root. They keep their places as activity changes, and grow while observed. Select a plant to see its actual usage."},
                                {name:"Lantern light · CPU",body:"More activity brings more drifting lights. The number below is your computer’s aggregate CPU usage, not a forecast."},
                                {name:"Rain · network",body:"Received network traffic brings a passing shower. Upload traffic appears in the reading below. This is your network, not the weather outside."},
                                {name:"The pond · memory",body:"The water reflects memory in use. Your garden stays healthy at every level; it does not need feeding or attention."},
                                {name:"Time & quiet",body:"Auto follows the local time of day. Press C to choose a palette, P to pause motion, or D to explore a clearly labeled demonstration."}
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
            }

            Item {
                id: readings
                width: parent.width
                height: root.readingsHeight
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
            id:sidebar;visible:!root.compact;width:252;height:body.height;spacing:13
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
                                color:modelData.missing>0?root.colors.muted:root.colors.leaf
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
                    width:parent.width
                    text:root.selected?
                        Model.formatPercent(root.selected.cpu)+" CPU · "+root.selected.count+" process"+(root.selected.count===1?"":"es")+"\nObserved "+Model.duration(root.selected.age)+(root.selected.missing>0?" · outside the current sample":""):
                        Model.narrative(root.snapshot)
                    textFormat:Text.PlainText;wrapMode:Text.WordWrap;color:root.colors.muted;font.pixelSize:12;lineHeight:1.45
                }
                Text { text:root.snapshot.processCount+" processes · uptime "+Model.duration(root.snapshot.uptimeSeconds);visible:!root.selected && root.snapshot.timestamp>0;color:root.colors.muted;font.pixelSize:10 }
            }
        }
    }
    Rectangle { x:24;y:parent.height-root.footerBand;width:parent.width-48;height:1;color:root.colors.line }
    Row {
        x:24;anchors.bottom:parent.bottom;anchors.bottomMargin:root.compact?4:7;spacing:6
        Control { text:root.motionPaused || root.reducedMotion?"Motion paused":"Pause motion";quiet:true;hintAbove:true;onClicked:root.motionRequested();hint:"Toggle motion (P)" }
        Control { text:root.paletteName==="auto"?"Palette: auto":"Palette: "+root.paletteName;quiet:true;hintAbove:true;onClicked:root.paletteRequested();hint:"Change palette (C)" }
        Control { text:root.demo?"Return to live":"Explore demo";quiet:true;selected:root.demo;hintAbove:true;onClicked:root.demoRequested();hint:"Toggle demonstration (D)" }
        Control { text:root.ambient?"On desktop":"Pin to desktop";quiet:true;selected:root.ambient;hintAbove:true;onClicked:root.ambientRequested();hint:"Pin to desktop (A)" }
    }
    Text {
        visible:root.width>1040
        anchors.right:parent.right;anchors.rightMargin:28;anchors.bottom:parent.bottom;anchors.bottomMargin:18
        text:"LOCAL BY NATURE";font.pixelSize:9;font.letterSpacing:1.6;color:root.colors.muted
    }
    Item { id:hintOverlay;anchors.fill:parent;z:100 }

    component Control: TerrariumControl {
        hintLayer:hintOverlay
        ink:root.colors.ink;muted:root.colors.muted;surface:root.colors.surface;line:root.colors.line;accent:root.colors.gold
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
