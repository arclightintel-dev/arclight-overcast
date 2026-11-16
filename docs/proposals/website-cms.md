# Website: self-service editing for arclightlabs.io (options and recommendation)

Status: **decisions W1-W6 accepted by the owner, 2026-11-16 ([O-020](../DECISIONS.md)).** The spec is [website.md](../specs/website.md). Nothing is built, pushed, created or changed: no `gh-pages` push, no repository, account, Cloudflare or DNS change.
Request: the owner, 2026-11-16. Live reads are dated 2026-11-16 and read-only.
**This repository is public (DR-14).** This document names the editor only by role.

## 1. Decisions for the owner

| # | Decision | Recommendation | Section |
|---|---|---|---|
| **W1** | Where the site lives | A **new private repository** for the site alone (working name `arclightlabs-site`), under `arclightintel-dev`. `gh-pages` is frozen and tagged after cutover. Closes DR-6 and removes the website as a reason this repository is public (DR-14) | 5, 7 |
| **W2** | How the editor edits | **Option A**: she asks Claude in plain language on the site repository, and each change arrives as a pull request with a preview link. Add **Option B** (a form editor on the same files) only if the pilot shows she prefers forms for routine posts | 5, 6 |
| **W3** | The review gate | **At launch, every change waits for the owner's approval**, as the owner proposed. Revisit after 30 days or 10 merged changes: content-only changes (text, posts, media) she merges herself once checks pass; structure (layouts, styles, new page types, configuration) stays owner-reviewed through `CODEOWNERS`. That is the step that actually takes the site off the owner's plate | 6 |
| **W4** | Gated material for approved visitors | **Bandersnatch** (D-079), not a second gate on the website. The site links to the request path; approved people get Bandersnatch tokens | 3, 8 |
| **W5** | Request Access | A **Microsoft Forms** form the editor owns, linked from the button in place of `mailto:`. No code, and responses land with her. It costs nothing if her account holds one of the tenant's Business Standard seats (`O365_BUSINESS_PREMIUM`, 2 of 3 in use at the 2026-09-30 inventory). An Exchange-only licence would not include Forms (Inferred). It can later become Bandersnatch's request front door | 6 |
| **W6** | Video | Long video as **YouTube embeds** (unlisted or public; privacy-enhanced mode), uploaded by the editor herself. The hero loop stays in the repository. Cloudflare R2 only for a file that must be self-hosted. Cloudflare's per-file limit is 25 MiB, so video cannot live in the build | 6 |

**Defaults**, which stand unless the owner says otherwise:
- **Astro**, static output. The current page is ported pixel-for-pixel first (R12); content moves into Markdown and YAML files. Astro is MIT-licensed, and Cloudflare acquired the company behind it in January 2026.
- Page types designed once: home, standard page, news list and article, downloads list, and the Request Access link. The spec fixes the exact set and their fields.
- A new Cloudflare project builds the new repository. Workers static assets or Pages is settled in the spec. Cloudflare's own guidance for new projects is Workers, and Astro's deploy guide targets it; Pages still works. Choose Workers unless branch previews behind Access prove weaker there.
- Preview deployments sit behind Cloudflare Access, admitting the owner and the editor.
- GitHub Pages on this repository is turned off at cutover (DR-5).

## 2. What was asked

The owner wants the public website off their plate: a co-owner (below, **the editor**) should be able to update and add content without depending on the owner. The owner also named the site's other problems and asked for "a comprehensive solution and way forward". Owner answers, 2026-11-16:

| Question | Answer |
|---|---|
| Which site | `arclightlabs.io` only. `ansanalytics.com` is out of scope |
| What the editor changes | Copy on existing pages, new pages, news/posts, images and video |
| What "host content" means | Downloads (PDFs, decks), video, and gated/private material for approved visitors, as well as pages and posts |
| The editor | A business co-owner. The tools must be direct and need no code, git or web-design knowledge (R1) |
| Layout freedom | Undecided. Owner's idea: "a private repo that she can edit and work with claude, but it comes to me for review/publishing before going live" |
| Problems to fix | Redundant GitHub Pages copy (DR-5); Request Access is a `mailto:`; one page with no structure; the site lives in the public infrastructure repository (DR-6, DR-14); "gh pages is fine but it is a poor replacement for something a bit more streamlined" |
| Budget | Up to about $30/month |
| Moving the site out of this repository | Decide after seeing the options |

## 3. Current state (verified 2026-11-16)

**What is served.** `arclightlabs.io` and `www` return 200 from Cloudflare. Cloudflare Pages project `arclight-labs` (account CF-01) deploys from the orphan `gh-pages` branch of this repository, production branch `gh-pages`, automatic production deploys on, previews limited to `site/*` (owner, 2026-10-16). The CF-01 API tokens still cannot read Pages (403), so the project's settings are known from the dashboard record, not an API read.

**The redundant copy (DR-5).** GitHub Pages on this repository is still enabled (`build_type: legacy`, source `gh-pages` `/`, status `built`) and serves the same files at `arclightintel-dev.github.io/arclight-overcast/`.

**What the site is.** `origin/gh-pages` last changed 2026-08-14 (`99dad57`). One hand-written `index.html` (11.6 KB, inline styles) holds all of the content:
- a background poster and a 10 s looping video (`bh-loop.mp4` 2.3 MB, `.webm` 2.1 MB), pre-rendered from the WebGL shader by `tools/prerender/`;
- a HUD frame, the headline "The unknown is not unknowable", one paragraph, a **Request Access** button that is a `mailto:` link, and the Amygdala platform lockup.
- `singularity-gpu.js` (19 KB) and `static/textures/noise_deep.png` (0.98 MB) are published but no longer referenced by the page; they exist for the prerender pipeline.
- `_headers` sets cache lifetimes. There is no navigation, no second page, no build step, no content model and no form.

**Where it lives.** The repository is public (DR-14), and its `main` branch is infrastructure-only by charter. The site's branch shares nothing with `main` (DR-6, owner 2026-10-16: keep it there for now). Anyone given write access to edit the site would get write access to the Terraform repository.

**Mail and DNS.** `arclightlabs.io` is also the company's Microsoft 365 mail domain (MX, SPF, DKIM `selector1`/`selector2`, DMARC). The apex and `www` are proxied CNAMEs to Pages. Mail records are out of scope and must not be touched. The Cloudflare Terraform token covers `arclight-complex.net` only, so any `arclightlabs.io` DNS or Pages change is the owner's dashboard work or needs a token extension the owner approves.

**Gated sharing already has a home.** Bandersnatch (O-019; Complex **D-079**, "the platform's external sharing path") serves material to named outside recipients behind per-address tokens, with accounts, audit and stamping. Its staging substrate is applied. Website "gated content" should not invent a second mechanism without a reason.

**Identity.** Entra is the workforce IdP. Cloudflare Access (team `spring-shape-5449`) gates `*.staging.arclight-complex.net`; Entra is not yet an Access IdP (one-time PIN and Cloudflare login only).

**Out of scope, noted.** `ansanalytics.com` is a static site with a custom WordPress theme (`wp-content/themes/ans-analytics`), served from CloudFront distribution `d13jp2ln0nkwzl.cloudfront.net` and S3, last modified 2025-12-15, DNS at WordPress.com. That distribution is **not** in AWS account 650880817826 (the account's only distribution is Backstage's downloads). Who hosts it is unknown.

## 4. Requirements

Derived from the answers; the spec phase confirms them.

| # | Requirement |
|---|---|
| R1 | The editor changes copy, adds pages and posts, and uploads images, video and downloads **without code, git or design knowledge** |
| R2 | New pages and posts stay on-brand without the editor doing layout: page types are designed once and filled in |
| R3 | **Every change is reviewed by the owner before it goes live** (owner's idea; see decision W3 on whether this lasts) |
| R4 | Review is cheap: one preview link and one approve action, from a phone if need be |
| R5 | The editor signs in with an account she already has or one that takes minutes to make; no shared passwords |
| R6 | Nothing the editor touches can change infrastructure: the site leaves the Terraform repository's write path |
| R7 | Gated material reaches only approved people and never sits in a public repository or a public URL |
| R8 | Request Access becomes a request the editor can act on, not a bare mail link |
| R9 | One public copy of the site (DR-5 retired) |
| R10 | About $30/month or less, all in |
| R11 | Low upkeep: no server of our own for the public site; anything self-hosted is small and on existing Cloudflare |
| R12 | The current look (video hero, typography, HUD) carries over unchanged |

## 5. Options

The site has to become **structured** for any option except a hosted builder. Today every word sits inside hand-written HTML. Neither a form editor nor Claude can safely add a news post or a page to that without someone designing the page each time. So Options A and B share one foundation: a private repository, an Astro port of the current page, and page types designed once. They differ only in how the editor drives changes, and both write the same files. That is why B can be added to A later without migrating anything.

### Option A: chat with Claude on a private site repository (the owner's idea)

**How it works:**
1. The editor opens Claude Code on the web on the site repository and asks in plain language, for example "add a news post about X with this PDF".
2. Claude edits the content files and pushes a branch; she presses **Create PR**.
3. Cloudflare builds a preview of that branch.
4. The owner reads the change and the preview, approves and merges, and production deploys.

**What it needs:**
- A GitHub account for the editor: Claude Code on the web requires "Sign in with GitHub".
- A Claude seat: Pro is $20/month, or $17/month billed annually. A Team Standard seat is $25 monthly or $20 annually, with at least 2 seats.
- The Claude GitHub App installed on that one repository; the owner installs it.
- A repository `CLAUDE.md` that confines routine work to the content folders.
- A CI check that labels any pull request touching layouts, styles or configuration.

**For:**
- Nothing new to host or pay for beyond the seat.
- Anything is possible, including a new page type, a fix or a restyle, under the same review.
- The editor learns no CMS: she describes what she wants.

**Against:**
- Two tools to learn: Claude's session view and GitHub's pull-request button.
- Output is not deterministic, and Claude can drift into styling. The `CLAUDE.md` fence, the CI label and the owner's review catch it; nothing structural prevents it.
- Whether an attachment such as an image or PDF reliably ends up committed is not proven. Claude's documentation says attachments are saved in the session's environment; committing them is Inferred. **Pilot item.**
- Review load stays with the owner until W3 relaxes it.

### Option B: a form editor on the same repository

The editor opens `/admin` and sees a form for each page type ("News post: title, date, body, attachment"). Saving opens a pull request, and the owner merges it. The candidates, as of 2026-11-16:

| Candidate | Sign-in for the editor | Review flow | Catch | Cost |
|---|---|---|---|---|
| **Sveltia CMS** | GitHub account | Editorial workflow opens pull requests | Pre-1.0 (1.0 expected late 2026), with near-daily releases. Sign-in runs through a small Cloudflare Worker we would host | Free (MIT) |
| **Decap CMS + Decap Turbo** | Email and password, or Google; no GitHub account | Editorial workflow | Turbo has been generally available only since 2026-10-16. The free tier has 1 seat and no media library | Free; Pro €19/month |
| **Pages CMS** | Email invitation; no GitHub account | None documented; saves appear to commit directly (Inferred) | No preview. Its GitHub App asks for Administration and Actions **write** on the repository | Free |
| **TinaCloud** | Email | Editorial workflow only on Team | Its October 2026 login change locked out sites on 3.11 and older until they upgraded | Free for 2 users; Team $29/month |

**For:**
- The editor can only change what the form allows, so the design cannot drift.
- Drafts and previews are built in.

**Against:**
- Another service and another sign-in.
- A new page type still needs a developer, or Claude.
- Every candidate has one of the catches above.

### Option C: a hosted site builder (Framer or Webflow)

Rebuild the site in a builder; the editor edits visually and publishes.

**For:** the most independent the editor can be, with hosting and editing in one product.

**Against:**
- It means rebuilding the site.
- It gives layout freedom the owner thinks she does not want.
- The owner's review gate is not native to the builders; publish permissions on paid seats are unverified.
- Lock-in is high, and git history and review are lost.
- Framer behind the Cloudflare proxy needs its Pro plan and an advanced-hosting add-on; otherwise the apex records become DNS-only.

**Cost:**
- Framer: Basic $10/month plus a content-editor seat at $10/month, about $20. Basic has 30 pages, 2 collections and 1,000 items.
- Webflow: Premium $25/month plus a Limited seat at $15/month, both billed annually, about $40. That is over budget.

### Option D: a headless CMS (Sanity, Storyblok). Not recommended

Content lives in a vendor's database, and the site fetches it at build time.
- **Sanity's free plan** has only public datasets and two roles.
- **Storyblok's free plan** has 1 seat; Growth is $99/month.
- **Single sign-on** is an Enterprise or Premium feature on both.

D still needs the same Astro build plus a webhook. It solves nothing A or B does not, at more cost and more lock-in.

**Watching:** EmDash, Cloudflare's own Astro-based CMS (1.0 on 2026-09-28). It is a server-side application, so we would run an app for a marketing site, and it is new. Revisit at the next site review.

### Side by side

| | A: Claude + PR | B: form editor | C: builder | D: headless |
|---|---|---|---|---|
| The editor's experience | Describe the change in words | Fill in a form | Edit on the page | Fill in a form |
| Owner review before live | Native (pull request) | Native (pull request) | Not native | Needs a build gate |
| A new page type | Yes, reviewed | Needs a developer | She designs it | Needs a developer |
| Design can drift | Possible; caught in review | No | Yes | No |
| Monthly cost | $17-25 (Claude seat) | $0-21 | $20-40 | $0-99 |
| Upkeep | Repository + CI | + a CMS and its sign-in | Vendor | Vendor + build hooks |
| Lock-in | Low (files in git) | Low | High | High |

## 6. Recommendation

**Build the foundation, use Option A, keep Option B in reserve.**

1. **The foundation fixes most of the named problems on its own:**
   - a private site repository (W1, DR-6);
   - structure and navigation, so the site is no longer one page;
   - a real Request Access path (W5);
   - one public copy (DR-5);
   - previews and a review gate.
2. **Option A is the owner's own idea, and it holds up.** Of the options, only A lets the editor ask for *anything* without web skills, including things no form anticipated, at the cost of a Claude seat. The pull request is the review gate, and the preview link makes review a two-minute job from a phone.
3. **B is the fallback, not a fork.** If chat proves awkward for routine posts, Sveltia goes on top: she will already have a GitHub account. The file layout does not change, so nothing migrates.
4. **Not C:**
   - it rebuilds the site;
   - it is the most lock-in;
   - it hands over layout freedom nobody asked for;
   - it drops the review gate the owner wants.
5. **Not D:** cost and lock-in for no gain.

**The tension to settle (W3).** "Off my plate" and "every change comes to me" pull against each other. Under A, the owner's remaining job is approving pull requests. W3 is the explicit path to shrinking that once the pilot shows the content fences hold.

## 7. Phased plan

Each phase waits for the owner's go; nothing below has started.

| Phase | Work | Live change | Owner's part |
|---|---|---|---|
| **P0** | Decisions W1-W6 | None | Decide; confirm the Claude seat type. The editor creates her own GitHub account with her `arclightlabs.io` address |
| **P1** | **Spec**: content model (page types and fields), design rules for new page types, repository layout, the `CLAUDE.md` content fence, CI checks (build, links, the structural-change label), Workers or Pages, preview access, the branch rule and `CODEOWNERS`, video and download handling, cutover and rollback, DNS record list | None | One review pass, then approve |
| **P2** | **Build**: create the private repository. Port the page and its prerender tooling, with a visual diff against the live site. Add the page types and sample content, then CI, then a new Cloudflare project serving only its preview URL | None (new project, no domain) | Create the repository (or approve its creation), install the Cloudflare and Claude GitHub apps on it, connect the project in the dashboard |
| **P3** | **Pilot**: the editor does 4-5 real tasks on previews. Examples: change the headline, add a news post with a PDF, add a page with an image, embed a video. Success: she finishes each without owner help, and owner review takes under 5 minutes per change | None | Review the pilot pull requests |
| **P4** | **Cutover**: attach `arclightlabs.io` and `www` to the new project. Back up the zone's DNS first; only the two web records change, never the mail records. Verify, then keep the old project two weeks for rollback, turn off GitHub Pages here (DR-5) and tag `gh-pages` as an archive | Yes | Dashboard work (the tokens cannot reach Pages or this zone), on a written checklist |
| **P5** | **Close-out**: DR-5 and DR-6 closed; DR-14 re-examined without the website as a reason; service registry updated; W3 revisit date set | None | Decide W3 at the revisit |

Rollback at P4 is re-attaching the two domains to the old project, which stays untouched until P5.

## 8. Risks and open points

| Risk | Handling |
|---|---|
| Attachments in Claude Code on the web may not reach a commit | Pilot task in P3. Fallback: she uploads the file through GitHub's web page, or a media folder in Option B |
| Claude drifts into design changes | `CLAUDE.md` fence, the CI structural label, and owner review; the W3 split keeps structure owner-reviewed permanently |
| The branch rule is unenforced on a private repository | Inferred available: the account enforces active rules on another private repository's `main` today. P2 verifies on the new repository before the editor is added |
| Unpublished content leaks through preview URLs | Access on previews. Cloudflare documents a `*.pages.dev` wildcard caveat; the spec closes it for whichever product is chosen |
| The apex shares a zone with company mail | P4 changes only the apex and `www` web records, from a fresh DNS backup. MX, SPF, DKIM and DMARC are not touched |
| Gated material ends up on the public site | W4 keeps it in Bandersnatch. If the editor is to issue tokens herself, Bandersnatch's operator tool must be usable without a command line: a Bandersnatch backlog item, not website work |
| The GitHub enterprise migration (deferred) | The site repository moves with the others when it happens. If the enterprise uses managed users, the editor's GitHub sign-in can come from Entra |

## 9. Cost

| Item | Monthly |
|---|---|
| Claude seat for the editor | $17 (Pro, annual) to $25 (Team, monthly) |
| Cloudflare hosting: free plan, 500 builds/month, 25 MiB per file | $0 |
| R2: 10 GB free, no egress charge | $0 at this size |
| YouTube embeds; Microsoft Forms (on a Business Standard seat) | $0 |
| GitHub: the account already enforces rules on private repositories (Inferred) | $0 expected |
| **Total** | **About $17-25, under the $30 ceiling.** Adding Sveltia keeps it there; Decap Turbo Pro would push past it |

## 10. Evidence

Vendor pages read 2026-11-16:
- Claude: [pricing](https://claude.com/pricing), [Claude Code on the web](https://code.claude.com/docs/en/claude-code-on-the-web).
- Cloudflare: [Pages limits](https://developers.cloudflare.com/pages/platform/limits/), [preview deployments](https://developers.cloudflare.com/pages/configuration/preview-deployments/), [Pages known issues](https://developers.cloudflare.com/pages/platform/known-issues/), [Workers best practices](https://developers.cloudflare.com/workers/best-practices/workers-best-practices/), [Access](https://developers.cloudflare.com/cloudflare-one/access-controls/applications/http-apps/self-hosted-public-app/), [R2 pricing](https://developers.cloudflare.com/r2/pricing/), [Astro joins Cloudflare](https://blog.cloudflare.com/astro-joins-cloudflare/), [Astro on Cloudflare](https://docs.astro.build/en/guides/deploy/cloudflare/).
- Sveltia: [GitHub backend](https://sveltiacms.app/en/docs/backends/github), [roadmap](https://sveltiacms.app/en/docs/roadmap).
- Decap: [Turbo](https://decapcms.org/turbo/), [GitHub backend](https://decapcms.org/docs/github-backend/).
- Pages CMS: [collaborators](https://pagescms.org/docs/configuration/collaborators/), [GitHub App](https://pagescms.org/docs/guides/installing/github-app/).
- TinaCMS: [pricing](https://tina.io/pricing), [auth change](https://tina.io/blog/october-tinacloud-auth-changes).
- Builders: [Framer pricing](https://www.framer.com/pricing), [Framer behind Cloudflare](https://www.framer.com/help/articles/how-to-proxy-with-cloudflare/), [Webflow pricing](https://webflow.com/pricing).
- Headless: [Sanity pricing](https://www.sanity.io/pricing), [Storyblok pricing](https://www.storyblok.com/pricing).
- EmDash: [announcement](https://blog.cloudflare.com/emdash-cms-plugin-registry/).

Repository and account reads, 2026-11-16:
- `git ls-tree` and `git show` of `origin/gh-pages`.
- `gh api` reads of this repository's Pages configuration and visibility.
- Ruleset enforcement on an existing private repository (read only).
- The AWS CloudFront distribution list.
- Public HTTP and DNS reads of both domains.
