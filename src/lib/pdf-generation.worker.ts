import {createLoanPdf} from './pdfDocument'
import type {Loan,Equipment} from './domain'
self.onmessage=async({data}:{data:{loan:Loan;equipment:Equipment[]}})=>{
 try{const blob=await createLoanPdf(data.loan,data.equipment);self.postMessage({blob})}
 catch(error){self.postMessage({error:error instanceof Error?error.message:'PDF를 생성하지 못했습니다.'})}
}
