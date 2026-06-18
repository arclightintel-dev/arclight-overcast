function cl(v, a, b) { return Math.max(a, Math.min(b, v)) }

function boot() {
  if (!window.ArclightBH) {
    setTimeout(boot, 60)
    return
  }

  const v1 = document.querySelector('[data-view1-text]')
  const v2 = document.querySelector('[data-view2-text]')
  const reduced = window.matchMedia('(prefers-reduced-motion: reduce)').matches

  window.ArclightBH.start({
    canvas: document.querySelector('[data-bh]'),
    logo: null,
    revealEls: [],
    zEl: document.querySelector('[data-zval]'),
    getScroll: () => window.scrollY || 0,
    onReady: () => {
      const poster = document.querySelector('[data-bh-poster]')
      if (poster) {
        poster.style.opacity = '0'
        setTimeout(() => { poster.style.display = 'none' }, 700)
      }
      if (!reduced) {
        v1.style.transition = 'opacity 1s ease'
        v1.style.opacity = '1'
      }
    },
    props: {}
  })

  if (reduced) {
    v1.style.opacity = '1'
    v2.style.opacity = '1'
    return
  }

  function onScroll() {
    const maxScroll = document.documentElement.scrollHeight - window.innerHeight
    const t = maxScroll > 0 ? window.scrollY / maxScroll : 0

    // View 1: visible 0–0.2, fades out 0.2–0.4
    const v1fade = cl((t - 0.2) / 0.2, 0, 1)
    const v1op = 1 - v1fade
    v1.style.opacity = v1op.toFixed(3)
    v1.style.filter = v1fade > 0.01 && v1fade < 0.99
      ? 'blur(' + (v1fade * 8).toFixed(1) + 'px)' : 'none'

    // View 2: fades in 0.6–0.85
    const v2fade = cl((t - 0.6) / 0.25, 0, 1)
    v2.style.opacity = v2fade.toFixed(3)
    v2.style.filter = v2fade > 0.01 && v2fade < 0.99
      ? 'blur(' + ((1 - v2fade) * 8).toFixed(1) + 'px)' : 'none'
    v2.style.pointerEvents = v2fade > 0.5 ? 'auto' : 'none'
  }

  window.addEventListener('scroll', onScroll, { passive: true })
  onScroll()
}

boot()
