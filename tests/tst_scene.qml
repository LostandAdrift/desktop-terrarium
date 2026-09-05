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
    property int underlyingClicks:0
    MouseArea { anchors.fill:parent; z:-1; onClicked:tests.underlyingClicks++ }
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
        var form=plant.form,stature=plant.stature;
        var paints=subject.botanicalPaintCount();
        subject.animate=true;
        for(var i=0;i<5;i++) {
            var next=copiedResidents(); next[0].cpu=90; subject.residents=next;
            wait(60);
        }
        compare(findChild(subject,"plant-firefox"),plant);
        verify(plant.form===form && plant.stature===stature,"Telemetry replacements retain the cached geometry and planting role");
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
    function test_growth_within_a_stage_and_absence_transform_the_cached_plant() {
        var plant=findChild(subject,"plant-firefox");
        var paints=plant.paintCount, initial=plant.shownGrowth;
        subject.animate=true;
        var next=copiedResidents(); next[0].growth=.55; next[0].missing=4; subject.residents=next;
        wait(450);
        verify(plant.shownGrowth>initial && plant.shownGrowth<.55);
        verify(plant.shownOpacity<1 && plant.shownOpacity>.45);
        compare(plant.paintCount,paints);
        subject.animate=false;
        compare(plant.shownGrowth,.55); compare(plant.shownOpacity,.45);
    }
    function test_pointer_interaction_is_bounded_and_settles() {
        subject.animate=true;
        mouseClick(subject,305,342);
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
        var clicks=underlyingClicks;
        mouseClick(subject,305,200);
        compare(selected.count,0);
        compare(underlyingClicks,clicks+1,"The actual pointer event must reach the surface behind the pin");
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
        // Growth within a botanical stage and CPU keep the existing texture.
        next=copiedResidents(); next[0].growth=.55; next[0].cpu=70; subject.residents=next;
        compare(subject.artReady,true);
    }
    function homogeneous(category,growth) {
        var result=[];
        for(var i=0;i<7;i++)result.push({key:"specimen-"+i,name:"Specimen "+i,category:category,slot:i,cpu:25,growth:growth,missing:0});
        return result;
    }
    function test_all_roots_remain_reachable_and_clear_water_does_not_select_plants() {
        var categories=["browser","editor","terminal","agent","media","system","other"];
        for(var compact=0;compact<2;compact++) {
            subject.width=compact?560:900;subject.height=compact?360:550;subject.fitVessel=compact===1;
            var plate=findChild(subject,"scenePlate");
            for(var c=0;c<categories.length;c++) {
                subject.residents=homogeneous(categories[c],1);
                tryCompare(subject,"artReady",true,2500);
                for(var i=0;i<7;i++) {
                    mouseMove(tests,5,5);selected.clear();
                    var point=plate.mapToItem(subject,Model.positions[i].x,Model.positions[i].y);
                    mouseClick(subject,point.x,point.y);
                    compare(selected.count,1,categories[c]+" root "+i);
                    compare(selected.signalArguments[0][0],"specimen-"+i);
                }
                mouseMove(tests,5,5);selected.clear();
                point=plate.mapToItem(subject,615,416);mouseClick(subject,point.x,point.y);
                compare(selected.count,0,categories[c]+" exposed water");
                compare(subject.staticTouch.kind,"pond");
                compare(subject.staticTouch.key,"");
                point=plate.mapToItem(subject,491,395);mouseClick(subject,point.x,point.y);
                compare(selected.count,0,categories[c]+" exposed bridge");
            }
        }
    }
    function test_painted_foliage_and_hover_use_the_transformed_botanical_shape() {
        subject.residents=homogeneous("browser",1);
        tryCompare(subject,"artReady",true,2500);
        // This point is in the left back canopy, well away from its root.
        mouseMove(subject,330,185);wait(20);
        verify(findChild(subject,"plant-label-specimen-0").visible);
        mouseClick(subject,330,185);
        compare(selected.count,1);compare(selected.signalArguments[0][0],"specimen-0");
        mouseMove(subject,615,416);wait(20);
        verify(!findChild(subject,"plant-label-specimen-0").visible);
        compare(subject.pointerKey,"");
    }
    function test_maturity_adds_cached_structure_only_at_three_stage_boundaries() {
        var plant=findChild(subject,"plant-firefox"),textures=subject.residentTextureCount;
        var previous=grabImage(subject),paintCount=plant.paintCount;
        var stages=[.65,.85,.98];
        for(var i=0;i<stages.length;i++) {
            var next=copiedResidents();next[0].growth=stages[i];subject.residents=next;
            compare(subject.artReady,false);tryCompare(subject,"artReady",true,2500);
            compare(findChild(subject,"plant-firefox"),plant);
            compare(plant.paintCount,++paintCount);
            var current=grabImage(subject);verify(!current.equals(previous));previous=current;
            compare(subject.residentTextureCount,textures);
        }
        subject.animate=true;
        for(i=0;i<10;i++) {
            next=copiedResidents();next[0].cpu=20+i*5;next[0].growth=.98+i*.001;
            subject.residents=next;wait(55);
        }
        compare(plant.paintCount,paintCount);
        verify(subject.animationRunning);
    }
}
