function boot() {
  if (!window.ArclightBH) {
    setTimeout(boot, 60)
    return
  }

  const root = document.getElementById('arclight-root')

  window.ArclightBH.start({
    canvas: root.querySelector('[data-bh]'),
    logo: root.querySelector('[data-logo]'),
    revealEls: Array.from(root.querySelectorAll('[data-reveal]')),
    zEl: root.querySelector('[data-zval]'),
    getScroll: () => window.scrollY || window.pageYOffset || 0,
    onReady: () => {
      const poster = root.querySelector('[data-bh-poster]')
      if (poster) {
        poster.style.opacity = '0'
        setTimeout(() => { poster.style.display = 'none' }, 700)
      }
    },
    props: {}
  })

  const reduced = window.matchMedia('(prefers-reduced-motion: reduce)').matches
  const sections = root.querySelectorAll('[data-reveal-section]')

  if (reduced) {
    sections.forEach(s => { s.style.opacity = 1 })
  } else {
    sections.forEach(s => {
      s.style.transform = 'translateY(26px)'
      s.style.transition = 'opacity 1.2s cubic-bezier(.16,.7,.2,1), transform 1.2s cubic-bezier(.16,.7,.2,1)'
    })
    const io = new IntersectionObserver(entries => {
      entries.forEach(e => {
        if (e.isIntersecting) {
          e.target.style.opacity = '1'
          e.target.style.transform = 'translateY(0)'
          io.unobserve(e.target)
        }
      })
    }, { threshold: 0.16 })
    sections.forEach(s => io.observe(s))
  }
}

boot()
