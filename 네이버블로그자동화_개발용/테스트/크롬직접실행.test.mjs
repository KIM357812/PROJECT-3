import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import {fileURLToPath} from 'node:url';
import {parseArgs,isAuthorizedNaverUrl,assertNewPostSafety,buildInsertionUnits,extractHtmlBodyFragment,verifyNaverAuthCookies,validatePlannedImagePaths,chooseEditorTargetAction,buildHeadingSpecs,previewClassFor} from '../프로그램/크롬직접실행.mjs';

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
    {order:2,type:'InsertVerticalSpacer',heightPx:32,mobileHeightPx:32,naverFontSizePx:16,naverLineHeightPercent:200},
    {order:3,type:'InsertStandaloneHeading',text:'소제목',fontSizePx:19,lineHeightPx:27,mobileLineHeightPx:23,level:2,textColor:'#4A78E0',underline:false,underlineOffsetPx:0,underlineThicknessPx:0,underlineColor:''},
    {order:4,type:'InsertVerticalSpacer',heightPx:21,mobileHeightPx:21,naverFontSizePx:13,naverLineHeightPercent:160},
    {order:5,type:'InsertImageAnchor',anchorId:'I1',text:'[[I1]]'}
  ]};
  const units=buildInsertionUnits(plan,p=>p==='body'?'<p>본문</p>':'');
  assert.equal(units.length,5);
  assert.deepEqual(units.map(x=>x.kind),['PasteStandaloneParagraphBlock','spacer','heading','spacer','image-anchor']);
  assert.equal(units[2].verifyText,'소제목');
  assert.equal(units[0].html.includes('소제목'),false);
  assert.match(units[1].html,/data-nte-mobile-height="32"/);
  assert.match(units[1].html,/data-nte-height="32"/);
  assert.match(units[2].html,/font-size:19px/);
  assert.match(units[2].html,/line-height:clamp\(23px,calc\(/);
  assert.match(units[2].html,/<span data-nte-heading-color="true" style="color:#4A78E0">소제목<\/span>/);
  assert.doesNotMatch(units[2].html,/<u\b|text-decoration|border-bottom/);
});
test('mobile heading specs keep PC values and apply narrower mobile-only child gaps',()=>{
  const plan={mobileHeadingSpacing:{tolerancePx:4,dominancePx:6},actions:[
    {order:1,type:'PasteStandaloneParagraphBlock'},
    {order:2,type:'InsertVerticalSpacer',heightPx:32,mobileHeightPx:32},
    {order:3,type:'InsertStandaloneHeading',text:'큰 소제목',level:2,fontSizePx:19,lineHeightPx:27,mobileLineHeightPx:23,textColor:'#4A78E0'},
    {order:4,type:'InsertVerticalSpacer',heightPx:12,mobileHeightPx:8},
    {order:5,type:'PasteStandaloneParagraphBlock'},
    {order:6,type:'InsertVerticalSpacer',heightPx:24,mobileHeightPx:24},
    {order:7,type:'InsertStandaloneHeading',text:'작은 소제목',level:3,fontSizePx:16,lineHeightPx:27,mobileLineHeightPx:22,textColor:'#111111'},
    {order:8,type:'InsertVerticalSpacer',heightPx:12,mobileHeightPx:8},
    {order:9,type:'PasteStandaloneParagraphBlock'}
  ]};
  const pc=buildHeadingSpecs(plan,'pc');
  const mobile=buildHeadingSpecs(plan,'mobile');
  assert.deepEqual(pc.map(s=>[s.level,s.expectedTopPx,s.expectedBottomPx,s.lineHeightPx]),[[2,32,12,27],[3,24,12,27]]);
  assert.deepEqual(mobile.map(s=>[s.level,s.expectedTopPx,s.expectedBottomPx,s.mobileLineHeightPx,s.requireGapDominance]),[[2,32,8,23,true],[3,24,8,22,true]]);
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
test('tag-only execution requires an explicit opt-in argument',()=>{
  const args=parseArgs(['--mode','execute','--allow-tag-only-publication-settings','true']);
  assert.equal(args['allow-tag-only-publication-settings'],'true');
});
test('preflight target id stays pinned and duplicate editor tabs are isolated',()=>{
  const candidates=[{targetId:'old-a'},{targetId:'preflight-target'},{targetId:'old-b'}];
  const pinned=chooseEditorTargetAction(candidates,['old-a','old-b'],'preflight-target');
  assert.equal(pinned.kind,'reuse');
  assert.equal(pinned.target.targetId,'preflight-target');
  assert.equal(pinned.preferred,true);
  const ambiguous=chooseEditorTargetAction(candidates,['old-a','old-b'],'missing');
  assert.equal(ambiguous.kind,'create');
  assert.equal(ambiguous.isolatedFromDuplicates,true);
});
test('mobile validation uses the Naver editor device preview instead of outer Chrome emulation',()=>{
  assert.equal(previewClassFor('desktop'),'se-util-button-device-desktop');
  assert.equal(previewClassFor('mobile'),'se-util-button-device-mobile');
  assert.throws(()=>previewClassFor('tablet'),/INVALID_PREVIEW_MODE/);
  const source=fs.readFileSync(fileURLToPath(new URL('../프로그램/크롬직접실행.mjs',import.meta.url)),'utf8');
  assert.doesNotMatch(source,/Emulation\.setDeviceMetricsOverride/);
  assert.match(source,/setEditorPreviewMode\(cdp,attached,'mobile'\)/);
});
