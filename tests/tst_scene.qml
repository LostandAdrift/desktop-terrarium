import QtQuick
import QtTest
import ".."
import "../Model.js" as Model

TestCase {
    id:tests
    name:"TerrariumScene"
    when:windowShown
    visible:true
    width:900; height:550
    property var subject
    Component {
        id:sceneComponent
        GardenScene {
            width:900; height:550; animate:false; hour:20
            residents:Model.updateGarden(Model.newGarden(),Model.demoSnapshot(3),1700000000000).residents
            weather:Model.weather(Model.demoSnapshot(3))
        }
    }
    SignalSpy { id:selected; signalName:"residentSelected" }
    function init() {
        failOnWarning(/.*/);
        subject=createTemporaryObject(sceneComponent,tests);
        verify(subject!==null);
        selected.target=subject; selected.clear();
        mouseMove(tests,5,5);
        tryCompare(subject,"artReady",true,2500);
    }
    function copiedResidents() { return JSON.parse(JSON.stringify(subject.residents)); }

    function test_samples_preserve_cached_plants_and_smooth_local_activity() {
        var plant=findChild(subject,"plant-firefox");
        var untouched=findChild(subject,"plant-neovim");
        var start=plant.energy, other=untouched.energy;
        var paints=subject.botanicalPaintCount();
        subject.animate=true;
        for(var i=0;i<5;i++) {
            var next=copiedResidents(); next[0].cpu=90; subject.residents=next;
            wait(60);
        }
        compare(findChild(subject,"plant-firefox"),plant);
        compare(subject.botanicalPaintCount(),paints);
        verify(plant.energy>start && plant.energy<.9);
        fuzzyCompare(untouched.energy,other,.00001);
    }
    function test_motion_changes_the_drawing_but_keeps_its_root_fixed() {
        var plant=findChild(subject,"plant-firefox");
        var botanical=findChild(subject,"botanical-firefox");
        var plate=findChild(subject,"scenePlate");
        subject.animate=true;
        var initial=plant.pose.angle;
        wait(400);
        verify(Math.abs(plant.pose.angle-initial)>.01);
        var rootPosition=botanical.mapToItem(plate,plant.rootX,plant.rootY);
        fuzzyCompare(rootPosition.x,Model.positions[0].x,.001);
        fuzzyCompare(rootPosition.y,Model.positions[0].y,.001);
    }
    function test_growth_and_absence_transform_the_whole_cached_plant() {
        var plant=findChild(subject,"plant-firefox");
        var paints=plant.paintCount, initial=plant.shownGrowth;
        subject.animate=true;
        var next=copiedResidents(); next[0].growth=1; next[0].missing=4; subject.residents=next;
        wait(450);
        verify(plant.shownGrowth>initial && plant.shownGrowth<1);
        verify(plant.shownOpacity<1 && plant.shownOpacity>.45);
        compare(plant.paintCount,paints);
        subject.animate=false;
        compare(plant.shownGrowth,1); compare(plant.shownOpacity,.45);
    }
    function test_pointer_interaction_is_bounded_and_settles() {
        subject.animate=true;
        mouseClick(subject,305,200);
        compare(selected.count,1); compare(selected.signalArguments[0][0],"firefox");
        mouseClick(subject,620,425);
        compare(subject.touches[subject.touches.length-1].kind,"pond");
        for(var i=0;i<30;i++)verify(subject.touchAt(620,425,""));
        compare(subject.transientCount,4);
        var paints=subject.botanicalPaintCount();
        tryCompare(subject,"transientCount",0,3800);
        compare(subject.botanicalPaintCount(),paints);
    }
    function test_paused_and_hidden_have_no_clock_but_static_feedback_works() {
        subject.selectedKey="firefox";
        var phase=subject.phase, paints=subject.botanicalPaintCount();
        verify(!subject.animationRunning);
        verify(subject.interactSelected());
        compare(subject.staticTouch.key,"firefox"); compare(subject.transientCount,0);
        wait(160); compare(subject.phase,phase); compare(subject.botanicalPaintCount(),paints);
        subject.animate=true; wait(100); verify(subject.phase>phase);
        subject.visible=false; phase=subject.phase;
        verify(!subject.animationRunning); verify(!subject.interactSelected());
        wait(160); compare(subject.phase,phase); compare(subject.transientCount,0);
    }
    function test_disabled_scene_does_not_intercept_or_accept_interaction() {
        subject.animate=true; subject.selectedKey="firefox"; subject.enabled=false;
        mouseClick(subject,305,200);
        compare(selected.count,0);
        verify(!subject.interactSelected()); verify(!subject.touchAt(620,425,""));
        compare(subject.transientCount,0);
        verify(subject.animationRunning,"The click-through ambient scene may still animate");
    }
    function test_selected_name_is_only_shown_for_discovery() {
        subject.selectedKey="firefox";
        var label=findChild(subject,"plant-label-firefox");
        verify(!label.visible);
        var plant=findChild(subject,"plant-firefox");
        plant.forceActiveFocus(); wait(20); verify(label.visible);
        keyClick(Qt.Key_Space); compare(selected.count,1); verify(subject.staticTouch!==null);
    }
    function test_local_time_changes_actual_pixels_without_changing_the_palette() {
        var paletteName=subject.colors.name;
        var night=grabImage(subject);
        subject.hour=12; wait(120);
        var day=grabImage(subject);
        compare(subject.colors.name,paletteName);
        verify(!day.equals(night));
        subject.hour=36; wait(80);
        verify(grabImage(subject).equals(day));
        subject.hour=20; wait(120);
        verify(grabImage(subject).equals(night));
    }
    function test_artwork_mode_suppresses_ui_and_input_without_stopping_motion() {
        subject.selectedKey="firefox"; subject.animate=true;
        verify(subject.interactSelected()); verify(subject.transientCount>0);
        subject.artworkOnly=true;
        compare(subject.transientCount,0); verify(subject.staticTouch===null);
        verify(!findChild(subject,"root-ring-firefox").visible);
        verify(!findChild(subject,"plant-label-firefox").visible);
        verify(!subject.interactSelected());
        mouseClick(subject,305,200); compare(selected.count,0);
        var phase=subject.phase; wait(100);
        verify(subject.animationRunning && subject.phase>phase);
    }
    function test_readiness_follows_painted_content_and_canvas_dimensions() {
        verify(subject.artReady);
        subject.hour=12; compare(subject.artReady,false);
        tryCompare(subject,"artReady",true,2500);
        var changed=JSON.parse(JSON.stringify(subject.colors)); changed.leaf="#ff5500";
        // Even a color change that keeps its palette name must invalidate art.
        subject.colors=changed; compare(subject.artReady,false);
        tryCompare(subject,"artReady",true,2500);
        var next=copiedResidents(); next[0].key="new-tree"; subject.residents=next;
        compare(subject.artReady,false);
        tryCompare(subject,"artReady",true,2500);
        var plant=findChild(subject,"plant-new-tree");
        plant.width=300; compare(subject.artReady,false);
        tryCompare(subject,"artReady",true,2500);
        subject.rasterScale=2; compare(subject.artReady,false);
        tryCompare(subject,"artReady",true,2500);
        compare(plant.textureScale,2);
        subject.rasterScale=1; compare(subject.artReady,false);
        tryCompare(subject,"artReady",true,2500);
        // Growth and CPU use the existing texture and do not invalidate it.
        next=copiedResidents(); next[0].growth=.99; next[0].cpu=70; subject.residents=next;
        compare(subject.artReady,true);
    }
}
