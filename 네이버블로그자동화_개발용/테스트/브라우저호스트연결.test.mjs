import test from 'node:test';
import assert from 'node:assert/strict';
import { connectNaverHost } from '../프로그램/브라우저호스트연결.mjs';
const browser = id => ({ id, family:'chrome', type:'extension', tabs:[{id:'naver-'+id,url:'https://blog.naver.com/ij1128/123'}] });
function host(state, failure) {
  const calls=[];
  return {calls, async getState(){return state;}, async getTab(id,opts){
    calls.push({id,...opts});
    if(failure) throw new Error(failure);
    return {async getAXState(){calls.push('read');}};
  }};
}
test('chooses Naver profile, not the first Chrome window or hard-coded browser ID', async()=>{
  const h=host({browsers:[{...browser('other'),tabs:[{id:'x',url:'https://www.naver.com'}]},browser('changed-id')]});
  const out=await connectNaverHost(h);
  assert.equal(out.browserId,'changed-id');
  assert.deepEqual(h.calls,[{id:'naver-changed-id',browser:'changed-id'},'read']);
});
test('permission denial stops before tab access', async()=>{
  const h=host({errors:['Local browser use is disabled in Work settings'],browsers:[browser('1')]});
  await assert.rejects(connectNaverHost(h),/BROWSER_HOST_PERMISSION/);
  assert.deepEqual(h.calls,[]);
});
test('does not guess between two signed-in-looking profiles', async()=>{
  await assert.rejects(connectNaverHost(host({browsers:[browser('1'),browser('2')]})),/MULTIPLE_NAVER_BROWSER_PROFILES/);
});
test('host URL safety rejection propagates without fallback', async()=>{
  const h=host({browsers:[browser('1')]},'URL_SAFETY_REJECTED');
  await assert.rejects(connectNaverHost(h),/URL_SAFETY_REJECTED/);
  assert.equal(h.calls.length,1);
});
test('fake Naver domains cannot qualify', async()=>{
  const b=browser('1');b.tabs[0].url='https://blog.naver.com.evil.test/ij1128';
  await assert.rejects(connectNaverHost(host({browsers:[b]})),/NAVER_TAB_UNAVAILABLE/);
});
