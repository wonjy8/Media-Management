import {useEffect,useState} from 'react'
import LoanPdf from './LoanPdf'
import type {Loan,Equipment} from '../lib/domain'
import '../App.css'
type DocumentData={loan:Loan;equipment:Equipment[];expires:number}
export default function PdfViewer(){
 const [data]=useState<DocumentData|null>(()=>{try{const value=JSON.parse(sessionStorage.getItem(location.hash.slice(1))||'null');return value?.expires>Date.now()&&!value.loan.rejected?value:null}catch{return null}})
 const [busy,setBusy]=useState(false),[error,setError]=useState(''),[ready,setReady]=useState(false)
 useEffect(()=>{document.title=data?data.loan.id+' · 신청서 PDF':'신청서 PDF'},[data])
 async function save(){if(!data)return;setBusy(true);try{const {downloadLoanPdf}=await import('../lib/pdf');await downloadLoanPdf(data.loan,data.equipment)}catch{setError('PDF를 저장하지 못했습니다. 다시 시도해 주세요.')}finally{setBusy(false)}}
 return <main className="document-viewer"><header className="document-toolbar"><span>{data?.loan.id||'신청서 PDF'}</span><div><button disabled={!data||busy} onClick={()=>void save()}>PDF 저장</button><button disabled={!data||!ready} onClick={()=>window.print()}>PDF 인쇄</button></div></header>{error&&<p role="alert">{error}</p>}{data?<LoanPdf loan={data.loan} equipment={data.equipment} onReady={setReady}/>:<p role="alert">신청 조회에서 신청서를 다시 열어 주세요.</p>}</main>
}
