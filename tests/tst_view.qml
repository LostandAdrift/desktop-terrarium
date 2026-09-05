import QtQuick
import QtTest
import ".."
import "../Model.js" as Model

TestCase {
    id:tests
    name:"TerrariumView"
    when:windowShown
    visible:true
    width:1120;height:720
    property var subject
    Component {
        id:viewComponent
        TerrariumView {
            width:1120;height:720;demo:true;active:false
            snapshot:Model.demoSnapshot(3)
            garden:Model.updateGarden(Model.newGarden(),Model.demoSnapshot(3),1700000000000)
        }
    }
    SignalSpy { id:closeSpy;signalName:"closeRequested" }
    SignalSpy { id:demoSpy;signalName:"demoRequested" }
    SignalSpy { id:motionSpy;signalName:"motionRequested" }
    SignalSpy { id:ambientSpy;signalName:"ambientRequested" }
    function init() {
        failOnWarning(/.*/);
        subject=createTemporaryObject(viewComponent,tests);
        verify(subject!==null);
        subject.forceActiveFocus();
        closeSpy.target=subject;demoSpy.target=subject;motionSpy.target=subject;ambientSpy.target=subject;
        closeSpy.clear();demoSpy.clear();motionSpy.clear();ambientSpy.clear();
        wait(100);
    }
    function test_navigation_and_escape() {
        keyClick(Qt.Key_J);compare(subject.section,"journal");
        keyClick(Qt.Key_Escape);compare(subject.section,"garden");compare(closeSpy.count,0);
        keyClick(Qt.Key_H);compare(subject.section,"guide");
        keyClick(Qt.Key_G);compare(subject.section,"garden");
        keyClick(Qt.Key_Escape);compare(closeSpy.count,1);
    }
    function test_actions_are_signals_not_system_commands() {
        keyClick(Qt.Key_D);compare(demoSpy.count,1);
        keyClick(Qt.Key_P);compare(motionSpy.count,1);
        keyClick(Qt.Key_A);compare(ambientSpy.count,1);
    }
    function test_default_selects_busiest_resident() {
        compare(subject.selectedKey,"firefox");
        compare(subject.selected.name,"Firefox");
        subject.selectedKey="";
        wait(50);
        compare(subject.selectedKey,"firefox");
    }
    function test_resident_keyboard_inspection() {
        compare(subject.selectedKey,"firefox");
        keyClick(Qt.Key_Right);compare(subject.selectedKey,"codex");
        keyClick(Qt.Key_Right);compare(subject.selectedKey,"neovim");
        keyClick(Qt.Key_Left);compare(subject.selectedKey,"codex");
        keyClick(Qt.Key_Left);compare(subject.selectedKey,"firefox");
        keyClick(Qt.Key_Left);compare(subject.selectedKey,"files");
        compare(subject.selected.name,"Files");
    }
    function test_keyboard_scrolls_reading_sections() {
        subject.width=720;subject.height=480;
        keyClick(Qt.Key_H);
        var guide=findChild(subject,"guideScroll");
        verify(guide.contentHeight>guide.height);
        var previous=subject.selectedKey;
        keyClick(Qt.Key_PageDown);verify(guide.contentY>0);compare(subject.selectedKey,previous);
        keyClick(Qt.Key_End);compare(guide.contentY,guide.contentHeight-guide.height);
        keyClick(Qt.Key_Home);compare(guide.contentY,0);
        var notes=[];
        for(var i=0;i<24;i++)notes.push({time:1700000000000+i*2000,text:"Synthetic application "+i+" took root."});
        subject.garden={residents:[],notes:notes,samples:1};
        wait(50);
        keyClick(Qt.Key_J);wait(100);
        var journal=findChild(subject,"journalScroll");
        keyClick(Qt.Key_Down);verify(journal.contentY>0);
        keyClick(Qt.Key_Home);compare(journal.contentY,0);
    }
    function test_tab_control_activation() {
        keyClick(Qt.Key_Tab);
        var focused=subject.Window.window.activeFocusItem;
        verify(focused!==null && focused!==subject,"Tab focus: "+focused+", view visible: "+subject.visible);
        keyClick(Qt.Key_Tab);
        keyClick(Qt.Key_Return);
        compare(subject.section,"journal");
    }
    function test_empty_state_and_error_state() {
        subject.snapshot=Model.emptySnapshot();subject.garden=Model.newGarden();
        wait(50);
        keyClick(Qt.Key_Right);compare(subject.selectedKey,"");
        subject.stale=true;subject.status="Observer unavailable";
        wait(100);compare(subject.selected,null);
    }
    function test_compact_and_palettes() {
        subject.width=720;subject.height=620;
        verify(subject.compact);
        ["dusk","dawn","moss","auto"].forEach(function(p){subject.paletteName=p;wait(100);verify(subject.colors.ink.length>0);});
        subject.width=1120;subject.height=720;verify(!subject.compact);
        subject.height=480;verify(subject.compact);
    }
    function test_connecting_is_not_live() {
        var badge=findChild(subject,"habitatStatus");
        compare(badge.text,"DEMONSTRATION");
        subject.demo=false;
        subject.stale=false;
        subject.snapshot=Model.emptySnapshot();
        subject.garden=Model.newGarden();
        subject.status="Connecting to your desktop…";
        wait(50);
        compare(badge.text,"CONNECTING");
        verify(badge.text!=="LIVE HABITAT");
        subject.stale=true;
        subject.status="The local observer stopped. You can try again.";
        wait(50);
        compare(badge.text,"OBSERVATION PAUSED");
        var live=Model.demoSnapshot(3);
        subject.stale=false;subject.status="";subject.snapshot=live;
        subject.garden=Model.updateGarden(Model.newGarden(),live,1700000000000);
        wait(50);
        compare(badge.text,"LIVE HABITAT");
    }
    function test_guide_button_selected_and_scroll_hint() {
        var button=findChild(subject,"guideButton");
        verify(!button.selected);
        keyClick(Qt.Key_H);
        compare(subject.section,"guide");
        verify(button.selected);
        var hint=findChild(subject,"guideScrollHint");
        var track=findChild(subject,"guideScrollTrack");
        verify(hint.visible);
        verify(track.visible);
        keyClick(Qt.Key_G);
        verify(!button.selected);
    }
    function test_compact_garden_well_and_caption() {
        subject.width=640;subject.height=480;
        wait(50);
        verify(subject.compact);
        var well=findChild(subject,"gardenWell");
        verify(well.width>=560);
        verify(well.height>=250);
        var caption=findChild(subject,"compactCaption");
        verify(caption.visible);
        verify(caption.text.indexOf("Firefox")>=0);
        var notice=findChild(subject,"noticeBox");
        verify(!notice.visible);
        var capBottom=caption.mapToItem(subject,0,caption.height).y;
        var wellTop=well.mapToItem(subject,0,0).y;
        verify(capBottom<=wellTop+1);
        subject.width=960;subject.height=480;
        wait(50);
        verify(subject.compact);
        verify(well.height>=250);
        subject.width=1120;subject.height=720;
        wait(50);
        verify(!subject.compact);
        verify(well.height>=390);
        verify(!caption.visible);
    }
    function test_compact_error_notice_separate_from_caption() {
        subject.width=720;subject.height=480;
        subject.demo=false;subject.stale=true;subject.status="Observer unavailable";
        wait(50);
        var caption=findChild(subject,"compactCaption");
        var notice=findChild(subject,"noticeBox");
        verify(caption.visible);
        verify(notice.visible);
        var capRect=caption.mapToItem(subject,0,0);
        var noticeRect=notice.mapToItem(subject,0,0);
        verify(capRect.y+caption.height<=noticeRect.y || noticeRect.y+notice.height<=capRect.y);
        var tree=findChild(subject,"plant-firefox");
        verify(tree.height>=220);
        var bloom=findChild(subject,"plant-codex");
        verify(bloom.height>=220);
    }
    function test_resident_row_keyboard_focus() {
        var row=findChild(subject,"resident-codex");
        verify(row!==null);
        row.forceActiveFocus();
        verify(row.activeFocus);
        keyClick(Qt.Key_Return);
        compare(subject.selectedKey,"codex");
        keyClick(Qt.Key_Right);
        compare(subject.selectedKey,"neovim");
    }
    function test_tight_header_leaves_nav_room() {
        subject.width=640;subject.height=480;
        wait(50);
        verify(subject.tight);
        var title=findChild(subject,"titleText");
        var nav=findChild(subject,"navRow");
        verify(!title.visible);
        verify(nav.mapToItem(subject,0,0).x>=300);
        subject.width=720;subject.height=620;
        wait(50);
        verify(!subject.tight);
        verify(title.visible);
        var titleRight=title.mapToItem(subject,title.width,0).x;
        var navLeft=nav.mapToItem(subject,0,0).x;
        verify(titleRight<=navLeft+2);
    }
    function test_control_hints_are_accessible_names() {
        var guide=findChild(subject,"guideButton");
        compare(guide.hint,"Field guide (H)");
        compare(guide.Accessible.name,"Field guide (H)");
    }
    function test_edge_tooltip_stays_inside_view() {
        subject.width=640;subject.height=480;
        var button=findChild(subject,"closeButton");
        button.forceActiveFocus();wait(50);
        var hint=findChild(subject,"hint-closeButton");
        verify(hint.visible);
        var position=hint.mapToItem(subject,0,0);
        verify(position.x>=0 && position.x+hint.width<=subject.width);
        verify(position.y>=0 && position.y+hint.height<=subject.height);
    }
    function test_full_resident_list_preserves_notes_and_scrolls_selection() {
        subject.height=640;
        var garden=JSON.parse(JSON.stringify(subject.garden));
        var extra=Object.assign({},garden.residents[0],{key:"extra",name:"Extra application",slot:6,category:"other",cpu:0});
        garden.residents.push(extra);
        subject.garden=garden;subject.selectedKey="extra";wait(100);
        verify(!subject.compact);
        var scroll=findChild(subject,"residentScroll");
        verify(scroll.contentHeight>scroll.height);
        var notes=findChild(subject,"specimenNotes");
        verify(notes.mapToItem(subject,0,notes.height).y<=subject.height-subject.footerBand);
        var row=findChild(subject,"resident-extra");
        var y=row.mapToItem(scroll,0,0).y;
        verify(y>=-1 && y+row.height<=scroll.height+1);
        keyClick(Qt.Key_Right);wait(50);compare(subject.selectedKey,"firefox");
        compare(scroll.contentY,0);
        keyClick(Qt.Key_Left);wait(50);
        compare(subject.selectedKey,"extra");
        y=row.mapToItem(scroll,0,0).y;
        verify(y>=-1 && y+row.height<=scroll.height+1);
    }
}
