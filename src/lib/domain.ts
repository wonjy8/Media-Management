import type {PdfTemplate} from './pdfTemplate'
export type Approver={id:string;name:string;department:string;position:string;active:boolean}
export type Equipment={id:string;code?:string;name:string;model:string;group:string;qty:number;image:string;available?:number;description?:string;repair?:number;active?:boolean}
export type Snapshot={name:string;code:string;model?:string;department?:string}
export type Loan={pdfTemplate?:PdfTemplate|null;id:string;databaseId?:string;name:string;phone:string;department?:string;position?:string;reason:string;start:string;end:string;note:string;items:Record<string,number>;returned:Record<string,number>;approved:boolean;out:boolean;revision?:number;createdAt?:string;approvalDue?:string;approvedAt?:string;checkoutAt?:string;cancelled?:boolean;rejected?:boolean;rejectionReason?:string;rejectedAt?:string;snapshots?:Record<string,Snapshot>;approvers?:Approver[];returnNotes?:{notes:string;createdAt:string;reversed:boolean;items?:Record<string,number>;reversedAt?:string;reversalReason?:string}[]}
export const today=()=>new Date().toLocaleDateString('en-CA',{timeZone:'Asia/Seoul'})
export function approvalDue(day:string){const date=new Date(`${day}T00:00:00+09:00`);const dow=new Date(`${day}T00:00:00Z`).getUTCDay();date.setTime(date.getTime()+(14-dow)*86400000);return date.toLocaleDateString('en-CA',{timeZone:'Asia/Seoul'})}
export const outstanding=(l:Loan)=>Object.entries(l.items).some(([id,q])=>q>(l.returned[id]||0))
export function loanState(l:Loan){if(l.cancelled)return '취소';if(l.rejected)return '반려';if(l.out&&!outstanding(l))return '반납 완료';if(l.out&&l.end<today())return '반납 지연';if(l.out)return '대여 중';return l.approved?'승인 완료':'미승인'}
export function localAvailable(e:Equipment,loans:Loan[],start:string,end:string,exclude?:string){if(e.active===false)return 0;let peak=0;for(let day=start;day<=end;){let used=0;for(const l of loans){if(l.id===exclude||l.cancelled||l.rejected)continue;if((l.start<=day&&l.end>=day)||(l.out&&outstanding(l)&&l.end<today()))used+=(l.items[e.id]||0)-(l.returned[e.id]||0)}peak=Math.max(peak,used);const d=new Date(day+'T00:00:00Z');d.setUTCDate(d.getUTCDate()+1);day=d.toISOString().slice(0,10)}return Math.max(0,e.qty-(e.repair||0)-peak)}
export function conflicts(l:Loan,loans:Loan[],equipment:Equipment[]){return Object.entries(l.items).some(([id,q])=>{const e=equipment.find(x=>x.id===id);return e&&localAvailable(e,loans,l.start,l.end,l.id)<q-(l.returned[id]||0)})}
export function imageUrl(image?:string){return image?.startsWith('https://')||image?.startsWith('data:')?image:`${import.meta.env.BASE_URL}equipment/${image||'photo-1516035069371-29a1b244cc32'}.svg`}

export const validPhone=(phone:string)=>/^010[0-9]{8}$/.test(phone)
export const loanTone=(l:Loan)=>l.rejected?'rejected':l.out&&!outstanding(l)?'returned':l.approved?'approved':'pending'
