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
    function init() {
        failOnWarning(/.*/);
        subject=createTemporaryObject(viewComponent,tests);
        verify(subject!==null);
        subject.forceActiveFocus();
        closeSpy.target=subject;demoSpy.target=subject;motionSpy.target=subject;
        closeSpy.clear();demoSpy.clear();motionSpy.clear();
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
    }
    function test_resident_keyboard_inspection() {
        keyClick(Qt.Key_Left);compare(subject.selectedKey,"files");
        subject.selectedKey="";
        keyClick(Qt.Key_Right);compare(subject.selectedKey,"firefox");
        keyClick(Qt.Key_Right);compare(subject.selectedKey,"codex");
        keyClick(Qt.Key_Left);compare(subject.selectedKey,"firefox");
        keyClick(Qt.Key_Left);compare(subject.selectedKey,"files");
        compare(subject.selected.name,"Files");
    }
    function test_keyboard_scrolls_reading_sections() {
        subject.width=720;subject.height=480;
        keyClick(Qt.Key_H);
        var guide=findChild(subject,"guideScroll");
        verify(guide.contentHeight>guide.height);
        keyClick(Qt.Key_PageDown);verify(guide.contentY>0);compare(subject.selectedKey,"");
        keyClick(Qt.Key_End);compare(guide.contentY,guide.contentHeight-guide.height);
        keyClick(Qt.Key_Home);compare(guide.contentY,0);
        var notes=[];
        for(var i=0;i<24;i++)notes.push({time:1700000000000+i*2000,text:"Synthetic application "+i+" took root."});
        subject.garden={residents:[],notes:notes,samples:1};
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
}
