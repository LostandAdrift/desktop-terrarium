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
    readonly property var colors: Model.palette(paletteName, hour)
    readonly property var atmosphere: Model.weather(snapshot)
    readonly property var selected: {
        for (var i=0;i<garden.residents.length;i++) if (garden.residents[i].key===selectedKey) return garden.residents[i];
        return null;
    }
    signal closeRequested()
    signal demoRequested()
    signal motionRequested()
    signal paletteRequested()
    signal retryRequested()
    signal ambientRequested()

    function moveSelection(direction) {
        if (!garden.residents.length) return;
        var index = -1;
        for (var i=0;i<garden.residents.length;i++) if(garden.residents[i].key===selectedKey) index=i;
        index=index<0?(direction>0?0:garden.residents.length-1):(index+direction+garden.residents.length)%garden.residents.length;
        selectedKey=garden.residents[index].key;
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
    Keys.onPressed: function(event) {
        if(event.key===Qt.Key_Escape) { if(section!=="garden")section="garden";else root.closeRequested(); }
        else if(event.key===Qt.Key_G) section="garden";
        else if(event.key===Qt.Key_J) section="journal";
        else if(event.key===Qt.Key_H || event.key===Qt.Key_Question) section="guide";
        else if(event.key===Qt.Key_P) root.motionRequested();
        else if(event.key===Qt.Key_D) root.demoRequested();
        else if(event.key===Qt.Key_C) root.paletteRequested();
        else if(root.scrollSection(event.key)) {}
        else if(event.key===Qt.Key_Right || event.key===Qt.Key_Down) root.moveSelection(1);
        else if(event.key===Qt.Key_Left || event.key===Qt.Key_Up) root.moveSelection(-1);
        else return;
        event.accepted=true;
    }

    Rectangle { anchors.fill:parent;color:root.colors.bg;radius:12;border.color:root.colors.line;border.width:1 }
    Rectangle { x:1;y:1;width:parent.width-2;height:92;radius:12;color:root.colors.panel }
    Rectangle { x:1;y:72;width:parent.width-2;height:21;color:root.colors.panel }
    Rectangle { x:24;y:92;width:parent.width-48;height:1;color:root.colors.line }

    Column {
        x:28;y:20;spacing:4
        Text { text:"TERRARIUM / NO. 001";font.pixelSize:10;font.letterSpacing:2;color:root.colors.gold }
        Text { text:"A little world of your own.";font.family:"serif";font.pixelSize:root.compact?23:29;color:root.colors.ink }
    }
    Row {
        anchors.right:parent.right;anchors.rightMargin:24;y:31;spacing:6
        Control { text:root.compact?"G":"Garden";selected:root.section==="garden";onClicked:root.section="garden";hint:"Garden (G)" }
        Control { text:root.compact?"J":"Journal";selected:root.section==="journal";onClicked:root.section="journal";hint:"Observation journal (J)" }
        Control { text:"?";onClicked:root.section=root.section==="guide"?"garden":"guide";hint:"Field guide (H)" }
        Control { text:"×";onClicked:root.closeRequested();hint:"Close terrarium (Escape)" }
    }

    Row {
        id:body;x:24;y:111;width:parent.width-48;height:parent.height-169;spacing:24
        Item {
            id: mainArea
            width: body.width-(root.compact?0:276)
            height:body.height
            Row {
                id:habitatLabel;spacing:8
                Rectangle { width:5;height:5;radius:3;y:4;color:root.demo?root.colors.gold:root.stale?root.colors.flower:root.colors.leaf }
                Text { text:root.demo?"DEMONSTRATION":root.stale?"OBSERVATION PAUSED":"LIVE HABITAT";font.pixelSize:10;font.letterSpacing:1.6;color:root.colors.muted }
            }
            Text {
                anchors.right:parent.right
                text:root.colors.label.toUpperCase();font.pixelSize:10;font.letterSpacing:1.2;color:root.colors.muted
            }

            Item {
                x:0;y:22;width:parent.width;height:parent.height-123
                visible:root.section==="garden"
                GardenScene {
                    id:scene;anchors.fill:parent
                    palette:root.colors;residents:root.garden.residents;weather:root.atmosphere
                    animate:root.active && root.section==="garden" && !root.motionPaused && !root.reducedMotion && !root.stale
                    selectedKey:root.selectedKey
                    onResidentSelected:function(key){root.selectedKey=root.selectedKey===key?"":key;}
                }
                Item {
                    visible:!root.demo && (root.snapshot.timestamp===0 || root.stale || root.status.length>0)
                    width:Math.min(parent.width-24,440);height:noticeContent.implicitHeight+20
                    anchors.horizontalCenter:parent.horizontalCenter;anchors.bottom:parent.bottom;anchors.bottomMargin:10
                    Rectangle { anchors.fill:parent;radius:6;color:root.colors.panel;border.color:root.colors.line }
                    Column {
                        id:noticeContent;x:10;y:10;width:parent.width-20;spacing:8
                        Text { width:parent.width;text:root.status;textFormat:Text.PlainText;horizontalAlignment:Text.AlignHCenter;wrapMode:Text.WordWrap;color:root.colors.ink;font.pixelSize:12 }
                        Control { visible:root.stale;anchors.horizontalCenter:parent.horizontalCenter;text:"Try again";onClicked:root.retryRequested() }
                    }
                }
                Text {
                    visible:root.compact && root.selected!==null
                    anchors.bottom:parent.bottom;anchors.horizontalCenter:parent.horizontalCenter
                    text:root.selected?root.selected.name+" · "+Model.formatPercent(root.selected.cpu)+" CPU · "+Model.formatBytes(root.selected.memoryBytes):""
                    textFormat:Text.PlainText;color:root.colors.ink;font.pixelSize:12
                }
            }

            Item {
                visible:root.section==="journal"
                x:12;y:46;width:parent.width-24;height:parent.height-160
                Text { text:"Field notes";font.family:"serif";font.pixelSize:29;color:root.colors.ink }
                Text { y:42;width:parent.width;text:"Small arrivals and departures, observed this session.";color:root.colors.muted;font.pixelSize:12;wrapMode:Text.WordWrap }
                ListView {
                    id:journalScroll;objectName:"journalScroll"
                    y:82;width:parent.width;height:parent.height-82;clip:true;spacing:14
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
                    visible:root.garden.notes.length===0;y:106;width:parent.width
                    text:"Nothing to hurry.\nNew observations will find their way here.";color:root.colors.muted;font.pixelSize:14;lineHeight:1.5
                }
            }

            Flickable {
                id:guideScroll;objectName:"guideScroll"
                visible:root.section==="guide"
                x:12;y:39;width:parent.width-24;height:parent.height-153
                contentWidth:width;contentHeight:guide.implicitHeight;clip:true;boundsBehavior:Flickable.StopAtBounds
                Column {
                    id:guide;width:parent.width;spacing:17
                    Text { text:"Reading your little world";font.family:"serif";font.pixelSize:26;color:root.colors.ink }
                    Text { width:parent.width;text:"A living illustration of your computer, with a little room for imagination.";color:root.colors.muted;font.pixelSize:12;wrapMode:Text.WordWrap;lineHeight:1.4 }
                    Repeater {
                        model:[
                            {name:"Plants · applications",body:"A few of your busiest process groups take root. They keep their places as activity changes, and grow while observed. Select a plant to see its actual usage."},
                            {name:"Lantern light · CPU",body:"More activity brings more drifting lights. The number below is your computer’s aggregate CPU usage, not a forecast."},
                            {name:"Rain · network",body:"Received network traffic brings a passing shower. Upload traffic appears in the reading below. This is your network, not the weather outside."},
                            {name:"The pond · memory",body:"The water reflects memory in use. Your garden stays healthy at every level; it does not need feeding or attention."},
                            {name:"Time & quiet",body:"Auto follows the local time of day. Press C to choose a palette, P to pause motion, or D to explore a clearly labeled demonstration."},
                            {name:"Private by nature",body:"No accounts, network requests, or saved activity history. Only process names and numeric counters are observed. Disappearance does not mean a task succeeded."}
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

            Row {
                id:readings;width:parent.width;anchors.bottom:parent.bottom;spacing:10;height:83
                Reading {
                    width:(readings.width-20)/3
                    heading:"LANTERNS";value:Model.formatPercent(root.snapshot.cpu);detail:"CPU activity"
                    points:root.atmosphere.activity
                }
                Reading {
                    width:(readings.width-20)/3
                    heading:"THE POND";value:Model.formatPercent(root.snapshot.memory.percent)
                    detail:root.snapshot.memory.percent===null?"Memory unavailable":Model.formatBytes(root.snapshot.memory.usedBytes)+" memory";points:root.atmosphere.water
                }
                Reading {
                    width:(readings.width-20)/3
                    heading:"PASSING RAIN";value:Model.formatRate(root.snapshot.network.rxBytesPerSec)
                    detail:"↑ "+Model.formatRate(root.snapshot.network.txBytesPerSec);points:root.atmosphere.rain
                }
            }
        }

        Column {
            id:sidebar;visible:!root.compact;width:252;height:body.height;spacing:13
            Row {
                width:parent.width
                Text { width:parent.width-45;text:"IN THE GARDEN";font.pixelSize:10;font.letterSpacing:1.6;color:root.colors.muted }
                Text { width:45;text:String(root.garden.residents.length).padStart(2,"0");horizontalAlignment:Text.AlignRight;font.family:"monospace";font.pixelSize:11;color:root.colors.gold }
            }
            Text {
                width:parent.width;text:root.selected?Model.speciesNames[root.selected.category]:"Every process leaves a little trace."
                font.family:"serif";font.pixelSize:21;color:root.colors.ink;wrapMode:Text.WordWrap
            }
            Column {
                width:parent.width;spacing:3
                Repeater {
                    model:root.garden.residents
                    Rectangle {
                        id:residentRow
                        required property var modelData
                        readonly property bool selected:root.selectedKey===modelData.key
                        width:sidebar.width;height:44;radius:5
                        color:selected || residentMouse.containsMouse?root.colors.surface:"transparent"
                        border.color:root.colors.line;border.width:selected?1:0
                        Accessible.role:Accessible.Button;Accessible.name:"Inspect "+modelData.name
                        Accessible.onPressAction:root.selectedKey=modelData.key
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
                        MouseArea { id:residentMouse;anchors.fill:parent;hoverEnabled:true;cursorShape:Qt.PointingHandCursor;onClicked:root.selectedKey=residentRow.selected?"":modelData.key }
                    }
                }
            }
            Rectangle { width:parent.width;height:1;color:root.colors.line }
            Column {
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
    Rectangle { x:24;y:parent.height-45;width:parent.width-48;height:1;color:root.colors.line }
    Row {
        x:24;anchors.bottom:parent.bottom;anchors.bottomMargin:7;spacing:6
        Control { text:root.motionPaused || root.reducedMotion?"Motion paused":"Pause motion";quiet:true;onClicked:root.motionRequested();hint:"Toggle motion (P)" }
        Control { text:root.paletteName==="auto"?"Palette: auto":"Palette: "+root.paletteName;quiet:true;onClicked:root.paletteRequested();hint:"Change palette (C)" }
        Control { text:root.demo?"Return to live":"Explore demo";quiet:true;selected:root.demo;onClicked:root.demoRequested();hint:"Toggle demonstration (D)" }
        Control { text:root.ambient?"On desktop":"Pin to desktop";quiet:true;selected:root.ambient;onClicked:root.ambientRequested();hint:"Show a quiet, click-through garden behind your windows" }
    }
    Text {
        visible:root.width>1040
        anchors.right:parent.right;anchors.rightMargin:28;anchors.bottom:parent.bottom;anchors.bottomMargin:18
        text:"LOCAL BY NATURE";font.pixelSize:9;font.letterSpacing:1.6;color:root.colors.muted
    }

    component Control: TerrariumControl {
        ink:root.colors.ink;muted:root.colors.muted;surface:root.colors.surface;line:root.colors.line;accent:root.colors.gold
    }
    component Reading: Rectangle {
        property string heading:""
        property string value:""
        property string detail:""
        property real points:0
        height:83;radius:7;color:root.colors.panel;border.color:root.colors.line
        Text { x:12;y:11;text:parent.heading;color:root.colors.muted;font.pixelSize:9;font.letterSpacing:1.2 }
        Text { x:12;y:27;text:parent.value;color:root.colors.ink;font.pixelSize:root.compact?19:22;font.family:"serif" }
        Text { x:12;y:58;text:parent.detail;color:root.colors.muted;font.pixelSize:10 }
        Rectangle { anchors.right:parent.right;anchors.rightMargin:12;y:32;width:3;height:30;radius:2;color:root.colors.line
            Rectangle { anchors.bottom:parent.bottom;width:3;height:Math.max(2,parent.height*parent.parent.points);radius:2;color:root.colors.gold }
        }
    }
}
