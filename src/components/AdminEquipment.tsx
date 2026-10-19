import { useCallback, useEffect, useMemo, useState } from 'react'
import { Plus, X, Pencil, Download } from 'lucide-react'
import { supabase, demoMode } from '../lib/supabase'
import { compressImage } from '../lib/images'
import {exportEquipment} from '../lib/exports'
import {loadAccessories,linksFor,parentsFor,loadEquipmentKinds,missingAccessorySchema} from '../lib/accessories'
import type {Accessory} from '../lib/domain'
import EquipmentLinksEditor from './EquipmentLinksEditor'
import {equipmentCodes,normalizeEquipmentCodes} from '../lib/equipmentCodes'

type Group = {id:string;name:string}
type Row = {is_accessory?:boolean;parents?:Accessory[];accessories?:Accessory[];id:string;code:string;name:string;model:string;group_id:string|null;image_path:string|null;description:string;quantity:number;repair_quantity:number;active:boolean}
export type DemoEquipment = {isAccessory?:boolean;accessories?:Accessory[];id:string;name:string;model:string;group:string;qty:number;image:string;available?:number;code?:string|null;description?:string;repair?:number;active?:boolean}
const empty:Omit<Row,'id'>={code:'',name:'',model:'',group_id:null,image_path:null,description:'',quantity:1,repair_quantity:0,active:true,is_accessory:false,parents:[],accessories:[]}
function message(error:unknown) {return error instanceof Error?error.message:typeof error==='object'&&error&&'message' in error?String(error.message):'저장하지 못했습니다.'}
export default function AdminEquipment({demoItems,onChange,onDemoChange,section}:{section:'equipment'|'groups';demoItems:DemoEquipment[];onChange:()=>Promise<void>;onDemoChange:(items:DemoEquipment[])=>void}) {
 const [rows,setRows]=useState<Row[]>([]),[groups,setGroups]=useState<Group[]>([]),[loading,setLoading]=useState(true),[error,setError]=useState(''),[busy,setBusy]=useState(false)
 const [editing,setEditing]=useState<string|null|undefined>(undefined),[form,setForm]=useState(empty),[photo,setPhoto]=useState<File|null>(null),[groupName,setGroupName]=useState(''),[groupEdit,setGroupEdit]=useState<string|null>(null),[search,setSearch]=useState(''),[equipmentStatus,setEquipmentStatus]=useState('all'),[status,setStatus]=useState(''),[accessoryReady,setAccessoryReady]=useState(demoMode),[rolesReady,setRolesReady]=useState(demoMode)
 const load=useCallback(async()=>{setLoading(true);setError('');try {
  if(demoMode){const gs=JSON.parse(localStorage.getItem('media-groups')||'null')||[...new Set(demoItems.map(x=>x.group))].map(name=>({id:name,name}));setGroups(gs);setRows(demoItems.map(e=>({is_accessory:e.isAccessory??demoItems.some(p=>p.accessories?.some(a=>a.id===e.id)),parents:demoItems.flatMap(p=>(p.accessories||[]).filter(a=>a.id===e.id).map(a=>({...a,id:p.id}))),accessories:e.accessories||[],id:e.id,code:e.code||'',name:e.name,model:e.model,group_id:gs.find((g:Group)=>g.name===e.group)?.id||null,image_path:e.image,description:e.description||'',quantity:e.qty,repair_quantity:e.repair||0,active:e.active!==false})));return}
  if(!supabase)throw new Error('서버 연결이 필요합니다.')
  const [eq,gs,links,kinds]=await Promise.all([supabase.from('equipment').select('*').order('code'),supabase.from('groups').select('*').order('name'),loadAccessories().catch(error=>{if(missingAccessorySchema(error))return null;throw error}),loadEquipmentKinds()]);setRolesReady(kinds!==null);setAccessoryReady(links!==null)
  if(eq.error)throw eq.error;if(gs.error)throw gs.error;setRows(eq.data.map(e=>({...e,code:e.code||'',model:e.model||'',description:e.description||'',is_accessory:e.is_accessory??(links||[]).some(a=>a.accessory_id===e.id),parents:parentsFor(links||[],e.id),accessories:linksFor(links||[],e.id)})));setGroups(gs.data)
 }catch(e){setError(message(e))}finally{setLoading(false)}},[demoItems])
 useEffect(()=>{queueMicrotask(()=>void load())},[load])
 const preview=useMemo(()=>photo?URL.createObjectURL(photo):'',[photo]);useEffect(()=>()=>{if(preview)URL.revokeObjectURL(preview)},[preview])
 function open(row?:Row){setEditing(row?.id||null);setForm(row?{...row}: {...empty});setPhoto(null);setError('');setStatus('')}
 function persistDemo(next:Row[],gs=groups){setRows(next);const items=next.map(e=>({isAccessory:e.is_accessory||false,accessories:e.accessories||[],id:e.id,code:e.code,name:e.name,model:e.model,group:gs.find(g=>g.id===e.group_id)?.name||'기타',qty:e.quantity,image:e.image_path||'',description:e.description,repair:e.repair_quantity,active:e.active}));onDemoChange(items)}
 async function save(event:React.FormEvent){event.preventDefault();if(busy)return;setBusy(true);setError('');let uploaded:string|null=null
 try{
  if(!form.name.trim()||!Number.isInteger(form.quantity)||!Number.isInteger(form.repair_quantity)||form.quantity<form.repair_quantity||form.repair_quantity<0)throw new Error('장비명과 수량을 확인해 주세요.')
  if((form.accessories||[]).length>50||(form.accessories||[]).some(a=>!Number.isInteger(a.quantity)||a.quantity<1||a.quantity>10000||a.id===editing))throw Error('부속품 연결과 수량을 확인해 주세요.')
  if(form.is_accessory&&!(form.parents||[]).length)throw Error('부속품이 종속될 장비를 하나 이상 선택해 주세요.')
  const code=normalizeEquipmentCodes(form.code)
  let image=form.image_path
  if(photo){const compressed=await compressImage(photo);if(demoMode){image=await new Promise<string>((resolve,reject)=>{const reader=new FileReader();reader.onload=()=>resolve(String(reader.result));reader.onerror=reject;reader.readAsDataURL(compressed)})}else{
    uploaded=`equipment/${crypto.randomUUID()}.jpg`;const {error}=await supabase!.storage.from('equipment-images').upload(uploaded,compressed,{contentType:'image/jpeg',upsert:false});if(error)throw new Error('이미지를 저장하지 못했습니다. 저장소 연결 상태를 확인해 주세요.');image=supabase!.storage.from('equipment-images').getPublicUrl(uploaded).data.publicUrl
  }}
  const data={...form,name:form.name.trim(),code,image_path:image};delete (data as Partial<Row>).id
  if(demoMode){
   if(rows.some(e=>e.id!==editing&&equipmentCodes(e.code).some(number=>equipmentCodes(code).includes(number))))throw Error('이미 사용 중인 관리번호입니다.')
   const id=editing||crypto.randomUUID()
   let next=editing?rows.map(e=>e.id===id?{...data,id}:e):[...rows,{...data,id}]
   next=next.map(e=>({...e,accessories:e.id===id&&form.is_accessory?[]:(e.accessories||[]).filter(a=>a.id!==id)}))
   if(form.is_accessory)next=next.map(e=>({...e,accessories:[...(e.accessories||[]),...(form.parents||[]).filter(p=>p.id===e.id).map(p=>({...p,id}))]}))
   if(next.some(e=>e.is_accessory&&(!next.some(parent=>parent.accessories?.some(a=>a.id===e.id))||e.accessories?.length))||next.some(e=>e.accessories?.some(a=>!next.find(child=>child.id===a.id)?.is_accessory)))throw Error('부속품은 일반 장비에 하나 이상 연결해야 하며, 다른 부속품을 연결할 수 없습니다.')
   persistDemo(next)
  }
  else {
   const {accessories,parents,...baseData}=data
   const equipmentData={...baseData,code:code||null};if(!rolesReady)delete equipmentData.is_accessory
   if(accessoryReady){const {data:saved,error}=await supabase!.rpc('admin_save_equipment_with_accessories',{p_equipment:equipmentData,p_accessories:form.is_accessory?[]:accessories||[],p_id:editing,...(rolesReady?{p_parents:form.is_accessory?parents||[]:[]}: {})});if(error){if(error.code==='23505')throw Error('이미 사용 중인 관리번호입니다.');throw error}if(!saved)throw Error('장비를 저장하지 못했습니다.')}
   else{const q=editing?supabase!.from('equipment').update(equipmentData).eq('id',editing):supabase!.from('equipment').insert(equipmentData);const {data:saved,error}=await q.select('id');if(error?.code==='23505')throw Error('이미 사용 중인 관리번호입니다.');if(error)throw error;if(!saved?.length)throw Error('저장 권한이 없습니다. 관리자 등록을 확인해 주세요.')}
   uploaded=null;await load();await onChange().catch(()=>setStatus('저장되었습니다. 목록을 새로고침해 주세요.'))
  }
  setEditing(undefined);setPhoto(null);setStatus('저장되었습니다.')
 }catch(e){if(uploaded)await supabase?.storage.from('equipment-images').remove([uploaded]);setError(message(e))}finally{setBusy(false)}}
 async function saveGroup(event:React.FormEvent){event.preventDefault();if(busy||!groupName.trim())return;setBusy(true);setError('');try{const name=groupName.trim();if(demoMode){if(groups.some(g=>g.name===name&&g.id!==groupEdit))throw new Error('이미 있는 그룹입니다.');const next=groupEdit?groups.map(g=>g.id===groupEdit?{...g,name}:g):[...groups,{id:crypto.randomUUID(),name}];setGroups(next);localStorage.setItem('media-groups',JSON.stringify(next));persistDemo(rows,next)}else{const q=groupEdit?supabase!.from('groups').update({name}).eq('id',groupEdit):supabase!.from('groups').insert({name});const {data,error}=await q.select('id');if(error?.code==='23505')throw new Error('이미 있는 그룹명입니다.');if(error||!data?.length)throw new Error('그룹을 저장하지 못했습니다. 관리 권한을 확인해 주세요.');await load();await onChange()}setGroupName('');setGroupEdit(null);setStatus('그룹이 저장되었습니다.')}catch(e){setError(message(e))}finally{setBusy(false)}}
 async function remove(kind:'group'|'equipment',id:string,name:string){
  if(busy||!window.confirm(kind==='group'?`${name} 그룹을 삭제할까요? 소속 장비는 기타로 이동합니다.`:`${name} 장비를 삭제할까요? 대여 이력이 있으면 기록을 보존하고 비활성화합니다.`))return
  setBusy(true);setError('');setStatus('')
  try{
   let archived=false
   if(demoMode){
    if(kind==='group'){const next=groups.filter(g=>g.id!==id);setGroups(next);localStorage.setItem('media-groups',JSON.stringify(next));persistDemo(rows.map(e=>e.group_id===id?{...e,group_id:null}:e),next)}
    else{const loans=JSON.parse(localStorage.getItem('media-loans')||'[]') as {items:Record<string,number>}[];archived=loans.some(l=>Object.hasOwn(l.items,id));const next=archived?rows.map(e=>e.id===id?{...e,active:false}:e):rows.filter(e=>e.id!==id).map(e=>({...e,accessories:e.accessories?.filter(a=>a.id!==id)}));persistDemo(next.map(e=>e.is_accessory&&!next.some(parent=>parent.accessories?.some(a=>a.id===e.id))?{...e,is_accessory:false,active:false}:e))}
   }else{
    const {data,error}=await supabase!.rpc('admin_delete_catalog',{p_kind:kind,p_id:id})
    if(error){if(error.code==='PGRST202')throw new Error('삭제 기능을 사용하려면 Supabase에서 005_catalog_delete.sql을 실행해 주세요.');throw error}
    archived=data==='archived';await load();await onChange()
   }
   if(kind==='group'&&groupEdit===id){setGroupEdit(null);setGroupName('')}
   setStatus(archived?'대여 이력이 있어 비활성화했습니다.':'삭제되었습니다.')
  }catch(e){setError(message(e))}finally{setBusy(false)}
 }
 async function csv(){if(busy)return;setBusy(true);setError('');try{await exportEquipment(demoItems)}catch(e){setError(message(e))}finally{setBusy(false)}}
 const tab=section
 const visibleRows=rows.filter(e=>`${e.name} ${e.code} ${e.model}`.toLowerCase().includes(search.toLowerCase())&&(equipmentStatus==='all'||(equipmentStatus==='inactive'?!e.active:equipmentStatus==='repair'?e.repair_quantity>0:e.active)))
 return <section className="equipment-management"><div className="management-toolbar">{tab==='equipment'&&<><button className="primary" onClick={()=>open()}><Plus size={15}/>장비 등록</button><button disabled={busy||loading} onClick={()=>void csv()}><Download size={15}/>전체 장비 CSV</button></>}</div>
 {error&&<p role="alert" className="management-error">{error}</p>}{status&&<p role="status" className="management-status">{status}</p>}
 {tab==='equipment'&&<div className="equipment-filters"><input aria-label="관리 장비 검색" placeholder="장비명, 관리번호 검색" value={search} onChange={e=>setSearch(e.target.value)}/><select aria-label="장비 상태" value={equipmentStatus} onChange={e=>setEquipmentStatus(e.target.value)}><option value="all">전체 상태</option><option value="active">목록 표시</option><option value="repair">수리 필요</option><option value="inactive">비활성</option></select></div>}{loading?<p className="empty">불러오는 중…</p>:tab==='groups'?<><form className="group-form" onSubmit={saveGroup}><label>그룹명<input value={groupName} maxLength={80} required onChange={e=>setGroupName(e.target.value)} placeholder="예: 음향"/></label><button className="primary" disabled={busy}>{groupEdit?'변경 저장':'그룹 추가'}</button>{groupEdit&&<button type="button" onClick={()=>{setGroupEdit(null);setGroupName('')}}>취소</button>}</form>{groups.map(g=><div className="management-row" key={g.id}><span>{g.name}</span><div className="catalog-row-actions"><button disabled={busy} onClick={()=>{setGroupEdit(g.id);setGroupName(g.name)}}>수정</button><button disabled={busy} aria-label={`${g.name} 그룹 삭제`} onClick={()=>void remove('group',g.id,g.name)}>삭제</button></div></div>)}</>:<>{!visibleRows.length&&<p className="empty">등록된 장비가 없거나 검색 결과가 없습니다.</p>}{visibleRows.map(e=><div className="management-row inventory-row" key={e.id}><div><strong>{e.name}</strong><small>{e.is_accessory?'부속품 · ':''}{e.code?`${e.code} · `:''}{groups.find(g=>g.id===e.group_id)?.name||'기타'} · 총 {e.quantity}개{e.repair_quantity>0?` · 수리 ${e.repair_quantity}개`:''}{!e.active?' · 비활성':''}</small></div><div className="catalog-row-actions"><button disabled={busy} aria-label={`${e.name} 수정`} onClick={()=>open(e)}><Pencil size={14}/>수정</button><button disabled={busy} aria-label={`${e.name} 장비 삭제`} onClick={()=>void remove('equipment',e.id,e.name)}>삭제</button></div></div>)}</>}
 {editing!==undefined&&<div className="overlay"><div className="dialog"><button className="close" aria-label="장비 편집 닫기" disabled={busy} onClick={()=>setEditing(undefined)}><X/></button><h2>{editing?'장비 수정':'장비 등록'}</h2><form onSubmit={save}><div className="form-grid"><label>장비명<input required maxLength={150} value={form.name} onChange={e=>setForm({...form,name:e.target.value})}/></label><label>관리번호<input aria-label="관리번호" aria-describedby="equipment-code-hint" maxLength={4200} value={form.code} onChange={e=>setForm({...form,code:e.target.value})} placeholder="예: CAM-001, CAM-002"/><small id="equipment-code-hint" className="field-hint">선택 입력 · 여러 개는 쉼표(,)로 구분</small></label><label>모델명<input maxLength={150} value={form.model} onChange={e=>setForm({...form,model:e.target.value})}/></label><label>그룹<select aria-label="그룹" value={form.group_id||''} onChange={e=>setForm({...form,group_id:e.target.value||null})}><option value="">기타</option>{groups.map(g=><option value={g.id} key={g.id}>{g.name}</option>)}</select></label><label>총 수량<input type="number" required min={0} max={10000} value={form.quantity} onChange={e=>setForm({...form,quantity:Number(e.target.value)})}/></label><label>수리 필요 수량<input type="number" required min={0} max={form.quantity} value={form.repair_quantity} onChange={e=>setForm({...form,repair_quantity:Number(e.target.value)})}/></label></div><label className="checkbox-label"><input type="checkbox" disabled={!rolesReady} checked={!!form.is_accessory} onChange={e=>setForm({...form,is_accessory:e.target.checked,accessories:e.target.checked?[]:form.accessories,parents:e.target.checked?form.parents:[]})}/>부속품</label>{!rolesReady&&<p className="field-hint">부속품 분류를 사용하려면 Supabase에 011_accessory_equipment_types.sql을 적용해 주세요.</p>}{accessoryReady&&<EquipmentLinksEditor key={form.is_accessory?'parents':'children'} id={editing} isAccessory={!!form.is_accessory} rows={rows} value={form.is_accessory?form.parents||[]:form.accessories||[]} onChange={value=>setForm({...form,[form.is_accessory?'parents':'accessories']:value})}/>}<label>설명 · 구성품 · 주의사항<textarea maxLength={2000} value={form.description||''} onChange={e=>setForm({...form,description:e.target.value})}/></label><label>장비 이미지<input type="file" accept="image/jpeg,image/png,image/webp" onChange={e=>setPhoto(e.target.files?.[0]||null)}/></label>{(preview||form.image_path?.startsWith('https://')||form.image_path?.startsWith('data:'))&&<img className="equipment-preview" src={preview||form.image_path!} alt="장비 이미지 미리보기"/>}<label className="checkbox-label"><input type="checkbox" checked={form.active} onChange={e=>setForm({...form,active:e.target.checked})}/>{form.is_accessory?'대여 가능':'대여 목록에 표시'}</label><p className="field-hint">비활성화해도 기존 대여 기록은 유지됩니다.</p>{error&&<p role="alert" className="management-error">{error}</p>}<button className="primary wide" disabled={busy}>{busy?'저장 중…':'저장'}</button></form></div></div>}
 </section>
}
