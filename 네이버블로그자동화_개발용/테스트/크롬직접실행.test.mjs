import test from 'node:test';
import assert from 'node:assert/strict';
import {parseArgs,isAuthorizedNaverUrl,assertNewPostSafety,buildInsertionUnits,extractHtmlBodyFragment,verifyNaverAuthCookies,validatePlannedImagePaths} from '../프로그램/크롬직접실행.mjs';

test('argument parser keeps Korean and spaced paths as values',()=>{
  assert.deepEqual(parseArgs(['--mode','execute','--package','C:\\한글 폴더\\실행패키지.json']),{mode:'execute',package:'C:\\한글 폴더\\실행패키지.json'});
});
test('only the configured Naver blog and a new editor are accepted',()=>{
  assert.equal(isAuthorizedNaverUrl('https://blog.naver.com/ij1128','ij1128'),true);
  assert.equal(isAuthorizedNaverUrl('https://blog.naver.com.evil.test/ij1128','ij1128'),false);
  assert.equal(isAuthorizedNaverUrl('https://blog.naver.com/ij1128?Redirect=Write&','ij1128',{allowWrite:true}),true);
  assert.equal(isAuthorizedNaverUrl('https://blog.naver.com/PostWriteForm.naver?blogId=ij1128&logNo=123','ij1128',{allowWrite:true}),false);
  assert.throws(()=>assertNewPostSafety('https://blog.naver.com/ij1128/2244','ij1128'),/UNSAFE_EDITOR_URL/);
});
test('plan becomes atomic units and never merges headings with body',()=>{
  const plan={actions:[
    {order:1,type:'PasteStandaloneParagraphBlock',path:'body'},
    {order:2,type:'InsertVerticalSpacer',heightPx:32},
    {order:3,type:'InsertStandaloneHeading',text:'소제목',fontSizePx:19},
    {order:4,type:'InsertVerticalSpacer',heightPx:21},
    {order:5,type:'InsertImageAnchor',anchorId:'I1',text:'[[I1]]'}
  ]};
  const units=buildInsertionUnits(plan,p=>p==='body'?'<p>본문</p>':'');
  assert.equal(units.length,5);
  assert.deepEqual(units.map(x=>x.kind),['PasteStandaloneParagraphBlock','spacer','heading','spacer','image-anchor']);
  assert.equal(units[2].verifyText,'소제목');
  assert.equal(units[0].html.includes('소제목'),false);
});
test('clipboard unit keeps only body fragment and never leaks HTML title',()=>{
  const fragment=extractHtmlBodyFragment('<!doctype html><html><head><title>네이버 독립 입력 블록 9</title></head><body><p>실제 본문</p><script>bad()</script></body></html>');
  assert.equal(fragment,'<p>실제 본문</p>');
  assert.equal(fragment.includes('독립 입력 블록'),false);
});
test('preflight requires both Naver authentication cookies',async()=>{
  const cdpWithBoth={send:async()=>({cookies:[{domain:'.naver.com',name:'NID_AUT'},{domain:'.naver.com',name:'NID_SES'}]})};
  const cdpWithPublicOnly={send:async()=>({cookies:[{domain:'.naver.com',name:'NNB'},{domain:'example.com',name:'NID_AUT'}]})};
  assert.deepEqual(await verifyNaverAuthCookies(cdpWithBoth),{verified:true});
  assert.deepEqual(await verifyNaverAuthCookies(cdpWithPublicOnly),{verified:false});
});
test('image actions must use only manifest optimized files in document order',()=>{
  const manifest={optimizedDirectory:'C:\\work\\images\\optimized',specification:{count:2},assets:[
    {order:1,outputFileName:'01-대표.jpg'},{order:2,outputFileName:'02-현황.jpg'}
  ]};
  const good={actions:[
    {type:'UploadImageAtAnchor',documentOrder:2,path:'C:\\work\\images\\optimized\\02-현황.jpg'},
    {type:'UploadImageAtAnchor',documentOrder:1,path:'C:\\work\\images\\optimized\\01-대표.jpg'}
  ]};
  assert.equal(validatePlannedImagePaths(good,manifest),true);
  const screenshot={actions:good.actions.map((a,i)=>({...a,path:`C:\\temp\\pc${i}.png`}))};
  assert.throws(()=>validatePlannedImagePaths(screenshot,manifest),/IMAGE_PLAN_PATH_MISMATCH/);
});
