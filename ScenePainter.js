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

function paintPlant(c,p,resident,opening,rasterScale,form) {
    beginCanvas(c,256,260,rasterScale);
    if(!resident)return;
    form=form||plantForm(resident.key,resident.category,3);
    c.save();c.translate(128,244);
    form.stems.forEach(function(stem) {
        var a=stem.points;c.beginPath();c.moveTo(a[0],a[1]);
        if(a.length===8)c.bezierCurveTo(a[2],a[3],a[4],a[5],a[6],a[7]);
        else if(a.length===6)c.quadraticCurveTo(a[2],a[3],a[4],a[5]);
        else c.lineTo(a[2],a[3]);
        c.strokeStyle=stem.role==="trunk"?"#a8936c":p[stem.role];c.lineWidth=stem.width;c.stroke();
    });
    form.leaves.forEach(function(l){leaf(c,l.x,l.y,l.size,l.angle,p[l.role]);});
    form.crowns.forEach(function(b) {
        ellipse(c,b.x,b.y,b.rx,b.ry,p[b.role]);
        c.globalAlpha=.2;leaf(c,b.x+4,b.y+4,18,-.5,p.leafLight);c.globalAlpha=1;
    });
    form.specks.forEach(function(b){ellipse(c,b.x,b.y,1.3,1.3,p.gold);});
    form.blooms.forEach(function(b) {
        var x=b.x,y=b.y;
        if(form.category==="agent") {
            var gl=c.createRadialGradient(x,y,0,x,y,23);gl.addColorStop(0,p.gold);gl.addColorStop(1,"transparent");
            c.globalAlpha=.15;c.fillStyle=gl;c.fillRect(x-25,y-25,50,50);c.globalAlpha=1;
            var spread=.7+(1-opening)*.3;
            path(c,[[x,y-12],[x+10*spread,y-3],[x+7*spread,y+10],[x,y+14],[x-7*spread,y+10],[x-10*spread,y-3]],p.flower);
            stroke(c,x,y-10,x,y+10,p.gold,1);ellipse(c,x,y+1,3,4,"#f4dca5");
        } else if(form.category==="media") {
            spread=.65+.35*opening;
            c.beginPath();c.moveTo(x-7*spread,y+5);c.bezierCurveTo(x-6*spread,y-15,x+6*spread,y-15,x+8*spread,y+5);c.quadraticCurveTo(x,y+1,x-7*spread,y+5);
            c.fillStyle=p[b.role];c.fill();ellipse(c,x,y+4,7*spread,2,p.gold);
        } else if(form.category==="system") {
            var rr=b.radius;
            c.beginPath();c.moveTo(x-rr,y);c.bezierCurveTo(x-rr,y-rr*1.7,x+rr,y-rr*1.7,x+rr,y);c.quadraticCurveTo(x,y+5,x-rr,y);
            c.fillStyle=p[b.role];c.fill();ellipse(c,x-3,y-7,1.5,1.1,p.ink);ellipse(c,x+4,y-4,1,1,p.ink);
        } else ellipse(c,x,y,3,3,p.flower);
    });
    c.restore();
}

// A form is generated only when identity/category/maturity changes. The painter
// and pointer resolver share it, so empty Canvas pixels never become buttons.
function plantForm(key,category,maturity) {
    var r=rng(hash(String(key))),stage=Math.max(0,Math.min(3,Math.floor(maturity)||0));
    var f={category:category,stems:[],leaves:[],crowns:[],specks:[],blooms:[],segments:[]};
    var i,j,x,y,h,dx,angle,order,count,allowed={};
    if(category==="browser") {
        var height=[.82,.9,.96,1][stage],spread=[.72,.84,.94,1][stage];
        addStem(f,[-4,0,4,-45*height,-8,-106*height,6,-157*height],5,"trunk");
        count=[4,7,10,12][stage];
        for(i=0;i<12;i++) {
            angle=i*2.399;var rad=28+Math.sqrt(r())*45;
            x=Math.cos(angle)*rad*spread;y=(-139+Math.sin(angle)*rad*.64)*height;
            var rx=20+r()*14,ry=16+r()*13;
            if(i>=count)continue;
            addStem(f,[1,-100*height,x,y],1.1,"rock");
            f.crowns.push({x:x,y:y,rx:rx*(.78+stage*.0733),ry:ry*(.78+stage*.0733),role:i%3===0?"leafLight":i%3===1?"leaf":"leafDark"});
        }
        for(i=0;i<30;i++) {
            angle=r()*Math.PI*2;rad=r()*59;
            if(stage>=2 && i<(stage===2?12:30))f.specks.push({x:Math.cos(angle)*rad*spread,y:(-141+Math.sin(angle)*rad*.6)*height});
        }
        addStem(f,[-2,-1,-18,4],2,"rock");addStem(f,[0,0,17,3],2,"rock");
    } else if(category==="editor" || category==="terminal") {
        order=[3,2,4,1,5,0,6];count=[3,5,6,7][stage];
        for(i=0;i<count;i++)allowed[order[i]]=true;
        for(i=0;i<7;i++) {
            angle=-1.1+i*.34;var length=55+r()*42;
            if(!allowed[i])continue;
            var cp=rotated(14,-length*.55,angle),tip=rotated(0,-length,angle);
            addStem(f,[0,0,cp.x,cp.y,tip.x,tip.y],1.1,"gold");
            for(j=1;j<8;j++) {
                var fraction=j/8,yy=-fraction*length,xx=Math.sin(fraction*Math.PI)*6,sz=(1-fraction)*18+4;
                var a=rotated(xx,yy,angle),b=rotated(xx,yy-3,angle);
                f.leaves.push({x:a.x,y:a.y,size:sz,angle:angle-1,role:i%2?"leaf":"leafLight"});
                f.leaves.push({x:b.x,y:b.y,size:sz,angle:angle+.95,role:i%2?"leafLight":"leaf"});
            }
        }
    } else if(category==="agent") {
        order=[1,2,0,3];count=[2,3,4,4][stage];for(i=0;i<count;i++)allowed[order[i]]=true;
        for(i=0;i<4;i++) {
            dx=(i-1.5)*22;h=76+r()*52;if(!allowed[i])continue;
            addStem(f,[0,0,dx*1.4,-h*.35,dx-9,-h,dx,-h],2,"leaf");
            f.leaves.push({x:dx*.6,y:-h*.35,size:26,angle:dx<0?-1:1,role:"leafLight"});
            if(stage===3)f.leaves.push({x:dx*.3,y:-h*.18,size:13,angle:dx<0?.75:-.75,role:"leaf"});
            f.blooms.push({x:dx,y:-h});
        }
    } else {
        order=[2,1,3,0,4];count=[2,3,4,5][stage];for(i=0;i<count;i++)allowed[order[i]]=true;
        for(i=0;i<5;i++) {
            if(category==="system") {
                dx=(i-2)*13;h=13+r()*28;var radius=8+r()*10;
                if(!allowed[i])continue;
                addStem(f,[dx,0,dx-2,-h],3,"leafLight");
                f.blooms.push({x:dx,y:-h,radius:radius,role:i%2?"flower":"gold"});
            } else if(category==="media") {
                dx=(i-2)*14;h=49+r()*47;if(!allowed[i])continue;
                addStem(f,[0,0,dx,-h],1.5,"leaf");
                f.leaves.push({x:dx*.6,y:-h*.45,size:23,angle:dx<0?-.8:.8,role:"leaf"});
                f.blooms.push({x:dx,y:-h,role:i%2?"flower":"leafLight"});
            } else {
                h=34+r()*39;dx=(i-2)*14;if(!allowed[i])continue;
                addStem(f,[0,0,dx,-h],1.5,"leaf");
                for(j=0;j<3;j++) {
                    fraction=.3+j*.23;
                    f.leaves.push({x:dx*fraction,y:-h*fraction,size:20-j*3,angle:j%2?-.9:.9,role:i%2?"leaf":"leafLight"});
                }
                f.blooms.push({x:dx,y:-h});
            }
        }
    }
    cacheHitGeometry(f);
    return f;
}
function rotated(x,y,angle) {return {x:x*Math.cos(angle)-y*Math.sin(angle),y:x*Math.sin(angle)+y*Math.cos(angle)};}
function addStem(form,points,width,role) {
    form.stems.push({points:points,width:width,role:role});
    var previous={x:points[0],y:points[1]},steps=points.length===4?1:8;
    for(var i=1;i<=steps;i++) {
        var t=i/steps,u=1-t,next;
        if(points.length===8)next={x:u*u*u*points[0]+3*u*u*t*points[2]+3*u*t*t*points[4]+t*t*t*points[6],y:u*u*u*points[1]+3*u*u*t*points[3]+3*u*t*t*points[5]+t*t*t*points[7]};
        else if(points.length===6)next={x:u*u*points[0]+2*u*t*points[2]+t*t*points[4],y:u*u*points[1]+2*u*t*points[3]+t*t*points[5]};
        else next={x:points[2],y:points[3]};
        form.segments.push({x1:previous.x,y1:previous.y,x2:next.x,y2:next.y,radius:width/2});previous=next;
    }
}
function cacheHitGeometry(form) {
    var shapes=[],i,b;
    for(i=0;i<form.crowns.length;i++) {b=form.crowns[i];shapes.push({x:b.x,y:b.y,rx:b.rx,ry:b.ry,cos:1,sin:0});}
    for(i=0;i<form.leaves.length;i++) {
        b=form.leaves[i];var center=rotated(0,-b.size*.5,b.angle);
        shapes.push({x:b.x+center.x,y:b.y+center.y,rx:b.size*.35,ry:b.size*.52,cos:Math.cos(b.angle),sin:Math.sin(b.angle)});
    }
    for(i=0;i<form.blooms.length;i++) {
        b=form.blooms[i];
        var rx=form.category==="agent"?10:form.category==="media"?8:form.category==="system"?b.radius:3;
        var ry=form.category==="agent"?15:form.category==="media"?10:form.category==="system"?b.radius*.8:3;
        var cy=b.y-(form.category==="system"?b.radius*.48:form.category==="media"?3:0);
        shapes.push({x:b.x,y:cy,rx:rx,ry:ry,cos:1,sin:0});
    }
    var bounds={left:0,right:0,top:0,bottom:0};
    shapes.forEach(function(shape) {
        var ex=Math.abs(shape.rx*shape.cos)+Math.abs(shape.ry*shape.sin);
        var ey=Math.abs(shape.rx*shape.sin)+Math.abs(shape.ry*shape.cos);
        bounds.left=Math.min(bounds.left,shape.x-ex);bounds.right=Math.max(bounds.right,shape.x+ex);
        bounds.top=Math.min(bounds.top,shape.y-ey);bounds.bottom=Math.max(bounds.bottom,shape.y+ey);
    });
    form.segments.forEach(function(line) {
        bounds.left=Math.min(bounds.left,line.x1-line.radius,line.x2-line.radius);bounds.right=Math.max(bounds.right,line.x1+line.radius,line.x2+line.radius);
        bounds.top=Math.min(bounds.top,line.y1-line.radius,line.y2-line.radius);bounds.bottom=Math.max(bounds.bottom,line.y1+line.radius,line.y2+line.radius);
    });
    form.hitEllipses=shapes;form.hitBounds=bounds;
}
function containsPlant(form,x,y,padding) {
    var pad=Math.max(0,Math.min(5,padding||0)),i,b,bounds=form.hitBounds;
    if(x<bounds.left-pad || x>bounds.right+pad || y<bounds.top-pad || y>bounds.bottom+pad)return false;
    for(i=0;i<form.hitEllipses.length;i++) {
        b=form.hitEllipses[i];var dx=x-b.x,dy=y-b.y;
        var xx=(dx*b.cos+dy*b.sin)/(b.rx+pad),yy=(-dx*b.sin+dy*b.cos)/(b.ry+pad);
        if(xx*xx+yy*yy<=1)return true;
    }
    for(i=0;i<form.segments.length;i++) {
        b=form.segments[i];dx=b.x2-b.x1;dy=b.y2-b.y1;
        var t=Math.max(0,Math.min(1,((x-b.x1)*dx+(y-b.y1)*dy)/(dx*dx+dy*dy||1)));
        dx=x-b.x1-t*dx;dy=y-b.y1-t*dy;
        if(dx*dx+dy*dy<=Math.pow(b.radius+pad,2))return true;
    }
    return false;
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
