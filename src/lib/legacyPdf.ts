import { PDFDocument,rgb,PageSizes } from 'pdf-lib'
import fontkit from '@pdf-lib/fontkit'
import type { Loan,Equipment } from './domain'
let fontBytes:Promise<ArrayBuffer>|undefined
export async function createLegacyLoanPdf(loan:Loan,equipment:Equipment[]){
 const doc=await PDFDocument.create();doc.registerFontkit(fontkit)
 fontBytes??=fetch(`${import.meta.env.BASE_URL}fonts/NanumGothic-Regular.ttf`).then(r=>{if(!r.ok)throw Error('PDF 글꼴을 불러오지 못했습니다.');return r.arrayBuffer()}).catch(e=>{fontBytes=undefined;throw e})
 const font=await doc.embedFont(await fontBytes,{subset:false});const [width,height]=PageSizes.A4;const margin=32;const tableWidth=width-margin*2
 const lines=(text:string,maxWidth:number,size=10)=>{const result:string[]=[];for(const paragraph of text.split('\n')){let line='';for(const ch of paragraph){if(font.widthOfTextAtSize(line+ch,size)>maxWidth&&line){result.push(line);line=ch}else line+=ch}result.push(line)}return result}
 const entries=Object.entries(loan.items).map(([id,q],index)=>{const snap=loan.snapshots?.[id],e=equipment.find(e=>e.id===id);return [String(index+1),snap?.code||e?.code||id,snap?.name||e?.name||'장비',String(q),snap?.department||e?.group||'', '']})
 const cols=[30,75,171,38,133,tableWidth-447];const rowHeights=entries.map(row=>Math.max(30,...row.map((cell,i)=>lines(cell,cols[i]-12).length*14+14)))
 const approvals=loan.approvers||[];const signatureHeight=148+Math.max(1,approvals.length)*32
 const noteLines=lines(`특이사항: ${loan.note||'-'}`,tableWidth-16,9)
 const noteHeight=noteLines.length*13+24
 const pages:number[][]=[];let current:number[]=[];let used=0
 entries.forEach((_,i)=>{if(used+rowHeights[i]>height-390&&current.length){pages.push(current);current=[];used=0}current.push(i);used+=rowHeights[i]});pages.push(current)
 // Reserve last-page space for both full notes and fixed-bottom signatures.
 const reserved=signatureHeight+Math.min(noteHeight,120)+30
 if(pages[pages.length-1].reduce((n,i)=>n+rowHeights[i],0)>height-360-reserved)pages.push([])
 // Long notes continue on dedicated pages rather than being truncated.
 const noteChunks:string[][]=[];for(let i=0;i<noteLines.length;i+=16)noteChunks.push(noteLines.slice(i,i+16))
 if(noteLines.length>7){for(let i=0;i<noteChunks.length;i++)pages.push([])}
 pages.forEach((indices,pageIndex)=>{const page=doc.addPage([width,height]);const text=(value:string,x:number,y:number,size=10)=>page.drawText(value,{x,y,size,font,color:rgb(0,0,0)})
 const box=(x:number,y:number,w:number,h:number,shade=false)=>page.drawRectangle({x,y,width:w,height:h,borderWidth:.6,borderColor:rgb(0,0,0),...(shade?{color:rgb(.92,.92,.92)}:{})})
 box(margin,height-86,tableWidth,45,true);text('집기 반출 및 폐기 대장',margin+135,height-69,20)
 text(loan.id,margin,height-104,9);const reason=lines(`반출사유  ${loan.reason}`,tableWidth,10);reason.forEach((line,i)=>text(line,margin,height-125-i*13,10));text(`반출기간  ${loan.start} ~ ${loan.end}`,margin,height-145-(reason.length-1)*13,10)
 let y=height-184-(reason.length-1)*13;const drawRow=(values:string[],h:number,shade=false)=>{let x=margin;values.forEach((value,i)=>{box(x,y-h,cols[i],h,shade);lines(value,cols[i]-12).forEach((line,j)=>text(line,x+6,y-17-j*14));x+=cols[i]});y-=h}
 drawRow(['NO','관리번호','품명','수량','집기/장비 소속','확인'],28,true);indices.forEach(i=>drawRow(entries[i],rowHeights[i]))
 if(noteLines.length>7){const notePage=pageIndex-(pages.length-noteChunks.length);if(notePage>=0)noteChunks[notePage].forEach((line,i)=>text(line,margin+8,y-24-i*13,9))}
 else if(pageIndex===pages.length-1)noteLines.forEach((line,i)=>text(line,margin+8,y-22-i*13,9))
 if(pageIndex===pages.length-1){['* 미디어장비는 반출 전 미디어사역부 담당자를 통해 장비점검을 받아주세요.','* 미디어사역부 담당자와 사무실 담당자를 통해 반출 내용을 확인해 주세요.','* 방송 장비 외 악기류 및 시설장비는 미디어사역부 대여 대상이 아닙니다.','* 사용 후 반드시 장비점검 확인 후 반납해 주세요.','* 반출증은 발행부서와 관리부에서 각각 보관합니다.'].forEach((line,i)=>text(line,margin,margin+signatureHeight+12-i*11,7));let sy=margin+signatureHeight-80;text(`반출일  ${loan.start}`,margin,sy+20,10);const cells=[90,160,100,tableWidth-350];const signatureRow=(values:string[],h:number,shade=false)=>{let x=margin;values.forEach((value,i)=>{box(x,sy-h,cells[i],h,shade);lines(value,cells[i]-12,9).slice(0,2).forEach((line,j)=>text(line,x+6,sy-17-j*12,9));x+=cells[i]});sy-=h}
 signatureRow(['구분','소속','직위','성명 / 서명'],26,true);(approvals.length?approvals:[{name:'',department:'',position:''}]).forEach(a=>signatureRow(['반출 승인자',a.department||'',a.position||'',`${a.name||''}          (인)`],32));signatureRow(['반출자',loan.department||'',loan.position||'',`${loan.name}          (인)`],36)
 }
 text('서울영동교회',margin,18,8);text(`${pageIndex+1} / ${pages.length}`,width-margin-40,18,8)
 });doc.setTitle(loan.id);doc.setAuthor('서울영동교회 미디어사역부');const bytes=await doc.save();return new Blob([new Uint8Array(bytes)],{type:'application/pdf'})
}
