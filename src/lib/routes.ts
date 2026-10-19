import { useEffect, useState } from 'react'
import type { MouseEvent } from 'react'

export const routes = {
  'application-pdf': { path: 'application-pdf/', area: 'user', tab: 'pdf' },
  equipment: { path: 'equipment/', area: 'user', tab: 'equipment' },
  cart: { path: 'cart/', area: 'user', tab: 'cart' },
  checkout: { path: 'checkout/', area: 'user', tab: 'checkout' },
  returns: { path: 'returns/', area: 'user', tab: 'returns' },
  'admin-equipment': { path: 'admin/equipment/', area: 'admin', tab: 'equipment' },
  'admin-groups': { path: 'admin/groups/', area: 'admin', tab: 'groups' },
  'admin-loans': { path: 'admin/loans/', area: 'admin', tab: 'loans' },
  'admin-pdf': { path: 'admin/pdf/', area: 'admin', tab: 'pdf' },
  'admin-approvers': { path: 'admin/approvers/', area: 'admin', tab: 'pdf' },
} as const
export type RouteKey = keyof typeof routes
const base = import.meta.env.BASE_URL
const snapshot = () => window.location.pathname + window.location.search

export function routeHref(key: RouteKey) {
  const query = new URLSearchParams(window.location.search).get('demo') === '1' ? '?demo=1' : ''
  return `${base}${routes[key].path}${query}`
}
function resolve() {
  const path = window.location.pathname.startsWith(base) ? window.location.pathname.slice(base.length).replace(/^\/+|\/+$/g, '') : '__unknown__'
  if (!path) return new URLSearchParams(window.location.search).get('view') === 'admin' ? 'admin-equipment' : 'equipment'
  if (path === 'admin/approvers') return 'admin-pdf'
  if (path === 'admin') return 'admin-equipment'
  return (Object.keys(routes) as RouteKey[]).find(key => routes[key].path.replace(/\/$/, '') === path) ?? 'not-found'
}

export function useAppRoute() {
  const [, setLocation] = useState(snapshot)
  useEffect(() => {
    const sync = () => setLocation(snapshot())
    window.addEventListener('popstate', sync)
    const key = resolve()
    if (key !== 'not-found') {
      const canonical = new URL(window.location.href)
      canonical.pathname = base + routes[key].path
      canonical.searchParams.delete('view')
      if (canonical.href !== window.location.href) {
        window.history.replaceState(window.history.state, '', canonical)
        sync()
      }
    }
    return () => window.removeEventListener('popstate', sync)
  }, [])
  function navigate(key: RouteKey) {
    const href = routeHref(key)
    if (window.location.pathname + window.location.search !== href) window.history.pushState({}, '', href)
    setLocation(snapshot())
    window.scrollTo(0, 0)
  }
  function follow(event: MouseEvent<HTMLAnchorElement>, key: RouteKey) {
    if (event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return
    event.preventDefault()
    navigate(key)
  }
  const key = resolve()
  const route = key === 'not-found' ? null : routes[key]
  return { key, route, follow, navigate }
}
