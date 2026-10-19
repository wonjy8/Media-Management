import {test,expect} from '@playwright/test'
import {execFileSync} from 'node:child_process'
test.use({launchOptions:{executablePath:'/usr/bin/chromium',args:['--no-sandbox']}})
const fixtures=[
 {id:'camera',code:'CAM',name:'테스트 카메라',model:'SONY',group:'영상',qty:2,image:'',accessories:[{id:'cable',quantity:1,selectedByDefault:true},{id:'bag',quantity:1,selectedByDefault:false}]},
 {id:'speaker',code:'SPK',name:'테스트 스피커',model:'JBL',group:'음향',qty:2,image:'',accessories:[{id:'cable',quantity:1,selectedByDefault:true}]},
 {id:'mic',code:'MIC',name:'테스트 마이크',model:'SHURE',group:'음향',qty:2,image:'',accessories:[{id:'bag',quantity:1,selectedByDefault:true}]},
 {id:'cable',code:'CBL',name:'공용 충전선',model:'USB',group:'부속품',qty:2,image:''},
 {id:'bag',code:'BAG',name:'장비 박스',model:'CASE',group:'부속품',qty:2,image:''},
]
async function setup(page:import('@playwright/test').Page){await page.addInitScript(items=>{if(!localStorage.getItem('media-equipment'))localStorage.setItem('media-equipment',JSON.stringify(items))},fixtures)}
test('모든 장비의 부속품 연결·수량·기본 선택 편집과 연결 해제',async({page})=>{
 await setup(page);await page.goto('http://localhost:5173/admin/equipment/?demo=1')
 for(const name of ['테스트 카메라','테스트 스피커','테스트 마이크']){
  await page.getByRole('button',{name:`${name} 수정`,exact:true}).click()
  const editor=page.locator('.accessory-editor')
  await expect(editor.getByLabel('연결할 장비')).toBeVisible()
  await expect(editor.locator('select option').filter({hasText:name})).toHaveCount(0)
  await page.getByRole('button',{name:'장비 편집 닫기'}).click()
 }
 await page.getByRole('button',{name:'테스트 마이크 수정',exact:true}).click()
 await page.getByLabel('연결할 장비').selectOption('cable')
 await page.getByLabel('공용 충전선 기본 수량',{exact:true}).fill('2')
 const row=page.locator('.accessory-editor-row').filter({hasText:'공용 충전선'})
 await row.getByLabel('기본 선택').uncheck()
 await page.locator('.dialog').getByRole('button',{name:'저장',exact:true}).click()
 await page.reload();await page.getByRole('button',{name:'테스트 마이크 수정',exact:true}).click()
 await expect(page.getByLabel('공용 충전선 기본 수량',{exact:true})).toHaveValue('2')
 await expect(page.locator('.accessory-editor-row').filter({hasText:'공용 충전선'}).getByLabel('기본 선택')).not.toBeChecked()
 await page.getByRole('button',{name:'공용 충전선 연결 해제'}).click()
 await page.locator('.dialog').getByRole('button',{name:'저장',exact:true}).click()
 expect(await page.evaluate(()=>JSON.parse(localStorage.getItem('media-equipment')!).find((e:{id:string})=>e.id==='mic').accessories.map((a:{id:string})=>a.id))).toEqual(['bag'])
})
test('공용 부속품을 여러 장비와 선택하면 재고를 합산하고 초과 시 부분 담기를 막음',async({page})=>{
 await setup(page);await page.goto('http://localhost:5173/equipment/?demo=1')
 await page.getByRole('button',{name:'테스트 카메라 담기',exact:true}).click()
 const picker=page.getByRole('dialog',{name:'함께 사용할 부속품'})
 await expect(picker.getByLabel('공용 충전선 함께 선택')).toBeChecked()
 await expect(picker.getByLabel('장비 박스 함께 선택')).not.toBeChecked()
 await picker.getByRole('button',{name:'취소',exact:true}).click()
 expect(await page.evaluate(()=>localStorage.getItem('media-cart-demo'))).toBe('{}')
 await page.getByRole('button',{name:'테스트 카메라 담기',exact:true}).click()
 await picker.getByLabel('공용 충전선 부속품 수량').fill('2')
 await picker.getByRole('button',{name:'선택한 장비 담기'}).click()
 await page.getByRole('button',{name:'테스트 스피커 담기',exact:true}).click()
 await expect(picker.getByLabel('공용 충전선 함께 선택')).toBeDisabled()
 await expect(picker).toContainText('대여용 재고 없음')
 await picker.getByRole('button',{name:'취소',exact:true}).click()
 await page.getByRole('link',{name:'장바구니',exact:true}).click()
 await expect(page.getByLabel('공용 충전선 장바구니 수량',{exact:true})).toHaveValue('2')
 const result=await page.evaluate(async()=>{const {appendSelection}=await import('/src/lib/accessories.ts');const equipment=JSON.parse(localStorage.getItem('media-equipment')!);const cart={camera:1,cable:2};try{appendSelection(cart,{speaker:1,cable:1},equipment);return null}catch{return cart}})
 expect(result).toEqual({camera:1,cable:2})
})
test('부속품도 신청·PDF에 포함되고 본체만 반납하면 부속품은 미반납',async({page})=>{
 test.setTimeout(90000);await setup(page);await page.goto('http://localhost:5173/equipment/?demo=1')
 await page.getByRole('button',{name:'테스트 카메라 담기',exact:true}).click()
 await page.getByRole('dialog').getByRole('button',{name:'선택한 장비 담기'}).click()
 await page.getByRole('link',{name:'장바구니',exact:true}).click()
 await expect(page.locator('.cart-item')).toHaveCount(2)
 await expect(page.locator('.cart-item').filter({hasText:'공용 충전선'})).toContainText('함께 선택: 테스트 카메라')
 await page.getByRole('button',{name:'사용 신청하기'}).click()
 for(const [label,value] of [['이름','부속품테스트'],['전화번호','01012345678'],['소속','청년부'],['직위','팀장'],['대여 사유','예배']])await page.getByLabel(label,{exact:true}).fill(value)
 await page.getByRole('button',{name:'신청 완료',exact:true}).click()
 await expect(page.getByRole('heading',{name:'신청이 완료되었어요'})).toBeVisible()
 const download=page.waitForEvent('download');await page.getByRole('button',{name:'PDF 저장하기',exact:true}).click();await(await download).saveAs('/tmp/media-accessories.pdf')
 const text=execFileSync('pdftotext',['-layout','/tmp/media-accessories.pdf','-'],{encoding:'utf8'});expect(text).toContain('테스트 카메라');expect(text).toContain('공용 충전선')
 await page.goto('http://localhost:5173/admin/loans/?demo=1');await page.getByRole('button',{name:'승인',exact:true}).click()
 await page.goto('http://localhost:5173/returns/?demo=1');await page.getByLabel('이름',{exact:true}).fill('부속품테스트');await page.getByLabel('전화번호').fill('01012345678');await page.getByRole('button',{name:'조회하기'}).click()
 await page.locator('.return-row').filter({hasText:'테스트 카메라'}).getByRole('checkbox').check()
 await page.getByRole('button',{name:'선택한 장비 반납'}).click();await page.getByRole('button',{name:'반납 완료',exact:true}).click()
 await expect(page.locator('.return-row').filter({hasText:'테스트 카메라'})).toContainText('반납 완료')
 await expect(page.locator('.return-row').filter({hasText:'공용 충전선'})).toContainText('미반납 1개')
})
test('모바일에서도 부속품 선택 화면이 넘치지 않음',async({page})=>{
 await page.setViewportSize({width:390,height:844});await setup(page);await page.goto('http://localhost:5173/equipment/?demo=1')
 await page.getByRole('button',{name:'테스트 마이크 담기',exact:true}).click()
 await expect(page.getByRole('dialog')).toContainText('장비 박스')
 expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth)).toBe(true)
})
test('실제 모드에서 연결 정보를 읽고 본체·부속품을 한 신청으로 전송하며 재고 오류를 보존',async({page})=>{
 const parent='90000000-0000-0000-0000-000000000001',child='90000000-0000-0000-0000-000000000002'
 const requests:{action:string;args:Record<string,unknown>}[]=[]
 await page.context().route('**/rest/v1/equipment?*',route=>route.fulfill({json:[{id:parent,is_accessory:false},{id:child,is_accessory:true}]}))
 await page.context().route('**/rest/v1/equipment_accessories?*',route=>route.fulfill({json:[{equipment_id:parent,accessory_id:child,quantity:1,selected_by_default:true}]}))
 await page.context().route('**/functions/v1/equipment-api',route=>{
  const body=route.request().postDataJSON();requests.push(body)
  if(body.action==='catalog')return route.fulfill({json:[{id:parent,name:'서버 스피커',model:'JBL',group:'음향',qty:2,available:2,image:''},{id:child,name:'서버 충전선',model:'USB',group:'부속품',qty:2,available:2,image:''}]})
  return route.fulfill({status:400,json:{error:'다른 신청으로 대여 가능 수량이 변경되었습니다.'}})
 })
 await page.goto('http://localhost:5173/equipment/')
 await page.getByRole('button',{name:'서버 스피커 담기'}).click()
 await expect(page.getByRole('dialog').getByLabel('서버 충전선 함께 선택')).toBeChecked()
 await page.getByRole('dialog').getByRole('button',{name:'선택한 장비 담기'}).click()
 await page.getByRole('link',{name:'장바구니',exact:true}).click();await page.getByRole('button',{name:'사용 신청하기'}).click()
 for(const [label,value] of [['이름','서버테스트'],['전화번호','01012345678'],['소속','청년부'],['직위','팀장'],['대여 사유','예배']])await page.getByLabel(label,{exact:true}).fill(value)
 await page.getByRole('button',{name:'신청 완료',exact:true}).click()
 await expect(page.getByRole('status')).toContainText('대여 가능 수량이 변경')
 expect(requests.find(r=>r.action==='create')?.args.items).toEqual({[parent]:1,[child]:1})
 expect(await page.evaluate(()=>localStorage.getItem('media-loans'))).toBeNull()
 await expect(page.getByLabel('이름',{exact:true})).toHaveValue('서버테스트')
})
test('관리자 실제 저장은 장비와 부속품 연결을 하나의 RPC로 전송',async({page})=>{
 const parent='90000000-0000-0000-0000-000000000001',child='90000000-0000-0000-0000-000000000002'
 let payload:Record<string,unknown>|undefined
 const rows=[{id:parent,code:'SPK',name:'관리 스피커',model:'JBL',group_id:null,image_path:null,description:'',quantity:2,repair_quantity:0,active:true},{id:child,code:'CBL',name:'관리 충전선',is_accessory:true,model:'USB',group_id:null,image_path:null,description:'',quantity:2,repair_quantity:0,active:true}]
 let links:unknown[]=[]
 await page.context().route('**/functions/v1/equipment-api',route=>{const {action}=route.request().postDataJSON();return route.fulfill({json:action==='catalog'?rows.map(r=>({id:r.id,code:r.code,name:r.name,model:r.model,group:'기타',qty:r.quantity,image:'',available:2})):[]})})
 await page.context().route('**/rest/v1/equipment?*',route=>route.fulfill({json:rows}))
 await page.context().route('**/rest/v1/groups?*',route=>route.fulfill({json:[]}))
 await page.context().route('**/rest/v1/equipment_accessories?*',route=>route.fulfill({json:links}))
 await page.context().route('**/rest/v1/rpc/admin_save_equipment_with_accessories',route=>{payload=route.request().postDataJSON();links=[{equipment_id:parent,accessory_id:child,quantity:2,selected_by_default:true}];return route.fulfill({json:parent})})
 await page.goto('http://localhost:5173/admin/equipment/')
 await page.getByRole('button',{name:'관리 스피커 수정',exact:true}).click()
 await page.getByLabel('연결할 장비').selectOption(child)
 await page.getByLabel('관리 충전선 기본 수량',{exact:true}).fill('2')
 await page.locator('.dialog').getByRole('button',{name:'저장',exact:true}).click()
 await expect(page.locator('.dialog')).toHaveCount(0)
 expect(payload?.p_id).toBe(parent)
 expect(payload?.p_accessories).toEqual([{id:child,quantity:2,selectedByDefault:true}])
 expect(payload?.p_equipment).not.toHaveProperty('accessories')
 await page.getByRole('button',{name:'관리 스피커 수정',exact:true}).click()
 await expect(page.getByLabel('관리 충전선 기본 수량',{exact:true})).toHaveValue('2')
})
