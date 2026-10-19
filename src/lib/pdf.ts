import type {Loan,Equipment} from './domain'

// Font parsing and document serialization run outside the UI thread.
export function createLoanPdf(loan:Loan,equipment:Equipment[],signal?:AbortSignal):Promise<Blob>{
 if(signal?.aborted)return Promise.reject(new DOMException('PDF generation cancelled','AbortError'))
 return new Promise((resolve,reject)=>{
  const worker=new Worker(new URL('./pdf-generation.worker.ts',import.meta.url),{type:'module'})
  const cleanup=()=>{signal?.removeEventListener('abort',abort);worker.terminate()}
  const abort=()=>{cleanup();reject(new DOMException('PDF generation cancelled','AbortError'))}
  signal?.addEventListener('abort',abort,{once:true})
  worker.onmessage=({data}:{data:{blob?:Blob;error?:string}})=>{cleanup();if(data.blob)resolve(data.blob);else reject(new Error(data.error||'PDF를 생성하지 못했습니다.'))}
  worker.onerror=()=>{cleanup();reject(new Error('PDF를 생성하지 못했습니다. 새로고침 후 다시 시도해 주세요.'))}
  try{worker.postMessage({loan,equipment:equipment.filter(e=>loan.items[e.id]).map(e=>({id:e.id,code:e.code,name:e.name,group:e.group,model:'',qty:0,image:''}))})}catch(error){cleanup();reject(error)}
 })
}
export async function downloadLoanPdf(loan:Loan,equipment:Equipment[]){const url=URL.createObjectURL(await createLoanPdf(loan,equipment));const a=document.createElement('a');a.href=url;a.download=`${loan.id}.pdf`;a.click();setTimeout(()=>URL.revokeObjectURL(url),30000)}
