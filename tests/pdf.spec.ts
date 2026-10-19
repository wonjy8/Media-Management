import {test,expect} from '@playwright/test'
import {PDFDocument} from 'pdf-lib'
import {execFileSync,spawnSync} from 'node:child_process'
import {readFileSync} from 'node:fs'
test.use({launchOptions:{executablePath:'/usr/bin/chromium',args:['--no-sandbox']}})
test('A4 다중 페이지 PDF: 한글과 마지막 장 승인자 보존',async({page})=>{
 await page.addInitScript(()=>{
 const equipment=Array.from({length:20},(_,i)=>({id:`TEST-${i}`,code:`TEST-${i}`,name:`음향장비 ${i+1}`,model:'테스트',group:'음향',qty:3,image:'photo-1590602847861-f357a9332bbc'}))
 localStorage.setItem('media-equipment',JSON.stringify(equipment))
 localStorage.setItem('media-approvers',JSON.stringify([{id:'a',name:'승인자성명',department:'미디어사역부',position:'부장',active:true}]))
 })
 await page.goto('http://localhost:4174/Media-Management/?demo=1')
 for(let i=1;i<=20;i++)await page.getByRole('button',{name:`음향장비 ${i} 담기`,exact:true}).click()
 await page.getByRole('link',{name:'장바구니',exact:true}).click()
 await page.getByRole('button',{name:'사용 신청하기',exact:true}).click()
 const d=page.locator('.checkout-page')
 await d.getByLabel('이름',{exact:true}).fill('신청자성명')
 await d.getByLabel('전화번호').fill('01000000000')
 await d.getByLabel('소속',{exact:true}).fill('청년부')
 await d.getByLabel('소속',{exact:true}).fill('청년부')
 await d.getByLabel('직위',{exact:true}).fill('팀원')
 await d.getByLabel('대여 사유').fill('수련회')
 await expect(d.getByLabel('특이사항',{exact:true})).toHaveCount(0)
 await d.getByRole('button',{name:'신청 완료',exact:true}).click()
 const downloadPromise=page.waitForEvent('download')
 await page.getByRole('button',{name:'PDF 저장하기',exact:true}).click()
 const download=await downloadPromise
 expect(download.suggestedFilename()).toMatch(/^반출-\d{4}-\d{2}-\d{3}\.pdf$/)
 await download.saveAs('/tmp/media-loan-test.pdf')
 const pdf=await PDFDocument.load(readFileSync('/tmp/media-loan-test.pdf'))
 expect(pdf.getPageCount()).toBeGreaterThan(1)
 for(const p of pdf.getPages()){expect(p.getWidth()).toBeCloseTo(595.28,0);expect(p.getHeight()).toBeCloseTo(841.89,0)}
 const text=execFileSync('pdftotext',['-layout','/tmp/media-loan-test.pdf','-'],{encoding:'utf8'})
 const pages=text.split('\f').filter(p=>p.trim())
 expect(text.replace(/\s+/g,'')).toContain('집기반출및폐기대장')
 expect(text).toContain('신청자성명')
 expect(text).not.toContain('01000000000')
 expect(text).not.toContain('승인 대기')
 await expect(page.getByRole('region',{name:'신청서 PDF 미리보기'}).getByRole('img')).toHaveCount(pdf.getPageCount(),{timeout:20000})
 await expect(page.locator('.pdf-preview [role=status]')).toHaveCount(0,{timeout:20000})
 const inkCount=await page.locator('.pdf-preview canvas').first().evaluate((canvas:HTMLCanvasElement)=>{const pixels=canvas.getContext('2d')!.getImageData(0,0,canvas.width,canvas.height).data;let ink=0;for(let i=0;i<pixels.length;i+=4)if(pixels[i+3]>200&&pixels[i]<150&&pixels[i+1]<150&&pixels[i+2]<150)ink++;return ink})
 expect(inkCount).toBeGreaterThan(1000)
 expect(pages.at(-1)).toContain('승인자성명')
 expect(pages.slice(0,-1).every(p=>!p.includes('승인자성명'))).toBe(true)
 const last=String(pdf.getPageCount())
 const rendered=spawnSync('pdftoppm',['-f',last,'-l',last,'-scale-to','1100','-singlefile','/tmp/media-loan-test.pdf','/tmp/media-pdf-visual'],{encoding:'utf8'})
 expect(rendered.status).toBe(0);expect(rendered.stderr).toBe('')
 const ppm=readFileSync('/tmp/media-pdf-visual.ppm')
 const header=/^P6\s+(\d+)\s+(\d+)\s+255\s/.exec(ppm.toString('ascii',0,80))!
 const pixels=ppm.subarray(header[0].length),width=Number(header[1]);let ink=0
 for(let y=65;y<100;y++)for(let x=100;x<700;x++){const i=(y*width+x)*3;if(pixels[i]<120&&pixels[i+1]<120&&pixels[i+2]<120)ink++}
 // Text extraction alone can pass with a broken glyph map; also check rendered title ink.
 expect(ink).toBeGreaterThan(700)
 const bbox=execFileSync('pdftotext',['-f',last,'-l',last,'-bbox','/tmp/media-loan-test.pdf','-'],{encoding:'utf8'})
 const signer=/<word[^>]*yMin="([0-9.]+)"[^>]*>승인자성명<\/word>/.exec(bbox)
 expect(signer).not.toBeNull();expect(Number(signer![1])).toBeGreaterThan(650)
})
