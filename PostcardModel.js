.pragma library

// A postcard owns only the values needed to draw its art. Names, readings,
// timestamps, process counts, interfaces, and journal entries never enter it.
var roles = ["bg","panel","surface","line","ink","muted","gold","leaf","leafLight","leafDark","flower","sky","water","soil","rock"];
var defaultColors = ["#111b20","#162329","#1c2b30","#304247","#e6e8d8","#9cacaa","#dfbc7b","#77ad8d","#b0ceb0","#315b50","#eeb589","#213b42","#468d94","#2b302b","#63776c"];
var categories = ["browser","editor","terminal","agent","media","system","other"];
function finite(value, fallback) { return typeof value === "number" && isFinite(value) ? value : fallback; }
function clamp(value, low, high) { return Math.max(low, Math.min(high, value)); }
function cleanKey(value) { return typeof value === "string" ? value.replace(/[\x00-\x1f\x7f-\x9f]/g, "").slice(0,64) : "resident"; }
function hash(text) {
    var h=2166136261;
    for(var i=0;i<text.length;i++)h=Math.imul(h^text.charCodeAt(i),16777619);
    return (h>>>0).toString(16);
}
function create(input) {
    var source=input && typeof input==="object" ? input : {};
    var incomingColors=source.colors && typeof source.colors==="object" ? source.colors : {};
    var colors={}, colorKey="";
    roles.forEach(function(role,index) {
        var value=incomingColors[role];
        colors[role]=typeof value==="string" && /^#[0-9a-fA-F]{6}$/.test(value) ? value.toLowerCase() : defaultColors[index];
        colorKey+=colors[role];
    });
    // Cache identity derives from colors, never from user-visible labels.
    colors.name="postcard-"+hash(colorKey);
    var residents=[], occupied=[false,false,false,false,false,false,false];
    var sourceResidents=Array.isArray(source.residents)?source.residents:[];
    for(var i=0;i<Math.min(32,sourceResidents.length);i++) {
        var resident=sourceResidents[i];
        if(!resident || !Number.isInteger(resident.slot) || resident.slot<0 || resident.slot>6 || occupied[resident.slot])continue;
        occupied[resident.slot]=true;
        residents.push(Object.freeze({
            key:cleanKey(resident.key), category:categories.indexOf(resident.category)>=0?resident.category:"other",
            slot:resident.slot, growth:clamp(finite(resident.growth,.35),0,1),
            cpu:typeof resident.cpu==="number" && isFinite(resident.cpu)?clamp(resident.cpu,0,100):null,
            missing:clamp(finite(resident.missing,0),0,18)
        }));
    }
    residents.sort(function(a,b){return a.slot-b.slot;});
    var sourceWeather=source.weather && typeof source.weather==="object"?source.weather:{};
    var activity=clamp(finite(sourceWeather.activity,0),0,1);
    return Object.freeze({ version:1, residents:Object.freeze(residents), colors:Object.freeze(colors),
        hour:((finite(source.hour,20)%24)+24)%24,
        weather:Object.freeze({rain:clamp(finite(sourceWeather.rain,0),0,1), activity:activity,
            water:clamp(finite(sourceWeather.water,0),0,1), particles:Math.round(5+activity*19)})
    });
}
