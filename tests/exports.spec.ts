import {test,expect} from '@playwright/test'
import {readFileSync} from 'node:fs'
test.use({launchOptions:{executablePath:'/usr/bin/chromium',args:['--no-sandbox']}})
test('CSV는 한글·줄바꿈·따옴표·전화번호를 보존하고 수식을 차단하며 전체 페이지를 조회',async({page})=>{
 await page.goto('http://localhost:5173/?demo=1')
 const result=await page.evaluate(async()=>{
  const {csvText,allPages}=await import('/src/lib/csv.ts')
  const calls:unknown[]=[]
  const rows=await allPages(async after=>{calls.push(after);return {data:after===null?Array.from({length:1000},(_,i)=>({id:i+1})):[{id:1001}],error:null}})
  let failed=false;try{await allPages(async()=>({data:null,error:{message:'denied'}}))}catch{failed=true}
  return {csv:csvText([['장비,"이름"','여러\n줄','01012345678','=HYPERLINK("x")']]),calls,count:rows.length,failed}
 })
 expect(result.csv).toBe('\ufeff"장비,""이름""","여러\n줄","\'01012345678","\'=HYPERLINK(""x"")"\r\n')
 expect(result.calls).toEqual([null,1000]);expect(result.count).toBe(1001);expect(result.failed).toBe(true)
})
test('장비와 반출·부분 반납·반납 취소를 전체 CSV로 저장',async({page})=>{
 await page.goto('http://localhost:5173/admin/equipment/?demo=1')
 const event=page.waitForEvent('download');await page.getByRole('button',{name:'전체 장비 CSV'}).click()
 const inventory=await event;expect(inventory.suggestedFilename()).toMatch(/^장비목록-.*\.csv$/)
 expect(readFileSync((await inventory.path())!,'utf8')).toContain('무선 핸드 마이크')
 await page.evaluate(()=>localStorage.setItem('media-loans',JSON.stringify([{id:'반출-2026-10-001',name:'테스트',phone:'01012345678',reason:'예배',start:'2026-10-20',end:'2026-10-21',approved:true,out:true,checkoutAt:'2026-10-20T00:00:00Z',items:{x:3},returned:{x:1},snapshots:{x:{code:'OLD',name:'당시 장비명'}},returnNotes:[{notes:'점검',createdAt:'2026-10-21T00:00:00Z',items:{x:1},reversed:true,reversedAt:'2026-10-21T01:00:00Z',reversalReason:'오처리'},{notes:'정상 반납',createdAt:'2026-10-21T02:00:00Z',items:{x:1},reversed:false}]}])))
 await page.goto('http://localhost:5173/admin/loans/?demo=1')
 await page.getByLabel('신청 검색',{exact:true}).fill('검색 결과 없음')
 const download=page.waitForEvent('download');await page.getByRole('button',{name:'전체 기록 CSV'}).click()
 const file=await download;expect(file.suggestedFilename()).not.toContain('테스트')
 const csv=readFileSync((await file.path())!,'utf8')
 expect(csv).toContain('"반출"');expect(csv).toContain('"반납 취소"');expect(csv).toContain('"오처리"');expect(csv).toContain('"당시 장비명"');expect(csv).toContain('"2026-10-21 11:00:00"');expect(csv).toContain('"\'01012345678"');expect(csv.split('\r\n').filter(Boolean)).toHaveLength(5)
})
test('세로 장비 이미지는 카드·상세·장바구니에서 전체 맞춤',async({page})=>{
 await page.goto('http://localhost:5173/?demo=1')
 const img=page.locator('.card-image img').first();await expect(img).toHaveCSS('object-fit','contain')
 await page.locator('.card-image').first().click();await expect(page.locator('.detail-img')).toHaveCSS('object-fit','contain')
 await page.getByRole('button',{name:'장비 담기',exact:true}).click()
 await page.getByRole('link',{name:'장바구니',exact:true}).click()
 await expect(page.locator('.cart-item>img').first()).toHaveCSS('object-fit','contain')
})
