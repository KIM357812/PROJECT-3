// The host supplies the documented Chrome-tab APIs. No page-script mutations.
export function createEditorRunner(domTab, nativeTab) {
  const frame = domTab.playwright.frameLocator('#mainFrame');
  const clean = s => s.replace(/[\u200b\ufeff]/g,'').replace(/\s+/g,' ').trim();
  async function paragraph(text) {
    const rows = await frame.locator('p').evaluateAll(ps => ps.map(p=>({id:p.id,text:p.textContent})));
    const found = rows.filter(p=>clean(p.text)===clean(text));
    if(found.length!==1) throw Error('Exact paragraph count: '+found.length+' '+text.slice(0,35));
    return frame.locator('#'+found[0].id);
  }
  async function select(text) {
    const p=typeof text==='string'?await paragraph(text):text;
    // Locator clicks can focus a virtualized off-screen paragraph without scrolling.
    // Never clamp an off-screen target to an unrelated visible paragraph.
    for(let attempt=0;attempt<30;attempt++) {
      const bounds=await p.evaluate(p=>{const r=p.getBoundingClientRect();return {top:r.top,bottom:r.bottom,viewport:p.ownerDocument.documentElement.clientHeight}});
      if(bounds.top>=155&&bounds.top<bounds.viewport-40) break;
      await nativeTab.scroll([800,400],bounds.top<155?'up':'down',0.5);
      await nativeTab.getAXState({emit:false});
      if(attempt===29) throw Error('Paragraph could not be scrolled into view');
    }
    const rect=await p.evaluate(p=>{const r=p.getBoundingClientRect();return {x:r.x+12,y:Math.max(170,Math.min(r.y+12,p.ownerDocument.documentElement.clientHeight-30))}});
    const outer=await domTab.playwright.locator('#mainFrame').evaluate(f=>{const r=f.getBoundingClientRect();return {x:r.x,y:r.y}});
    await nativeTab.click([rect.x+outer.x,rect.y+outer.y],{clickCount:3});
    await nativeTab.getAXState({emit:false});
    return p;
  }
  async function button(name) {
    if(await frame.getByRole('button',{name:name+' 선택됨',exact:true}).count()===1) {
      await frame.getByRole('button',{name:name+' 선택됨',exact:true}).click(); return;
    }
    const toolbar=frame.getByRole('banner').getByRole('button',{name,exact:true});
    if(await toolbar.count()===1) await toolbar.click();
    else await frame.getByRole('button',{name,exact:true}).click();
  }
  async function size(px) {
    await button('글자 크기 변경'); await button(String(px));
  }
  async function inspect(text) {
    return (await paragraph(text)).evaluate(p=>({
      text:p.textContent,
      runs:Array.from(p.querySelectorAll('span.__se-node')).map(s=>({text:s.textContent,size:+getComputedStyle(s).fontSize.replace('px',''),bold:!!s.querySelector('b,strong')})),
      lineHeight:getComputedStyle(p).lineHeight,
      componentClass:p.closest('.se-component')?.className||'',
      paragraphClass:p.className||'',
      html:p.outerHTML
    }));
  }
  async function apply(action) {
    const url=await domTab.url();
    if(url!=='https://blog.naver.com/ij1128?Redirect=Write&') throw Error('Not the authorized new-post editor');
    const p=await select(action.text);
    if(action.action==='ApplyHeadingByExactText') {
      // Mobile Naver ignores the line-height of a body paragraph that merely
      // looks like a heading.  Convert it to Naver's native section-title
      // component first, then explicitly restore the approved 19/16px size.
      // Once isolated as a section-title component, Ctrl+A is scoped to that
      // component and reliably selects every text run (including wrapped text).
      await button('문단 서식 변경'); await button('소제목');
      await select(action.text);
      await nativeTab.pressKey(null,'ctrl+a');
      await nativeTab.getAXState({emit:false});
      await size(action.fontSizePx===17?16:action.fontSizePx);
      if(await frame.getByRole('button',{name:'굵기 적용',exact:true}).count()) await button('굵기 적용');
    } else if(action.action==='ApplyMixedCalloutParagraphByExactText') {
      if(await frame.getByRole('banner').getByRole('button',{name:'굵기 해제',exact:true}).count()) await button('굵기 해제');
      // Replace only the selected paragraph, preserving its surrounding callout.
      const escape=s=>s.replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;');
      let html=escape(action.text);
      for(const label of action.boldLabels) html=html.replace(escape(label),'<b>'+escape(label)+'</b>');
      await nativeTab.paste(null,'<p style="font-size:15px;font-weight:400;line-height:1.6"><span style="font-size:15px;font-weight:400">'+html+'</span></p>',{format:'html'});
      await nativeTab.getAXState({emit:false});
      for(const label of action.boldLabels) {
        if(!action.text.startsWith(label)) throw Error('Only a leading fact label is supported');
        await select(action.text);
        await nativeTab.pressKey(null,'Left');
        for(const character of label) await nativeTab.pressKey(null,'Shift_L+Right');
        await nativeTab.getAXState({emit:false});
        if(await frame.getByRole('banner').getByRole('button',{name:'굵기 적용',exact:true}).count()) await button('굵기 적용');
      }
    } else if(['ApplyBodyParagraphByExactText','ApplyCalloutBodyByExactText','ApplyCalloutTitleByExactText'].includes(action.action)) {
      await size(15);
      const desired=action.action==='ApplyCalloutTitleByExactText';
      const control=desired?'굵기 적용':'굵기 해제';
      if(await frame.getByRole('banner').getByRole('button',{name:control,exact:true}).count()) await button(control);
    } else throw Error('Unsupported action: '+action.action);
    const observed=await inspect(action.text);
    const expected=action.fontSizePx===17?16:action.fontSizePx;
    if(!observed.runs.length || observed.runs.some(r=>r.size!==expected)) throw Error('Rendered font size mismatch: '+JSON.stringify(observed));
    if(action.action==='ApplyHeadingByExactText' && !/\bse-sectionTitle\b/.test(observed.componentClass)) {
      throw Error('Heading is not a native Naver section-title component: '+JSON.stringify(observed));
    }
    if(action.action==='ApplyMixedCalloutParagraphByExactText') {
      const bold=clean(observed.runs.filter(r=>r.bold).map(r=>r.text).join(''));
      if(bold!==clean(action.boldLabels.join(''))) throw Error('Inline bold mismatch: '+bold);
    }
    return {sequence:action.sequence,status:'TypographyVerified',observed,spacingVerified:false};
  }
  async function space(action) {
    const p=await paragraph(action.text);
    const adjacent=await p.evaluate(p=>{
      const component=p.closest('.se-component');
      const previous=component?.previousElementSibling;
      const next=component?.nextElementSibling;
      const r=component?.getBoundingClientRect();
      const pr=previous?.getBoundingClientRect();
      const nr=next?.getBoundingClientRect();
      return {
        componentClass:component?.className||'',
        before:pr&&r?r.top-pr.bottom:null,
        after:nr&&r?nr.top-r.bottom:null,
        previousClass:previous?.className||'',
        nextClass:next?.className||''
      };
    });
    if(!/\bse-sectionTitle\b/.test(adjacent.componentClass)) throw Error('Native section-title component missing');
    if(adjacent.before===null || adjacent.after===null || adjacent.before<0 || adjacent.after<0) {
      throw Error('Native section-title spacing could not be measured: '+JSON.stringify(adjacent));
    }
    // Naver applies different absolute values in PC and mobile preview.  The
    // stable semantic invariant is the one the user requested: the heading is
    // visually attached to the following content, not the preceding paragraph.
    if(adjacent.before-adjacent.after<6) throw Error('Heading hierarchy is unclear: '+JSON.stringify(adjacent));
    return adjacent;
  }
  async function audit(plan) {
    const headings=plan.actions.filter(a=>a.action==='ApplyHeadingByExactText');
    const facts=plan.actions.filter(a=>a.action==='ApplyMixedCalloutParagraphByExactText'&&/^(누가|무엇을|언제|어디서|어떻게|왜)\s/.test(a.text));
    if(facts.length!==6) throw Error('Six source fact rows are required');
    const records=[];
    for(const a of [...headings,...facts]) {
      const observed=await inspect(a.text);
      const gaps=a.action==='ApplyHeadingByExactText'?await space(a):await (await paragraph(a.text)).evaluate(p=>({
        before:p.previousElementSibling?.getBoundingClientRect().height,
        after:p.nextElementSibling?.getBoundingClientRect().height,
        nextText:p.nextElementSibling?.nextElementSibling?.textContent
      }));
      const px=a.fontSizePx===17?16:a.fontSizePx;
      const bold=clean(observed.runs.filter(r=>r.bold).map(r=>r.text).join(''));
      const valid=observed.runs.length>0 && observed.runs.every(r=>r.size===px) &&
        (a.action==='ApplyHeadingByExactText'
          ? observed.runs.every(r=>r.bold)&&/\bse-sectionTitle\b/.test(observed.componentClass)&&gaps.before-gaps.after>=6
          : bold===clean(a.boldLabels.join('')));
      records.push({text:a.text,valid,observed,gaps});
    }
    for(const a of plan.actions.filter(a=>a.action==='ApplyBodyParagraphByExactText')) {
      const observed=await inspect(a.text);
      records.push({text:a.text,valid:observed.runs.length>0&&observed.runs.every(r=>r.size===15&&!r.bold),observed});
    }
    return {scope:'BodyTypographyHeadingsAndSixFacts',passed:records.every(r=>r.valid),records,publicationAttempted:false};
  }
  async function run(plan) {
    if(!plan.publicationForbidden || plan.mode!=='RepairUnsavedNewPostFormatting') throw Error('Unsupported execution plan');
    const headings=plan.actions.filter(a=>a.action==='ApplyHeadingByExactText');
    const facts=plan.actions.filter(a=>a.action==='ApplyMixedCalloutParagraphByExactText'&&/^(누가|무엇을|언제|어디서|어떻게|왜)\s/.test(a.text));
    for(const a of [...plan.actions.filter(a=>a.action==='ApplyBodyParagraphByExactText'),...headings,...facts]) await apply(a);
    for(const a of headings) await space(a);
    return audit(plan);
  }
  async function normalize(text, bold, percent=160) {
    await select(text); await size(15);
    const control=bold?'굵기 적용':'굵기 해제';
    if(await frame.getByRole('banner').getByRole('button',{name:control,exact:true}).count()) await button(control);
    await button('줄간격 열기'); await button(percent+'%');
    const result=await inspect(text);
    if(result.runs.some(r=>r.size!==15||r.bold!==bold)) throw Error('Typography verification failed: '+text);
    return result;
  }
  async function repairRemainder(plan) {
    const rows=await frame.locator('article p').evaluateAll(ps=>ps.map(p=>({text:p.textContent,
      table:!!p.closest('table'),title:!!p.closest('table')&&p===p.closest('table').querySelector('p'),
      header:!!p.closest('tr')&&p.closest('tr')===p.closest('table')?.querySelector('tr'),
      cellCount:p.closest('table')?.querySelectorAll('td,th').length})));
    const results=[];
    for(const row of rows) {
      if(!clean(row.text)||/^(누가|무엇을|언제|어디서|어떻게|왜)\s/.test(row.text)) continue;
      if(row.table) results.push(await normalize(row.text,row.cellCount>1?row.header:row.title));
      else if(row.text.startsWith('참고자료')) results.push(await normalize(row.text,false));
    }
    for(const a of plan.actions.filter(a=>a.action==='ApplyBodyParagraphByExactText')) results.push(await normalize(a.text,false,180));
    return results;
  }
  async function measureGaps() {
    return frame.locator('article').evaluate(el=>{
      const blocks=Array.from(el.querySelectorAll('p,img')).filter(p=>p.tagName==='IMG'||(p.textContent.trim()&&!['사진 설명을 입력하세요.','AI 활용 설정'].includes(p.textContent.trim())));
      return blocks.map((p,i)=>({id:p.id,text:p.textContent,tag:p.tagName,
        gap:i?p.getBoundingClientRect().top-blocks[i-1].getBoundingClientRect().bottom:null,
        beforeId:p.previousElementSibling?.id,beforeText:p.previousElementSibling?.textContent,
        beforeHeight:p.previousElementSibling?.getBoundingClientRect().height}));
    });
  }
  async function adjustExistingGap(text,target) {
    const row=(await measureGaps()).find(r=>clean(r.text||'')===clean(text));
    if(!row) throw Error('Gap target missing');
    if(Math.abs(row.gap-target)<1) return row;
    if(!row.beforeId||clean(row.beforeText||'')) return {...row,unresolved:true,reason:'No adjustable spacer'};
    const height=target-(row.gap-row.beforeHeight);
    if(height<0) return {...row,unresolved:true,reason:'Native component spacing exceeds target'};
    const spacer=frame.locator('#'+row.beforeId);
    await select(spacer);
    await nativeTab.paste(null,'<p style="line-height:'+(height/11)+';font-size:11px"><span style="font-size:11px">&nbsp;</span></p>',{format:'html'});
    await nativeTab.getAXState({emit:false});
    const result=(await measureGaps()).find(r=>clean(r.text||'')===clean(text));
    return {...result,unresolved:Math.abs(result.gap-target)>1};
  }
  return {apply,inspect,space,audit,run,normalize,repairRemainder,measureGaps,adjustExistingGap};
}
