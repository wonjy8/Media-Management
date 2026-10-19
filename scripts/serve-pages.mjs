// Strict local static host used to test GitHub Pages direct links without Vite's SPA fallback.
import { createServer } from 'node:http'
import { readFile, stat } from 'node:fs/promises'
import { resolve, extname, sep } from 'node:path'
const root = resolve('dist')
const base = '/Media-Management/'
const types = {'.html':'text/html; charset=utf-8','.js':'text/javascript','.mjs':'text/javascript','.css':'text/css','.svg':'image/svg+xml','.ttf':'font/ttf','.png':'image/png'}
createServer(async (req,res) => {
  try {
    const url = new URL(req.url, 'http://localhost')
    if (!url.pathname.startsWith(base)) throw new Error('404')
    const file = resolve(root, decodeURIComponent(url.pathname.slice(base.length)))
    if (file !== root && !file.startsWith(root + sep)) throw new Error('404')
    const info = await stat(file)
    if(info.isDirectory()&&!url.pathname.endsWith('/')){res.writeHead(301,{Location:url.pathname+'/'+url.search});res.end();return}
    const actual = info.isDirectory() ? resolve(file,'index.html') : file
    res.writeHead(200,{'Content-Type':types[extname(actual)]||'application/octet-stream'})
    res.end(await readFile(actual))
  } catch {
    res.writeHead(404,{'Content-Type':'text/html; charset=utf-8'})
    res.end(await readFile(resolve(root,'404.html')))
  }
}).listen(4175,'0.0.0.0',()=>console.log('Static Pages test host: port 4175'))
