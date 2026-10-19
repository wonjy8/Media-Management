import {displayedCode} from './equipmentCodes'
import {supabase,demoMode} from './supabase'
import {allPages,downloadCsv} from './csv'
import type {CsvValue} from './csv'
import {loanState,today} from './domain'
import type {Equipment,Loan,Snapshot} from './domain'

type ReturnEvent={id:string;loanId:string;quantities:Record<string,number>;notes:string;createdAt:string;reversedAt?:string|null;reversalReason?:string}
type ExportLoan=Loan&{cancelledAt?:string|null}
type DbEquipment={id:string;code:string|null;name:string;model:string|null;group_id:string|null;quantity:number;repair_quantity:number;active:boolean;description:string|null;image_path:string|null}
type DbLoan={id:string;number:string;borrower_name:string|null;borrower_phone:string|null;borrower_department:string;borrower_position:string;reason:string;application_note:string|null;start_date:string;end_date:string;created_at:string;approved_at:string|null;checked_out_at:string|null;cancelled_at:string|null;rejected_at:string|null;rejection_reason:string|null;loan_items:{equipment_id:string;quantity:number;returned_quantity:number;equipment_snapshot:Snapshot}[]}
export function equipmentCsv(items:Equipment[]):CsvValue[][]{
 return [['관리번호','장비명','모델','그룹','총 수량','수리 필요 수량','대여 대상 수량','표시 상태','설명','이미지'],...items.map(e=>[e.code||'',e.name,e.model,e.group,e.qty,e.repair||0,e.active===false?0:Math.max(0,e.qty-(e.repair||0)),e.active===false?'비활성':'표시',e.description||'',e.image||''])]
}
export function koreanTime(value?:string|null){
 if(!value||Number.isNaN(Date.parse(value)))return ''
 const parts=new Intl.DateTimeFormat('en-CA',{timeZone:'Asia/Seoul',year:'numeric',month:'2-digit',day:'2-digit',hour:'2-digit',minute:'2-digit',second:'2-digit',hourCycle:'h23'}).formatToParts(new Date(value))
 const get=(key:string)=>parts.find(p=>p.type===key)?.value||''
 return `${get('year')}-${get('month')}-${get('day')} ${get('hour')}:${get('minute')}:${get('second')}`
}
export function movementCsv(loans:ExportLoan[],equipment:Equipment[],events:ReturnEvent[]):CsvValue[][]{
 const headers=['처리일시 (한국시간)','구분','신청번호','현재 신청상태','이름','전화번호','소속','직위','대여 사유','반출일','반납 예정일','관리번호','장비명','장비 소속','수량','현재 반납 수량','현재 미반납 수량','비고']
 const records:{time:number;row:CsvValue[]}[]=[]
 for(const loan of loans){
  const add=(kind:string,at:string|undefined|null,quantities:Record<string,number>,note='')=>{for(const [id,quantity] of Object.entries(quantities)){const eq=equipment.find(e=>e.id===id),snap=loan.snapshots?.[id];records.push({time:at?Date.parse(at):Number.MAX_SAFE_INTEGER,row:[koreanTime(at),kind,loan.id,loanState(loan),loan.name||'익명',loan.phone||'',loan.department||'',loan.position||'',loan.reason,loan.start,loan.end,displayedCode(snap,eq),snap?.name||eq?.name||'장비',snap?.department||eq?.group||'',quantity,loan.returned[id]||0,loan.out?Math.max(0,(loan.items[id]||0)-(loan.returned[id]||0)):0,note]})}}
  if(loan.out)add('반출',loan.checkoutAt,loan.items)
  else add(loan.rejected?'반려':loan.cancelled?'신청 취소':'현재 신청',loan.rejected?loan.rejectedAt:loan.cancelled?loan.cancelledAt:loan.createdAt,loan.items,loan.rejected?loan.rejectionReason||'':loan.note||'')
  const returns=events.filter(e=>e.loanId===(loan.databaseId||loan.id))
  for(const event of returns){add('반납',event.createdAt,event.quantities,event.notes);if(event.reversedAt)add('반납 취소',event.reversedAt,event.quantities,event.reversalReason||'')}
  // Older records may have cumulative returns but no individual return event.
  const recorded:Record<string,number>={};for(const event of returns.filter(e=>!e.reversedAt))for(const [id,q] of Object.entries(event.quantities))recorded[id]=(recorded[id]||0)+q
  const missing=Object.fromEntries(Object.entries(loan.returned).map(([id,q])=>[id,q-(recorded[id]||0)]).filter(([,q])=>Number(q)>0))
  if(Object.keys(missing).length)add('누적 반납 (일시 미기록)',null,missing,'개별 반납 이력이 없는 기존 기록')
 }
 records.sort((a,b)=>(Number.isFinite(a.time)?a.time:Number.MAX_SAFE_INTEGER)-(Number.isFinite(b.time)?b.time:Number.MAX_SAFE_INTEGER))
 return [headers,...records.map(r=>r.row)]
}
async function requireAdmin(){const {data,error}=await supabase!.rpc('is_admin');if(error||!data)throw Error('관리자 로그인과 관리 권한을 확인해 주세요.')}
export async function exportEquipment(demoItems:Equipment[]){
 let items=demoItems
 if(!demoMode){await requireAdmin();const [eq,groups]=await Promise.all([
  allPages<DbEquipment>(after=>{let q=supabase!.from('equipment').select('id,code,name,model,group_id,quantity,repair_quantity,active,description,image_path').order('id').limit(1000);if(after!==null)q=q.gt('id',after);return q}),
  allPages<{id:string;name:string}>(after=>{let q=supabase!.from('groups').select('id,name').order('id').limit(1000);if(after!==null)q=q.gt('id',after);return q})
 ]);items=eq.map(e=>({id:e.id,code:e.code,name:e.name,model:e.model||'',group:groups.find(g=>g.id===e.group_id)?.name||'기타',qty:e.quantity,repair:e.repair_quantity,active:e.active,description:e.description||'',image:e.image_path||''}))}
 downloadCsv(`장비목록-${today()}.csv`,equipmentCsv([...items].sort((a,b)=>(a.code||a.id).localeCompare(b.code||b.id))))
}
export async function exportMovements(demoLoans:Loan[],equipment:Equipment[]){
 let loans:ExportLoan[]=demoLoans;let events:ReturnEvent[]=[]
 if(demoMode){events=loans.flatMap(l=>(l.returnNotes||[]).filter(e=>e.items).map((e,i)=>({id:`${l.id}:${i}`,loanId:l.databaseId||l.id,quantities:e.items!,notes:e.notes,createdAt:e.createdAt,reversedAt:e.reversed?e.reversedAt||e.createdAt:null,reversalReason:e.reversalReason})))}
 else{await requireAdmin();const cutoff=new Date().toISOString();const [data,returns,undo]=await Promise.all([
  allPages<DbLoan>(after=>{let q=supabase!.from('loans').select('id,number,borrower_name,borrower_phone,borrower_department,borrower_position,reason,application_note,start_date,end_date,created_at,approved_at,checked_out_at,cancelled_at,rejected_at,rejection_reason,loan_items(equipment_id,quantity,returned_quantity,equipment_snapshot)').lte('created_at',cutoff).order('id').limit(1000);if(after!==null)q=q.gt('id',after);return q}),
  allPages<{id:string;loan_id:string;quantities:Record<string,number>;notes:string|null;created_at:string;reversed_at:string|null}>(after=>{let q=supabase!.from('return_events').select('id,loan_id,quantities,notes,created_at,reversed_at').lte('created_at',cutoff).order('id').limit(1000);if(after!==null)q=q.gt('id',after);return q}),
  allPages<{id:number;loan_id:string;created_at:string;reason:string|null}>(after=>{let q=supabase!.from('audit_log').select('id,loan_id,created_at,reason').eq('action','undo_return').lte('created_at',cutoff).order('id').limit(1000);if(after!==null)q=q.gt('id',after);return q})
 ]);loans=data.map(l=>({id:l.number,databaseId:l.id,name:l.borrower_name||'익명',phone:l.borrower_phone||'',department:l.borrower_department,position:l.borrower_position,reason:l.reason,note:l.application_note||'',start:l.start_date,end:l.end_date,createdAt:l.created_at,approved:!!l.approved_at,approvedAt:l.approved_at||undefined,out:!!l.checked_out_at,checkoutAt:l.checked_out_at||undefined,cancelled:!!l.cancelled_at,cancelledAt:l.cancelled_at,rejected:!!l.rejected_at,rejectedAt:l.rejected_at||undefined,rejectionReason:l.rejection_reason||'',items:Object.fromEntries(l.loan_items.map(i=>[i.equipment_id,i.quantity])),returned:Object.fromEntries(l.loan_items.map(i=>[i.equipment_id,i.returned_quantity])),snapshots:Object.fromEntries(l.loan_items.map(i=>[i.equipment_id,i.equipment_snapshot]))}));events=returns.map(e=>({id:e.id,loanId:e.loan_id,quantities:e.quantities,notes:e.notes||'',createdAt:e.created_at,reversedAt:e.reversed_at,reversalReason:undo.find(a=>a.loan_id===e.loan_id&&Date.parse(a.created_at)===Date.parse(e.reversed_at||''))?.reason||''}))}
 downloadCsv(`반출반납기록-${today()}.csv`,movementCsv(loans,equipment,events))
}
