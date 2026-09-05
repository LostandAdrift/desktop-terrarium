const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const placement = vm.createContext({});
vm.runInContext(fs.readFileSync(`${__dirname}/../Placement.js`, 'utf8').replace(/^\.pragma library\s*/, ''), placement);
const plain = value => JSON.parse(JSON.stringify(value));
const monitor = (name, width = 1920, height = 1080, scale = 1) => ({ name, width, height, scale });
const approximate = (actual, expected) => assert.ok(Math.abs(actual - expected) <= Math.max(1e-9, Math.abs(expected) * 1e-12), `${actual} != ${expected}`);

test('saved options normalize without changing their input or losing display case', () => {
    const saved = Object.freeze({ display: ' DP-2\n', corner: ' TOP-LEFT ', size: ' LARGE ' });
    assert.deepEqual(plain(placement.normalizeOptions(saved)), { display: 'DP-2', corner: 'top-left', size: 'large' });
    assert.equal(saved.display, ' DP-2\n');
    assert.equal(placement.normalizeDisplay('eDP-1'), 'eDP-1');
    assert.equal(placement.normalizeDisplay('display\x1b\x00-name'), 'display-name');
    assert.equal(placement.normalizeDisplay('x'.repeat(1000)).length, 256);
});

test('invalid settings use safe defaults without coercing objects into display names', () => {
    for (const value of [null, undefined, 5, 'bad', [], {}]) {
        assert.deepEqual(plain(placement.normalizeOptions(value)), { display: '', corner: 'bottom-right', size: 'medium' });
    }
    assert.deepEqual(plain(placement.normalizeOptions({ display: { toString() { throw Error('must not call'); } }, corner: '__proto__', size: 'constructor' })),
        { display: '', corner: 'bottom-right', size: 'medium' });
});

test('a connected saved display is selected by name with its original object identity', () => {
    const first = monitor('DP-1'), saved = monitor('HDMI-A-1');
    const choice = placement.chooseScreen([first, saved], 'HDMI-A-1');
    assert.equal(choice.screen, saved);
    assert.equal(choice.index, 1);
    assert.equal(choice.display, 'HDMI-A-1');
    assert.equal(choice.requestedDisplay, 'HDMI-A-1');
    assert.equal(choice.fallback, false);
});

test('disconnect fallback does not overwrite preference and reconnect restores the destination', () => {
    const first = monitor('DP-1'), saved = monitor('HDMI-A-1');
    const preference = 'HDMI-A-1';
    const disconnected = placement.chooseScreen([first], preference);
    assert.equal(disconnected.screen, first);
    assert.equal(disconnected.fallback, true);
    assert.equal(disconnected.requestedDisplay, preference);
    const restored = placement.chooseScreen([saved, first], disconnected.requestedDisplay);
    assert.equal(restored.screen, saved);
    assert.equal(restored.fallback, false);
});

test('automatic destination follows live list order and does not claim a fallback', () => {
    const a = monitor('DP-1'), b = monitor('DP-2');
    assert.equal(placement.chooseScreen([a, b], '').screen, a);
    const reordered = placement.chooseScreen([b, a], '');
    assert.equal(reordered.screen, b);
    assert.equal(reordered.fallback, false);
});

test('QML array-like lists and zero-sized transient screen entries are supported', () => {
    const target = monitor('DP-2');
    const screens = { 0: null, 1: monitor('pending', 0, 0), 2: target, length: 3 };
    const choice = placement.chooseScreen(screens, 'pending');
    assert.equal(choice.screen, target);
    assert.equal(choice.index, 2);
    assert.equal(choice.fallback, true);
});

test('zero live screens return no target while retaining the requested display', () => {
    for (const screens of [[], null, {}, { length: Infinity }, [monitor('bad', NaN, 100)]]) {
        const choice = placement.chooseScreen(screens, 'eDP-1');
        assert.equal(choice.screen, null);
        assert.equal(choice.index, -1);
        assert.equal(choice.display, '');
        assert.equal(choice.requestedDisplay, 'eDP-1');
        assert.equal(choice.fallback, false);
    }
});

test('ordinary destinations use target logical widths and preserve the illustration ratio', () => {
    for (const [size, width] of [['small', 440], ['medium', 600], ['large', 760]]) {
        const geometry = placement.geometry(monitor('DP-1'), size, 'bottom-right');
        assert.equal(geometry.width, width);
        approximate(geometry.height, width * 550 / 900);
        assert.equal(geometry.margin, 36);
        assert.equal(geometry.visible, true);
    }
});

test('fractional output scale does not multiply logical placement dimensions', () => {
    const one = placement.geometry(monitor('DP-1', 1440, 2560, 1), 'large', 'top-left');
    const two = placement.geometry(monitor('DP-1', 1440, 2560, 2.5), 'large', 'top-left');
    assert.deepEqual(plain(one), plain(two));
});

test('each corner attaches exactly one horizontal and one vertical edge', () => {
    for (const corner of ['top-left', 'top-right', 'bottom-left', 'bottom-right']) {
        const geometry = placement.geometry(monitor('DP-1'), 'medium', corner);
        const { anchors, margins } = geometry;
        assert.equal(Number(anchors.left) + Number(anchors.right), 1);
        assert.equal(Number(anchors.top) + Number(anchors.bottom), 1);
        for (const edge of ['top', 'bottom', 'left', 'right']) {
            assert.equal(anchors[edge], corner.split('-').includes(edge));
            assert.equal(margins[edge], anchors[edge] ? 36 : 0);
        }
    }
});

test('portrait and short landscape destinations constrain the limiting dimension', () => {
    const portrait = placement.geometry(monitor('portrait', 360, 800), 'large', 'bottom-right');
    assert.equal(portrait.width, 288);
    approximate(portrait.height, 288 * 550 / 900);
    const short = placement.geometry(monitor('short', 1080, 200), 'large', 'top-left');
    assert.equal(short.margin, 25);
    approximate(short.height, 150);
    approximate(short.width, 150 * 900 / 550);
});

test('tiny and unusual valid screens keep dimensions and margins within both logical edges', () => {
    for (const width of [1, 2, 8, 20, 50, 180, 300, 800, 10000]) {
        for (const height of [1, 5, 20, 50, 160, 400, 10000]) {
            for (const size of ['small', 'medium', 'large']) {
                const geometry = placement.geometry(monitor('tiny', width, height), size, 'bottom-right');
                assert.ok(geometry.width > 0 && geometry.height > 0);
                assert.ok(geometry.margin >= 0 && geometry.margin <= 36);
                assert.ok(geometry.width + geometry.margin * 2 <= width + 1e-9);
                assert.ok(geometry.height + geometry.margin * 2 <= height + 1e-9);
                approximate(geometry.width / geometry.height, 900 / 550);
            }
        }
    }
});

test('missing or invalid geometry produces a hidden zero-area result', () => {
    for (const screen of [null, {}, monitor('bad', 0, 1080), monitor('bad', 1920, -1), monitor('bad', Infinity, 100), monitor('bad', '1920', 1080)]) {
        const geometry = placement.geometry(screen, 'medium', 'invalid');
        assert.equal(geometry.width, 0);
        assert.equal(geometry.height, 0);
        assert.equal(geometry.margin, 0);
        assert.equal(geometry.visible, false);
    }
});
