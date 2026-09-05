const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const model = vm.createContext({});
vm.runInContext(fs.readFileSync(`${__dirname}/../Model.js`, 'utf8').replace(/^\.pragma library\s*/, ''), model);
const plain = v => JSON.parse(JSON.stringify(v));

test('rejects unsupported telemetry; unavailable values stay unavailable', () => {
    assert.throws(() => model.normalize({version:2}));
    const s = model.normalize(model.emptySnapshot());
    assert.equal(s.cpu, null); assert.equal(s.memory.percent, null);
    assert.equal(s.network.rxBytesPerSec, null); assert.equal(model.formatRate(null), '—');
});
test('bounds and sanitizes untrusted process data, including prototype-like names', () => {
    const s = plain(model.demoSnapshot(0));
    s.cpu = 234; s.processes = Array(20).fill({key:'__proto__', name:'A\u001b\nB', count:0, cpu:-2, memoryBytes:-8, category:'evil'});
    const out = model.normalize(s);
    assert.equal(out.cpu,100); assert.equal(out.processes.length,1);
    assert.equal(out.processes[0].name,'AB'); assert.equal(out.processes[0].category,'other');
    assert.equal(out.processes[0].memoryBytes,0);
});
test('a changed process ranking preserves resident positions and growth', () => {
    const snap = plain(model.demoSnapshot(0));
    let a = model.updateGarden(model.newGarden(), snap, 0);
    snap.processes.reverse();
    let b = model.updateGarden(a, snap, 2000);
    for (const p of b.residents) {
        const old = a.residents.find(x=>x.key===p.key);
        assert.equal(p.slot,old.slot); assert.ok(p.growth > old.growth);
    }
});
test('temporary absence retains a resident; departure never claims successful completion', () => {
    const snap = plain(model.demoSnapshot(0)); snap.interval=2;
    let state = model.updateGarden(model.newGarden(),snap,0);
    snap.processes = snap.processes.filter(p=>p.key!=='firefox');
    state=model.updateGarden(state,snap,2000);
    assert.ok(state.residents.some(p=>p.key==='firefox'));
    for(let i=0;i<10;i++) state=model.updateGarden(state,snap,4000+i*2000);
    assert.ok(!state.residents.some(p=>p.key==='firefox'));
    assert.ok(state.notes.some(n=>n.kind==='departed'));
    assert.ok(!state.notes.some(n=>/success|completed|finished/i.test(n.text)));
});
test('gaps and suspend do not instantly grow the garden; history is bounded', () => {
    const snap=plain(model.demoSnapshot(0)); snap.interval=999999;
    let state=model.newGarden();
    for(let i=0;i<500;i++) {
        snap.processes=[{...snap.processes[0],key:'resident'+i}];
        state=model.updateGarden(state,snap,i*2000);
        assert.ok(state.residents.length<=7);
        assert.ok(new Set(state.residents.map(p=>p.slot)).size===state.residents.length);
    }
    assert.ok(state.notes.length<=24); assert.ok(state.observedSeconds<=5000);
});
test('weather and display formats stay finite at extreme values', () => {
    const snap=plain(model.demoSnapshot(0)); snap.network.rxBytesPerSec=1e300;
    assert.equal(model.weather(snap).rain,1);
    assert.equal(model.formatBytes(1024),'1.0 KiB'); assert.equal(model.formatBytes(-2),'0 B');
    assert.equal(model.formatPercent(null),'—'); assert.equal(model.duration(3661),'1h 1m');
    assert.equal(model.palette('invalid',5).name,'dusk');
});
test('demo fixture is explicit, deterministic and does not need a real account', () => {
    assert.deepEqual(plain(model.demoSnapshot(3)),plain(model.demoSnapshot(3)));
    assert.deepEqual(plain(model.demoSnapshot(3).network.interfaces),['demo']);
    let state=model.newGarden();
    for(let t=0;t<100;t++)state=model.updateGarden(state,model.demoSnapshot(t),1700000000000+t*2000);
    assert.ok(state.notes.some(n=>n.kind==='arrival'));
    assert.ok(state.notes.some(n=>n.kind==='departed'));
});
test('an unavailable process scan freezes the habitat without manufacturing departures', () => {
    const healthy = plain(model.demoSnapshot(3));
    let state = model.updateGarden(model.newGarden(), healthy, 0);
    const before = plain(state);
    const failed = {...healthy, processes: [], processesAvailable: false, errors: ['process scan incomplete'], cpu: 70};
    for (let i=0;i<100;i++) state=model.updateGarden(state,model.normalize(failed),2000+i*2000);
    assert.deepEqual(plain(state.residents.map(p=>[p.key,p.slot,p.age,p.growth,p.missing])), before.residents.map(p=>[p.key,p.slot,p.age,p.growth,p.missing]));
    assert.deepEqual(plain(state.notes),before.notes);
    assert.ok(state.residents.every(p=>p.unavailable && p.cpu===null && p.memoryBytes===null));
    assert.equal(model.weather(model.normalize(failed)).activity,0.7);
    state=model.updateGarden(state,healthy,202000);
    assert.ok(state.residents.every(p=>!p.unavailable && p.cpu!==null));
    assert.equal(state.notes.length,0);
    assert.deepEqual(plain(state.residents.map(p=>p.slot)),before.residents.map(p=>p.slot));
});
test('a complete empty scan can record departures; legacy failure samples cannot', () => {
    const healthy = plain(model.demoSnapshot(3));
    let state = model.updateGarden(model.newGarden(),healthy,0);
    const legacy = {...healthy, processes:[], errors:['process scan incomplete']};
    delete legacy.processesAvailable;
    assert.equal(model.normalize(legacy).processesAvailable,false);
    const empty = {...healthy, processes:[], processesAvailable:true};
    for(let i=0;i<10;i++)state=model.updateGarden(state,empty,2000+i*2000);
    assert.equal(state.residents.length,0);
    assert.equal(state.notes.filter(n=>n.kind==='departed').length,healthy.processes.length);
});
test('residents unfurl early and keep growing across an observed afternoon', () => {
    const snap = plain(model.demoSnapshot(0));
    snap.processes = [snap.processes[0]];
    let state = model.updateGarden(model.newGarden(), snap, 0);
    const checkpoints = new Map();
    let priorGrowth = state.residents[0].growth;
    for (let elapsed=2; elapsed<=21600; elapsed+=2) {
        state = model.updateGarden(state, snap, elapsed*1000);
        const resident = state.residents[0];
        assert.equal(resident.age, elapsed);
        assert.ok(resident.growth >= priorGrowth && resident.growth <= 1);
        priorGrowth = resident.growth;
        if ([120,600,3600,10800,21600].includes(elapsed)) checkpoints.set(elapsed,resident.growth);
    }
    assert.ok(checkpoints.get(120)>.5 && checkpoints.get(120)<.65, 'First minutes visibly unfurl without exhausting growth');
    assert.ok(checkpoints.get(3600)>checkpoints.get(600)+.1, 'Growth remains visible during the first hour');
    assert.ok(checkpoints.get(10800)>checkpoints.get(3600)+.1, 'The afternoon continues changing');
    assert.ok(checkpoints.get(21600)>.98 && checkpoints.get(21600)<1);
    assert.equal(state.notes.length,0);
    assert.equal(state.residents[0].slot,0);
});
test('absence and unavailable scans cannot age plants, and calendar jumps cannot accelerate them', () => {
    const snap = plain(model.demoSnapshot(0));
    snap.processes = [snap.processes[0]];
    let state = model.updateGarden(model.newGarden(),snap,0);
    state = model.updateGarden(state,snap,864000000000);
    assert.equal(state.residents[0].age,2);
    assert.ok(state.residents[0].growth<.37);
    const before = plain(state.residents[0]);
    state = model.updateGarden(state,{...snap,processes:[]},-864000000000);
    state = model.updateGarden(state,{...snap,processesAvailable:false},864000000000);
    assert.equal(state.residents[0].age,before.age);
    assert.equal(state.residents[0].growth,before.growth);
    assert.equal(model.growthForAge(-10),.35);
    assert.equal(model.growthForAge(NaN),.35);
    assert.ok(model.growthForAge(1e300)<=1);
});
test('demo growth previews preserve the complete observation state and resident identity fields', () => {
    let base = model.newGarden();
    for(let step=0;step<35;step++)base=model.updateGarden(base,model.demoSnapshot(step),1700000000000+step*2000);
    assert.ok(base.residents.some(resident=>resident.missing>0));
    assert.ok(base.notes.length>0);
    const before=plain(base);
    base.residents.forEach(Object.freeze);Object.freeze(base.residents);Object.freeze(base.notes);Object.freeze(base);
    for(const age of [3600,21600]) {
        const preview=model.demoGrowthPreview(base,age);
        assert.notEqual(preview,base);assert.notEqual(preview.residents,base.residents);
        assert.equal(preview.notes,base.notes);
        const restored=plain(preview);
        preview.residents.forEach((resident,index)=>{
            assert.notEqual(resident,base.residents[index]);
            assert.equal(resident.growth,model.growthForAge(age));
            assert.ok(resident.growth>=.35 && resident.growth<=1);
            restored.residents[index].growth=before.residents[index].growth;
        });
        assert.deepEqual(restored,before);
    }
    assert.deepEqual(plain(base),before);
});
test('natural, invalid and already-projected demo growth reuse unchanged state', () => {
    const base=model.updateGarden(model.newGarden(),model.demoSnapshot(0),0);
    for(const age of [-1,0,3601,-3600,NaN,Infinity,undefined,null,true,'3600'])
        assert.equal(model.demoGrowthPreview(base,age),base);
    const projected=model.demoGrowthPreview(base,3600);
    assert.equal(model.demoGrowthPreview(projected,3600),projected);
    const empty=model.newGarden();
    assert.equal(model.demoGrowthPreview(empty,21600),empty);
    assert.equal(model.demoGrowthPreview(null,21600),null);
    assert.equal(model.demoGrowthPreview(undefined,3600),undefined);
});
test('new demo samples advance the base normally while preview growth stays independent', () => {
    const initial=model.updateGarden(model.newGarden(),model.demoSnapshot(0),0);
    const hour=model.demoGrowthPreview(initial,3600);
    const frozenHour=plain(hour);
    const next=model.updateGarden(initial,model.demoSnapshot(1),2000);
    const afternoon=model.demoGrowthPreview(next,21600);
    assert.equal(next.residents[0].age,2);
    assert.ok(next.residents[0].growth<.37);
    assert.equal(next.observedSeconds,4);
    assert.equal(next.samples,2);
    assert.equal(afternoon.residents[0].age,next.residents[0].age);
    assert.equal(afternoon.residents[0].growth,model.growthForAge(21600));
    assert.equal(model.demoGrowthPreview(next,-1),next);
    assert.deepEqual(plain(hour),frozenHour);
});
