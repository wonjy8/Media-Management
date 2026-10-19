export type CsvValue=string|number|boolean|null|undefined
export function csvText(rows:CsvValue[][]){
 const cell=(value:CsvValue)=>{let text=value==null?'':String(value)
  // Keep spreadsheet programs from executing user-supplied formulas; preserve leading zeros.
  // eslint-disable-next-line no-control-regex -- Strip control prefixes before detecting spreadsheet formulas.
  if((typeof value==='string'&&/^0\d+$/.test(text))||/^[\s\u0000-\u001f]*[=+\-@]/.test(text)||/^[\t\r\n]/.test(text))text="'"+text
  return '"'+text.replace(/"/g,'""')+'"'
 }
 return '\ufeff'+rows.map(row=>row.map(cell).join(',')).join('\r\n')+'\r\n'
}
export function downloadCsv(filename:string,rows:CsvValue[][]){
 const url=URL.createObjectURL(new Blob([csvText(rows)],{type:'text/csv;charset=utf-8'}))
 const link=document.createElement('a');link.href=url;link.download=filename;link.click();setTimeout(()=>URL.revokeObjectURL(url),30000)
}
export async function allPages<T extends {id:string|number}>(fetchPage:(after:string|number|null)=>PromiseLike<{data:T[]|null;error:{message:string}|null}>){
 const rows:T[]=[];let after:string|number|null=null
 for(;;){const {data,error}=await fetchPage(after);if(error)throw Error('CSV 데이터를 불러오지 못했습니다. 관리자 권한과 연결 상태를 확인해 주세요.');if(!data)throw Error('CSV 데이터를 불러오지 못했습니다.');rows.push(...data);if(data.length<1000)return rows;const next=data.at(-1)!.id;if(next===after)throw Error('CSV 목록을 이어서 불러오지 못했습니다.');after=next}
}
