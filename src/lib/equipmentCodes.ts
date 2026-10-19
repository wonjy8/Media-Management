export function equipmentCodes(value?:string|null){return (value||'').split(',').map(code=>code.trim()).filter(Boolean)}
export function normalizeEquipmentCodes(value?:string|null){
 const codes=equipmentCodes(value)
 if(codes.length>50||codes.some(code=>code.length>80))throw Error('관리번호는 번호당 80자, 최대 50개까지 입력해 주세요.')
 if(new Set(codes).size!==codes.length)throw Error('같은 관리번호를 중복 입력할 수 없습니다.')
 return codes.join(', ')
}
export function displayedCode(snapshot:{code?:string|null}|undefined,equipment:{code?:string|null}|undefined){
 return snapshot&&Object.hasOwn(snapshot,'code')?snapshot.code||'':equipment?.code||''
}
