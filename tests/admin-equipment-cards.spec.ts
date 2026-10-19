import {test,expect} from '@playwright/test'
test.use({launchOptions:{executablePath:'/usr/bin/chromium',args:['--no-sandbox']}})
const items=[
 {id:'camera',name:'카메라',model:'SONY',code:'CAM-001',group:'영상',qty:2,image:'',accessories:[{id:'battery',quantity:1,selectedByDefault:true}]},
 {id:'battery',name:'배터리',model:'NP-FZ100',code:'',group:'영상',qty:4,image:'',isAccessory:true},
 {id:'cable',name:'케이블',model:'XLR',code:'',group:'음향',qty:10,image:'',repair:2,active:false},
]
test.beforeEach(async({page})=>{await page.addInitScript(items=>{if(!localStorage.getItem('media-equipment'))localStorage.setItem('media-equipment',JSON.stringify(items))},items)})
test('관리자 이미지 카드에서 전체 장비와 부속품 검색·그룹·상태 필터',async({page})=>{
 await page.goto('http://localhost:5173/admin/equipment/?demo=1')
 const cards=page.locator('.admin-equipment-card')
 await expect(cards).toHaveCount(3)
 await expect(cards.filter({hasText:'배터리'}).locator('.badge')).toHaveText('부속품')
 await expect(cards.first().locator('img')).toHaveCSS('object-fit','contain')
 await page.getByRole('button',{name:'영상',exact:true}).click();await expect(cards).toHaveCount(2)
 await page.getByLabel('관리 장비 검색').fill('NP-FZ100');await expect(cards).toHaveCount(1)
 await expect(cards).toContainText('배터리')
 await page.getByLabel('관리 장비 검색').fill('');await page.getByRole('button',{name:'전체',exact:true}).click()
 await page.getByLabel('장비 상태').selectOption('repair');await expect(cards).toHaveCount(1);await expect(cards).toContainText('케이블')
 await cards.getByRole('button',{name:'케이블 상세'}).click();await expect(page.getByLabel('장비명',{exact:true})).toHaveValue('케이블')
})
test('부속품 탭 개별 URL·새로고침·등록·모바일 레이아웃',async({page})=>{
 await page.goto('http://localhost:4175/Media-Management/admin/equipment/?demo=1')
 await page.getByRole('link',{name:'부속품',exact:true}).click()
 await expect(page).toHaveURL(/\/admin\/accessories\/\?demo=1$/)
 await expect(page.locator('.admin-equipment-card')).toHaveCount(1)
 await page.reload();await expect(page.locator('.admin-equipment-card')).toContainText('배터리')
 await page.getByRole('button',{name:'부속품 등록',exact:true}).click()
 await expect(page.getByRole('checkbox',{name:'부속품',exact:true})).toBeChecked()
 await expect(page.getByLabel('종속될 장비 선택')).toBeVisible()
 await page.getByRole('button',{name:'장비 편집 닫기'}).click()
 await page.setViewportSize({width:390,height:844})
 expect(await page.evaluate(()=>document.documentElement.scrollWidth<=window.innerWidth)).toBe(true)
 await expect(page.locator('.admin-equipment-card')).toBeVisible()
 await page.goBack();await expect(page.locator('.admin-equipment-card')).toHaveCount(3)
})
