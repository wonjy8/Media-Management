import { test,expect } from '@playwright/test'
import { approvalDue,localAvailable } from '../src/lib/domain'
import type {Loan} from '../src/lib/domain'
test('승인 기한은 신청 당일 제외 두번째 일요일',()=>{expect(approvalDue('2026-10-19')).toBe('2026-11-01');expect(approvalDue('2026-10-25')).toBe('2026-11-08');expect(approvalDue('2026-10-24')).toBe('2026-11-01')})
test('서로 겹치지 않는 예약 수량을 합산하지 않음',()=>{const e={id:'x',name:'장비',model:'',group:'',qty:3,image:''};const base={name:'테스트',phone:'',reason:'',note:'',returned:{},approved:false,out:false,items:{x:2}};const loans:Loan[]=[{...base,id:'a',start:'2027-01-01',end:'2027-01-02'},{...base,id:'b',start:'2027-01-03',end:'2027-01-04'}];expect(localAvailable(e,loans,'2027-01-01','2027-01-04')).toBe(1)})
