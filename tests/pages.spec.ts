import { test, expect } from '@playwright/test'
test.use({ launchOptions: { executablePath: '/usr/bin/chromium', args: ['--no-sandbox'] } })
test('Pages 하위 경로에서 앱과 이미지가 로드됨',async({page})=>{
 const errors:string[]=[]
 page.on('pageerror',e=>errors.push(e.message))
 await page.goto('http://localhost:4174/Media-Management/?demo=1')
 await expect(page.getByRole('heading',{name:'어떤 장비가 필요하세요?'})).toBeVisible()
 await expect(page.locator('.card')).toHaveCount(6)
 const images=await page.locator('img').evaluateAll(imgs=>imgs.map(img=>({path:img.getAttribute('src'),loaded:img.complete&&img.naturalWidth>0})))
 expect(images.every(i=>i.path?.startsWith('/Media-Management/')&&i.loaded)).toBe(true)
 expect(errors).toEqual([])
 await page.getByRole('button',{name:'무선 핸드 마이크 담기'}).click()
 await expect(page.getByRole('button',{name:'반출 신청하기'})).toBeVisible()
})
