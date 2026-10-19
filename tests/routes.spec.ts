import {test,expect} from '@playwright/test'
import {readFileSync,existsSync} from 'node:fs'
test.use({launchOptions:{executablePath:'/usr/bin/chromium',args:['--no-sandbox']}})
const base='http://localhost:4175/Media-Management/'
for(const [path,selector] of [
 ['equipment/','장비명, 모델명 검색'],['cart/','장바구니'],['checkout/','장바구니가 비어 있습니다.'],['returns/','조회하기'],
 ['admin/equipment/','장비 등록'],['admin/groups/','그룹 추가'],
 ['admin/loans/','신청 검색'],['admin/approvers/','승인자 추가'],
])test(`직접 접속과 새로고침: ${path}`,async({page})=>{
 expect(existsSync(`dist/${path}index.html`)).toBe(true)
 expect(readFileSync(`dist/${path}index.html`,'utf8')).toContain('/Media-Management/assets/')
 const response=await page.goto(`${base}${path}?demo=1`)
 expect(response?.status()).toBe(200)
 if(path==='equipment/')await expect(page.getByPlaceholder(selector)).toBeVisible()
 else if(path==='cart/'||path==='checkout/')await expect(page.getByRole('heading',{name:selector,exact:true})).toBeVisible()
 else if(selector==='신청 검색')await expect(page.getByLabel(selector,{exact:true})).toBeVisible()
 else await expect(page.getByRole('button',{name:selector,exact:true})).toBeVisible()
 expect((await page.reload())?.status()).toBe(200)
 await expect(page).toHaveURL(`${base}${path}?demo=1`)
})
test('탭 URL, 뒤로/앞으로, 새 탭, 기존 관리자 URL 호환',async({page})=>{
 await page.goto(`${base}?demo=1`)
 await expect(page).toHaveURL(`${base}equipment/?demo=1`)
 await page.getByRole('button',{name:'무선 핸드 마이크 담기',exact:true}).click()
 const returns=page.getByRole('link',{name:'신청 조회 · 반납',exact:true})
 await expect(returns).toHaveAttribute('href','/Media-Management/returns/?demo=1')
 await returns.click()
 await expect(page).toHaveURL(`${base}returns/?demo=1`)
 await page.goBack()
 await expect(page).toHaveURL(`${base}equipment/?demo=1`)
 await expect(page.getByRole('link',{name:'장바구니',exact:true})).toBeVisible()
 await page.goForward()
 await expect(page.getByRole('button',{name:'조회하기',exact:true})).toBeVisible()
 await page.goto(`${base}?view=admin&demo=1`)
 await expect(page).toHaveURL(`${base}admin/equipment/?demo=1`)
 await page.getByRole('link',{name:'그룹 관리',exact:true}).click()
 await expect(page).toHaveURL(`${base}admin/groups/?demo=1`)
 await page.getByRole('link',{name:'승인자',exact:true}).click()
 await expect(page).toHaveURL(`${base}admin/approvers/?demo=1`)
 await page.goBack()
 await expect(page.getByRole('button',{name:'그룹 추가',exact:true})).toBeVisible()
})
test('알 수 없는 경로는 404로 안내',async({page})=>{
 const response=await page.goto(`${base}missing/?demo=1`)
 expect(response?.status()).toBe(404)
 await expect(page.getByRole('heading',{name:'페이지를 찾을 수 없습니다.'})).toBeVisible()
})
test('사용자 탭의 콘텐츠 여백과 로고 헤더는 PC·모바일에서 동일',async({page})=>{
 for(const width of [1440,390]){
  await page.setViewportSize({width,height:900})
  const boxes=[]
  for(const path of ['equipment','cart','returns']){
   await page.goto(`http://localhost:5173/${path}/?demo=1`)
   const brand=page.locator('.church-identity')
   await expect(brand).toContainText('서울영동교회 미디어사역부')
   await expect(brand.locator('img')).toBeVisible()
   const bounds=await page.locator('.user-app>main>section').boundingBox()
   boxes.push(bounds!)
   expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth)).toBe(true)
   expect((await brand.boundingBox())!.y).toBeLessThan((await page.getByRole('navigation',{name:'사용자 메뉴'}).boundingBox())!.y)
  }
  expect(boxes.map(b=>[b.x,b.y,b.width])).toEqual(Array(3).fill([boxes[0].x,boxes[0].y,boxes[0].width]))
 }
})
