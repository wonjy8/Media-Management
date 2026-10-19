import {useEffect,useRef,useState} from 'react'
import workerUrl from 'pdfjs-dist/build/pdf.worker.min.mjs?url'
import type {Loan,Equipment} from '../lib/domain'

export default function LoanPdf({loan,equipment}:{loan:Loan;equipment:Equipment[]}){
 const container=useRef<HTMLDivElement>(null)
 const [state,setState]=useState('PDF 미리보기 준비 중…')
 useEffect(()=>{
  let live=true
  let destroy:(()=>void)|undefined
  const root=container.current!
  root.replaceChildren()
  void (async()=>{
   try{
    const [{createLoanPdf},pdfjs]=await Promise.all([import('../lib/pdf'),import('pdfjs-dist')])
    if(!live)return
    pdfjs.GlobalWorkerOptions.workerSrc=workerUrl
    const blob=await createLoanPdf(loan,equipment)
    if(!live)return
    const task=pdfjs.getDocument({data:new Uint8Array(await blob.arrayBuffer())})
    destroy=()=>{void task.destroy()}
    const doc=await task.promise
    for(let i=1;i<=doc.numPages&&live;i++){
     const page=await doc.getPage(i)
     if(!live)return
     const viewport=page.getViewport({scale:1.4})
     const canvas=document.createElement('canvas')
     canvas.width=viewport.width;canvas.height=viewport.height
     canvas.setAttribute('role','img');canvas.setAttribute('aria-label',`신청서 ${i} / ${doc.numPages} 페이지`)
     root.append(canvas)
     await page.render({canvas,viewport}).promise
    }
    if(live)setState('')
   }catch{if(live)setState('미리보기를 불러오지 못했습니다. PDF 저장하기로 확인해 주세요.')}
  })()
  return()=>{live=false;destroy?.();root.replaceChildren()}
 },[loan,equipment])
 return <section className="pdf-preview" aria-label="신청서 PDF 미리보기">{state&&<p role="status">{state}</p>}<div ref={container}/></section>
}
