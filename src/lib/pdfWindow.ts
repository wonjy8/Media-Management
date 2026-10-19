import type {Loan,Equipment} from './domain'
import {routeHref} from './routes'
export function openApplicationPdf(loan:Loan,equipment:Equipment[]){
 const key='media-pdf-'+crypto.randomUUID()
 sessionStorage.setItem(key,JSON.stringify({loan:{...loan,phone:''},equipment:equipment.filter(e=>loan.items[e.id]).map(e=>({...e,image:'',description:undefined})),expires:Date.now()+10*60*1000}))
 try{const view=window.open(routeHref('application-pdf')+'#'+key,'_blank','popup,width=1000,height=900');if(!view)throw Error('팝업을 허용한 후 다시 눌러 주세요.');view.opener=null}finally{sessionStorage.removeItem(key)}
}
