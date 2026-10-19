import {test,expect} from '@playwright/test'
import {execFileSync} from 'node:child_process'
test.use({launchOptions:{executablePath:'/usr/bin/chromium',args:['--no-sandbox']}})
test('관리번호 없이 여러 장비 저장·재편집, 쉼표 번호 정리와 개별 중복 방지',async({page})=>{
 await page.goto('http://localhost:5173/admin/equipment/?demo=1')
 for(const name of ['번호 없는 케이블A','번호 없는 케이블B']){
  await page.getByRole('button',{name:'장비 등록',exact:true}).click()
  await page.getByLabel('장비명',{exact:true}).fill(name)
  await expect(page.getByLabel('관리번호',{exact:true})).not.toHaveAttribute('required','')
  await page.locator('.dialog').getByRole('button',{name:'저장',exact:true}).click()
  await expect(page.locator('.dialog')).toHaveCount(0)
 }
 await page.getByRole('button',{name:'장비 등록',exact:true}).click()
 await page.getByLabel('장비명',{exact:true}).fill('여러 대 카메라')
 await page.getByLabel('관리번호',{exact:true}).fill(' CAM-001 , CAM-002, ')
 await page.getByLabel('총 수량',{exact:true}).fill('2')
 await page.locator('.dialog').getByRole('button',{name:'저장',exact:true}).click()
 await page.reload()
 await page.getByRole('button',{name:'여러 대 카메라 수정',exact:true}).click()
 await expect(page.getByLabel('관리번호',{exact:true})).toHaveValue('CAM-001, CAM-002')
 await page.getByRole('button',{name:'장비 편집 닫기'}).click()
 await page.getByRole('button',{name:'번호 없는 케이블A 수정',exact:true}).click()
 await expect(page.getByLabel('관리번호',{exact:true})).toHaveValue('')
 await page.getByLabel('관리번호',{exact:true}).fill('CAM-002')
 await page.locator('.dialog').getByRole('button',{name:'저장',exact:true}).click()
 await expect(page.locator('.dialog').getByRole('alert')).toContainText('이미 사용 중인 관리번호')
 await page.getByLabel('관리번호',{exact:true}).fill('CBL-001, CBL-001')
 await page.locator('.dialog').getByRole('button',{name:'저장',exact:true}).click()
 await expect(page.locator('.dialog').getByRole('alert')).toContainText('중복 입력')
})
test('관리번호 없는 PDF·CSV에는 내부 ID를 노출하지 않고 다중 번호는 모두 보존',async({page})=>{
 test.setTimeout(90000)
 await page.goto('http://localhost:5173/equipment/?demo=1')
 const bytes=await page.evaluate(async()=>{
  const {createLoanPdf}=await import('/src/lib/pdf.ts'),{defaultTemplate}=await import('/src/lib/pdfTemplate.ts')
  const equipment=[{id:'internal-secret-cable',name:'번호 없는 케이블',code:'나중에추가한번호',model:'',group:'케이블',qty:5,image:''},{id:'internal-camera',name:'카메라',code:'CAM-001, CAM-002',model:'',group:'영상',qty:2,image:''}]
  const loan={id:'반출-2026-10-001',name:'테스트',phone:'',reason:'예배',start:'2026-10-21',end:'2026-10-22',items:{'internal-secret-cable':1,'internal-camera':2},returned:{},approved:false,out:false,note:'',snapshots:{'internal-secret-cable':{name:'번호 없는 케이블',code:null}},pdfTemplate:defaultTemplate}
  return Array.from(new Uint8Array(await(await createLoanPdf(loan,equipment)).arrayBuffer()))
 })
 const fs=await import('node:fs');fs.writeFileSync('/tmp/media-codes.pdf',Buffer.from(bytes))
 const text=execFileSync('pdftotext',['-layout','/tmp/media-codes.pdf','-'],{encoding:'utf8'})
 expect(text).toContain('CAM-001');expect(text).toContain('CAM-002');expect(text).not.toContain('internal-');expect(text).not.toContain('나중에추가한번호')
 const csv=await page.evaluate(async()=>{const {equipmentCsv,movementCsv}=await import('/src/lib/exports.ts');return {inventory:equipmentCsv([{id:'secret-id',code:null,name:'케이블',model:'',group:'기타',qty:1,image:''}]),history:movementCsv([{id:'반출',name:'사용자',phone:'',reason:'사용',start:'2026-10-21',end:'2026-10-22',items:{'secret-id':1},returned:{},out:false,approved:false,note:'',snapshots:{'secret-id':{code:null,name:'케이블'}}}],[],[])}})
 expect(csv.inventory[1][0]).toBe('');expect(csv.history[1][11]).toBe('')
})
