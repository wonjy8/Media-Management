import { createClient } from 'npm:@supabase/supabase-js@2.118.0'
const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Cache-Control': 'no-store',
}
const respond = (data: unknown, status = 200) => new Response(JSON.stringify(data), { status, headers: { ...cors, 'Content-Type': 'application/json' } })
const db = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!, { auth: { persistSession: false } })
Deno.serve(async req => {
  if (req.method === 'OPTIONS') return new Response(null, { headers: cors })
  if (req.method !== 'POST') return respond({ error: '허용되지 않는 요청입니다.' }, 405)
  try {
    const text = await req.text()
    if (text.length > 20000) return respond({ error: '입력 내용이 너무 깁니다.' }, 413)
    const { action, args = {} } = JSON.parse(text)
    const publicActions = ['catalog', 'create', 'lookup', 'update', 'cancel', 'return']
    const adminActions = ['admin_list', 'approve', 'reject', 'undo_return', 'stock']
    if (![...publicActions, ...adminActions].includes(action)) return respond({ error: '잘못된 요청입니다.' }, 400)
    if (['create','update','return'].includes(action)) {
      const items = args.items
      if (!items || typeof items !== 'object' || Array.isArray(items) || !Object.keys(items).length || Object.keys(items).length > 100 ||
          Object.entries(items).some(([id,q]) => !/^[0-9a-f-]{36}$/i.test(id) || !Number.isInteger(q) || Number(q) < 1 || Number(q) > 10000)) {
        return respond({ error: '장비와 수량을 확인해 주세요.' }, 400)
      }
      if (['create','update'].includes(action) &&
          (!/^\d{4}-\d{2}-\d{2}$/.test(args.start || '') || !/^\d{4}-\d{2}-\d{2}$/.test(args.end || '') ||
           !String(args.reason || '').trim() || String(args.reason).length > 500 || args.end < args.start)) {
        return respond({ error: '대여 사유와 날짜를 확인해 주세요.' }, 400)
      }
      if (String(args.note || '').length > 2000) return respond({ error: '특이사항은 2,000자 이하로 입력해 주세요.' }, 400)
    }
    if (['create','update'].includes(action) && (typeof args.phone!=='string'||!/^010[0-9]{8}$/.test(args.phone))) return respond({error:'전화번호는 010으로 시작하는 숫자 11자리로 입력해 주세요. (- 없이)'},400)
    if(['create','update'].includes(action) && ['department','position'].some(field=>typeof args[field]!=='string'||!args[field].trim()||args[field].trim().length>80)) return respond({error:'소속과 직위를 입력해 주세요.'},400)
    if(action==='reject' && (typeof args.reason!=='string'||!args.reason.trim()||args.reason.length>500)) return respond({error:'반려 사유를 1~500자로 입력해 주세요.'},400)
    if(['create','update'].includes(action))args.note=''
    if(action==='return')args.photoPaths=[]
    let actor: string | null = null
    if (adminActions.includes(action)) {
      const token = req.headers.get('authorization')?.replace(/^Bearer\s+/i, '')
      if (!token) return respond({ error: '관리자 로그인이 필요합니다.' }, 401)
      const { data: { user }, error } = await db.auth.getUser(token)
      if (error || !user) return respond({ error: '관리자 로그인이 필요합니다.' }, 401)
      const { data: admin } = await db.from('admins').select('user_id').eq('user_id', user.id).maybeSingle()
      if (!admin) return respond({ error: '관리 권한이 없습니다.' }, 403)
      actor = user.id
    }
    // Cloud ingress supplies this header; don't accept an IP from JSON.
    const ip = req.headers.get('x-forwarded-for')?.split(',')[0]?.trim() || 'unknown'
    const phone = String(args.phone || '').replace(/\D/g, '')
    const identityName = String(args.identityName || args.name || '').trim()
    const identityPhone = String(args.identityPhone || args.phone || '').replace(/\D/g,'')
    if (['create', 'lookup', 'update', 'cancel', 'return'].includes(action)) {
      if (!identityName || identityName.length > 80 || !/^[0-9]{9,15}$/.test(identityPhone) || !String(args.name || '').trim() || String(args.name).length>80 || !/^[0-9]{9,15}$/.test(phone)) return respond({ error: '이름과 전화번호를 확인해 주세요.' }, 400)
      const { data: allowed, error } = await db.rpc('consume_request_limit', { p_ip: ip, p_target: `${identityName}:${identityPhone}`, p_action: action })
      if (error) throw error
      if (!allowed) return respond({ error: '조회 또는 요청이 너무 많습니다. 15분 후 다시 시도해 주세요.' }, 429)
    }
    const { data, error } = await db.rpc('equipment_workflow', { p_action: action, p_args: { ...args, phone, identityName, identityPhone }, p_actor: actor })
    if (error) {
      const messages: Record<string,string> = {
        INSUFFICIENT_STOCK: '다른 신청으로 대여 가능 수량이 변경되었습니다. 장비와 날짜를 다시 확인해 주세요.',
        REJECTED_APPLICATION:'반려된 신청은 수정하거나 취소할 수 없습니다. 새로 신청해 주세요.',
        INVALID_PHONE:'전화번호는 010으로 시작하는 숫자 11자리로 입력해 주세요.',
        INVALID_REQUEST: '입력 내용을 확인해 주세요.', NOT_FOUND: '일치하는 신청이 없습니다.',
        ALREADY_CHECKED_OUT: '이미 반출된 신청은 수정하거나 취소할 수 없습니다.',
        INVALID_RETURN: '반납할 장비와 수량을 다시 확인해 주세요.',
        CONFLICT: '신청 상태가 변경되었습니다. 다시 조회해 주세요.',
      }
      const code = Object.keys(messages).find(code => error.message.includes(code))
      return respond({ error: code ? messages[code] : '처리하지 못했습니다. 잠시 후 다시 시도해 주세요.' }, 400)
    }
    return respond(data)
  } catch {
    return respond({ error: '요청을 처리하지 못했습니다. 잠시 후 다시 시도해 주세요.' }, 500)
  }
})
