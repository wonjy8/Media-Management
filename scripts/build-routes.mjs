import { readFile, mkdir, writeFile } from 'node:fs/promises'
import { join } from 'node:path'

// GitHub Pages serves directories, not SPA rewrites. Generate a real HTML entry
// for every route so direct links and refreshes receive HTTP 200.
const html = await readFile('dist/index.html', 'utf8')
const source = await readFile('src/lib/routes.ts', 'utf8')
const paths = [...source.matchAll(/path: '([^']+)'/g)].map(match => match[1])
for (const route of [...paths, 'admin/']) {
  const directory = join('dist', route)
  await mkdir(directory, { recursive: true })
  await writeFile(join(directory, 'index.html'), html)
}
await writeFile('dist/404.html', html)
await writeFile('dist/.nojekyll', '')
console.log(`Generated ${paths.length} tab routes, admin entry, and 404 page`)
