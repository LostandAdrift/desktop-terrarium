.pragma library

// Original procedural botanical illustration. Ground, plants, bridge, and glass
// are cached separately; motion only transforms their QtQuick scene-graph items.
function rng(seed) { var n=seed>>>0; return function() { n=(Math.imul(n,1664525)+1013904223)>>>0; return n/4294967296; }; }
function hash(s) { var n=0; for(var i=0;i<s.length;i++) n=(Math.imul(n,31)+s.charCodeAt(i))|0; return n>>>0; }
function ellipse(c,x,y,rx,ry,fill) {
    c.save(); c.translate(x,y); c.scale(rx,ry); c.beginPath(); c.arc(0,0,1,0,Math.PI*2); c.fillStyle=fill; c.fill(); c.restore();
}
function path(c,points,fill,stroke,lineWidth) {
    c.beginPath(); c.moveTo(points[0][0],points[0][1]);
    for(var i=1;i<points.length;i++) c.lineTo(points[i][0],points[i][1]);
    c.closePath(); if(fill){c.fillStyle=fill;c.fill();} if(stroke){c.strokeStyle=stroke;c.lineWidth=lineWidth||1;c.stroke();}
}
function stroke(c,x1,y1,x2,y2,color,width) { c.beginPath();c.moveTo(x1,y1);c.lineTo(x2,y2);c.strokeStyle=color;c.lineWidth=width||1;c.stroke(); }
function leaf(c,x,y,size,angle,color) {
    c.save();c.translate(x,y);c.rotate(angle);c.beginPath();c.moveTo(0,0);
    c.bezierCurveTo(-size*0.62,-size*0.38,-size*0.42,-size*0.92,0,-size);
    c.bezierCurveTo(size*0.42,-size*0.8,size*0.5,-size*0.35,0,0);
    c.fillStyle=color;c.fill();c.restore();
}
function glassPath(c) {
    c.beginPath();c.moveTo(154,425);c.bezierCurveTo(129,395,142,325,151,232);
    c.bezierCurveTo(163,94,273,45,450,45);c.bezierCurveTo(629,45,737,94,749,232);
    c.bezierCurveTo(758,325,771,395,746,425);c.bezierCurveTo(700,486,202,486,154,425);c.closePath();
}
function beginCanvas(c,width,height,rasterScale) {
    var scale=typeof rasterScale==="number" && isFinite(rasterScale)?Math.max(1,Math.min(2,rasterScale)):1;
    c.reset();c.clearRect(0,0,width*scale,height*scale);c.scale(scale,scale);
    c.lineCap="round";c.lineJoin="round";
}
function paintGround(c,p,water,sky,rasterScale) {
    beginCanvas(c,900,550,rasterScale);
    var r=rng(1209);
    var interior=sky.interior>=0?sky.interior:sky.daylight;
    var sunA=sky.sun>0?sky.sun:0;
    var moonA=sky.moon>0?sky.moon:0;
    var starlight=sky.stars>0?sky.stars:0;
    var horizon=sky.horizon>=0?sky.horizon:sky.warmth;
    // Fine stars and instrument registration marks outside the vessel.
    // Stars follow local night only; they must not remain at full day.
    for(var i=0;i<46;i++) {
        var sx=80+r()*740,sy=25+r()*440;
        c.globalAlpha=(0.10+r()*0.17)*starlight;ellipse(c,sx,sy,0.55,0.55,p.gold);
    }
    c.globalAlpha=1;
    for(i=0;i<4;i++) {
        var tx=i%2?811:89,ty=i<2?118:442;
        stroke(c,tx-5,ty,tx+5,ty,p.line,1);stroke(c,tx,ty-5,tx,ty+5,p.line,1);
    }
    // Shadow, turned wooden plinth, and its concentric brass edges.
    for(i=0;i<8;i++) {c.globalAlpha=0.04;ellipse(c,450,492+i*2,270+i*8,31+i*3,"#000000");}
    c.globalAlpha=1;
    c.beginPath();c.moveTo(153,448);c.lineTo(153,473);c.bezierCurveTo(180,532,720,532,747,473);c.lineTo(747,448);c.closePath();
    var wood=c.createLinearGradient(0,441,0,513);wood.addColorStop(0,"#524832");wood.addColorStop(0.4,"#292d27");wood.addColorStop(1,"#101b19");
    c.fillStyle=wood;c.fill();ellipse(c,450,450,297,66,"#25352e");
    c.beginPath();c.ellipse(153,384,594,132);c.strokeStyle=p.gold;c.globalAlpha=.52;c.lineWidth=1;c.stroke();c.globalAlpha=1;
    c.beginPath();c.moveTo(170,476);c.bezierCurveTo(262,527,642,527,730,476);c.strokeStyle=p.gold;c.lineWidth=1;c.globalAlpha=.24;c.stroke();c.globalAlpha=1;
    // Curved glass atmosphere, clipped before drawing the ecosystem.
    glassPath(c);var glass=c.createLinearGradient(0,40,0,485);glass.addColorStop(0,p.sky);glass.addColorStop(.65,p.bg);glass.addColorStop(1,p.surface);
    c.globalAlpha=.7;c.fillStyle=glass;c.fill();c.globalAlpha=1;
    c.save();glassPath(c);c.clip();
    // Local time changes the light and the celestial body, independently of the
    // chosen palette. Minute-sized updates keep this texture off the frame loop.
    var daylight=c.createLinearGradient(0,48,0,430);
    daylight.addColorStop(0,"#f2e6b4");daylight.addColorStop(.42,"#e8d49a");daylight.addColorStop(1,"transparent");
    c.globalAlpha=interior*.44;c.fillStyle=daylight;c.fillRect(140,45,620,400);c.globalAlpha=1;
    var well=c.createLinearGradient(0,210,0,430);
    well.addColorStop(0,"transparent");well.addColorStop(1,"#eadba8");
    c.globalAlpha=interior*.20;c.fillStyle=well;c.fillRect(160,200,580,240);c.globalAlpha=1;
    if(horizon>0) {
        var band=c.createLinearGradient(0,250,0,400);
        band.addColorStop(0,"transparent");band.addColorStop(.65,"#e8b45a");band.addColorStop(1,"transparent");
        c.globalAlpha=horizon*.18;c.fillStyle=band;c.fillRect(150,250,600,160);c.globalAlpha=1;
        var hx=sky.sunX,hy=sky.sunY+22;
        var hglow=c.createRadialGradient(hx,hy,6,hx,hy,200);
        hglow.addColorStop(0,"#f3c56a");hglow.addColorStop(.4,"#e8b15a");hglow.addColorStop(1,"transparent");
        c.fillStyle=hglow;c.globalAlpha=horizon*.22;c.fillRect(hx-210,hy-210,420,420);c.globalAlpha=1;
    }
    if(moonA>0) {
        var moonGlow=c.createRadialGradient(567,138,6,567,138,90);
        moonGlow.addColorStop(0,p.gold);moonGlow.addColorStop(1,"transparent");
        c.fillStyle=moonGlow;c.globalAlpha=moonA*.12;c.fillRect(477,48,180,180);c.globalAlpha=1;
    }
    if(sunA>0) {
        var flatten=1-horizon*.18, rx=26+6*interior, ry=rx*flatten;
        var sunGlow=c.createRadialGradient(sky.sunX,sky.sunY,6,sky.sunX,sky.sunY,78);
        sunGlow.addColorStop(0,"#fff4c4");sunGlow.addColorStop(.32,"#f0c14a");sunGlow.addColorStop(1,"transparent");
        c.globalAlpha=sunA*(.22+interior*.16);c.fillStyle=sunGlow;c.fillRect(sky.sunX-80,sky.sunY-80,160,160);
        c.globalAlpha=sunA;ellipse(c,sky.sunX,sky.sunY,rx,ry,"#f3d266");
        c.globalAlpha=sunA*horizon*.5;ellipse(c,sky.sunX,sky.sunY,rx,ry,"#e8963c");
        c.globalAlpha=sunA;ellipse(c,sky.sunX,sky.sunY-2,rx*.55,ry*.5,"#fff6cc");
    }
    if(moonA>0) {
        // Fill a real crescent so its cutout never paints over the daylight gradient.
        c.globalAlpha=moonA;
        c.beginPath();c.arc(567,138,26,-1.949,.378,true);c.arc(576,129,24,.887,-2.458,false);c.closePath();c.fillStyle=p.gold;c.fill();
    }
    c.globalAlpha=1;
    c.globalAlpha=.16;
    for(i=0;i<8;i++) {var dx=220+i*65;stroke(c,dx,390,dx-8,230+r()*40,p.leaf,2);for(var j=0;j<4;j++){leaf(c,dx-4,260+j*27,36,j%2?-.8:.8,p.leafDark);}}
    c.globalAlpha=1;
    // Cutaway island: irregular strata give the garden physical depth.
    c.beginPath();c.moveTo(179,389);c.bezierCurveTo(255,352,637,350,718,394);
    c.bezierCurveTo(709,443,641,486,528,493);c.bezierCurveTo(391,516,242,485,190,436);c.closePath();c.fillStyle=p.soil;c.fill();
    path(c,[[190,412],[271,431],[300,477],[241,462]],"#354334");
    path(c,[[271,431],[419,450],[411,498],[300,477]],"#252f29");
    path(c,[[419,450],[571,445],[544,491],[411,498]],"#1d2b28");
    path(c,[[571,445],[710,411],[659,462],[544,491]],"#344135");
    // Roots, small stones and strata, deterministic so they never flicker.
    r=rng(7091);
    for(i=0;i<55;i++) {
        var x=214+r()*473,y=416+r()*61;
        if(Math.pow((x-450)/240,2)+Math.pow((y-410)/92,2)<1) {
            c.globalAlpha=.18+r()*.18;ellipse(c,x,y,1+r()*3,.7+r()*1.5,p.rock);
        }
    }
    c.globalAlpha=.3;
    for(i=0;i<8;i++) {
        x=270+i*50;c.beginPath();c.moveTo(x,414);c.bezierCurveTo(x+8,435,x-17,448,x+4,476);
        c.strokeStyle=p.gold;c.lineWidth=.8;c.stroke();stroke(c,x,450,x+10,443,p.gold,.7);
    }
    c.globalAlpha=1;
    // Moss lip and winding stream.
    c.beginPath();c.moveTo(177,389);c.bezierCurveTo(199,361,283,341,350,349);c.bezierCurveTo(412,323,462,345,503,342);
    c.bezierCurveTo(602,335,685,363,720,391);c.bezierCurveTo(699,433,598,455,455,459);
    c.bezierCurveTo(306,459,202,436,177,389);c.closePath();
    var moss=c.createLinearGradient(0,340,0,461);moss.addColorStop(0,p.leafDark);moss.addColorStop(.7,"#354f3f");moss.addColorStop(1,"#769078");c.fillStyle=moss;c.fill();
    c.globalAlpha=interior*.12;c.fillStyle="#ead9a4";c.fill();c.globalAlpha=1;
    c.beginPath();c.moveTo(187,400);c.bezierCurveTo(264,462,622,483,711,402);c.strokeStyle=p.leafLight;c.globalAlpha=.44;c.lineWidth=2;c.stroke();c.globalAlpha=1;
    c.beginPath();c.moveTo(459,354);c.bezierCurveTo(413,375,494,394,472,411);c.bezierCurveTo(451,431,522,439,590,431);
    c.bezierCurveTo(660,421,658,397,615,392);c.bezierCurveTo(570,386,531,393,517,379);c.bezierCurveTo(506,366,487,354,459,354);c.closePath();
    var pool=c.createLinearGradient(0,367,0,440);pool.addColorStop(0,p.sky);pool.addColorStop(1,p.water);c.fillStyle=pool;c.fill();
    if(interior>0) {
        var sheen=c.createLinearGradient(0,367,0,440);
        sheen.addColorStop(0,"#f0e7c0");sheen.addColorStop(.4,"#d5e0b8");sheen.addColorStop(1,"transparent");
        c.globalAlpha=interior*.32;c.fillStyle=sheen;c.fill();
        c.globalAlpha=interior*.18;ellipse(c,548,398,16,5,"#f4ecc0");
        if(sunA>0.3){c.globalAlpha=sunA*.12;ellipse(c,560+(sky.sunX-562)*0.12,410,11,4,"#f6e08a");}
        c.globalAlpha=1;
    }
    for(i=0;i<8;i++){c.globalAlpha=.16+i*.022+interior*.08;var yy=400+i*4;stroke(c,525-i*2,yy,610-i*4,yy,p.leafLight,.7);}c.globalAlpha=1;
    // The water level is memory used. A subtle internal contour, not a warning.
    c.globalAlpha=.22;ellipse(c,565,416-water*9,43+water*16,6+water*3,p.water);c.globalAlpha=1;
    r=rng(210);
    for(i=0;i<150;i++) {
        x=195+r()*510;y=358+r()*87;
        var onGround=Math.pow((x-450)/267,2)+Math.pow((y-399)/57,2)<1;
        if(onGround && !(x>455 && x<635 && y>375 && y<433)) {
            c.globalAlpha=.3+r()*.45;ellipse(c,x,y,1+r()*2,.7+r(),i%3?p.leaf:p.leafLight);
        }
    }c.globalAlpha=1;
    // Some perennial life remains even before the first telemetry sample.
    fern(c,200,393,.44,p,rng(14));fern(c,700,398,.5,p,rng(30));
    mushrooms(c,294,424,.42,p,rng(20));mushrooms(c,618,451,.38,p,rng(17));
    c.restore();
}

function paintPlant(c,p,resident,opening,rasterScale) {
    beginCanvas(c,256,260,rasterScale);
    if(!resident)return;
    var seed=rng(hash(resident.key));
    if(resident.category==="browser")tree(c,128,244,1,p,seed);
    else if(resident.category==="agent")lantern(c,128,244,1,p,seed,opening);
    else if(resident.category==="editor" || resident.category==="terminal")fern(c,128,244,1,p,seed);
    else if(resident.category==="media")bells(c,128,244,1,p,seed,opening);
    else if(resident.category==="system")mushrooms(c,128,244,1,p,seed);
    else sprout(c,128,244,1,p,seed);
}

function lanternTips(key) {
    var r=rng(hash(key)),tips=[];
    for(var i=0;i<4;i++)tips.push({x:128+(i-1.5)*22,y:244-76-r()*52});
    return tips;
}

function paintBridge(c,p,rasterScale) {
    beginCanvas(c,900,550,rasterScale);
    // A small footbridge, and a ladder of stepping stones.
    c.save();c.translate(491,390);c.rotate(-.28);
    for(var i=0;i<7;i++){c.fillStyle=i%2?"#a3946d":"#867d5c";c.fillRect(-28+i*8,-6,6,22);}
    stroke(c,-32,-7,26,-7,"#d3c396",1.5);stroke(c,-32,17,26,17,"#d3c396",1.5);c.restore();
    for(i=0;i<5;i++)ellipse(c,394+i*9,420-i*4,6,2.4,p.rock);
}

function paintGlass(c,p,rasterScale) {
    beginCanvas(c,900,550,rasterScale);
    // Glass edge, reflected slivers, and a brass hanging loop.
    glassPath(c);c.lineWidth=1.2;c.strokeStyle=p.leafLight;c.globalAlpha=.34;c.stroke();c.globalAlpha=1;
    c.save();glassPath(c);c.clip();
    c.beginPath();c.moveTo(191,329);c.bezierCurveTo(170,181,242,91,342,79);c.strokeStyle="#ecf6e4";c.lineWidth=5;c.globalAlpha=.085;c.stroke();
    c.beginPath();c.moveTo(207,207);c.bezierCurveTo(222,163,243,134,273,120);c.lineWidth=2;c.globalAlpha=.14;c.stroke();
    c.beginPath();c.moveTo(703,272);c.bezierCurveTo(714,324,718,365,702,398);c.lineWidth=3;c.globalAlpha=.08;c.stroke();c.restore();c.globalAlpha=1;
    c.beginPath();c.arc(450,31,12,0,Math.PI*2);c.strokeStyle=p.gold;c.lineWidth=3;c.stroke();ellipse(c,450,47,20,4,p.gold);
    ellipse(c,450,47,14,2,"#6b634b");
    // Maker's plaque, deliberately separate from live data labels.
    c.fillStyle="#34413a";c.fillRect(412,489,76,17);c.strokeStyle=p.gold;c.globalAlpha=.45;c.strokeRect(412,489,76,17);c.globalAlpha=1;
    c.font="8px sans-serif";c.fillStyle=p.gold;c.textAlign="center";c.fillText("T E R R A R I U M",450,500);
}

function tree(c,x,y,s,p,r) {
    c.save();c.translate(x,y);c.scale(s,s);
    c.beginPath();c.moveTo(-4,0);c.bezierCurveTo(4,-45,-8,-106,6,-157);c.strokeStyle="#a8936c";c.lineWidth=5;c.stroke();
    for(var i=0;i<12;i++) {
        var angle=i*2.399, rad=28+Math.sqrt(r())*45;
        var lx=Math.cos(angle)*rad,ly=-139+Math.sin(angle)*rad*.64;
        stroke(c,1,-100,lx,ly,p.rock,1.1);
        ellipse(c,lx,ly,20+r()*14,16+r()*13,i%3===0?p.leafLight:i%3===1?p.leaf:p.leafDark);
        c.globalAlpha=.2;leaf(c,lx+4,ly+4,18,-.5,p.leafLight);c.globalAlpha=1;
    }
    for(i=0;i<30;i++){var a=r()*Math.PI*2,rr=r()*59;ellipse(c,Math.cos(a)*rr,-141+Math.sin(a)*rr*.6,1.3,1.3,p.gold);}
    stroke(c,-2,-1,-18,4,p.rock,2);stroke(c,0,0,17,3,p.rock,2);c.restore();
}
function fern(c,x,y,s,p,r) {
    c.save();c.translate(x,y);c.scale(s,s);
    for(var i=0;i<7;i++) {
        var angle=-1.1+i*.34, length=55+r()*42;
        c.save();c.rotate(angle);c.beginPath();c.moveTo(0,0);c.quadraticCurveTo(14,-length*.55,0,-length);c.strokeStyle=p.gold;c.lineWidth=1.1;c.stroke();
        for(var j=1;j<8;j++) {
            var f=j/8,yy=-f*length,xx=Math.sin(f*Math.PI)*6,sz=(1-f)*18+4;
            leaf(c,xx,yy,sz,-1.0,i%2?p.leaf:p.leafLight);leaf(c,xx,yy-3,sz,.95,i%2?p.leafLight:p.leaf);
        }c.restore();
    }c.restore();
}
function lantern(c,x,y,s,p,r,opening) {
    c.save();c.translate(x,y);c.scale(s,s);
    for(var i=0;i<4;i++) {
        var dx=(i-1.5)*22,h=76+r()*52;
        c.beginPath();c.moveTo(0,0);c.bezierCurveTo(dx*1.4,-h*.35,dx-9,-h,dx,-h);c.strokeStyle=p.leaf;c.lineWidth=2;c.stroke();
        leaf(c,dx*.6,-h*.35,26,dx<0?-1:1,p.leafLight);
        var gl=c.createRadialGradient(dx,-h,0,dx,-h,23);gl.addColorStop(0,p.gold);gl.addColorStop(1,"transparent");
        c.globalAlpha=.15;c.fillStyle=gl;c.fillRect(dx-25,-h-25,50,50);c.globalAlpha=1;
        var spread=opening===undefined?1:.7+(1-opening)*.3;
        path(c,[[dx,-h-12],[dx+10*spread,-h-3],[dx+7*spread,-h+10],[dx,-h+14],[dx-7*spread,-h+10],[dx-10*spread,-h-3]],p.flower);
        stroke(c,dx,-h-10,dx,-h+10,p.gold,1);ellipse(c,dx,-h+1,3,4,"#f4dca5");
    }c.restore();
}
function bells(c,x,y,s,p,r,opening) {
    c.save();c.translate(x,y);c.scale(s,s);
    for(var i=0;i<5;i++) {
        var dx=(i-2)*14,h=49+r()*47;stroke(c,0,0,dx,-h,p.leaf,1.5);
        leaf(c,dx*.6,-h*.45,23,dx<0?-.8:.8,p.leaf);
        var spread=opening===undefined?1:.65+.35*opening;
        c.beginPath();c.moveTo(dx-7*spread,-h+5);c.bezierCurveTo(dx-6*spread,-h-15,dx+6*spread,-h-15,dx+8*spread,-h+5);c.quadraticCurveTo(dx,-h+1,dx-7*spread,-h+5);
        c.fillStyle=i%2?p.flower:p.leafLight;c.fill();ellipse(c,dx,-h+4,7*spread,2,p.gold);
    }c.restore();
}
function mushrooms(c,x,y,s,p,r) {
    c.save();c.translate(x,y);c.scale(s,s);
    for(var i=0;i<5;i++) {
        var dx=(i-2)*13,hh=13+r()*28,rr=8+r()*10;
        stroke(c,dx,0,dx-2,-hh,p.leafLight,3);
        c.beginPath();c.moveTo(dx-rr,-hh);c.bezierCurveTo(dx-rr,-hh-rr*1.7,dx+rr,-hh-rr*1.7,dx+rr,-hh);
        c.quadraticCurveTo(dx,-hh+5,dx-rr,-hh);c.fillStyle=i%2?p.flower:p.gold;c.fill();
        ellipse(c,dx-3,-hh-7,1.5,1.1,p.ink);ellipse(c,dx+4,-hh-4,1,1,p.ink);
    }c.restore();
}
function sprout(c,x,y,s,p,r) {
    c.save();c.translate(x,y);c.scale(s,s);
    for(var i=0;i<5;i++) {
        var h=34+r()*39,dx=(i-2)*14;stroke(c,0,0,dx,-h,p.leaf,1.5);
        for(var j=0;j<3;j++){var f=.3+j*.23;leaf(c,dx*f,-h*f,20-j*3,j%2?-.9:.9,i%2?p.leaf:p.leafLight);}
        ellipse(c,dx,-h,3,3,p.flower);
    }c.restore();
}
