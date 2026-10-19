import { defineConfig } from '@playwright/test'

export default defineConfig({
  testDir: './tests',
  webServer: [
    {
      command: 'npm run dev -- --host 0.0.0.0 --port 5173',
      url: 'http://localhost:5173',
      reuseExistingServer: !process.env.CI,
    },
    {
      command: 'npm run build && npm run preview -- --host 0.0.0.0 --port 4174',
      env: { VITE_BASE_PATH: '/Media-Management/' },
      url: 'http://localhost:4174/Media-Management/',
      reuseExistingServer: !process.env.CI,
    },
  ],
})
