import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {execFileSync} from 'node:child_process';

export function parseArgs(argv){
  const out={};
  for(let i=0;i<argv.length;i+=2){
    if(!argv[i]?.startsWith('--')) throw new Error(`INVALID_ARGUMENT:${argv[i]}`);
    out[argv[i].slice(2)]=argv[i+1];
  }
  return out;
}
export function isAuthorizedNaverUrl(raw,blogId,{allowWrite=false}={}){
  let u; try{u=new URL(raw)}catch{return false}
  if(u.protocol!=='https:'||u.hostname!=='blog.naver.com') return false;
  if(u.searchParams.has('logNo')||u.searchParams.has('postNo')) return false;
  const owner=u.pathname===`/${blogId}`||u.pathname.startsWith(`/${blogId}/`)||u.searchParams.get('blogId')===blogId;
  if(!owner) return false;
  return allowWrite?(/Redirect=Write/.test(u.search)||/postwrite/i.test(u.pathname)):true;
}
export function buildInsertionUnits(plan,readFile=p=>fs.readFileSync(p,'utf8')){
  const units=[];
  for(const a of [...plan.actions].sort((x,y)=>x.order-y.order)){
    if(a.type==='InsertImageAnchor') units.push({type:'html',kind:'image-anchor',anchorId:a.anchorId,html:`<p>${escapeHtml(a.text)}</p>`,verifyText:a.text});
    else if(a.type==='PasteStandaloneParagraphBlock'||a.type==='PasteRenderedAtomicBlock') units.push({type:'html',kind:a.type,html:extractHtmlBodyFragment(readFile(a.path)),verifyText:null});
    else if(a.type==='InsertVerticalSpacer') units.push({type:'html',kind:'spacer',html:'<p><br></p>',heightPx:Number(a.heightPx)});
    else if(a.type==='InsertStandaloneHeading') units.push({type:'html',kind:'heading',html:`<p><b>${escapeHtml(a.text)}</b></p>`,verifyText:a.text,fontSizePx:Number(a.fontSizePx)});
  }
  return units;
}
export function extractHtmlBodyFragment(html){
  const source=String(html??'').replace(/^\uFEFF/,'');
  const body=source.match(/<body\b[^>]*>([\s\S]*?)<\/body\s*>/i);
  return (body?body[1]:source).replace(/<script\b[^>]*>[\s\S]*?<\/script\s*>/gi,'').trim();
}
export function assertNewPostSafety(url,blogId){
  if(!isAuthorizedNaverUrl(url,blogId,{allowWrite:true})) throw new Error('UNSAFE_EDITOR_URL');
}
function escapeHtml(s){return String(s??'').replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;')}
function normalizeText(s){return String(s??'').replace(/\u00a0/g,' ').replace(/\s+/g,' ').trim()}
function atomicWrite(file,data){
  fs.mkdirSync(path.dirname(file),{recursive:true});
  const tmp=`${file}.tmp-${process.pid}-${Date.now()}`;
  fs.writeFileSync(tmp,JSON.stringify(data,null,2),'utf8');
  fs.renameSync(tmp,file);
}
function readJson(file){return JSON.parse(fs.readFileSync(file,'utf8').replace(/^\uFEFF/,''))}
const sleep=ms=>new Promise(r=>setTimeout(r,ms));
async function json(url,options){const r=await fetch(url,options);if(!r.ok)throw new Error(`HTTP_${r.status}:${url}`);return r.json()}

class Cdp {
  constructor(url){this.url=url;this.next=1;this.pending=new Map();this.listeners=new Map()}
  async connect(){
    this.ws=new WebSocket(this.url);
    await new Promise((resolve,reject)=>{this.ws.addEventListener('open',resolve,{once:true});this.ws.addEventListener('error',reject,{once:true})});
    this.ws.addEventListener('message',e=>{
      const m=JSON.parse(String(e.data));
      if(m.id){const p=this.pending.get(m.id);if(!p)return;this.pending.delete(m.id);clearTimeout(p.timer);m.error?p.reject(new Error(`${m.error.code}:${m.error.message}`)):p.resolve(m.result);return}
      for(const f of this.listeners.get(m.method)??[])f(m.params,m.sessionId);
    });
  }
  send(method,params={},sessionId){
    const id=this.next++;
    const message={id,method,params};if(sessionId)message.sessionId=sessionId;
    return new Promise((resolve,reject)=>{const timer=setTimeout(()=>{if(this.pending.delete(id))reject(new Error(`CDP_TIMEOUT:${method}`))},30000);this.pending.set(id,{resolve,reject,timer});this.ws.send(JSON.stringify(message))});
  }
  on(method,fn){if(!this.listeners.has(method))this.listeners.set(method,[]);this.listeners.get(method).push(fn)}
  close(){this.ws?.close()}
}

async function attach(cdp,targetId){
  const {sessionId}=await cdp.send('Target.attachToTarget',{targetId,flatten:true});
  const contexts=new Map();
  cdp.on('Runtime.executionContextCreated',(p,s)=>{if(s===sessionId)contexts.set(p.context.id,p.context)});
  cdp.on('Runtime.executionContextDestroyed',(p,s)=>{if(s===sessionId)contexts.delete(p.executionContextId)});
  await cdp.send('Page.enable',{},sessionId);await cdp.send('Runtime.enable',{},sessionId);await cdp.send('DOM.enable',{},sessionId);
  return {sessionId,contexts};
}
async function evaluate(cdp,sessionId,expression,contextId){
  const params={expression,awaitPromise:true,returnByValue:true,userGesture:true};if(contextId)params.contextId=contextId;
  const r=await cdp.send('Runtime.evaluate',params,sessionId);
  if(r.exceptionDetails)throw new Error(`PAGE_EVALUATION_FAILED:${r.exceptionDetails.text}`);
  return r.result?.value;
}
async function currentUrl(cdp,sessionId){return evaluate(cdp,sessionId,'location.href')}
async function waitFor(cdp,sessionId,expression,{contextId,timeout=30000}={}){
  const end=Date.now()+timeout;let last;
  while(Date.now()<end){try{last=await evaluate(cdp,sessionId,expression,contextId);if(last)return last}catch{}await sleep(250)}
  throw new Error(`WAIT_TIMEOUT:${String(expression).slice(0,80)}:${JSON.stringify(last)}`);
}
async function findEditorContext(cdp,attached,timeout=45000){
  const expression=`(()=>{const e=[...document.querySelectorAll('[contenteditable="true"]')];return e.length&&document.querySelector('.se-documentTitle,.se-main-container')?{url:location.href,count:e.length}:null})()`;
  const end=Date.now()+timeout;
  while(Date.now()<end){
    for(const [id] of attached.contexts){try{const v=await evaluate(cdp,attached.sessionId,expression,id);if(v)return {contextId:id,...v}}catch{}}
    await sleep(300);
  }
  const outer=await currentUrl(cdp,attached.sessionId);
  if(/nid\.naver\.com/.test(outer))throw new Error('NAVER_LOGIN_REQUIRED');
  throw new Error('NAVER_EDITOR_NOT_READY');
}
async function probeNewEditorAccess(cdp,writeUrl){
  const created=await cdp.send('Target.createTarget',{url:writeUrl,newWindow:false});
  try{
    const attached=await attach(cdp,created.targetId);
    const context=await findEditorContext(cdp,attached,15000);
    const url=await currentUrl(cdp,attached.sessionId);
    return {verified:true,url,contextUrl:context.url};
  }catch(e){
    return {verified:false,reason:String(e?.message||e)};
  }finally{
    await cdp.send('Target.closeTarget',{targetId:created.targetId}).catch(()=>{});
  }
}
async function verifyOwnerLogin(cdp,attached,blogId){
  const expression=`(()=>({loggedIn:!!document.querySelector('#gnb_my'),owner:!!document.querySelector('a[href*="admin.blog.naver.com"],a[href*="/${blogId}/postwrite"],a[href*="/${blogId}?Redirect=Write"]'),url:location.href}))()`;
  const end=Date.now()+12000;
  while(Date.now()<end){
    for(const [id] of attached.contexts){try{const v=await evaluate(cdp,attached.sessionId,expression,id);if(v?.loggedIn&&v?.owner)return {verified:true,contextId:id,url:v.url}}catch{}}
    await sleep(250);
  }
  return {verified:false};
}
export async function verifyNaverAuthCookies(cdp){
  const {cookies=[]}=await cdp.send('Storage.getCookies');
  const naver=cookies.filter(c=>/(^|\.)naver\.com$/i.test(c.domain||''));
  const names=new Set(naver.map(c=>c.name));
  return {verified:names.has('NID_AUT')&&names.has('NID_SES')};
}
async function dismissRecoveryDialog(cdp,sessionId,contextId){
  const expression=`(()=>{const compact=s=>String(s||'').replace(/\\s+/g,'');const cancel=[...document.querySelectorAll('button')].find(b=>b.offsetParent&&compact(b.textContent)==='취소'&&compact(document.body.innerText).includes('작성중인글이있습니다'));if(!cancel)return null;const r=cancel.getBoundingClientRect();return{x:r.x+r.width/2,y:r.y+r.height/2}})()`;
  const end=Date.now()+5000;let rect=null;
  while(Date.now()<end){rect=await evaluate(cdp,sessionId,expression,contextId).catch(()=>null);if(rect)break;await sleep(200)}
  if(!rect)return false;
  await cdp.send('Input.dispatchMouseEvent',{type:'mouseMoved',x:rect.x,y:rect.y},sessionId);
  await cdp.send('Input.dispatchMouseEvent',{type:'mousePressed',x:rect.x,y:rect.y,button:'left',clickCount:1},sessionId);
  await cdp.send('Input.dispatchMouseEvent',{type:'mouseReleased',x:rect.x,y:rect.y,button:'left',clickCount:1},sessionId);
  await waitFor(cdp,sessionId,`!document.body.innerText.replace(/\\s+/g,'').includes('작성중인글이있습니다')`,{contextId,timeout:5000});
  return true;
}
async function nativePaste(cdp,sessionId,contextId,selector,mode,payload,runDir,name,{selectAll=false,skipClick=false}={}){
  const encoded=JSON.stringify(selector);
  const metrics=await waitFor(cdp,sessionId,`(()=>{const e=document.querySelector(${encoded});if(!e)return null;e.scrollIntoView({block:'center',inline:'center'});const r=e.getBoundingClientRect();return r.width>0&&r.height>0?{x:r.x+Math.min(12,r.width/2),y:r.y+Math.min(12,r.height/2),width:innerWidth,height:innerHeight,scale:devicePixelRatio}:null})()`,{contextId});
  const payloadPath=path.join(runDir,`.native-${name}.${mode==='Html'?'html':'txt'}`);
  fs.mkdirSync(runDir,{recursive:true});
  fs.writeFileSync(payloadPath,String(payload),'utf8');
  const helper=path.join(path.dirname(fileURLToPath(import.meta.url)),'크롬네이티브입력.ps1');
  const args=['-NoLogo','-NoProfile','-STA','-ExecutionPolicy','Bypass','-File',helper,'-ViewportX',String(metrics.x),'-ViewportY',String(metrics.y),'-ViewportWidth',String(metrics.width),'-ViewportHeight',String(metrics.height),'-DeviceScaleFactor',String(metrics.scale),'-Mode',mode,'-PayloadPath',payloadPath];
  if(selectAll)args.push('-SelectAll');
  if(skipClick)args.push('-SkipClick');
  const output=execFileSync('powershell.exe',args,{stdio:['ignore','pipe','pipe'],windowsHide:true,encoding:'utf8'});
  fs.appendFileSync(path.join(runDir,'native-input.log'),`${name}\t${output.trim()}\n`,'utf8');
  return metrics;
}
async function nativeSelectExactParagraph(cdp,sessionId,contextId,text,runDir,name){
  const expected=JSON.stringify(normalizeText(text));
  const metrics=await waitFor(cdp,sessionId,`(()=>{const normalize=s=>String(s||'').replace(/\\u00a0/g,' ').replace(/\\s+/g,' ').trim();const matches=[...document.querySelectorAll('.se-component:not(.se-documentTitle) p.se-text-paragraph')].filter(p=>normalize(p.textContent)===${expected});if(matches.length!==1)return null;const e=matches[0];e.scrollIntoView({block:'center',inline:'center'});const r=e.getBoundingClientRect();return r.width>0&&r.height>0?{x:r.x+Math.min(12,r.width/2),y:r.y+Math.min(12,r.height/2),width:innerWidth,height:innerHeight,scale:devicePixelRatio}:null})()`,{contextId});
  const payloadPath=path.join(runDir,`.native-${name}.txt`);fs.writeFileSync(payloadPath,'','utf8');
  const helper=path.join(path.dirname(fileURLToPath(import.meta.url)),'크롬네이티브입력.ps1');
  const args=['-NoLogo','-NoProfile','-STA','-ExecutionPolicy','Bypass','-File',helper,'-ViewportX',String(metrics.x),'-ViewportY',String(metrics.y),'-ViewportWidth',String(metrics.width),'-ViewportHeight',String(metrics.height),'-DeviceScaleFactor',String(metrics.scale),'-Mode','Click','-PayloadPath',payloadPath];
  const output=execFileSync('powershell.exe',args,{stdio:['ignore','pipe','pipe'],windowsHide:true,encoding:'utf8'});
  fs.appendFileSync(path.join(runDir,'native-input.log'),`${name}\t${output.trim()}\n`,'utf8');
}
async function clickVisible(cdp,sessionId,contextId,selector){
  const encoded=JSON.stringify(selector);
  const rect=await waitFor(cdp,sessionId,`(()=>{const e=document.querySelector(${encoded});if(!e||!e.offsetParent)return null;const r=e.getBoundingClientRect();return{x:r.x+r.width/2,y:r.y+r.height/2}})()`,{contextId});
  await cdp.send('Input.dispatchMouseEvent',{type:'mouseMoved',x:rect.x,y:rect.y},sessionId);
  await cdp.send('Input.dispatchMouseEvent',{type:'mousePressed',x:rect.x,y:rect.y,button:'left',clickCount:1},sessionId);
  await cdp.send('Input.dispatchMouseEvent',{type:'mouseReleased',x:rect.x,y:rect.y,button:'left',clickCount:1},sessionId);
}
async function clickIfVisible(cdp,sessionId,contextId,selector){
  const encoded=JSON.stringify(selector);
  const rect=await evaluate(cdp,sessionId,`(()=>{const e=document.querySelector(${encoded});if(!e||!e.offsetParent)return null;const r=e.getBoundingClientRect();return{x:r.x+r.width/2,y:r.y+r.height/2}})()`,contextId).catch(()=>null);
  if(!rect)return false;
  await cdp.send('Input.dispatchMouseEvent',{type:'mouseMoved',x:rect.x,y:rect.y},sessionId);
  await cdp.send('Input.dispatchMouseEvent',{type:'mousePressed',x:rect.x,y:rect.y,button:'left',clickCount:1},sessionId);
  await cdp.send('Input.dispatchMouseEvent',{type:'mouseReleased',x:rect.x,y:rect.y,button:'left',clickCount:1},sessionId);
  return true;
}
async function uploadImageAtAnchor(cdp,attached,contextId,action,runDir){
  if(!fs.existsSync(action.path)) throw new Error(`IMAGE_FILE_MISSING:${action.path}`);
  await nativeSelectExactParagraph(cdp,attached.sessionId,contextId,action.anchorText,runDir,`anchor-${action.anchorId}`);
  const beforeSources=await evaluate(cdp,attached.sessionId,`[...document.querySelectorAll('img.se-image-resource')].map(i=>i.src)`,contextId);
  const before=beforeSources.length;
  let resolveChooser,rejectChooser;
  const chooser=new Promise((resolve,reject)=>{resolveChooser=resolve;rejectChooser=reject});
  const timer=setTimeout(()=>rejectChooser(new Error(`FILE_CHOOSER_TIMEOUT:${action.anchorId}`)),10000);
  cdp.on('Page.fileChooserOpened',(params,sessionId)=>{if(sessionId===attached.sessionId)resolveChooser(params)});
  await cdp.send('Page.setInterceptFileChooserDialog',{enabled:true},attached.sessionId);
  try{
    await clickVisible(cdp,attached.sessionId,contextId,'.se-image-toolbar-button');
    const opened=await chooser;clearTimeout(timer);
    await cdp.send('DOM.setFileInputFiles',{files:[path.resolve(action.path)],backendNodeId:opened.backendNodeId},attached.sessionId);
    await waitFor(cdp,attached.sessionId,`document.querySelectorAll('img.se-image-resource').length>${before}`,{contextId,timeout:30000});
    await waitFor(cdp,attached.sessionId,`[...document.querySelectorAll('img.se-image-resource')].some(i=>/^https:\\/\\/blogfiles\\.pstatic\\.net\\//.test(i.src))`,{contextId,timeout:30000});
    const prior=JSON.stringify(beforeSources);
    const imageRect=await waitFor(cdp,attached.sessionId,`(()=>{const prior=new Set(${prior});const e=[...document.querySelectorAll('img.se-image-resource')].find(i=>!prior.has(i.src));if(!e||!/^https:\\/\\/blogfiles\\.pstatic\\.net\\//.test(e.src))return null;e.scrollIntoView({block:'center'});const r=e.getBoundingClientRect();return{x:r.x+r.width/2,y:r.y+r.height/2}})()`,{contextId,timeout:30000});
    await cdp.send('Input.dispatchMouseEvent',{type:'mouseMoved',x:imageRect.x,y:imageRect.y},attached.sessionId);
    await cdp.send('Input.dispatchMouseEvent',{type:'mousePressed',x:imageRect.x,y:imageRect.y,button:'left',clickCount:1},attached.sessionId);
    await cdp.send('Input.dispatchMouseEvent',{type:'mouseReleased',x:imageRect.x,y:imageRect.y,button:'left',clickCount:1},attached.sessionId);
    await clickVisible(cdp,attached.sessionId,contextId,'.se-property-toolbar-group-toggle-button.se-align-center-toolbar-button');
    await clickVisible(cdp,attached.sessionId,contextId,'.se-resizing-toolbar-button');
    await nativePaste(cdp,attached.sessionId,contextId,'#resizing-input-width','Text',String(action.displayWidth||400),runDir,`resize-${action.anchorId}`,{selectAll:true});
    await clickVisible(cdp,attached.sessionId,contextId,'.se-custom-layer-resizing-apply-button');
    const width=Number(action.displayWidth||400);
    await waitFor(cdp,attached.sessionId,`[...document.querySelectorAll('img.se-image-resource')].filter(i=>Math.abs(i.getBoundingClientRect().width-${width})<=2).length>${before}`,{contextId,timeout:10000});
    const uploaded=await waitFor(cdp,attached.sessionId,`(()=>{const prior=new Set(${prior});const e=[...document.querySelectorAll('img.se-image-resource')].find(i=>!prior.has(i.src)&&/^https:\\/\\/blogfiles\\.pstatic\\.net\\//.test(i.src));if(!e)return null;const r=e.getBoundingClientRect();const section=e.closest('.se-section-image');return{src:e.src,name:e.getAttribute('data-file-name')||e.alt||'',width:r.width,centered:!!section?.classList.contains('se-section-align-center')}})()`,{contextId,timeout:10000});
    await clickIfVisible(cdp,attached.sessionId,contextId,'.se-sidebar-close-button');
    return {...uploaded,documentOrder:Number(action.documentOrder),sourcePath:action.path};
  }finally{
    clearTimeout(timer);
    await cdp.send('Page.setInterceptFileChooserDialog',{enabled:false},attached.sessionId).catch(()=>{});
  }
}
async function prepareEditor(cdp,attached,contextId,plan){
  assertNewPostSafety(await currentUrl(cdp,attached.sessionId),plan.blogId);
  const title=JSON.stringify(plan.title);
  await nativePaste(cdp,attached.sessionId,contextId,'.se-documentTitle .se-text-paragraph','Text',plan.title,plan.runDir,'title',{selectAll:true});
  await waitFor(cdp,attached.sessionId,`document.querySelector('.se-documentTitle .se-text-paragraph')?.textContent.replace(/\\u00a0/g,' ').replace(/\\s+/g,' ').trim()===${title}`,{contextId,timeout:5000});
  const bodySelector='.se-component:not(.se-documentTitle) .se-section-text .se-text-paragraph';
  const units=buildInsertionUnits(plan);
  await nativePaste(cdp,attached.sessionId,contextId,bodySelector,'Html',units.map(unit=>unit.html).join('\n'),plan.runDir,'body-all',{selectAll:true});
  for(const unit of units){
    if(unit.verifyText){const expected=JSON.stringify(normalizeText(unit.verifyText));await waitFor(cdp,attached.sessionId,`[...document.querySelectorAll('p')].filter(p=>p.textContent.replace(/\\u00a0/g,' ').replace(/\\s+/g,' ').trim()===${expected}).length===1`,{contextId,timeout:5000})}
  }
  const uploads=[...plan.actions].filter(a=>a.type==='UploadImageAtAnchor').sort((a,b)=>a.order-b.order);
  const uploadedImages=[];
  for(const upload of uploads) uploadedImages.push(await uploadImageAtAnchor(cdp,attached,contextId,upload,plan.runDir));
  if(uploads.length){
    await waitFor(cdp,attached.sessionId,`document.querySelectorAll('img.se-image-resource').length===${uploads.length}`,{contextId,timeout:10000});
    const anchors=JSON.stringify(uploads.map(x=>normalizeText(x.anchorText)));
    await waitFor(cdp,attached.sessionId,`(()=>{const expected=new Set(${anchors});return ![...document.querySelectorAll('.se-component:not(.se-documentTitle) p.se-text-paragraph')].some(p=>expected.has(p.textContent.replace(/\\u00a0/g,' ').replace(/\\s+/g,' ').trim()))})()`,{contextId,timeout:5000});
  }
  return {titleExpected:JSON.parse(title),unitCount:buildInsertionUnits(plan).length,imageUploadCount:uploads.length,uploadedImages:uploadedImages.sort((a,b)=>a.documentOrder-b.documentOrder)};
}
async function inspectEditor(cdp,attached,contextId,plan){
  const title=await evaluate(cdp,attached.sessionId,`(()=>document.querySelector('.se-documentTitle [contenteditable="true"],.se-title-text[contenteditable="true"],.se-documentTitle .se-text-paragraph')?.textContent.trim()||'')()`,contextId);
  const body=await evaluate(cdp,attached.sessionId,`(()=>{const root=document.querySelector('.se-main-container,article');if(!root)return null;const ps=[...root.querySelectorAll('p')];return {text:root.innerText,paragraphs:ps.map(p=>p.textContent),rawUrlVisible:/https?:\\/\\//.test(root.innerText),horizontalOverflow:root.scrollWidth>root.clientWidth+1,images:[...root.querySelectorAll('img.se-image-resource')].map(i=>{const r=i.getBoundingClientRect();const container=i.closest('.se-section-image,.se-component-content')||i.parentElement;const c=container.getBoundingClientRect();return{src:i.src,name:i.getAttribute('data-file-name')||i.alt||'',width:r.width,height:r.height,left:r.left,centered:Math.abs((r.left+r.width/2)-(c.left+c.width/2))<=2}}),links:[...root.querySelectorAll('span.se-link[data-href],a[href]')].map(a=>({text:a.textContent.trim(),href:a.getAttribute('data-href')||a.href}))}})()`,contextId);
  const headings=plan.actions.filter(a=>a.type==='InsertStandaloneHeading').map(a=>a.text);
  return {title,body,headingsVerified:headings.every(h=>body?.paragraphs?.filter(p=>p.trim()===h.trim()).length===1)};
}
async function inspectEditableDom(cdp,attached){
  const rows=[];
  for(const [id,context] of attached.contexts){
    try{
      const value=await evaluate(cdp,attached.sessionId,`(()=>({url:location.href,title:document.title,bodyClass:document.body?.className||'',activeElement:{tag:document.activeElement?.tagName||'',id:document.activeElement?.id||'',className:document.activeElement?.className||'',contenteditable:document.activeElement?.getAttribute?.('contenteditable')||'',outerHTML:document.activeElement?.outerHTML?.slice(0,500)||''},frames:[...document.querySelectorAll('iframe')].map(f=>({name:f.name,id:f.id,className:f.className,src:f.src})),imageSummary:[...document.querySelectorAll('img.se-image-resource')].map(i=>{const r=i.getBoundingClientRect();return{src:i.src,name:i.getAttribute('data-file-name')||i.alt||'',width:r.width,height:r.height,left:r.left}}),fileInputs:[...document.querySelectorAll('input[type=file]')].map(e=>({id:e.id,className:e.className,accept:e.accept,multiple:e.multiple,outerHTML:e.outerHTML.slice(0,800)})),formControls:[...document.querySelectorAll('input:not([type=file]),select,textarea')].filter(e=>e.offsetParent).map(e=>({tag:e.tagName,id:e.id,className:e.className,type:e.type,value:e.value,min:e.min,max:e.max,ariaLabel:e.getAttribute('aria-label'),outerHTML:e.outerHTML.slice(0,800)})),buttons:[...document.querySelectorAll('button,[role=button]')].filter(e=>e.offsetParent).map(e=>({tag:e.tagName,id:e.id,className:e.className,ariaLabel:e.getAttribute('aria-label'),title:e.getAttribute('title'),text:(e.innerText||e.textContent||'').trim().slice(0,80),outerHTML:e.outerHTML.slice(0,600)})).slice(0,160),elements:[...document.querySelectorAll('[contenteditable]')].map((e,index)=>({index,tag:e.tagName,className:e.className,contenteditable:e.getAttribute('contenteditable'),role:e.getAttribute('role'),ariaLabel:e.getAttribute('aria-label'),text:(e.innerText||e.textContent||'').slice(0,120),outerHTML:e.outerHTML.slice(0,1200),ancestors:(()=>{const a=[];let n=e;for(let i=0;i<6&&n;i++,n=n.parentElement)a.push({tag:n.tagName,id:n.id,className:n.className});return a})()})),paragraphs:[...document.querySelectorAll('.se-text-paragraph')].slice(0,12).map((p,index)=>({index,text:p.textContent.slice(0,160),outerHTML:p.outerHTML.slice(0,800),rect:(()=>{const r=p.getBoundingClientRect();return{x:r.x,y:r.y,width:r.width,height:r.height}})(),ancestors:(()=>{const a=[];let n=p;for(let i=0;i<5&&n;i++,n=n.parentElement)a.push({tag:n.tagName,id:n.id,className:n.className});return a})()})),markers:{documentTitle:!!document.querySelector('.se-documentTitle'),mainContainer:!!document.querySelector('.se-main-container'),titleText:!!document.querySelector('.se-title-text'),textParagraphCount:document.querySelectorAll('.se-text-paragraph').length,componentCount:document.querySelectorAll('.se-component').length}}))()`,id);
      value.imageOuterHtml=await evaluate(cdp,attached.sessionId,`[...document.querySelectorAll('img.se-image-resource')].map(i=>i.outerHTML.slice(0,1600))`,id);
      value.imageComponents=await evaluate(cdp,attached.sessionId,`[...document.querySelectorAll('img.se-image-resource')].map(i=>(i.closest('.se-component')||i.parentElement).outerHTML.slice(0,5000))`,id);
      value.frameRects=await evaluate(cdp,attached.sessionId,`[...document.querySelectorAll('iframe')].map(f=>{const r=f.getBoundingClientRect();return{id:f.id,name:f.name,x:r.x,y:r.y,width:r.width,height:r.height}})`,id);
      value.selection=await evaluate(cdp,attached.sessionId,`(()=>{const s=getSelection();const n=s?.anchorNode;const e=n?.nodeType===1?n:n?.parentElement;return{rangeCount:s?.rangeCount||0,text:s?.toString()||'',anchorTag:e?.tagName||'',anchorId:e?.id||'',anchorClass:e?.className||'',anchorText:e?.textContent?.slice(0,120)||''}})()`,id);
      rows.push({contextId:id,contextName:context?.name||'',...value});
    }catch{}
  }
  return rows;
}
async function capture(cdp,sessionId,file){const r=await cdp.send('Page.captureScreenshot',{format:'png',captureBeyondViewport:false},sessionId);fs.writeFileSync(file,Buffer.from(r.data,'base64'))}

async function main(){
  const a=parseArgs(process.argv.slice(2));
  const port=Number(a.port);const version=await json(`http://127.0.0.1:${port}/json/version`);const cdp=new Cdp(version.webSocketDebuggerUrl);await cdp.connect();
  try{
    const targets=(await cdp.send('Target.getTargets')).targetInfos.filter(t=>t.type==='page');
    const blogTarget=targets.find(t=>isAuthorizedNaverUrl(t.url,a['blog-id']));
    const auth=await verifyNaverAuthCookies(cdp);
    if(a.mode==='preflight'){
      const editorProbe=blogTarget?await probeNewEditorAccess(cdp,a['write-url']):{verified:false,reason:'NAVER_TAB_UNAVAILABLE'};
      const ready=!!(blogTarget&&editorProbe.verified);
      const out=ready?{status:'Ready',errorCode:'',reason:'전용 Chrome DevTools 연결과 새 글 편집기 접근을 실제로 확인했습니다.',extensionConnected:false,directChromeConnected:true,naverTabReadVerified:true,ownerLoginVerified:true,newEditorAccessVerified:true,browserId:`cdp:${port}`,tabId:blogTarget.targetId,url:blogTarget.url}:{status:'Failed',errorCode:blogTarget?'NAVER_LOGIN_REQUIRED':'NAVER_TAB_UNAVAILABLE',reason:blogTarget?'자동화 전용 Chrome에서 새 글 편집기가 로그인 화면으로 전환되었습니다. 이 전용 Chrome에서 네이버 로그인을 완료한 뒤 다시 실행하세요.':'전용 Chrome에서 네이버 블로그 탭을 확인할 수 없습니다.',extensionConnected:false,directChromeConnected:true,naverTabReadVerified:!!blogTarget,ownerLoginVerified:false,newEditorAccessVerified:false,authCookiePairPresent:auth.verified,browserId:`cdp:${port}`,tabId:blogTarget?.targetId||'',url:blogTarget?.url||'',probeReason:editorProbe.reason||''};
      atomicWrite(a.result,out);return;
    }
    if(a.mode==='inspect'){
      const editorTarget=a['target-id']?targets.find(t=>t.targetId===a['target-id']):targets.find(t=>isAuthorizedNaverUrl(t.url,a['blog-id'],{allowWrite:true}));
      if(!editorTarget){atomicWrite(a.result,{status:'Failed',reason:'EDITOR_TARGET_NOT_FOUND'});return}
      const attached=await attach(cdp,editorTarget.targetId);
      await sleep(1000);
      if(a['select-last-image']){
        const editorContext=await findEditorContext(cdp,attached,5000);
        const rect=await evaluate(cdp,attached.sessionId,`(()=>{const images=[...document.querySelectorAll('img.se-image-resource')];const e=images.at(-1);if(!e)return null;e.scrollIntoView({block:'center'});const r=e.getBoundingClientRect();return{x:r.x+r.width/2,y:r.y+r.height/2}})()`,editorContext.contextId);
        if(rect){await cdp.send('Input.dispatchMouseEvent',{type:'mouseMoved',x:rect.x,y:rect.y},attached.sessionId);await cdp.send('Input.dispatchMouseEvent',{type:'mousePressed',x:rect.x,y:rect.y,button:'left',clickCount:1},attached.sessionId);await cdp.send('Input.dispatchMouseEvent',{type:'mouseReleased',x:rect.x,y:rect.y,button:'left',clickCount:1},attached.sessionId);await sleep(500)}
        if(a['open-image-size']){await clickVisible(cdp,attached.sessionId,editorContext.contextId,'.se-resizing-toolbar-button');await sleep(300)}
      }
      const screenshot=path.join(a['run-dir'],`inspect-${editorTarget.targetId}.png`);
      await capture(cdp,attached.sessionId,screenshot);
      atomicWrite(a.result,{status:'Ready',targetId:editorTarget.targetId,targetUrl:editorTarget.url,screenshot,contexts:await inspectEditableDom(cdp,attached)});
      return;
    }
    const pkg=readJson(a.package);const plan=readJson(pkg.editorPlan);plan.blogId=a['blog-id'];plan.runDir=a['run-dir'];
    const missingImages=plan.actions.filter(x=>x.type==='UploadImageAtAnchor'&&!fs.existsSync(x.path)).map(x=>x.path);
    if(missingImages.length){atomicWrite(a.result,{status:'Blocked',reason:'IMAGE_FILES_REQUIRED',missingImages,publicationSettingsOpened:false,published:false});return}
    const created=await cdp.send('Target.createTarget',{url:a['write-url'],newWindow:false});
    await cdp.send('Target.activateTarget',{targetId:created.targetId});
    const attached=await attach(cdp,created.targetId);
    let context;
    try{context=await findEditorContext(cdp,attached)}catch(e){
      const outer=await currentUrl(cdp,attached.sessionId).catch(()=> '');
      if(/nid\.naver\.com/.test(outer)) await cdp.send('Target.closeTarget',{targetId:created.targetId}).catch(()=>{});
      throw e;
    }
    const outer=await currentUrl(cdp,attached.sessionId);
    if(/nid\.naver\.com/.test(outer)){await cdp.send('Target.closeTarget',{targetId:created.targetId}).catch(()=>{});atomicWrite(a.result,{status:'Blocked',reason:'NAVER_LOGIN_REQUIRED',publicationSettingsOpened:false,published:false});return}
    assertNewPostSafety(outer,a['blog-id']);
    await dismissRecoveryDialog(cdp,attached.sessionId,context.contextId);
    await cdp.send('Target.activateTarget',{targetId:created.targetId});
    await sleep(600);
    const prepared=await prepareEditor(cdp,attached,context.contextId,plan);
    const observed=await inspectEditor(cdp,attached,context.contextId,plan);
    const pc=path.join(a['run-dir'],'pc.png');await capture(cdp,attached.sessionId,pc);
    await cdp.send('Emulation.setDeviceMetricsOverride',{width:390,height:844,deviceScaleFactor:1,mobile:true},attached.sessionId);await sleep(500);
    const mobileObserved=await inspectEditor(cdp,attached,context.contextId,plan);const mobile=path.join(a['run-dir'],'mobile.png');await capture(cdp,attached.sessionId,mobile);
    await cdp.send('Emulation.clearDeviceMetricsOverride',{},attached.sessionId);
    const measurement=path.join(a['run-dir'],'measurement.json');
    const pcImages=observed.body?.images||[];const mobileImages=mobileObserved.body?.images||[];
    const uploaded=prepared.uploadedImages||[];
    const imagesVerified=prepared.imageUploadCount===pcImages.length&&prepared.imageUploadCount===mobileImages.length&&uploaded.length===prepared.imageUploadCount&&uploaded.every(i=>/^https:\/\/blogfiles\.pstatic\.net\//.test(i.src)&&Math.abs(i.width-400)<=2&&i.centered);
    const imageFileNames=uploaded.map(i=>path.basename(i.sourcePath));const imageServerUrls=uploaded.map(i=>i.src);
    const m={schemaVersion:1,measurementSource:'RenderedNaverDomAndScreen',pc:{horizontalOverflow:!!observed.body?.horizontalOverflow,imageFileNames,imageServerUrls,imageWidths:pcImages.map(i=>i.width),imagesCentered:pcImages.map(i=>i.centered),rawUrlVisible:!!observed.body?.rawUrlVisible,sourceLinks:observed.body?.links||[]},mobile:{horizontalOverflow:!!mobileObserved.body?.horizontalOverflow,imageFileNames,imageServerUrls,imageWidths:mobileImages.map(i=>i.width),imagesCentered:mobileImages.map(i=>i.centered),rawUrlVisible:!!mobileObserved.body?.rawUrlVisible},secondPass:{wholeArticleFromStart:true,titleVerified:normalizeText(observed.title)===normalizeText(plan.title),bodyVerified:!!observed.body?.text,headingsVerified:observed.headingsVerified,imagesVerified,linksVerified:(observed.body?.links?.length||0)>0}};
    atomicWrite(measurement,m);
    atomicWrite(a.result,{status:'Blocked',reason:'CONTENT_AND_IMAGES_VERIFIED_TAGS_REQUIRE_PUBLICATION_SETTINGS',editorUrl:outer,publicationSettingsOpened:false,published:false,imagesGenerated:imagesVerified,imagesOptimized:imagesVerified,imagesUploaded:imagesVerified,titleVerified:m.secondPass.titleVerified,bodyVerified:m.secondPass.bodyVerified,linksVerified:m.secondPass.linksVerified,tagsVerified:false,formatVerified:m.secondPass.headingsVerified,mobileVerified:!m.mobile.horizontalOverflow,secondPassVerified:false,pcScreenshot:pc,mobileScreenshot:mobile,measurementFile:measurement});
  } finally {cdp.close()}
}
// Windows의 한글/공백/OneDrive 경로는 argv 경로와 import.meta.url의 문자열 표현이
// 달라질 수 있다. 실행 래퍼가 항상 --mode를 전달하므로 이를 진입점 표식으로 쓴다.
if(process.argv.includes('--mode')) main().catch(e=>{
  const message=String(e?.stack||e);
  console.error(message);
  try{
    const a=parseArgs(process.argv.slice(2));
    if(a.result) atomicWrite(a.result,{
      status:'Blocked',
      reason:String(e?.message||e),
      errorStack:message,
      publicationSettingsOpened:false,
      published:false
    });
  }catch{}
  process.exitCode=1;
});
