import {useEffect,useState} from 'react'
import {demoMode,supabase} from '../lib/supabase'
import type {Approver} from '../lib/domain'
const blank:Approver={id:'',name:'',department:'',position:'',active:true}
export default function Approvers({onChange}:{onChange?:(rows:Approver[])=>void}){
 const [form,setForm]=useState(blank),[loaded,setLoaded]=useState(false),[busy,setBusy]=useState(false),[error,setError]=useState(''),[status,setStatus]=useState('')
 useEffect(()=>{let live=true;void(async()=>{try{
  let rows:Approver[]
  if(demoMode)rows=JSON.parse(localStorage.getItem('media-approvers')||'[]')
  else{const {data,error}=await supabase!.from('approvers').select('*').order('id');if(error)throw error;rows=data}
  const value=rows.find(r=>r.active)||blank
  if(live){setForm({...value,department:value.department||'',position:value.position||''});onChange?.([value]);setLoaded(true)}
 }catch{if(live)setError('승인자 정보를 불러오지 못했습니다.')} })();return()=>{live=false}},[onChange])
 function edit(key:'name'|'department'|'position',value:string){const next={...form,[key]:value};setForm(next);onChange?.([next]);setStatus('')}
 async function save(e:React.FormEvent){e.preventDefault();if(!form.name.trim())return;setBusy(true);setError('');try{
  const value={name:form.name.trim(),department:form.department.trim(),position:form.position.trim(),active:true}
  let saved:Approver
  if(demoMode){saved={...value,id:form.id||crypto.randomUUID()};localStorage.setItem('media-approvers',JSON.stringify([saved]))}
  else{
   const query=form.id?supabase!.from('approvers').update(value).eq('id',form.id):supabase!.from('approvers').insert(value)
   const {data,error}=await query.select('*').single();if(error)throw error;saved=data
   const {error:otherError}=await supabase!.from('approvers').update({active:false}).neq('id',saved.id).eq('active',true);if(otherError)throw otherError
  }
  setForm(saved);onChange?.([saved]);setStatus('승인자가 저장되었습니다.')
 }catch{setError('승인자를 저장하지 못했습니다. 다시 시도해 주세요.')}finally{setBusy(false)}}
 return <section><form onSubmit={save} className="approver-form"><fieldset disabled={!loaded||busy}>{(['department','position','name'] as const).map((key,i)=><label key={key}>{['소속','직위','이름'][i]}<input required={key==='name'} value={form[key]} maxLength={80} onChange={e=>edit(key,e.target.value)}/></label>)}<button className="primary" disabled={!loaded||busy}>승인자 저장</button></fieldset></form>{error&&<p role="alert">{error}</p>}{status&&<p role="status">{status}</p>}</section>
}
