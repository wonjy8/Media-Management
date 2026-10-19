// Re-encode uploads (including metadata) and enforce <= 1,000,000 bytes.
export async function compressImage(file: File): Promise<File> {
  if (!['image/jpeg','image/png','image/webp'].includes(file.type)) throw new Error('JPG, PNG, WebP 이미지를 선택해 주세요.')
  if (file.size > 30_000_000) throw new Error('30MB 이하 이미지를 선택해 주세요.')
  const bitmap = await createImageBitmap(file)
  try {
    let scale = Math.min(1, 1600 / Math.max(bitmap.width, bitmap.height))
    for (let attempt = 0; attempt < 6; attempt++) {
      const canvas = document.createElement('canvas')
      canvas.width = Math.max(1,Math.round(bitmap.width*scale))
      canvas.height = Math.max(1,Math.round(bitmap.height*scale))
      const ctx = canvas.getContext('2d')
      if (!ctx) throw new Error('이미지를 처리하지 못했습니다.')
      ctx.fillStyle = '#fff'; ctx.fillRect(0,0,canvas.width,canvas.height)
      ctx.drawImage(bitmap,0,0,canvas.width,canvas.height)
      for (const quality of [.85,.7,.55,.4]) {
        const blob = await new Promise<Blob|null>(resolve=>canvas.toBlob(resolve,'image/jpeg',quality))
        if (blob && blob.size<=1_000_000) return new File([blob],`${crypto.randomUUID()}.jpg`,{type:'image/jpeg'})
      }
      scale *= .7
    }
    throw new Error('사진 압축에 실패했습니다. 다른 사진을 선택해 주세요.')
  } finally { bitmap.close() }
}
