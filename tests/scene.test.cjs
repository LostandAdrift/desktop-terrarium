const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const dynamics = vm.createContext({});
vm.runInContext(fs.readFileSync(`${__dirname}/../SceneDynamics.js`, 'utf8').replace(/^\.pragma library\s*/, ''), dynamics);
const plain = value => JSON.parse(JSON.stringify(value));

test('the local sky is continuous around sunrise, sunset, and midnight', () => {
    assert.equal(dynamics.skyAt(12).daylight, 1);
    assert.equal(dynamics.skyAt(0).daylight, 0);
    assert.deepEqual(plain(dynamics.skyAt(25)), plain(dynamics.skyAt(1)));
    assert.deepEqual(plain(dynamics.skyAt(-1)), plain(dynamics.skyAt(23)));
    for (let h = 0; h < 24; h += 1 / 60) {
        const a = dynamics.skyAt(h), b = dynamics.skyAt(h + 1 / 60);
        assert.ok(Math.abs(a.daylight - b.daylight) < .013);
        assert.ok(Math.abs(a.sun - b.sun) < .022);
        assert.ok(Math.abs(a.moon - b.moon) < .022);
        assert.ok(Math.abs(a.stars - b.stars) < .022);
        assert.ok(Math.abs(a.interior - b.interior) < .016);
        assert.ok(Math.abs(a.horizon - b.horizon) < .022);
        assert.ok(a.opening >= .32 && a.opening <= 1);
        assert.ok(a.sunX >= 505 && a.sunX <= 620);
        assert.ok(a.sunY >= 108 && a.sunY <= 197);
        for (const field of ['hour', 'daylight', 'night', 'warmth', 'sunX', 'sunY', 'opening'])
            assert.equal(typeof a[field], 'number');
    }
    assert.ok(Math.abs(dynamics.skyAt(23.999).daylight - dynamics.skyAt(0).daylight) < .001);
    assert.deepEqual(plain(dynamics.skyAt(NaN)), plain(dynamics.skyAt(20)));
});

test('noon, night, and twilight are distinct skies that never stack two bodies', () => {
    const noon = dynamics.skyAt(12);
    const midnight = dynamics.skyAt(0);
    const dawn = dynamics.skyAt(6.5);
    const dusk = dynamics.skyAt(17.5);
    const late = dynamics.skyAt(20);

    assert.equal(noon.daylight, 1);
    assert.equal(noon.night, 0);
    assert.ok(noon.sun > .99);
    assert.equal(noon.moon, 0);
    assert.equal(noon.stars, 0);
    assert.ok(noon.interior > .99);
    assert.equal(noon.horizon, 0);
    assert.ok(noon.sunY < 120);

    assert.equal(midnight.daylight, 0);
    assert.equal(midnight.sun, 0);
    assert.ok(midnight.moon > .99);
    assert.ok(midnight.stars > .99);
    assert.equal(midnight.interior, 0);
    assert.deepEqual(plain(late), plain(dynamics.skyAt(20)));
    assert.equal(late.sun, 0);
    assert.ok(late.moon > .99);

    assert.ok(dawn.sun > .4);
    assert.equal(dawn.moon, 0);
    assert.equal(dawn.stars, 0);
    assert.ok(dawn.horizon > .3);
    assert.ok(dawn.sunY > 160);
    assert.ok(dawn.interior > noon.interior * .4);
    assert.ok(dawn.interior < noon.interior);
    assert.ok(dawn.sunX > noon.sunX);
    assert.equal(dawn.interior, dawn.daylight);

    assert.ok(dusk.sun > .3);
    assert.equal(dusk.moon, 0);
    assert.equal(dusk.stars, 0);
    assert.ok(dusk.horizon > .3);
    assert.ok(dusk.sunY > 160);
    assert.ok(dusk.sunX < noon.sunX);
    assert.ok(dusk.interior < noon.interior);

    const gapDawn = dynamics.skyAt(5.5), gapDusk = dynamics.skyAt(18.5);
    assert.equal(gapDawn.sun, 0);
    assert.equal(gapDawn.moon, 0);
    assert.ok(gapDawn.horizon > .8);
    assert.equal(gapDusk.sun, 0);
    assert.equal(gapDusk.moon, 0);
    assert.ok(gapDusk.horizon > .8);

    const handoff = [];
    for (let h = 0; h < 24; h += 1 / 60) {
        const sky = dynamics.skyAt(h);
        assert.ok(sky.sun >= 0 && sky.sun <= 1);
        assert.ok(sky.moon >= 0 && sky.moon <= 1);
        assert.ok(sky.stars >= 0 && sky.stars <= 1);
        assert.equal(sky.stars, sky.moon);
        assert.ok(!(sky.sun > .05 && sky.moon > .05), `stacked bodies at hour ${h}`);
        if (sky.sun <= .02 && sky.moon <= .02) handoff.push(h);
        if (sky.daylight === 1) {
            assert.equal(sky.stars, 0);
            assert.equal(sky.moon, 0);
            assert.ok(sky.sun > .99);
            assert.ok(sky.interior > .99);
        }
        if (sky.daylight === 0 && (h < 4 || h > 20)) {
            assert.equal(sky.sun, 0);
            assert.ok(sky.moon > .99);
        }
    }
    assert.ok(handoff.some(h => h > 5 && h < 6));
    assert.ok(handoff.some(h => h > 18 && h < 19));
    assert.ok(Math.abs(dawn.opening - dusk.opening) < .02);
    assert.ok(noon.opening > dawn.opening);
    assert.ok(midnight.opening < dawn.opening);
});

test('a burst of input remains bounded and decays without retaining history', () => {
    let touches = [];
    for (let i = 0; i < 1000; i++) touches = dynamics.addTouch(touches, 300 + i % 50, 300, 'glass');
    assert.equal(touches.length, 4);
    touches = dynamics.ageTouches(touches, .1);
    assert.ok(Math.abs(dynamics.impulseAt(touches, 325, 310)) > .1);
    assert.equal(dynamics.impulseAt(touches, 900, 500), 0);
    for (let i = 0; i < 33; i++) touches = dynamics.ageTouches(touches, .1);
    assert.equal(touches.length, 0);
    assert.equal(dynamics.impulseAt(touches, 325, 310), 0);
});

test('motion stays rooted, finite, and restrained for every species at extreme input', () => {
    const categories = ['browser', 'editor', 'terminal', 'agent', 'media', 'system', 'other', '__proto__'];
    for (const category of categories) for (let frame = 0; frame < 800; frame++) {
        const pose = dynamics.pose(category, '__proto__', frame / 20, frame % 2 ? 999 : NaN, 1000);
        assert.ok(Number.isFinite(pose.angle) && Math.abs(pose.angle) <= 7);
        assert.ok(pose.stretch > .98 && pose.stretch < 1.02);
        assert.ok(pose.glow >= 0 && pose.glow <= 1);
    }
    assert.notEqual(dynamics.pose('browser', 'same', 1, .5, 0).angle, dynamics.pose('system', 'same', 1, .5, 0).angle);
});

test('render-only smoothing approaches a changed reading without overshoot', () => {
    let energy = .05;
    const first = dynamics.smooth(energy, .95, .05, 1.25);
    assert.ok(first > energy && first < .15);
    for (let i = 0; i < 120; i++) {
        const next = dynamics.smooth(energy, .95, .05, 1.25);
        assert.ok(next >= energy && next <= .95);
        energy = next;
    }
    assert.ok(energy > .94);
    assert.equal(dynamics.targetEnergy({cpu:null}), 0);
    assert.equal(dynamics.targetEnergy({cpu:Infinity}), 0);
});

test('the renderer bounds slots and preserves their identity independently of ranking', () => {
    const residents = [{key:'a',slot:5}, {key:'b',slot:0}, {key:'duplicate',slot:5}, {key:'invalid',slot:8}];
    const slots = dynamics.slotsFor(residents);
    assert.equal(slots.length, 7);
    assert.equal(slots[5].key, 'a');
    assert.equal(slots[0].key, 'b');
    assert.equal(slots.filter(Boolean).length, 2);
    assert.deepEqual(plain(dynamics.slotsFor([residents[1], residents[0]])), plain(slots));
    assert.equal(dynamics.inPond(620,425), true);
    assert.equal(dynamics.inPond(305,342), false);
    assert.equal(dynamics.inGlass(450,480), false);
    assert.equal(dynamics.inGlass(150,60), false);
});
