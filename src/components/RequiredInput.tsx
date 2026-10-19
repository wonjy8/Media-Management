import {useId,useState} from 'react'
import type {InputHTMLAttributes} from 'react'

type Props=InputHTMLAttributes<HTMLInputElement>&{label:string;help?:string}
export default function RequiredInput({label,help,id,...input}:Props){
 const generatedId=useId()
 const fieldId=id||generatedId
 const [touched,setTouched]=useState(false)
 const empty=touched&&!String(input.value??'').trim()
 const helpId=`${fieldId}-help`,errorId=`${fieldId}-error`
 return <div className="required-field">
  <label htmlFor={fieldId}>{label}</label>
  <input {...input} id={fieldId} required aria-invalid={empty||undefined} aria-describedby={[help?helpId:'',empty?errorId:''].filter(Boolean).join(' ')||undefined} onFocus={event=>{setTouched(true);input.onFocus?.(event)}}/>
  {help&&<small id={helpId} className="input-help">{help}</small>}
  {empty&&<small id={errorId} className="input-error" role="alert">*필수 입력해 주세요.</small>}
 </div>
}
