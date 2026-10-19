export type ColumnKey='number'|'code'|'name'|'quantity'|'department'|'check'
export type PdfTemplate={
 version:number;title:string;organization:string;department:string;showLogo:boolean;logoUrl:string|null;
 notices:string[];noticeHeading:string;signatureHeading:string;approverLabels:string[];borrowerLabel:string;
 showSignatureDepartment:boolean;showSignaturePosition:boolean;fontSize:number;margin:number;rowHeight:number;
 columns:{key:ColumnKey;label:string;visible:boolean}[]
}
export const defaultTemplate:PdfTemplate={
 version:1,title:'장비 사용 신청서',organization:'서울영동교회',department:'미디어사역부',showLogo:true,logoUrl:null,
 notices:[
 '미디어장비를 반출할 경우, 반출 전 반드시 <미디어 사역부> 담당자 통해 장비점검 받아주세요.',
 '미디어 사역부 담당자, 사무실 담당자의 확인을 받아야 반출할 수 있습니다.',
 '방송 장비외의 악기류 및 시설장비는 <미디어 사역부> 대여 대상이 아닙니다.',
 '사용 후 반드시 장비점검 확인 후 반납해주세요. 추후 장비 문제가 있을 경우 책임을 물을 수 있습니다.',
 '본 반출증은 1부 작성 후 복사하여 1부는 발행부서, 1부는 관리부에서 보관합니다.'
 ],noticeHeading:'사용 및 반납 확인',signatureHeading:'신청 및 승인',approverLabels:['장비 승인자','사무실 확인','추가 승인자','추가 승인자'],borrowerLabel:'신청자',
 showSignatureDepartment:true,showSignaturePosition:true,fontSize:9,margin:48,rowHeight:31,
 columns:[{key:'number',label:'No.',visible:true},{key:'code',label:'관리번호',visible:true},{key:'name',label:'장비명',visible:true},{key:'quantity',label:'수량',visible:true},{key:'department',label:'장비 소속',visible:true},{key:'check',label:'확인',visible:true}]
}
export function demoTemplate():PdfTemplate{
 try{return JSON.parse(localStorage.getItem('media-pdf-template')||'null')||structuredClone(defaultTemplate)}catch{return structuredClone(defaultTemplate)}
}
export function validateTemplate(t:PdfTemplate){
 const strings=[t.title,t.organization,t.department,t.noticeHeading,t.signatureHeading,t.borrowerLabel,...t.approverLabels]
 if(strings.some(s=>typeof s!=='string'||!s.trim()||s.length>80))throw Error('제목과 서명란 이름은 1~80자로 입력해 주세요.')
 if(t.title.length>30||t.organization.length>30||t.department.length>30)throw Error('문서 제목과 교회·부서명은 30자 이하로 입력해 주세요.')
 if(!Array.isArray(t.notices)||t.notices.length>20||t.notices.some(s=>typeof s!=='string'||s.length>1000)||t.notices.join('').length>5000)throw Error('안내 문구는 최대 20개, 전체 5,000자까지 입력할 수 있습니다.')
 if(t.fontSize<8||t.fontSize>11||t.margin<36||t.margin>60||t.rowHeight<26||t.rowHeight>44)throw Error('글자 크기와 여백을 확인해 주세요.')
 const keys=defaultTemplate.columns.map(c=>c.key)
 if(t.columns.length!==6||new Set(t.columns.map(c=>c.key)).size!==6||t.columns.some(c=>!keys.includes(c.key)||typeof c.label!=='string'||!c.label.trim()||c.label.length>24)||!t.columns.some(c=>c.key==='name'&&c.visible)||!t.columns.some(c=>c.key==='quantity'&&c.visible))throw Error('장비명·수량은 표시해야 하며, 열 제목은 1~24자로 입력해 주세요.')
 if(t.approverLabels.length!==4||typeof t.showLogo!=='boolean'||typeof t.showSignatureDepartment!=='boolean'||typeof t.showSignaturePosition!=='boolean')throw Error('서명란 구성을 확인해 주세요.')
 if(t.logoUrl!==null&&(typeof t.logoUrl!=='string'||!(t.logoUrl.startsWith('https://')||t.logoUrl.startsWith('data:image/jpeg;base64,'))||t.logoUrl.length>1340000))throw Error('로고 이미지를 확인해 주세요.')
}
