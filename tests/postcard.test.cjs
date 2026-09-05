const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const postcard = vm.createContext({});
vm.runInContext(fs.readFileSync(`${__dirname}/../PostcardModel.js`, 'utf8').replace(/^\.pragma library\s*/, ''), postcard);
const plain = value => JSON.parse(JSON.stringify(value));

function source() {
    return { residents:[{key:'browser', name:'Private application name', category:'browser', slot:0, growth:.6, cpu:8, missing:0,
        memoryBytes:1234, count:3, age:600, commandLine:'private command'}],
        colors:{name:'dusk', bg:'#111B20', label:'Private palette label'}, hour:20.25,
        weather:{rain:.2, activity:.3, water:.4, particles:11, interfaces:['private-interface']},
        notes:[{text:'Private history'}], snapshot:{uptime:3600}, timestamp:42 };
}

test('postcards whitelist drawing data and carry no labels, readings, or history', () => {
    const card = postcard.create(source());
    assert.deepEqual(Object.keys(card).sort(), ['colors','hour','residents','version','weather']);
    assert.deepEqual(Object.keys(card.residents[0]).sort(), ['category','cpu','growth','key','missing','slot']);
    assert.deepEqual(Object.keys(card.weather).sort(), ['activity','particles','rain','water']);
    assert.ok(!JSON.stringify(card).includes('Private'));
    assert.ok(!JSON.stringify(card).includes('private'));
    assert.equal(card.colors.bg, '#111b20');
});
test('the immutable snapshot stays unchanged when its live source updates', () => {
    const input = source(), card = postcard.create(input), before = plain(card);
    input.residents[0].cpu = 99;
    input.residents.push({...input.residents[0], key:'new', slot:1});
    input.colors.bg = '#ffffff'; input.weather.rain = 1; input.hour = 12;
    assert.deepEqual(plain(card), before);
    assert.ok(Object.isFrozen(card) && Object.isFrozen(card.residents) && Object.isFrozen(card.residents[0]));
    assert.ok(Object.isFrozen(card.colors) && Object.isFrozen(card.weather));
    assert.deepEqual(plain(postcard.create(card)), before);
});
test('names and readings cannot change the art snapshot', () => {
    const first = source(), second = source();
    second.residents[0].name = 'A completely different account or process name';
    second.residents[0].memoryBytes = 999999;
    second.notes = [{text:'Unrelated history'}]; second.timestamp = 999;
    assert.deepEqual(plain(postcard.create(first)), plain(postcard.create(second)));
});
test('bad input stays bounded and cannot smuggle CSS colors or extra residents', () => {
    const input = source();
    input.residents = Array.from({length:100}, (_,i) => ({key:'\u001b'.repeat(30)+'k'.repeat(200), category:'__proto__', slot:i%7,
        growth:20, cpu:Infinity, missing:999, name:'secret'}));
    input.colors.bg = 'url(secret)'; input.hour = -1;
    input.weather = {rain:Infinity, activity:999, water:-1};
    const card = postcard.create(input);
    assert.equal(card.residents.length, 7);
    assert.ok(card.residents.every(r => r.key.length<=64 && r.category==='other' && r.growth===1 && r.cpu===null && r.missing===18));
    assert.equal(card.colors.bg, '#111b20'); assert.equal(card.hour, 23);
    assert.equal(card.weather.activity, 1); assert.equal(card.weather.water, 0);
    assert.ok(!JSON.stringify(card).includes('secret'));
});
