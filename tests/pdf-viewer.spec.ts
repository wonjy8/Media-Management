import {test,expect} from '@playwright/test'
import {PDFDocument} from 'pdf-lib'
test.use({launchOptions:{executablePath:'/usr/bin/chromium',args:['--no-sandbox']}})
test('신청 조회의 별도 PDF 창에서 저장·인쇄하고 새로고침해도 문서 유지',async({page})=>{
 test.setTimeout(90000)
 await page.goto('http://localhost:4175/Media-Management/returns/?demo=1')
 await page.evaluate(async()=>{
  const res=await fetch('/Media-Management/equipment/?demo=1');if(!res.ok)throw Error('route missing')
  const items=Object.fromEntries(Array.from({length:20},(_,i)=>['x'+i,1]))
  localStorage.setItem('media-loans',JSON.stringify([{id:'반출-2026-10-001',name:'보기테스트',phone:'01012345678',department:'청년부',position:'팀장',reason:'예배',start:'2026-10-24',end:'2026-10-25',items,returned:{},out:false,approved:false,note:'',snapshots:Object.fromEntries(Object.keys(items).map(x=>[x,{code:x,name:'장비 '+x}]))}]))
 })
 await page.reload()
 await page.getByLabel('이름',{exact:true}).fill('보기테스트')
 await page.getByLabel('전화번호',{exact:true}).fill('01012345678')
 await page.getByRole('button',{name:'조회하기'}).click()
 const popup=page.waitForEvent('popup');await page.getByRole('button',{name:'신청서 PDF 보기'}).click();const viewer=await popup
 await expect(viewer).toHaveURL(/\/application-pdf\/\?demo=1#media-pdf-/)
 expect(viewer.url()).not.toContain('보기테스트');expect(viewer.url()).not.toContain('01012345678')
 await expect(viewer.getByRole('button',{name:'PDF 인쇄',exact:true})).toBeEnabled({timeout:30000})
 expect(await viewer.evaluate(()=>window.opener===null)).toBe(true)
 const count=await viewer.locator('canvas').count();expect(count).toBeGreaterThan(1)
 const download=viewer.waitForEvent('download');await viewer.getByRole('button',{name:'PDF 저장',exact:true}).click()
 expect((await download).suggestedFilename()).toBe('반출-2026-10-001.pdf')
 await viewer.evaluate(()=>{window.print=()=>{document.body.dataset.printed='yes'}})
 await viewer.getByRole('button',{name:'PDF 인쇄',exact:true}).click()
 expect(await viewer.locator('body').getAttribute('data-printed')).toBe('yes')
 const printed=await PDFDocument.load(await viewer.pdf({preferCSSPageSize:true}))
 expect(printed.getPageCount()).toBe(count)
 for(const p of printed.getPages()){expect(p.getWidth()).toBeCloseTo(595,0);expect(p.getHeight()).toBeCloseTo(842,0)}
 await viewer.reload()
 await expect(viewer.getByRole('button',{name:'PDF 인쇄',exact:true})).toBeEnabled({timeout:30000})
 await expect(page.getByRole('button',{name:'조회하기'})).toBeVisible()
})
test('조회 없이 직접 연 PDF 창은 개인정보 없이 다시 조회하도록 안내',async({page})=>{
 await page.goto('http://localhost:4175/Media-Management/application-pdf/')
 await expect(page.getByRole('alert')).toHaveText('신청 조회에서 신청서를 다시 열어 주세요.')
 await expect(page.getByRole('button',{name:'PDF 저장',exact:true})).toBeDisabled()
})
