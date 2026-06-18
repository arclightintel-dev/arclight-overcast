function boot() {
  if (!window.ArclightBH) {
    setTimeout(boot, 60)
    return
  }

  const root = document.getElementById('arclight-root')
  const v1 = root.querySelector('[data-view1-text]')
  const v2 = root.querySelector('[data-view2-text]')

  window.ArclightBH.start({
    canvas: root.querySelector('[data-bh]'),
    logo: null,
    revealEls: [],
    zEl: root.querySelector('[data-zval]'),
    getScroll: () => window.scrollY || window.pageYOffset || 0,
    onReady: () => {
      const poster = root.querySelector('[data-bh-poster]')
      if (poster) {
        poster.style.opacity = '0'
        setTimeout(() => { poster.style.display = 'none' }, 700)
      }
      v1.style.opacity = '1'
    },
    props: {}
  })

  const reduced = window.matchMedia('(prefers-reduced-motion: reduce)').matches

  if (reduced) {
    v1.style.opacity = '1'
    v2.style.opacity = '1'
    return
  }

  v1.style.opacity = '0'
  v1.style.transition = 'none'
  requestAnimationFrame(() => {
    v1.style.transition = 'opacity 1.2s ease, filter 0.8s ease'
    v1.style.opacity = '1'
  })

  function onScroll() {
    const vh = window.innerHeight
    const s = window.scrollY

    const fadeOut = Math.max(0, Math.min(1, (s - vh * 0.15) / (vh * 0.35)))
    v1.style.opacity = (1 - fadeOut).toFixed(3)
    if (fadeOut > 0 && fadeOut < 1) {
      v1.style.filter = 'blur(' + (fadeOut * 6).toFixed(1) + 'px)'
    } else {
      v1.style.filter = 'none'
    }

    const fadeIn = Math.max(0, Math.min(1, (s - vh * 0.85) / (vh * 0.4)))
    v2.style.opacity = fadeIn.toFixed(3)
    if (fadeIn > 0 && fadeIn < 1) {
      v2.style.filter = 'blur(' + ((1 - fadeIn) * 5).toFixed(1) + 'px)'
    } else {
      v2.style.filter = fadeIn >= 1 ? 'none' : 'blur(5px)'
    }
  }

  window.addEventListener('scroll', onScroll, { passive: true })
  onScroll()
}

boot()
