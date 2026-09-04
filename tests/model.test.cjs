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
