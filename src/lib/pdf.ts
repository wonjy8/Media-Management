import {PDFDocument,rgb,PageSizes} from 'pdf-lib'
import fontkit from '@pdf-lib/fontkit'
import type {Loan,Equipment} from './domain'
import {validateTemplate} from './pdfTemplate'
import type {ColumnKey} from './pdfTemplate'
let fontBytes:Promise<ArrayBuffer>|undefined
const logos=new Map<string,Promise<ArrayBuffer>>()
export async function createLoanPdf(loan:Loan,equipment:Equipment[]){
 if(!loan.pdfTemplate){const {createLegacyLoanPdf}=await import('./legacyPdf');return createLegacyLoanPdf(loan,equipment)}
 const t=loan.pdfTemplate;validateTemplate(t)
 const doc=await PDFDocument.create();doc.registerFontkit(fontkit)
 fontBytes??=fetch(`${import.meta.env.BASE_URL}fonts/NanumGothic-Regular.ttf`).then(r=>{if(!r.ok)throw Error('PDF 글꼴을 불러오지 못했습니다.');return r.arrayBuffer()}).catch(e=>{fontBytes=undefined;throw e})
 const font=await doc.embedFont(await fontBytes,{subset:false}),[W,H]=PageSizes.A4,L=t.margin,R=W-L,CW=R-L,fs=t.fontSize,lh=fs+3
 const black=rgb(.12,.13,.14),gray=rgb(.43,.45,.47),line=rgb(.8,.82,.83),light=rgb(.96,.965,.97)
 const wrap=(value:string,width:number,size=fs)=>{const result:string[]=[];for(const p of String(value).split('\n')){let row='';for(const ch of p){if(row&&font.widthOfTextAtSize(row+ch,size)>width){result.push(row);row=ch}else row+=ch}result.push(row)}return result}
 type Page=ReturnType<typeof doc.addPage>
 const text=(p:Page,v:string,x:number,y:number,size=fs,color=black,bold=false)=>{p.drawText(v,{x,y:H-y-size,font,size,color});if(bold)p.drawText(v,{x:x+.18,y:H-y-size,font,size,color})}
 const right=(p:Page,v:string,x:number,y:number,size=fs,color=black)=>text(p,v,x-font.widthOfTextAtSize(v,size),y,size,color)
 const hline=(p:Page,y:number,color=line,width=.5)=>p.drawLine({start:{x:L,y:H-y},end:{x:R,y:H-y},color,thickness:width})
 const shade=(p:Page,y:number,h:number)=>p.drawRectangle({x:L,y:H-y-h,width:CW,height:h,color:light})
 const fit=(v:string,width:number,size:number)=>{while(size>6&&font.widthOfTextAtSize(v,size)>width)size-=.25;return size}
 let logo:Awaited<ReturnType<typeof doc.embedPng>>|undefined
 if(t.showLogo){const url=t.logoUrl||`${import.meta.env.BASE_URL}pdf-assets/church-v1.png`;let promise=logos.get(url);if(!promise){promise=fetch(url).then(r=>{if(!r.ok)throw Error('로고를 불러오지 못했습니다.');return r.arrayBuffer()}).catch(e=>{logos.delete(url);throw e});logos.set(url,promise)}const bytes=await promise;const data=new Uint8Array(bytes);logo=data[0]===0x89?await doc.embedPng(bytes):await doc.embedJpg(bytes)}
 const columns=t.columns.filter(c=>c.visible),weights:Record<ColumnKey,number>={number:26,code:68,name:181,quantity:36,department:136,check:52}
 const totalWeight=columns.reduce((n,c)=>n+weights[c.key],0),widths=columns.map(c=>CW*weights[c.key]/totalWeight)
 const headerLines=columns.map((c,i)=>wrap(c.label,widths[i]-(c.key==='number'?6:16),fs-1)),headerH=Math.max(27,...headerLines.map(l=>l.length*(fs+2)+14))
 const entries=Object.entries(loan.items)
 const rows=entries.map(([id,quantity],index)=>{const e=equipment.find(e=>e.id===id),s=loan.snapshots?.[id];const values:Record<ColumnKey,string>={number:String(index+1),code:s?.code||e?.code||id,name:s?.name||e?.name||'장비',quantity:String(quantity),department:s?.department||e?.group||'',check:''};const cells=columns.map((c,i)=>c.key==='number'||c.key==='quantity'?[values[c.key]]:wrap(values[c.key],widths[i]-16,c.key==='code'?fs-1:fs));return {cells,height:Math.max(t.rowHeight,...cells.map(c=>c.length*lh+14))}})
 const org=[t.organization,t.department].filter(Boolean).join(' ')
 const date=(value:string)=>value.replace(/-/g,'. ')+'.'
 const period=`${date(loan.start)} – ${loan.start.slice(0,4)===loan.end.slice(0,4)?date(loan.end.slice(5)):date(loan.end)}`
 const metaValues=[loan.name,[loan.department,loan.position].filter(Boolean).join(' / '),period]
 const metaWidths=[CW*.31,CW*.34,CW*.35],meta=metaValues.map((v,i)=>wrap(v,metaWidths[i]-14,9.5)),metaTop=L+102
 const metaBottom=metaTop+17+Math.max(...meta.map(l=>l.length))*13+13
 const rule=Math.max(L+145,metaBottom),reasonLines=wrap(loan.reason,CW-76,10)
 const firstTop=rule+70+(reasonLines.length-1)*14,continuationTop=L+55,normalBottom=H-96
 const sigCols=[90,...(t.showSignatureDepartment?[134]:[]),...(t.showSignaturePosition?[102]:[])];sigCols.push(CW-sigCols.reduce((a,b)=>a+b,0))
 const approvers=loan.approvers?.length?loan.approvers:[{name:'',department:'',position:''}]
 const signatureData=[...approvers.map((a,i)=>[t.approverLabels[i]||t.approverLabels[0],...(t.showSignatureDepartment?[a.department||'']:[]),...(t.showSignaturePosition?[a.position||'']:[]),a.name||'']),[t.borrowerLabel,...(t.showSignatureDepartment?[loan.department||'']:[]),...(t.showSignaturePosition?[loan.position||'']:[]),loan.name]]
 const sigRows=signatureData.map(values=>{const cells=values.map((v,i)=>wrap(v,sigCols[i]-(i===values.length-1?48:20),fs));return {cells,height:Math.max(39,...cells.map(c=>c.length*lh+16))}})
 const sigTableTop=H-76-26-sigRows.reduce((n,r)=>n+r.height,0),sigHeadingTop=sigTableTop-23
 if(sigHeadingTop<continuationTop)throw Error('서명란 내용이 한 페이지에 들어가지 않습니다. 서명란 이름이나 글자 크기를 줄여 주세요.')
 const noticeLines=t.notices.filter(n=>n.trim()).map(n=>wrap(n,CW-12,fs-1))
 const noticeH=noticeLines.length?22+noticeLines.reduce((n,l)=>n+l.length*(fs+3)+5,0):0
 const noticeTop=noticeH?Math.min(L+396,sigHeadingTop-22-noticeH):sigHeadingTop,compactFooter=noticeTop>=continuationTop+headerH+Math.min(t.rowHeight,31)+35
 type Plan={indices:number[];notes?:{text:string;y:number;bullet:boolean}[];noticeTitle?:number;sign?:boolean}
 const plans:Plan[]=[{indices:[]}]
 const top=(i:number)=>i===0?firstTop:continuationTop
 const rowEnd=(i:number)=>top(i)+(plans[i].indices.length?headerH:0)+plans[i].indices.reduce((n,j)=>n+rows[j].height,0)
 rows.forEach((r,i)=>{let page=plans.length-1;if(rowEnd(page)+(plans[page].indices.length?0:headerH)+r.height>normalBottom){if(!plans[page].indices.length&&page>0)throw Error('장비 정보가 한 페이지보다 깁니다. 글자 크기나 표 구성을 조절해 주세요.');plans.push({indices:[]});page++}plans[page].indices.push(i)})
 if(compactFooter){
  let page=plans.length-1
  if(rowEnd(page)+35>noticeTop){
   const last=plans[page].indices.at(-1)
   const move=last!==undefined&&plans[page].indices.length>1&&continuationTop+headerH+rows[last].height+35<=noticeTop
   if(move)plans[page].indices.pop()
   plans.push({indices:move?[last!]:[]});page++
  }
  const plan=plans[page];plan.sign=true
  if(noticeLines.length){plan.noticeTitle=noticeTop;plan.notes=[];let y=noticeTop+22;noticeLines.forEach(lines=>{lines.forEach((value,i)=>{plan.notes!.push({text:value,y,bullet:i===0});y+=fs+3});y+=5})}
 }else{
  let page=plans.length-1,y=rowEnd(page)+45
  for(const paragraph of noticeLines){for(let i=0;i<paragraph.length;i++){
   if(y+(plans[page].noticeTitle===undefined?22:0)+fs+3>normalBottom){plans.push({indices:[]});page++;y=continuationTop}
   if(plans[page].noticeTitle===undefined){plans[page].noticeTitle=y;y+=22}
   ;(plans[page].notes??=[]).push({text:paragraph[i],y,bullet:i===0});y+=fs+3
  }y+=5}
  if(y>sigHeadingTop-20){plans.push({indices:[]});page++}
  plans[page].sign=true
 }
 plans.forEach((plan,index)=>{
  const p=doc.addPage(PageSizes.A4)
  if(logo)p.drawImage(logo,{x:L,y:H-(L+15),width:20,height:23})
  const brandX=L+(logo?30:0)
  text(p,t.organization,brandX,L-10,fit(t.organization,CW-70,10),black,true)
  text(p,t.department,brandX,L+5,fit(t.department,CW-70,8),gray)
  hline(p,L+31,black,1.4)
  if(index===0){
   text(p,t.title,L,L+50,fit(t.title,CW-155,25),black,true)
   right(p,'신청번호',R,L+52,7,gray);right(p,loan.id,R,L+66,fit(loan.id,150,10))
   let x=L
   ;['신청자','소속 / 직위','사용 기간'].forEach((label,i)=>{text(p,label,x,metaTop,8,gray);meta[i].forEach((v,j)=>text(p,v,x,metaTop+17+j*13,9.5));x+=metaWidths[i]})
   hline(p,rule);text(p,'사용 목적',L,rule+14,8,gray);reasonLines.forEach((v,i)=>text(p,v,L+76,rule+12+i*14,10))
   if(plan.indices.length){text(p,'신청 장비 목록',L,firstTop-25,11,black,true);right(p,`${entries.length}개 항목`,R,firstTop-23,8,gray)}
  }
  let y=top(index)
  if(plan.indices.length){
   hline(p,y,black,1);shade(p,y,headerH);let x=L
   columns.forEach((_,i)=>{headerLines[i].forEach((v,j)=>text(p,v,x+8,y+8+j*(fs+2),fs-1,gray));x+=widths[i]});y+=headerH
   for(const j of plan.indices){const r=rows[j];let x=L;columns.forEach((c,i)=>{r.cells[i].forEach((v,k)=>{const size=c.key==='code'?fs-1:c.key==='number'||c.key==='quantity'?fit(v,widths[i]-6,fs):fs,px=c.key==='number'||c.key==='quantity'?x+(widths[i]-font.widthOfTextAtSize(v,size))/2:x+8;text(p,v,px,y+10+k*lh,size,c.key==='number'||c.key==='code'?gray:black,c.key==='quantity')});x+=widths[i]});y+=r.height;hline(p,y)}
   if(index===plans.length-1||!plans.slice(index+1).some(p=>p.indices.length)){text(p,'합계',L+8,y+13,fs,black,true);right(p,`${entries.length}개 항목 · 총 ${Object.values(loan.items).reduce((a,b)=>a+b,0)}점`,R-8,y+13,fs+1)}
   else right(p,'장비 목록은 다음 페이지에 이어집니다.',R,y+15,8,gray)
  }
  if(plan.noticeTitle!==undefined)text(p,t.noticeHeading,L,plan.noticeTitle,fit(t.noticeHeading,CW,10),black,true)
  plan.notes?.forEach(n=>{if(n.bullet)text(p,'*',L,n.y,fs-1,gray);text(p,n.text,L+10,n.y,fs-1,gray)})
  if(plan.sign){
   text(p,t.signatureHeading,L,sigHeadingTop,fit(t.signatureHeading,CW,11),black,true);hline(p,sigTableTop,black,1);shade(p,sigTableTop,26)
   const headers=['구분',...(t.showSignatureDepartment?['소속']:[]),...(t.showSignaturePosition?['직위']:[]),'성명 / 서명'];let x=L
   headers.forEach((v,i)=>{text(p,v,x+10,sigTableTop+8,8,gray);x+=sigCols[i]})
   let sy=sigTableTop+26
   sigRows.forEach(r=>{let x=L;r.cells.forEach((lines,i)=>{lines.forEach((v,j)=>text(p,v,x+10,sy+13+j*lh,fs));x+=sigCols[i]});right(p,'(서명)',R-10,sy+13,8,gray);sy+=r.height;hline(p,sy)})
  }
  hline(p,H-52);text(p,org,L,H-41,fit(org,CW*.43,7),gray);const mid=font.widthOfTextAtSize(loan.id,7);text(p,loan.id,(W-mid)/2,H-41,7,gray);right(p,`${index+1} / ${plans.length}`,R,H-41,8,gray)
 })
 doc.setTitle(loan.id);doc.setAuthor(org)
 return new Blob([new Uint8Array(await doc.save())],{type:'application/pdf'})
}
export async function downloadLoanPdf(loan:Loan,equipment:Equipment[]){const url=URL.createObjectURL(await createLoanPdf(loan,equipment));const a=document.createElement('a');a.href=url;a.download=`${loan.id}.pdf`;a.click();setTimeout(()=>URL.revokeObjectURL(url),30000)}
