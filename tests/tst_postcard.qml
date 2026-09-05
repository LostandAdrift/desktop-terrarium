import QtQuick
import QtTest
import ".."
import "../Model.js" as Model

TestCase {
    id:tests
    name:"TerrariumPostcard"
    when:windowShown
    visible:true
    width:900; height:550
    property var subject
    property string prefix:"/tmp/terrarium-v2-postcard-"+Date.now()+"-"+Math.floor(Math.random()*1000000)
    property int sequence:0
    Component { id:cardComponent; Postcard { width:900; height:550 } }
    Component { id:imageComponent; Image { width:900; height:550; cache:false; asynchronous:false } }
    function input() {
        var source=Model.demoSnapshot(3);
        var residents=Model.updateGarden(Model.newGarden(),source,1700000000000).residents;
        residents.forEach(function(resident){resident.growth=1;});
        return {residents:residents,colors:Model.palette("dusk",20),hour:20,weather:Model.weather(source)};
    }
    function path() { return prefix+"-"+(sequence++)+".png"; }
    function init() {
        failOnWarning(/.*/);
        subject=createTemporaryObject(cardComponent,tests,{card:input()});
        verify(subject!==null);
        tryCompare(subject,"ready",true,4000);
    }
    function savedImage(location) {
        var item=createTemporaryObject(imageComponent,tests,{source:"file://"+location});
        tryCompare(item,"status",Image.Ready,3000);
        return item;
    }
    function save(location) {
        var result=null;
        verify(subject.capture(location,function(value){result=value;}));
        tryVerify(function(){return result!==null;},4000);
        verify(result.ok && !result.cancelled,result.error);
        compare(subject.busy,false);
        return result;
    }
    function test_native_dimensions_and_complete_first_frame() {
        var data=input();
        data.colors.leaf="#f06530"; data.colors.leafLight="#f06530"; data.colors.leafDark="#f06530";
        subject.card=data;
        tryCompare(subject,"ready",true,4000);
        var location=path(); save(location);
        var image=savedImage(location);
        compare(image.sourceSize.width,1800); compare(image.sourceSize.height,1100);
        var pixels=grabImage(image), orange=0;
        for(var x=250;x<360;x+=10)for(var y=150;y<240;y+=10)
            if(pixels.red(x,y)>pixels.green(x,y)*1.2 && pixels.red(x,y)>pixels.blue(x,y)*1.2)orange++;
        verify(orange>10,"The saved first frame must contain the finished botanical texture");
        console.log("POSTCARD_EXPORT "+location);
    }
    function test_source_updates_do_not_change_the_frozen_preview() {
        var live=input(); subject.card=live;
        tryCompare(subject,"ready",true,4000);
        var state=JSON.stringify(subject.snapshot), before=grabImage(subject);
        live.residents[0].name="A new private process name";
        live.residents[0].cpu=99; live.residents[0].growth=.1;
        live.colors.bg="#ff0000"; live.hour=12; live.weather.rain=1;
        wait(60);
        compare(JSON.stringify(subject.snapshot),state);
        verify(grabImage(subject).equals(before));
        verify(!JSON.stringify(subject.snapshot).includes("private"));
    }
    function test_different_names_and_history_produce_identical_saved_pixels() {
        var first=input(); first.residents[0].name="Private name one"; first.notes=[{text:"secret activity"}];
        subject.card=first; tryCompare(subject,"ready",true,4000);
        var firstPath=path(); save(firstPath);
        var firstPixels=grabImage(savedImage(firstPath));
        var second=input(); second.residents[0].name="Totally different private name";
        second.residents[0].memoryBytes=888888; second.notes=[{text:"different secret"}];
        subject.card=second; tryCompare(subject,"ready",true,4000);
        var secondPath=path(); save(secondPath);
        verify(grabImage(savedImage(secondPath)).equals(firstPixels));
    }
    function test_overlap_and_cancel_prevent_a_late_save() {
        var location=path(); save(location);
        var before=grabImage(savedImage(location));
        var changed=input(); changed.colors.bg="#ff0000"; subject.card=changed;
        tryCompare(subject,"ready",true,4000);
        var callbacks=[];
        verify(subject.capture(location,function(result){callbacks.push(result);}));
        verify(!subject.capture(path(),function(result){callbacks.push(result);}));
        verify(subject.cancelCapture());
        compare(callbacks.length,1); verify(callbacks[0].cancelled && !callbacks[0].ok);
        wait(200); compare(callbacks.length,1); compare(subject.busy,false);
        verify(grabImage(savedImage(location)).equals(before));
    }
    function test_destroy_during_grab_cannot_overwrite_the_previous_file() {
        var location=path(); save(location);
        var before=grabImage(savedImage(location));
        var changed=input(); changed.colors.bg="#ff0000"; subject.card=changed;
        tryCompare(subject,"ready",true,4000);
        verify(subject.capture(location,function(result){}));
        subject.destroy(); subject=null;
        wait(200);
        verify(grabImage(savedImage(location)).equals(before));
    }
    function test_failed_save_releases_the_operation_and_reports_once() {
        var callbacks=[];
        verify(subject.capture(prefix+"-missing-directory/postcard.png",function(result){callbacks.push(result);}));
        tryVerify(function(){return callbacks.length>0;},4000);
        compare(callbacks.length,1); verify(!callbacks[0].ok && !callbacks[0].cancelled);
        compare(callbacks[0].error,"save_failed"); compare(subject.busy,false);
        save(path());
    }
    function test_unready_or_invalid_requests_are_not_accepted() {
        var callbacks=0;
        verify(!subject.capture("relative.png",function(){callbacks++;}));
        verify(!subject.capture("/tmp/not-a-png.jpg",function(){callbacks++;}));
        subject.card=null;
        verify(!subject.ready);
        verify(!subject.capture(path(),function(){callbacks++;}));
        compare(callbacks,0); verify(!subject.busy);
    }
}
