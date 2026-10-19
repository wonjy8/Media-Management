import {callApi,supabase} from './supabase'
import type {Accessory,Equipment} from './domain'
export type AccessoryRow={equipment_id:string;accessory_id:string;quantity:number;selected_by_default:boolean}
export function missingAccessorySchema(error:{code?:string}){return error.code==='42P01'||error.code==='PGRST205'||error.code==='PGRST202'}
export async function loadAccessories(){
 const rows:AccessoryRow[]=[]
 for(let offset=0;;offset+=1000){
  const {data,error}=await supabase!.from('equipment_accessories').select('equipment_id,accessory_id,quantity,selected_by_default').order('equipment_id').order('accessory_id').range(offset,offset+999)
  if(error)throw error
  rows.push(...data as AccessoryRow[])
  if(data.length<1000)return rows
 }
}
export function linksFor(rows:AccessoryRow[],id:string):Accessory[]{return rows.filter(r=>r.equipment_id===id).map(r=>({id:r.accessory_id,quantity:r.quantity,selectedByDefault:r.selected_by_default}))}
export async function loadCatalog(args:{start:string;end:string}){
 const [equipment,links]=await Promise.all([callApi<Equipment[]>('catalog',args),loadAccessories().catch(error=>{if(missingAccessorySchema(error))return [];throw Error('부속품 정보를 불러오지 못했습니다. 다시 시도해 주세요.')})])
 return equipment.map(e=>({...e,accessories:linksFor(links,e.id)}))
}
// Accessories share the same inventory even when connected to different parents.
export function appendSelection(cart:Record<string,number>,selection:Record<string,number>,equipment:Equipment[]){
 const next={...cart}
 for(const [id,q] of Object.entries(selection)){
  const item=equipment.find(e=>e.id===id),limit=item&&item.active!==false?Math.max(0,item.qty-(item.repair||0)):0
  if(!Number.isInteger(q)||q<1||!item||(cart[id]||0)+q>limit)throw Error(`${item?.name||'장비'}의 대여용 수량을 확인해 주세요.`)
  next[id]=(cart[id]||0)+q
 }
 if(Object.values(next).filter(q=>q>0).length>100)throw Error('한 신청에는 최대 100종류의 장비를 담을 수 있습니다.')
 return next
}
