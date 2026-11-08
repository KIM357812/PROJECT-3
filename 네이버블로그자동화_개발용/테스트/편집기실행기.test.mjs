import {test} from 'node:test';
import assert from 'node:assert/strict';
import {createEditorRunner} from '../프로그램/편집기실행기.mjs';
const tab=url=>({url:async()=>url,playwright:{frameLocator:()=>({})}});
test('publication-enabled plan cannot execute',async()=>{
  const runner=createEditorRunner(tab(''),{});
  await assert.rejects(runner.run({publicationForbidden:false}),/Unsupported execution plan/);
});
test('existing post cannot be mutated',async()=>{
  const runner=createEditorRunner(tab('https://blog.naver.com/PostUpdateForm.naver'),{});
  await assert.rejects(runner.apply({action:'ApplyHeadingByExactText',text:'test'}),/authorized new-post editor/);
});
test('missing six-fact rows cannot pass audit',async()=>{
  const runner=createEditorRunner(tab(''),{});
  await assert.rejects(runner.audit({actions:[]}),/Six source fact rows/);
});
