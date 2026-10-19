import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import './index.css'
import App from './App.tsx'
import PdfViewer from './components/PdfViewer'
const pdfView=location.pathname===import.meta.env.BASE_URL+'application-pdf/'

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    {pdfView?<PdfViewer/>:<App />}
  </StrictMode>,
)
