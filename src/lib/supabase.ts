import { createClient } from '@supabase/supabase-js'
const url = import.meta.env.VITE_SUPABASE_URL
const key = import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY
export const supabase = url && key ? createClient(url, key, {
  auth: { persistSession: true, autoRefreshToken: true, detectSessionInUrl: true },
}) : null
export const demoMode = new URLSearchParams(window.location.search).get('demo') === '1' || !supabase

export async function callApi<T>(action: string, args: Record<string, unknown> = {}): Promise<T> {
  if (!supabase) throw new Error('서버 연결 설정이 필요합니다.')
  const { data, error } = await supabase.functions.invoke('equipment-api', { body: { action, args } })
  if (error) {
    // Do not log request bodies containing names / phone numbers.
    if ('context' in error && error.context instanceof Response) {
      const response = await error.context.json().catch(() => null)
      if (response?.error) throw new Error(response.error)
    }
    throw new Error('서버에 연결하지 못했습니다. 잠시 후 다시 시도해 주세요.')
  }
  if (data?.error) throw new Error(data.error)
  return data as T
}
