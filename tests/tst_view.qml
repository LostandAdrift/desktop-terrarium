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
            width:1120;height:720;demo:true;active:true
            snapshot:Model.demoSnapshot(3)
            garden:Model.updateGarden(Model.newGarden(),Model.demoSnapshot(3),1700000000000)
        }
    }
    Component {
        id:clipboardProbeComponent
        TextEdit { textFormat:TextEdit.PlainText;visible:false }
    }
    SignalSpy { id:closeSpy;signalName:"closeRequested" }
    SignalSpy { id:demoSpy;signalName:"demoRequested" }
    SignalSpy { id:motionSpy;signalName:"motionRequested" }
    SignalSpy { id:ambientSpy;signalName:"ambientRequested" }
    SignalSpy { id:placementSpy;signalName:"placementRequested" }
    SignalSpy { id:paletteSpy;signalName:"paletteRequested" }
    SignalSpy { id:postcardSpy;signalName:"postcardRequested" }
    SignalSpy { id:exportSpy;signalName:"exportRequested" }
    SignalSpy { id:cancelExportSpy;signalName:"exportCancelRequested" }
    function init() {
        failOnWarning(/.*/);
        subject=createTemporaryObject(viewComponent,tests);
        verify(subject!==null);
        subject.forceActiveFocus();
        closeSpy.target=subject;demoSpy.target=subject;motionSpy.target=subject;ambientSpy.target=subject;
        placementSpy.target=subject;paletteSpy.target=subject;postcardSpy.target=subject;
        exportSpy.target=subject;cancelExportSpy.target=subject;
        closeSpy.clear();demoSpy.clear();motionSpy.clear();ambientSpy.clear();
        placementSpy.clear();paletteSpy.clear();postcardSpy.clear();
        exportSpy.clear();cancelExportSpy.clear();
        wait(100);
    }
    function openPostcard() {
        subject.postcardAvailable=true;
        keyClick(Qt.Key_S,Qt.ControlModifier);
        compare(subject.section,"postcard");
        tryCompare(subject,"postcardReady",true,5000);
        return findChild(subject,"postcardLoader").item;
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
    function test_failed_process_observation_is_marked_unavailable() {
        var failed=Model.demoSnapshot(3);
        failed.processes=[];failed.processesAvailable=false;
        failed.errors=["process scan incomplete"];
        subject.snapshot=failed;
        subject.garden=Model.updateGarden(subject.garden,failed,1700000002000);
        wait(50);
        compare(subject.selectedKey,"firefox");
        compare(subject.selected.cpu,null);
        compare(subject.selected.memoryBytes,null);
        verify(findChild(subject,"specimenBody").text.indexOf("unavailable")>=0);
        subject.selectedKey="";
        var summary=findChild(subject,"processSummary");
        verify(!summary.visible);
        var observed=Model.demoSnapshot(4);
        observed.uptimeSeconds=0;
        subject.snapshot=observed;
        verify(summary.visible);
        compare(summary.text,observed.processCount+" processes");
        subject.snapshot=failed;
        subject.selectedKey="firefox";
        subject.width=640;subject.height=480;wait(50);
        verify(findChild(subject,"compactCaption").text.indexOf("readings unavailable")>=0);
    }
    function test_space_touches_selected_plant_without_system_action() {
        var scene=findChild(subject,"gardenScene");
        subject.reducedMotion=true;subject.forceActiveFocus();
        keyClick(Qt.Key_Space);wait(50);
        verify(scene.staticTouch!==null);
        compare(scene.staticTouch.key,subject.selectedKey);
        compare(scene.animationRunning,false);
        compare(closeSpy.count,0);compare(demoSpy.count,0);compare(motionSpy.count,0);
    }
    function test_options_navigation_stops_scene_motion_and_keeps_quick_pin() {
        subject.active=true;
        tryCompare(subject,"sceneAnimating",true);
        var selected=subject.selectedKey;
        keyClick(Qt.Key_O);
        compare(subject.section,"options");
        tryCompare(subject,"sceneAnimating",false);
        verify(findChild(subject,"optionsButton").selected);
        tryVerify(function(){return findChild(subject,"optionsScroll").activeFocus;});
        keyClick(Qt.Key_Tab);
        verify(findChild(subject,"pinOption").activeFocus);
        keyClick(Qt.Key_Tab);
        verify(findChild(subject,"artOption").activeFocus);
        keyClick(Qt.Key_Backtab);
        verify(findChild(subject,"pinOption").activeFocus);
        keyClick(Qt.Key_A);compare(ambientSpy.count,1);
        keyClick(Qt.Key_Right);compare(subject.selectedKey,selected);
        keyClick(Qt.Key_Escape);
        compare(subject.section,"garden");compare(closeSpy.count,0);
        tryCompare(subject,"sceneAnimating",true);
        keyClick(Qt.Key_O);keyClick(Qt.Key_H);
        compare(subject.section,"guide");
    }
    function test_art_mode_reuses_scene_and_restores_keyboard_focus() {
        subject.active=true;
        var scene=findChild(subject,"gardenScene");
        var originalWidth=scene.width, originalHeight=scene.height;
        var selected=subject.selectedKey;
        var trigger=findChild(subject,"artButton");
        trigger.forceActiveFocus();
        keyClick(Qt.Key_F);
        compare(subject.section,"art");
        tryVerify(function(){return findChild(subject,"artBack").activeFocus;});
        compare(findChild(subject,"gardenScene"),scene);
        verify(scene.width>originalWidth && scene.height>originalHeight);
        verify(!findChild(subject,"readings").visible);
        verify(!findChild(subject,"residentSidebar").visible);
        verify(!findChild(subject,"navRow").visible);
        verify(!scene.artworkOnly,"Art mode remains interactive; only export disables interaction.");
        tryCompare(subject,"sceneAnimating",true);
        subject.reducedMotion=true;tryCompare(subject,"sceneAnimating",false);
        keyClick(Qt.Key_F);
        compare(subject.section,"garden");
        tryVerify(function(){return trigger.activeFocus;});
        compare(subject.selectedKey,selected);
        compare(scene.width,originalWidth);compare(scene.height,originalHeight);
        verify(findChild(subject,"readings").visible);
        keyClick(Qt.Key_F);wait(20);keyClick(Qt.Key_Escape);
        compare(subject.section,"garden");compare(closeSpy.count,0);
    }
    function test_art_back_returns_to_options_and_its_trigger() {
        keyClick(Qt.Key_O);wait(20);
        var trigger=findChild(subject,"artOption");
        trigger.forceActiveFocus();keyClick(Qt.Key_Return);
        compare(subject.section,"art");
        var back=findChild(subject,"artBack");
        tryVerify(function(){return back.activeFocus;});
        keyClick(Qt.Key_Return);
        compare(subject.section,"options");
        tryVerify(function(){return trigger.activeFocus;});
        compare(closeSpy.count,0);
    }
    function test_options_emit_native_preferences_without_mutating_them() {
        subject.displays=[{name:"DP-1",label:"Desk display"},{name:"HDMI-A-1",label:"Portrait display"}];
        keyClick(Qt.Key_O);wait(20);
        var display=findChild(subject,"display-1");
        display.forceActiveFocus();keyClick(Qt.Key_Return);
        compare(placementSpy.count,1);
        compare(placementSpy.signalArguments[0][0],"ambientDisplay");
        compare(placementSpy.signalArguments[0][1],"HDMI-A-1");
        compare(subject.ambientDisplay,"");
        subject.ambientDisplay="HDMI-A-1";
        verify(display.selected);
        var corner=findChild(subject,"corner-top-left");
        corner.forceActiveFocus();keyClick(Qt.Key_Space);
        compare(placementSpy.count,2);
        compare(placementSpy.signalArguments[1][0],"ambientCorner");
        compare(placementSpy.signalArguments[1][1],"top-left");
        compare(subject.ambientCorner,"bottom-right");
        var size=findChild(subject,"size-large");
        size.forceActiveFocus();keyClick(Qt.Key_Return);
        compare(placementSpy.signalArguments[2][0],"ambientSize");
        compare(placementSpy.signalArguments[2][1],"large");
        var automatic=findChild(subject,"display-automatic");
        automatic.forceActiveFocus();keyClick(Qt.Key_Return);
        compare(placementSpy.signalArguments[3][0],"ambientDisplay");
        compare(placementSpy.signalArguments[3][1],"");
        compare(subject.ambientDisplay,"HDMI-A-1");
    }
    function test_saved_display_survives_disconnect_and_reconnect() {
        subject.displays=[{name:"DP-1",label:"Desk"}];
        subject.ambientDisplay="HDMI-A-1";
        keyClick(Qt.Key_O);wait(20);
        var notice=findChild(subject,"displayFallbackNotice");
        verify(notice.visible);
        verify(notice.text.indexOf("HDMI-A-1")>=0);
        verify(notice.text.indexOf("first available")>=0);
        compare(subject.ambientDisplay,"HDMI-A-1");
        subject.displays=[];
        wait(20);
        verify(notice.visible);
        verify(notice.text.indexOf("when a display is available")>=0);
        subject.displays=[{name:"DP-1",label:"Desk"},{name:"HDMI-A-1",label:"Returned display"}];
        wait(20);
        verify(!notice.visible);
        verify(findChild(subject,"display-1").selected);
        compare(subject.ambientDisplay,"HDMI-A-1");
        compare(placementSpy.count,0);
    }
    function test_compact_options_scroll_and_reveal_keyboard_choices() {
        subject.width=640;subject.height=480;
        subject.displays=[{name:"DP-1",label:"A very long display label with spaces and 日本語 that should stay inside its selection row"},{name:"DP-2",label:"Second display"}];
        keyClick(Qt.Key_O);wait(50);
        var scroll=findChild(subject,"optionsScroll");
        verify(scroll.contentHeight>scroll.height);
        verify(findChild(subject,"optionsScrollTrack").visible);
        var choices=["display-automatic","display-0","display-1","corner-bottom-right","size-large","demoOption"];
        for(var i=0;i<choices.length;i++) {
            var choice=findChild(subject,choices[i]);
            choice.forceActiveFocus();wait(20);
            var local=choice.mapToItem(scroll,0,0);
            verify(local.x>=0 && local.x+choice.width<=scroll.width,choices[i]+" extends horizontally");
            verify(local.y>=-1 && local.y+choice.height<=scroll.height+1,choices[i]+" not revealed while focused");
        }
        keyClick(Qt.Key_Home);compare(scroll.contentY,0);
        keyClick(Qt.Key_PageDown);verify(scroll.contentY>0);
        keyClick(Qt.Key_End);compare(scroll.contentY,scroll.contentHeight-scroll.height);
        var selected=subject.selectedKey;
        keyClick(Qt.Key_Down);compare(subject.selectedKey,selected);
    }
    function test_options_initial_layout_starts_at_top_and_reveals_first_control() {
        var initial=createTemporaryObject(viewComponent,tests,{width:160,height:120,section:"options",displays:[{name:"DP-1",label:"Desk display"},{name:"DP-2",label:"Second display"}]});
        verify(initial!==null);
        wait(20);
        initial.width=640;initial.height=480;
        wait(100);
        var scroll=findChild(initial,"optionsScroll");
        var pin=findChild(initial,"pinOption");
        compare(scroll.contentY,0);
        verify(scroll.activeFocus);
        keyClick(Qt.Key_Tab);
        verify(pin.activeFocus);
        var position=pin.mapToItem(scroll,0,0);
        verify(position.y>=-1 && position.y+pin.height<=scroll.height+1,"Focused pin is hidden after the panel finishes layout");
    }
    function test_option_tooltip_follows_scroll_and_hides_when_clipped() {
        subject.width=640;subject.height=480;
        keyClick(Qt.Key_O);wait(50);
        var scroll=findChild(subject,"optionsScroll");
        var button=findChild(subject,"pinOption");
        button.forceActiveFocus();wait(20);
        var hint=findChild(subject,"hint-pinOption");
        verify(hint.visible);
        var before=hint.mapToItem(subject,0,0).y;
        scroll.contentY+=15;wait(20);
        verify(hint.visible);
        var after=hint.mapToItem(subject,0,0).y;
        compare(after,before-15);
        keyClick(Qt.Key_End);wait(20);
        verify(!hint.visible,"A focused button outside the scroller must not leave a tooltip over unrelated content");
        keyClick(Qt.Key_Home);wait(20);
        verify(hint.visible);
    }
    function test_options_color_motion_and_demo_controls_remain_actions() {
        keyClick(Qt.Key_O);wait(20);
        findChild(subject,"paletteOption").forceActiveFocus();keyClick(Qt.Key_Return);
        compare(paletteSpy.count,1);
        findChild(subject,"motionOption").forceActiveFocus();keyClick(Qt.Key_Return);
        compare(motionSpy.count,1);
        findChild(subject,"demoOption").forceActiveFocus();keyClick(Qt.Key_Return);
        compare(demoSpy.count,1);
        compare(subject.section,"options");
        compare(placementSpy.count,0);
    }
    function test_art_preserves_demo_and_paused_status_in_compact_layout() {
        subject.width=640;subject.height=480;
        keyClick(Qt.Key_F);wait(20);
        var badge=findChild(subject,"artStatus");
        verify(badge.visible);compare(badge.text,"DEMONSTRATION");
        var back=findChild(subject,"artBack");
        var backRight=back.mapToItem(subject,back.width,0).x;
        verify(badge.mapToItem(subject,0,0).x>backRight);
        var scene=findChild(subject,"gardenScene");
        verify(scene.width<=subject.width && scene.height<=subject.height);
        subject.demo=false;subject.stale=true;
        compare(badge.text,"OBSERVATION PAUSED");
        verify(badge.visible);
        subject.stale=false;
        verify(!badge.visible);
        compare(closeSpy.count,0);
    }
    function test_postcard_shortcut_is_gated_until_native_integration() {
        keyClick(Qt.Key_S,Qt.ControlModifier);
        compare(postcardSpy.count,0);
        subject.postcardAvailable=true;
        keyClick(Qt.Key_S,Qt.ControlModifier);
        compare(postcardSpy.count,1);
        compare(subject.section,"postcard");
    }
    function test_postcard_is_on_demand_and_stops_original_scene() {
        var loader=findChild(subject,"postcardLoader");
        var scene=findChild(subject,"gardenScene");
        compare(loader.item,null);
        verify(!loader.active);
        verify(scene.visible && scene.animationRunning);
        var card=openPostcard();
        verify(card!==null);
        verify(!scene.visible && !scene.animationRunning);
        verify(!subject.sceneAnimating);
        var illustration=findChild(subject,"postcardScene");
        verify(illustration.visible);
        verify(illustration.artworkOnly);
        verify(!illustration.animationRunning);
        keyClick(Qt.Key_Escape);
        compare(subject.section,"garden");
        compare(loader.item,null);
        compare(subject.postcardSnapshot,null);
        verify(scene.visible && scene.animationRunning);
    }
    function test_postcard_freezes_art_and_source_until_explicit_refresh() {
        var card=openPostcard();
        var frozen=JSON.stringify(card.snapshot);
        var snapshotReference=subject.postcardSnapshot;
        verify(Object.isFrozen(snapshotReference));
        verify(Object.isFrozen(snapshotReference.residents));
        compare(typeof snapshotReference.residents[0].name,"undefined");
        compare(typeof snapshotReference.residents[0].memoryBytes,"undefined");
        compare(subject.postcardSource,"Demonstration snapshot");
        subject.garden.residents[0].growth=1;
        subject.snapshot=Model.demoSnapshot(40);
        subject.garden=Model.updateGarden(subject.garden,subject.snapshot,1700000060000);
        subject.paletteName="dawn";subject.hour=8.25;subject.demo=false;subject.stale=true;
        wait(50);
        compare(JSON.stringify(card.snapshot),frozen);
        compare(subject.postcardSnapshot,snapshotReference);
        compare(subject.postcardSource,"Demonstration snapshot");
        subject.exportBusy=true;
        verify(!subject.refreshPostcard());
        compare(JSON.stringify(card.snapshot),frozen);
        compare(cancelExportSpy.count,0);
        subject.exportBusy=false;
        verify(subject.refreshPostcard());
        tryCompare(subject,"postcardReady",true,5000);
        compare(findChild(subject,"postcardLoader").item,card);
        verify(JSON.stringify(card.snapshot)!==frozen);
        compare(subject.postcardSource,"Paused observation snapshot");
        compare(card.snapshot.hour,8.25);
        compare(cancelExportSpy.count,1);
        compare(postcardSpy.count,2);
    }
    function test_postcard_save_emits_ready_item_and_rejects_busy_requests() {
        var card=openPostcard();
        tryVerify(function(){return findChild(subject,"postcardPane").activeFocus;});
        keyClick(Qt.Key_S,Qt.ControlModifier);
        compare(exportSpy.count,1);
        compare(exportSpy.signalArguments[0][0],card);
        verify(card.ready);
        compare(postcardSpy.count,1);
        subject.exportBusy=true;
        verify(!findChild(subject,"postcardSave").enabled);
        verify(!findChild(subject,"postcardRefresh").enabled);
        keyClick(Qt.Key_S,Qt.ControlModifier);
        verify(!subject.savePostcard());
        compare(exportSpy.count,1);
        subject.exportBusy=false;
        verify(findChild(subject,"postcardSave").enabled);
    }
    function test_postcard_busy_tab_focuses_cancel_and_returns() {
        openPostcard();
        subject.exportBusy=true;
        var pane=findChild(subject,"postcardPane");
        var back=findChild(subject,"postcardBack");
        pane.forceActiveFocus();
        verify(pane.activeFocus);
        keyClick(Qt.Key_Tab);
        verify(back.activeFocus);
        compare(back.text,"Cancel & back");
        keyClick(Qt.Key_Return);
        compare(subject.section,"garden");
        compare(cancelExportSpy.count,1);
        compare(subject.postcardSnapshot,null);
        compare(exportSpy.count,0);
    }
    function test_postcard_cancels_before_direct_navigation_unloads_item() {
        openPostcard();
        var loader=findChild(subject,"postcardLoader");
        var observations=[];
        subject.exportCancelRequested.connect(function(){observations.push(loader.item!==null && subject.postcardSnapshot!==null);});
        subject.exportBusy=true;
        subject.section="guide";
        compare(cancelExportSpy.count,1);
        compare(observations.length,1);verify(observations[0]);
        compare(loader.item,null);
        compare(subject.postcardSnapshot,null);
        compare(subject.section,"guide");
        compare(closeSpy.count,0);
    }
    function test_postcard_cancel_on_close_and_visibility_loss() {
        openPostcard();
        var loader=findChild(subject,"postcardLoader");
        subject.exportBusy=true;
        subject.requestClose();
        compare(cancelExportSpy.count,1);compare(closeSpy.count,1);
        compare(loader.item,null);compare(subject.postcardSnapshot,null);
        subject.exportBusy=false;subject.forceActiveFocus();
        openPostcard();subject.active=false;
        compare(cancelExportSpy.count,2);
        compare(loader.item,null);compare(subject.postcardSnapshot,null);
        verify(!subject.requestPostcard());
        subject.active=true;subject.forceActiveFocus();
        openPostcard();subject.visible=false;
        compare(cancelExportSpy.count,3);
        compare(loader.item,null);compare(subject.postcardSnapshot,null);
        verify(!subject.requestPostcard());
    }
    function test_postcard_restores_options_and_art_focus() {
        subject.postcardAvailable=true;
        keyClick(Qt.Key_O);wait(20);
        var option=findChild(subject,"postcardOption");
        verify(option.visible);
        option.forceActiveFocus();keyClick(Qt.Key_Return);
        compare(subject.section,"postcard");
        tryCompare(subject,"postcardReady",true,5000);
        keyClick(Qt.Key_Escape);
        compare(subject.section,"options");
        tryVerify(function(){return option.activeFocus;});
        keyClick(Qt.Key_G);wait(20);
        var artTrigger=findChild(subject,"artButton");
        artTrigger.forceActiveFocus();keyClick(Qt.Key_F);wait(20);
        var artPostcard=findChild(subject,"artPostcard");
        verify(artPostcard.visible);
        artPostcard.forceActiveFocus();keyClick(Qt.Key_Return);
        compare(subject.section,"postcard");
        tryCompare(subject,"postcardReady",true,5000);
        keyClick(Qt.Key_Escape);
        compare(subject.section,"art");
        tryVerify(function(){return artPostcard.activeFocus;});
        keyClick(Qt.Key_F);
        compare(subject.section,"garden");
        tryVerify(function(){return artTrigger.activeFocus;});
    }
    function test_postcard_compact_controls_and_plaintext_saved_path() {
        subject.width=640;subject.height=480;
        var card=openPostcard();
        subject.exportStatus="Saved <b>locally</b> & ready.";
        subject.exportPath="/synthetic/Pictures/Terrarium/a postcard & <markup> 日本語.png";
        wait(20);
        var status=findChild(subject,"postcardExportStatus");
        var path=findChild(subject,"postcardExportPath");
        compare(status.text,subject.exportStatus);compare(status.textFormat,Text.PlainText);
        compare(path.text,subject.exportPath);compare(path.textFormat,Text.PlainText);
        verify(path.visible);
        var names=["postcardSave","postcardRefresh","postcardBack","postcardExportStatus","postcardExportPath","postcardCopyPath"];
        for(var i=0;i<names.length;i++) {
            var control=findChild(subject,names[i]);
            var point=control.mapToItem(subject,0,0);
            verify(point.x>=0 && point.y>=0,names[i]+" lies before the panel");
            verify(point.x+control.width<=subject.width && point.y+control.height<=subject.height,names[i]+" exceeds the panel");
        }
        verify(card.width>300 && card.height>180);
        verify(findChild(subject,"postcardWell").height>=card.height);
        subject.exportBusy=true;
        compare(findChild(subject,"postcardBack").text,"Cancel & back");
        subject.forceActiveFocus();keyClick(Qt.Key_S,Qt.ControlModifier);
        compare(exportSpy.count,0);
    }
    function test_postcard_copies_full_plaintext_path_with_keyboard_feedback() {
        subject.width=640;subject.height=480;
        openPostcard();
        var copy=findChild(subject,"postcardCopyPath");
        verify(!copy.visible);
        verify(!subject.copyPostcardPath());
        var fullPath="/synthetic/Pictures/a directory with a deliberately long name/another long directory/Terrarium/a postcard & <b>plain text</b> 日本語.png";
        subject.exportPath=fullPath;
        var path=findChild(subject,"postcardExportPath");
        compare(path.Accessible.name,"Saved location: "+fullPath);
        compare(copy.Accessible.description,fullPath);
        compare(copy.text,"Copy path");
        var back=findChild(subject,"postcardBack");
        back.forceActiveFocus();
        keyClick(Qt.Key_Tab);
        verify(copy.activeFocus);
        keyClick(Qt.Key_Return);
        verify(copy.activeFocus);
        compare(copy.text,"Copied");
        var probe=createTemporaryObject(clipboardProbeComponent,tests);
        verify(probe!==null);
        probe.paste();
        compare(probe.text,fullPath);
        keyClick(Qt.Key_Tab);
        verify(!copy.activeFocus);
        compare(subject.section,"postcard");
        subject.exportPath="/synthetic/Pictures/Terrarium/next.png";
        compare(copy.text,"Copy path");
        subject.exportPath="";
        verify(!copy.visible);
        verify(!subject.copyPostcardPath());
    }
    function test_postcard_source_label_distinguishes_live_paused_and_empty() {
        subject.demo=false;
        openPostcard();compare(subject.postcardSource,"Live garden snapshot");
        subject.stale=true;
        verify(subject.refreshPostcard());
        compare(subject.postcardSource,"Paused observation snapshot");
        subject.stale=false;subject.snapshot=Model.emptySnapshot();subject.garden=Model.newGarden();
        verify(subject.refreshPostcard());
        compare(subject.postcardSource,"Before the first observation");
        tryCompare(subject,"postcardReady",true,5000);
        compare(findChild(subject,"postcardLoader").item.snapshot.residents.length,0);
    }
}
