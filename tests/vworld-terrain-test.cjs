'use strict';
// No network/key needed: execute the shipped browser script and SDK adapter with a controlled provider.
const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
const html=fs.readFileSync('AddOns/vworld/terrain.html','utf8');
const code=html.match(/<script>\s*([\s\S]*?)<\/script>/)[1];
const elements=new Map();
function element(id){if(!elements.has(id))elements.set(id,{value:'',disabled:false,textContent:'',addEventListener(){},replaceChildren(){},append(){},contentWindow:{postMessage(){}}});return elements.get(id);}
const browser={document:{getElementById:element},window:{addEventListener(){}},console,setTimeout,clearTimeout,crypto:require('node:crypto').webcrypto};
vm.createContext(browser);vm.runInContext(code,browser);
let passed=0;
function check(name,f){f();passed++;console.log('PASS '+name);}
check('single coordinate preserves lon lat',()=>assert.equal(JSON.stringify(browser.makePoints('127,37',3)),'[[127,37]]'));
check('grid includes edges and center',()=>{const p=browser.makePoints('127,37,127.002,37.002',3);assert.equal(p.length,9);assert.equal(JSON.stringify(p[4]),'[127.001,37.001000000000005]');assert.equal(JSON.stringify(p[8]),'[127.002,37.002]');});
check('grid limited to 100 points',()=>assert.equal(browser.makePoints('127,37,127.02,37.02',10).length,100));
for(const value of ['127,,37','127,37,128,38','127,38,127.001,37','181,37','127,90','NaN,37'])check('reject coordinates '+value,()=>assert.throws(()=>browser.makePoints(value,3)));
check('reject unbounded grid',()=>assert.throws(()=>browser.makePoints('127,37,127.01,37.01',100)));
async function adapter(provider,fail){
    const messages=[],listeners={};let sampled=0,gotLevel;
    const parent={postMessage(m){messages.push(m);}};
    function Ellipsoid(){}
    const sdk={Cartographic:{fromDegrees:(lon,lat)=>({longitude:lon,latitude:lat,height:0})},EllipsoidTerrainProvider:Ellipsoid,
        async sampleTerrain(p,level,positions){sampled++;gotLevel=level;if(fail)throw Error('network key=must-not-escape');positions.forEach((p,i)=>p.height=i===0?12.34:undefined);return positions;}};
    const map={onClick:{addEventListener(){}},setOption(){},start(){ctx.vw.ws3dInitCallBack();}};
    const ctx={parent,Number,Array,Error,Promise,window:null,ws3d:{viewer:{terrainProvider:provider==='flat'?new Ellipsoid():{}}},Cesium:sdk,
        vw:{Map:function(){return map;},CameraPosition:function(){},CoordZ:function(){},Direction:function(){}},setInterval(){return 1;},clearInterval(){}};
    ctx.window=ctx;ctx.addEventListener=(type,f)=>listeners[type]=f;
    vm.createContext(ctx);vm.runInContext('('+browser.boot.toString()+')({session:"test",lon:127,lat:37})',ctx);
    listeners.message({source:parent,data:{probeTerrain:'test',type:'query',points:[[127,37],[127.001,37.001]],level:14}});
    await new Promise(resolve=>setImmediate(resolve));return {messages,sampled,gotLevel};
}
(async()=>{
    let r=await adapter('terrain',false);
    check('SDK samples terrain at requested tile level',()=>{assert.equal(r.sampled,1);assert.equal(r.gotLevel,14);});
    check('height and missing sample remain distinct',()=>{const s=r.messages.find(m=>m.type==='samples').value;assert.equal(s[0].height,12.34);assert.equal(s[1].height,null);});
    r=await adapter('flat',false);
    check('flat ellipsoid fallback is refused',()=>{assert.equal(r.sampled,0);assert(r.messages.some(m=>m.type==='error'));});
    r=await adapter('terrain',true);
    check('SDK errors hide sensitive exception text and release busy state',()=>{assert(!JSON.stringify(r.messages).includes('must-not-escape'));assert.equal(r.messages.at(-1).type,'idle');});
    console.log('Terrain browser tests: '+passed+' passed');
})().catch(e=>{console.error(e);process.exitCode=1;});
