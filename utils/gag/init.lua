<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>House of Noctis — Script Hub</title>
  <meta name="description" content="House of Noctis — a sleek, modern script hub. Fast. Minimal. Night-coded." />
  <meta name="theme-color" content="#10121a" />

  <link rel="preconnect" href="https://fonts.googleapis.com" />
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin />
  <link href="https://fonts.googleapis.com/css2?family=Inter:wght@300;400;500;600;700;800;900&display=swap" rel="stylesheet" />

  <script src="https://cdn.tailwindcss.com"></script>
  <script>
    tailwind.config = {
      theme: {
        extend: {
          fontFamily: { sans: ["Inter", "ui-sans-serif", "system-ui"] },
          colors: {
            noctis: {
              bg: "#0b0e15",
              surface: "#0f1420",
              edge: "#121826",
              text: "#c7d2fe",
              mute: "#9aa4c5",
              ring: "#2b3347",
              accent: "#8b5cf6",
              accent2: "#22d3ee",
            },
          },
          boxShadow: {
            glow: "0 0 40px rgba(139, 92, 246, .25)",
            glowCyan: "0 0 48px rgba(34, 211, 238, .28)",
          },
        },
      },
      darkMode: "class",
    }
  </script>

  <style>
    :root {
      --accent: 139, 92, 246;
      --accent-2: 34, 211, 238;
      --ring: 43, 51, 71;
    }
    * { box-sizing: border-box; }
    html, body { height: 100%; margin: 0; padding: 0; overflow-x: hidden; width: 100%; }
    body { background: #0b0e15; color: #e6e8ef; }

    canvas#starfield { position: fixed; inset: 0; z-index: -2; display: block; }
    .veil { position: absolute; inset: auto; filter: blur(64px); opacity: .55; pointer-events: none; background: radial-gradient(60% 60% at 50% 50%, rgba(var(--accent), .25), transparent 60%); }

    .reveal { opacity: 0; transform: translateY(12px); transition: opacity .7s ease, transform .7s ease; }
    .reveal.in { opacity: 1; transform: translateY(0); }

    .gborder { position: relative; border-radius: 16px; overflow: hidden; }
    .gborder::before { content: ""; position: absolute; inset: -2px; border-radius: 18px; z-index: 0; background: linear-gradient(135deg, rgba(var(--accent), .35), rgba(var(--accent-2), .35)); mask: linear-gradient(#000, #000) content-box, linear-gradient(#000, #000); -webkit-mask: linear-gradient(#000, #000) content-box, linear-gradient(#000, #000); -webkit-mask-composite: xor; mask-composite: exclude; padding: 2px; }
    .gborder > * { position: relative; z-index: 1; }

    pre { 
      overflow-x: auto; 
      max-width: 100%; 
      word-wrap: break-word;
      white-space: pre-wrap;
    }
    pre code { 
      display: block; 
      word-break: break-all;
      white-space: pre-wrap;
      overflow-wrap: break-word;
    }

    html { scroll-behavior: smooth; }

    @media (max-width: 640px) {
      .veil { width: 80vw !important; height: 80vw !important; }
      h1 { font-size: 2rem !important; line-height: 1.2 !important; }
      h2 { font-size: 1.75rem !important; }
      h3 { font-size: 1.25rem !important; }
      pre { 
        font-size: 10px !important; 
        padding: 10px !important;
        max-width: calc(100vw - 80px) !important;
      }
      pre code {
        font-size: 10px !important;
      }
      section { padding-left: 16px !important; padding-right: 16px !important; }
      .loader-container { max-width: 100% !important; }
    }

    @media (prefers-reduced-motion: reduce) { .reveal { transition: none; } }
  </style>
</head>

<body class="min-h-screen font-sans tracking-tight selection:bg-purple-500/20 selection:text-white">
  <canvas id="starfield" aria-hidden="true"></canvas>
  <div class="veil -top-16 left-1/2 -translate-x-1/2 w-[60vw] h-[60vw]"></div>
  <div class="veil bottom-0 -left-20 w-[40vw] h-[40vw]" style="background: radial-gradient(60% 60% at 50% 50%, rgba(var(--accent-2), .18), transparent 60%)"></div>

  <header class="sticky top-0 z-40 supports-backdrop-blur:bg-noctis/60">
    <div class="mx-auto max-w-7xl px-4 sm:px-6 lg:px-8">
      <div class="mt-4 mb-3 flex items-center justify-between rounded-2xl border border-noctis.ring/30 bg-white/5 backdrop-blur-lg gborder">
        <a href="#" class="flex items-center gap-2 sm:gap-3 p-2 sm:p-3">
          <span class="inline-grid h-8 w-8 sm:h-10 sm:w-10 place-items-center rounded-xl bg-gradient-to-br from-noctis.accent/90 to-noctis.accent2/90 shadow-glowCyan flex-shrink-0">
            <svg viewBox="0 0 24 24" class="h-5 w-5 sm:h-6 sm:w-6" fill="none" stroke="white" stroke-width="1.5" stroke-linecap="round">
              <path d="M21 12.8A8.5 8.5 0 1 1 11.2 3 7 7 0 1 0 21 12.8Z"/>
            </svg>
          </span>
          <div class="leading-tight">
            <div class="text-xs sm:text-sm text-noctis.mute">House of</div>
            <div class="text-base sm:text-lg font-semibold">Noctis</div>
          </div>
        </a>

        <nav class="hidden md:flex items-center gap-1">
          <a href="#use" class="px-4 py-2.5 text-sm/none text-slate-200 hover:text-white">Use Noctis</a>
          <a href="#games" class="px-4 py-2.5 text-sm/none text-slate-200 hover:text-white">Supported</a>
          <a href="#faq" class="px-4 py-2.5 text-sm/none text-slate-200 hover:text-white">FAQ</a>
        </nav>

        <div class="hidden md:flex items-center gap-3 pr-3">
          <a href="#loader" class="rounded-xl bg-white/10 px-4 py-2.5 text-sm font-medium hover:bg-white/15 focus:outline-none focus:ring-2 focus:ring-white/20">Get Loader</a>
          <a id="discordBtn" href="#" class="rounded-xl bg-gradient-to-r from-noctis.accent to-noctis.accent2 px-4 py-2.5 text-sm font-semibold text-white shadow-glow hover:opacity-95 focus:outline-none focus:ring-2 focus:ring-white/20">Join Discord</a>
        </div>

        <button id="menuBtn" class="md:hidden mr-2 rounded-xl border border-white/10 bg-white/5 p-2 sm:p-2.5 focus:outline-none focus:ring-2 focus:ring-white/20 flex-shrink-0" aria-label="Open menu">
          <svg viewBox="0 0 24 24" class="h-5 w-5 sm:h-6 sm:w-6" fill="none" stroke="currentColor" stroke-width="1.5"><path d="M4 6h16M4 12h16M4 18h16"/></svg>
        </button>
      </div>
      <div id="mobileMenu" class="md:hidden hidden -mt-2 mb-4 rounded-2xl border border-white/10 bg-white/5 p-2 backdrop-blur-lg">
        <a href="#use" class="block rounded-xl px-4 py-3 hover:bg-white/5">Use Noctis</a>
        <a href="#games" class="block rounded-xl px-4 py-3 hover:bg-white/5">Supported</a>
        <a href="#faq" class="block rounded-xl px-4 py-3 hover:bg-white/5">FAQ</a>
        <div class="mt-2 grid grid-cols-2 gap-2">
          <a href="#loader" class="rounded-xl bg-white/10 px-4 py-3 text-center text-sm font-medium">Get Loader</a>
          <a id="discordBtnM" href="#" class="rounded-xl bg-gradient-to-r from-noctis.accent to-noctis.accent2 px-4 py-3 text-center text-sm font-semibold text-white">Discord</a>
        </div>
      </div>
    </div>
  </header>

  <section class="relative overflow-hidden">
    <div class="mx-auto max-w-7xl px-4 sm:px-6 lg:px-8 py-12 sm:py-16 lg:py-24">
      <div class="grid items-center gap-8 sm:gap-12 md:grid-cols-2">
        <div class="reveal">
          <h1 class="text-3xl sm:text-4xl lg:text-5xl xl:text-6xl font-black leading-tight tracking-tight">
            Night-coded.<br>
            House of Noctis
          </h1>
          <p class="mt-4 sm:mt-5 max-w-xl text-sm sm:text-base text-slate-300">
            Built to Dominate.
          </p>
          <div class="mt-6 sm:mt-8 flex flex-wrap gap-2 sm:gap-3">
            <a href="#games" class="rounded-xl bg-white/10 px-4 sm:px-5 py-2.5 sm:py-3 text-sm font-semibold hover:bg-white/15 focus:outline-none focus:ring-2 focus:ring-white/20">Supported Games</a>
            <a id="discordBtnHero" href="#" class="rounded-xl border border-white/10 px-4 sm:px-5 py-2.5 sm:py-3 text-sm font-semibold hover:bg-white/5">Join Discord</a>
          </div>
          <div class="mt-5 sm:mt-6 flex flex-wrap items-center gap-4 sm:gap-6 text-xs sm:text-sm text-slate-400">
            <div class="flex items-center gap-2"><span class="inline-block h-2 w-2 rounded-full bg-emerald-400"></span> Undetected</div>
            <div class="flex items-center gap-2"><span class="inline-block h-2 w-2 rounded-full bg-cyan-400"></span> Mobile-ready</div>
          </div>
        </div>
        <div class="reveal loader-container w-full">
          <div class="relative mx-auto max-w-lg w-full">
            <div class="absolute -inset-6 rounded-3xl bg-gradient-to-br from-noctis.accent/25 to-noctis.accent2/25 blur-2xl"></div>
            <div class="relative rounded-2xl sm:rounded-3xl border border-white/10 bg-noctis.surface p-4 sm:p-6 shadow-2xl shadow-black/40 gborder w-full">
              <div class="mb-3 sm:mb-4 flex items-center gap-2 text-xs text-slate-400">
                <span class="inline-flex h-2 w-2 rounded-full bg-red-400"></span>
                <span class="inline-flex h-2 w-2 rounded-full bg-yellow-400"></span>
                <span class="inline-flex h-2 w-2 rounded-full bg-emerald-400"></span>
                <span class="ml-2">Main Loader</span>
              </div>
              <pre id="loaderBlock" class="overflow-x-auto rounded-xl border border-white/10 bg-black/60 p-3 sm:p-4 text-[10px] sm:text-[12.5px] leading-relaxed text-slate-100 w-full"><code>-- House of Noctis
loadstring(game:HttpGet("https://houseofnoctis.lol/loader"))()</code></pre>
              <div class="mt-3 sm:mt-4 flex gap-2">
                <button id="copyLoader" class="inline-flex items-center gap-2 rounded-xl bg-gradient-to-r from-noctis.accent to-noctis.accent2 px-3 sm:px-4 py-2 text-xs sm:text-sm font-semibold text-white shadow-glow hover:opacity-95">
                  <svg viewBox="0 0 24 24" class="h-4 w-4" fill="none" stroke="currentColor" stroke-width="1.5"><path d="M9 9h9a2 2 0 0 1 2 2v9a2 2 0 0 1-2 2H9a2 2 0 0 1-2-2V11a2 2 0 0 1 2-2Z"/><path d="M7 15H6a2 2 0 0 1-2-2V6a2 2 0 0 1 2-2h7a2 2 0 0 1 2 2v1"/></svg>
                  Copy loader
                </button>
              </div>
              <p class="mt-3 text-[11px] sm:text-[12px] text-slate-400">Tip: Use executor with high UNC and sUNC.</p>
            </div>
          </div>
        </div>
      </div>
    </div>
  </section>

  <section class="reveal py-8 sm:py-12">
    <div class="mx-auto max-w-7xl px-4 sm:px-6 lg:px-8">
      <div class="gborder rounded-2xl border border-white/10 bg-white/5 p-5 sm:p-6 text-center">
        <div class="text-2xl sm:text-3xl font-extrabold">99.9%</div>
        <div class="text-xs sm:text-sm text-slate-400">Uptime</div>
      </div>
    </div>
  </section>

  <section id="use" class="py-12 sm:py-16 lg:py-20">
    <div class="mx-auto max-w-7xl px-4 sm:px-6 lg:px-8">
      <div class="reveal text-center">
        <h2 class="text-2xl sm:text-3xl lg:text-4xl font-extrabold">Use Noctis</h2>
        <p class="mt-2 sm:mt-3 text-sm sm:text-base text-slate-400">Experience the power of the most advanced Roblox script hub.</p>
      </div>

      <div class="mt-8 sm:mt-10 grid gap-4 sm:gap-6 sm:grid-cols-2 lg:grid-cols-3">
        <article class="reveal rounded-2xl border border-white/10 bg-white/5 p-5 sm:p-6 gborder">
          <div class="mb-3 inline-grid h-9 w-9 sm:h-10 sm:w-10 place-items-center rounded-xl bg-gradient-to-br from-noctis.accent/40 to-noctis.accent2/40">
            <svg viewBox="0 0 24 24" class="h-5 w-5" fill="none" stroke="white" stroke-width="1.5"><path d="M12 3l6 6-6 6-6-6 6-6Z"/></svg>
          </div>
          <h3 class="text-base sm:text-lg font-semibold">Keyless</h3>
          <p class="mt-1 text-xs sm:text-sm text-slate-400">No annoying key systems. Just load and play. Simple and straightforward.</p>
        </article>

        <article class="reveal rounded-2xl border border-white/10 bg-white/5 p-5 sm:p-6 gborder">
          <div class="mb-3 inline-grid h-9 w-9 sm:h-10 sm:w-10 place-items-center rounded-xl bg-gradient-to-br from-noctis.accent/40 to-noctis.accent2/40">
            <svg viewBox="0 0 24 24" class="h-5 w-5" fill="none" stroke="white" stroke-width="1.5"><path d="M4 7h16M4 12h10M4 17h7"/></svg>
          </div>
          <h3 class="text-base sm:text-lg font-semibold">Fast Updates</h3>
          <p class="mt-1 text-xs sm:text-sm text-slate-400">Always up-to-date, New features delivered instantly.</p>
        </article>

        <article class="reveal rounded-2xl border border-white/10 bg-white/5 p-5 sm:p-6 gborder">
          <div class="mb-3 inline-grid h-9 w-9 sm:h-10 sm:w-10 place-items-center rounded-xl bg-gradient-to-br from-noctis.accent/40 to-noctis.accent2/40">
            <svg viewBox="0 0 24 24" class="h-5 w-5" fill="none" stroke="white" stroke-width="1.5"><path d="M3 13h8V3H3v10Zm0 8h8v-6H3v6Zm10 0h8V11h-8v10Zm0-18v4h8V3h-8Z"/></svg>
          </div>
          <h3 class="text-base sm:text-lg font-semibold">Easy to Use</h3>
          <p class="mt-1 text-xs sm:text-sm text-slate-400">Intuitive interface designed for everyone. From beginners to pros.</p>
        </article>
      </div>
    </div>
  </section>

  <section id="games" class="py-12 sm:py-16">
    <div class="mx-auto max-w-7xl px-4 sm:px-6 lg:px-8">
      <div class="reveal text-center">
        <h2 class="text-2xl sm:text-3xl font-extrabold">Supported Games</h2>
        <p class="mt-2 text-sm sm:text-base text-slate-400">Beta stage. Help us improve by reporting bugs via Discord.</p>
      </div>
      <div class="mt-8 sm:mt-10 grid gap-4 sm:gap-6 grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4">
        <div class="reveal rounded-2xl border border-white/10 bg-white/5 p-3 sm:p-4 gborder" data-slug="fishit">
          <picture>
            <source srcset="assets/fishit.webp" type="image/webp" />
            <img src="assets/fishit.png" alt="Fish It" class="aspect-video w-full rounded-xl object-cover" loading="lazy" />
          </picture>
          <div class="mt-3 flex items-center justify-between">
            <div>
              <div class="text-xs sm:text-sm text-slate-400">Keyless</div>
              <div class="text-sm sm:text-base font-semibold">Fish It</div>
            </div>
            <a href="#loader" class="rounded-lg border border-white/10 px-2.5 sm:px-3 py-1.5 text-xs sm:text-sm hover:bg-white/5">Get Script</a>
          </div>
        </div>

        <div class="reveal rounded-2xl border border-white/10 bg-white/5 p-3 sm:p-4 gborder" data-slug="comingsoon">
          <picture>
            <source srcset="assets/comingsoon.webp" type="image/webp" />
            <img src="assets/comingsoon.png" alt="Coming Soon" class="aspect-video w-full rounded-xl object-cover" loading="lazy" />
          </picture>
          <div class="mt-3 flex items-center justify-between">
            <div>
              <div class="text-xs sm:text-sm text-slate-400">Keyless</div>
              <div class="text-sm sm:text-base font-semibold">Coming Soon</div>
            </div>
            <a href="#loader" class="rounded-lg border border-white/10 px-2.5 sm:px-3 py-1.5 text-xs sm:text-sm hover:bg-white/5">Soon</a>
          </div>
        </div>
      </div>
    </div>
  </section>

  <section id="loader" class="reveal py-12 sm:py-16">
    <div class="mx-auto max-w-7xl px-4 sm:px-6 lg:px-8">
      <div class="rounded-2xl sm:rounded-3xl border border-white/10 bg-white/5 p-5 sm:p-8 gborder w-full">
        <div class="grid gap-6 sm:gap-8 lg:grid-cols-2">
          <div class="w-full overflow-hidden">
            <h3 class="text-xl sm:text-2xl font-bold">Get the Loader</h3>
            <p class="mt-2 text-sm sm:text-base text-slate-400">Copy loader below.</p>
            <pre id="loaderBlock2" class="mt-4 overflow-x-auto rounded-xl border border-white/10 bg-black/60 p-3 sm:p-4 text-[10px] sm:text-[12.5px] leading-relaxed text-slate-100 w-full"><code>loadstring(game:HttpGet("https://houseofnoctis.lol/loader"))()</code></pre>
            <div class="mt-3 sm:mt-4 flex flex-wrap gap-2">
              <button id="copyLoader2" class="rounded-xl bg-gradient-to-r from-noctis.accent to-noctis.accent2 px-3 sm:px-4 py-2 text-xs sm:text-sm font-semibold text-white shadow-glow">Copy</button>
            </div>
          </div>
          <div>
            <h3 class="text-xl sm:text-2xl font-bold">Requirements</h3>
            <ul class="mt-2 space-y-2 text-sm sm:text-base text-slate-300">
              <li>• Executor with high UNC and sUNC</li>
              <li>• Stable Network</li>
            </ul>
          </div>
        </div>
      </div>
    </div>
  </section>

  <section id="faq" class="reveal py-12 sm:py-16 lg:py-20">
    <div class="mx-auto max-w-4xl px-4 sm:px-6 lg:px-8">
      <h2 class="text-center text-2xl sm:text-3xl font-extrabold">FAQ</h2>
      <div class="mt-6 sm:mt-8 space-y-3">
        <details class="group rounded-2xl border border-white/10 bg-white/5 p-4 sm:p-5 gborder">
          <summary class="cursor-pointer list-none text-sm sm:text-base font-semibold">How do I submit suggestions?</summary>
          <div class="mt-3 text-xs sm:text-sm text-slate-300">Join our Discord server and post your ideas in the suggestions forum. We review all feedback regularly.</div>
        </details>
        <details class="group rounded-2xl border border-white/10 bg-white/5 p-4 sm:p-5 gborder">
          <summary class="cursor-pointer list-none text-sm sm:text-base font-semibold">How do I request game support?</summary>
          <div class="mt-3 text-xs sm:text-sm text-slate-300">Create threads on Discord with the game name and your use case. Popular requests get prioritized.</div>
        </details>
        <details class="group rounded-2xl border border-white/10 bg-white/5 p-4 sm:p-5 gborder">
          <summary class="cursor-pointer list-none text-sm sm:text-base font-semibold">How do I report bugs?</summary>
          <div class="mt-3 text-xs sm:text-sm text-slate-300">Report bugs via Discord tickets or bugs forum. Include your executor name, error logs, and steps to reproduce.</div>
        </details>
      </div>
    </div>
  </section>

  <footer class="relative border-t border-white/10 py-8 sm:py-10 text-xs sm:text-sm">
    <div class="mx-auto max-w-7xl px-4 sm:px-6 lg:px-8">
      <div class="flex flex-col items-center justify-between gap-4 sm:flex-row">
        <div class="flex items-center gap-2 sm:gap-3 text-slate-400">
          <div class="inline-grid h-7 w-7 sm:h-8 sm:w-8 place-items-center rounded-lg bg-gradient-to-br from-noctis.accent/90 to-noctis.accent2/90 flex-shrink-0">
            <svg viewBox="0 0 24 24" class="h-4 w-4 sm:h-5 sm:w-5" fill="none" stroke="white" stroke-width="1.5"><path d="M21 12.8A8.5 8.5 0 1 1 11.2 3 7 7 0 1 0 21 12.8Z"/></svg>
          </div>
          <span>© <span id="year"></span> House of Noctis. All Rights Reserved.</span>
        </div>
        <div class="flex items-center gap-3 sm:gap-4 text-slate-400">
          <a href="#" class="hover:text-white">Terms</a>
          <a href="#" class="hover:text-white">Privacy</a>
          <a href="#" class="hover:text-white">Discord</a>
        </div>
      </div>
    </div>
  </footer>

  <script>
    const menuBtn = document.getElementById('menuBtn');
    const mobileMenu = document.getElementById('mobileMenu');
    menuBtn?.addEventListener('click', () => mobileMenu.classList.toggle('hidden'));

    document.getElementById('year').textContent = new Date().getFullYear();

    const copyLoader = document.getElementById('copyLoader');
    const loaderBlock = document.getElementById('loaderBlock');
    copyLoader?.addEventListener('click', async () => {
      const txt = loaderBlock?.innerText.trim();
      try { 
        await navigator.clipboard.writeText(txt); 
        copyLoader.innerHTML = '<svg viewBox="0 0 24 24" class="h-4 w-4" fill="none" stroke="currentColor" stroke-width="1.5"><path d="M9 9h9a2 2 0 0 1 2 2v9a2 2 0 0 1-2 2H9a2 2 0 0 1-2-2V11a2 2 0 0 1 2-2Z"/><path d="M7 15H6a2 2 0 0 1-2-2V6a2 2 0 0 1 2-2h7a2 2 0 0 1 2 2v1"/></svg>Copied!'; 
        setTimeout(()=>copyLoader.innerHTML='<svg viewBox="0 0 24 24" class="h-4 w-4" fill="none" stroke="currentColor" stroke-width="1.5"><path d="M9 9h9a2 2 0 0 1 2 2v9a2 2 0 0 1-2 2H9a2 2 0 0 1-2-2V11a2 2 0 0 1 2-2Z"/><path d="M7 15H6a2 2 0 0 1-2-2V6a2 2 0 0 1 2-2h7a2 2 0 0 1 2 2v1"/></svg>Copy loader', 1200) 
      } catch(e) {}
    });

    const copyLoader2 = document.getElementById('copyLoader2');
    const loaderBlock2 = document.getElementById('loaderBlock2');
    copyLoader2?.addEventListener('click', async () => {
      const txt = loaderBlock2?.innerText.trim();
      try { 
        await navigator.clipboard.writeText(txt); 
        copyLoader2.textContent = 'Copied!'; 
        setTimeout(()=>copyLoader2.textContent='Copy', 1200) 
      } catch(e) {}
    });

    const canvas = document.getElementById('starfield');
    const ctx = canvas.getContext('2d', { alpha: true });
    let stars = []; let width = 0, height = 0, scale = window.devicePixelRatio || 1;

    function resize() {
      width = window.innerWidth; height = window.innerHeight;
      canvas.width = Math.floor(width * scale);
      canvas.height = Math.floor(height * scale);
      ctx.setTransform(scale, 0, 0, scale, 0, 0);
      const count = Math.min(220, Math.floor((width*height)/7000));
      stars = Array.from({ length: count }, () => ({ x: Math.random()*width, y: Math.random()*height, z: Math.random()*0.6 + 0.4, s: Math.random()*1.2 + 0.2 }));
    }
    window.addEventListener('resize', resize, { passive: true });
    resize();

    function loop() {
      ctx.clearRect(0, 0, width, height);
      for (const st of stars) {
        const twinkle = (Math.sin((Date.now()/500 + st.x)*st.z) + 1) * 0.5;
        ctx.globalAlpha = 0.35 + twinkle*0.45;
        ctx.fillStyle = `rgba(${st.z>0.9? '255,255,255' : '200,220,255'},1)`;
        ctx.fillRect(st.x, st.y, st.s, st.s);
        st.y += st.z * 0.06;
        if (st.y > height) st.y = -2;
      }
      requestAnimationFrame(loop);
    }
    if (!window.matchMedia('(prefers-reduced-motion: reduce)').matches) loop();

    const IO = new IntersectionObserver((entries)=>{
      entries.forEach(e=>{ if (e.isIntersecting) { e.target.classList.add('in'); IO.unobserve(e.target); } });
    }, { threshold: 0.1 });
    document.querySelectorAll('.reveal').forEach(el=>IO.observe(el));

    const discordURL = 'https://discord.gg/3AzvRJFT3M';
    document.getElementById('discordBtn')?.setAttribute('href', discordURL);
    document.getElementById('discordBtnM')?.setAttribute('href', discordURL);
    document.getElementById('discordBtnHero')?.setAttribute('href', discordURL);
  </script>
</body>
</html>