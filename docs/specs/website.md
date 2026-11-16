# Website spec: arclightlabs.io

Status: **approved by the owner, 2026-11-16, with the defaults for Q1-Q4 (§12).** This is phase P1 of the [website proposal](../proposals/website-cms.md). The owner accepted decisions W1-W6 the same day ([O-020](../DECISIONS.md)). Nothing is built yet, and P2 starts only on the owner's go.
**This repository is public (DR-14).** The editor is named by role only. Her accounts and addresses never appear here.

## 1. Purpose and boundaries

This spec fixes everything P2 builds:
- the site repository;
- the content model;
- the design rules for new pages;
- how the editor works with Claude;
- the checks and the review gate;
- hosting, preview access, Request Access;
- cutover and rollback.

**One source of truth per topic.** P2 carries §3-§7 into the site repository's `README.md` and `CLAUDE.md`. From then on those files govern, and changes to them are owner-reviewed (§7). This spec keeps §8-§10 (where it runs), which Overcast owns under D-058.

**Not in scope:**
- **A redesign.** The home page is ported as it is (R12), and new page types extend its style (§5).
- **Server code, a database or a CMS.** The site is static output only. Option B (a form editor) stays in reserve.
- **Gated or confidential material** anywhere in the site repository. It goes through Bandersnatch (W4).
- **Analytics, cookies or trackers.** There are none today, and adding any is a separate owner decision.
- **Scheduled publishing, comments, search, a newsletter.**
- **`ansanalytics.com`.**

## 2. People, accounts and access

| Who | Account | Access |
|---|---|---|
| Owner | `arclightintel-dev` on GitHub; Cloudflare account CF-01 | Repository admin. Approves and merges; does the dashboard work |
| Editor (a co-owner) | Her own GitHub account, made with her `arclightlabs.io` address, with two-factor sign-in; a Claude seat (Pro or Team; cloud sessions are not on the free plan) | Collaborator on the site repository only. On a personal-account repository that access is always write and cannot be lowered, so the ruleset (§7) is what keeps her changes off `main` |
| Claude, in her sessions | The Claude GitHub App, installed on the site repository only | Pushes branches and opens pull requests at her request |
| Cloudflare | Cloudflare's GitHub App, installed on the site repository only | Reads the repository, builds, reports the preview |

There are no shared passwords. The site repository holds no tokens or secrets: it is static, and Cloudflare builds through its own GitHub connection.

## 3. Repository

**`arclightlabs-site`**, private, under `arclightintel-dev`, default branch `main`. The owner creates it in P2, or Overcast does on the owner's go. It starts with fresh history. The `gh-pages` history stays in this repository under an archive tag (§10).

```
arclightlabs-site/
├── CLAUDE.md                   rules Claude follows in the editor's sessions (§6.2)
├── README.md                   how the site works, for the owner
├── .github/
│   ├── CODEOWNERS              (§7)
│   ├── pull_request_template.md
│   └── workflows/checks.yml    (§6.3)
├── astro.config.mjs  package.json  package-lock.json  tsconfig.json  wrangler.jsonc
├── public/
│   ├── _headers                (§8.3)
│   ├── favicon.svg  robots.txt
│   ├── hero/                   bh-loop.mp4, bh-loop.webm, bh-poster.jpg
│   ├── brand/                  logomark.png
│   └── downloads/              CONTENT: public PDFs (§4.5)
├── src/
│   ├── content.config.ts       collection schemas (§4)
│   ├── site.ts                 site name, address, Request Access link (§4.1)
│   ├── content/                CONTENT: everything the editor changes
│   │   ├── home.yaml
│   │   ├── pages/<slug>.md
│   │   ├── news/<slug>.md
│   │   ├── downloads/<slug>.yaml
│   │   └── media/              images used by the entries above
│   ├── layouts/  components/  pages/  styles/
└── tools/prerender/            the hero loop pipeline; not part of the build
```

**Content paths** are `src/content/**` and `public/downloads/**`. Everything else is **structure**.

**What moves from `gh-pages`** (`99dad57`, read 2026-11-16):

| Today | Size | In the site repository |
|---|---|---|
| `index.html` | 11.6 KB | Split into the home layout and `home.yaml` (§5.1) |
| `bh-loop.mp4`, `bh-loop.webm`, `bh-poster.jpg` | 2.3 MB, 2.1 MB, 63 KB | `public/hero/`, unchanged |
| `assets/logomark.png`, `favicon.svg` | 27 KB, 9.5 KB | `public/brand/`, `public/` |
| `singularity-gpu.js`, `static/textures/noise_deep.png` | 19 KB, 0.98 MB | `tools/prerender/`, **no longer published**. They only feed the pipeline |
| `tools/prerender/*` | 9 KB | `tools/prerender/`. Paths are adjusted; the loop is not regenerated in P2 |
| `_headers` | | Replaced by §8.3, which keeps its cache rules |
| `.gitignore`, `.claude/launch.json` | | Replaced for Astro |

## 4. Content model

The schemas live in `src/content.config.ts` and are enforced at build. A content file that breaks a rule fails the build, and the error names the file and the rule. The length limits protect the layout.

Raw HTML in content Markdown is **not rendered**: the build sanitizes it. Content cannot add scripts, frames or styling.

### 4.1 Site settings (structure: `src/site.ts`)

- Name: `Arclight Labs`. Address: `https://arclightlabs.io`.
- Default description: the current meta description.
- `requestAccessUrl`: the form's link (§9). Until the form exists it stays `mailto:access@arclightlabs.io`, as today.

### 4.2 Home (`src/content/home.yaml`)

| Field | Rule | Today |
|---|---|---|
| `eyebrow` | ≤ 60 characters | "Collection · Modeling · Inference" |
| `headline` | ≤ 60 | "The unknown is not unknowable" |
| `intro` | ≤ 320 | The hero paragraph (about 220) |
| `ctaLabel` | ≤ 24 | "Request Access" |
| `platformLabel`, `platformName` | ≤ 24 each | "The Platform", "Amygdala" |
| `description` | ≤ 160 | The meta description |

The video, the HUD, the Amygdala mark and the layout are structure.

### 4.3 Standard page (`src/content/pages/<slug>.md`, served at `/<slug>/`)

| Field | Rule |
|---|---|
| `title` | Required, ≤ 70 |
| `description` | Required, ≤ 160. Used in search results and link previews |
| `image` | Optional: an image in `media/` and its `alt` text, which is then required |
| `video` | Optional: a YouTube video ID (11 characters), shown under the title |
| `nav` | Optional: `label` (≤ 20) and `order`. When set, the page appears in the site navigation |
| Body | Markdown: headings from level 2, paragraphs, lists, links, images with alt text |

Slugs use lowercase letters, digits and hyphens. They may not be `news`, `downloads`, `hero`, `brand` or `404`.

### 4.4 News (`src/content/news/<slug>.md`, served at `/news/<slug>/`)

| Field | Rule |
|---|---|
| `title` | Required, ≤ 90 |
| `date` | Required. Shown on the post; the list at `/news/` is newest first |
| `summary` | Required, ≤ 240. Shown in the list and as the description |
| `image`, `video` | As for standard pages |
| `downloads` | Optional list of download entries, by slug, shown as attachments |
| Body | As for standard pages |

There is no scheduling: a post goes live when its pull request merges.

### 4.5 Downloads (`src/content/downloads/<slug>.yaml` plus the file in `public/downloads/`)

| Field | Rule |
|---|---|
| `title` | Required, ≤ 90 |
| `description` | Required, ≤ 240 |
| `date` | Required |
| `file` | A PDF in `public/downloads/` that exists, with a lowercase, hyphenated name. The listed size is computed at build |

- **Every download is public and listed** at `/downloads/`. There is no unlisted or private download. Anything meant for named people goes through Bandersnatch (W4).
- **PDF only.** Decks are exported to PDF. Allowing another format is a structure change.
- **Up to 20 MiB per file.** Cloudflare's limit is 25 MiB per file, so the checks keep a margin.

### 4.6 Images

- Images live in `src/content/media/` and are referenced from entries. Never in `public/`, which would skip processing.
- The build resizes them and converts them to modern formats. It is expected to strip camera and location metadata too (Inferred from the image pipeline; P2 checks, A9).
- Every image needs alt text. Claude asks the editor for a description if she gives none.
- Source images are capped at 10 MiB each.

### 4.7 Video (W6)

- **Long video goes on YouTube.** The editor uploads to the company's YouTube channel and gives Claude the link. Entries store the 11-character ID.
- **How it shows:** an embed from `www.youtube-nocookie.com` (privacy-enhanced mode), loaded lazily.
- **No video files in content.** The checks reject `.mp4`, `.webm` and `.mov` outside `public/hero/`.
- **"Unlisted" on YouTube is not private.** Confidential video goes through Bandersnatch.
- **A YouTube channel needs a Google account.** The company runs on Microsoft 365, so the first video needs a Google account made with a company address, and a channel (§13).

## 5. Page types and design rules (R2, R12)

### 5.1 Home: ported as it is

**Visual parity with the live page** is the first acceptance test (A1).

**Kept as is:**
- the poster and video loop, and the vignette;
- the HUD, including the animated Z readout;
- the hero text styles and the reveal animation;
- the reduced-motion behaviour and the short-viewport rules.

**Changed without visible effect:**
- the text comes from `home.yaml`;
- the inline styles move into a stylesheet;
- the fonts are self-hosted, in the same families and weights (§8.3);
- the copyright year comes from the build date.

**One visible addition:** navigation links, once pages, news or downloads exist (Q2).

**Found while reading the page.** The hero paragraph sets no font, so it renders in the browser's default serif (Times New Roman on Windows). The port keeps it, as decided at approval (Q1).

### 5.2 New page types

Standard pages, the news list and article, the downloads list and the 404 page share one reading layout:
- **Header:** the logomark and "Arclight Labs" wordmark as on the home page (linking home), plus the navigation.
- **Column:** one column, at most about 68 characters per line, with body text no smaller than 17 px. No video background.
- **Footer:** the bottom bar of the home page's HUD (name, ©).
- **Built only from the tokens in §5.3.** A new font, colour or effect is a structure change.
- **Accessibility:** WCAG 2.2 AA contrast, visible keyboard focus, alt text, and reduced motion honoured.
- **Metadata:** every page has a title, description, canonical address and Open Graph tags. The site has `sitemap-index.xml` and `robots.txt`.

The owner signs off each page type on the preview, with sample content, before the pilot (A2).

### 5.3 Design tokens (taken from the live page)

| Token | Value | Used for |
|---|---|---|
| `--bg` | `#000` | Background |
| `--text` / `--text-strong` | `#e7eaef` / `#f3f5f9` | Body / headings |
| `--text-muted` | `rgba(196,203,214,0.78)` | Intro and secondary text |
| `--label` | `rgba(178,187,201,0.72)` | Eyebrows and labels |
| `--faint` | `rgba(150,160,176,0.4)` | Footer bar |
| `--line` | `rgba(180,190,205,0.32)` | HUD corner lines, rules |
| `--gold` | `#D9BC84` | The Amygdala ring; used sparingly |
| `--btn-bg` / `--btn-text` | `rgba(244,246,250,0.95)` / `#06080c` | Primary button |
| `--font-display` | Cormorant Garamond 300/400/500 | Headlines |
| `--font-mono` | IBM Plex Mono 300/400/500, uppercase, tracked | Labels, navigation, dates |
| `--font-wordmark` | System UI sans, 500/300 | "Arclight Labs" |
| `--font-lockup` | Jost 200/300 | "Amygdala" |
| `--font-body` | Jost 300/400 (Q1) | Reading text on new pages |

## 6. Editing (W2)

### 6.1 A change, end to end

1. The editor opens Claude Code on the web, in a browser or in the Code tab of the Claude phone app, and chooses the site repository. She describes the change and attaches any images or PDFs.
2. Claude edits the content files under `CLAUDE.md`'s rules, runs the checks and pushes a branch. She presses **Create PR** on the session's changes card, and Claude writes the title and description.
3. Cloudflare builds a preview, and its link appears on the pull request. The checks run.
4. The owner opens the preview, then approves and merges, from GitHub's phone app if need be. Production deploys from `main`.
5. If the owner asks for changes, the editor goes back to the session and asks Claude to make them. The same pull request updates.

### 6.2 The `CLAUDE.md` rules

P2 writes these; the file is structure, so only the owner changes it.

- **Who you are helping.** A co-owner who does not use code or git. Use plain language and no jargon, and never ask her to run a command. Say what changed and what the owner will see.
- **Where you work.** Content paths only. If a request needs anything else (layout, styles, a new page type, the navigation design, configuration), say so and explain that it goes to the owner as a design change. Do it only if she confirms, in its own pull request.
- **Her words are hers.** Fix typos, but do not rewrite her copy unless she asks. Offer suggestions separately.
- **Public by default.** Everything merged is public. Stop and ask if material looks confidential: marked internal or confidential, client names, prices, other people's personal details. Confidential material goes through Bandersnatch, never the site.
- **Files:**
  - Images go to `media/` with alt text; ask her for a description.
  - PDFs go to `public/downloads/` with a lowercase, hyphenated name.
  - No video files: ask for a YouTube link instead.
  - Refuse a file over its limit, and say why.
- **Never:**
  - add scripts, trackers, analytics, fonts, or embeds other than the YouTube component;
  - change `CLAUDE.md`, `CODEOWNERS`, workflows, `_headers`, `wrangler.jsonc` or dependencies on a content request;
  - merge a pull request, push to `main` or force-push;
  - put secrets or anyone's personal data in the repository.
- **Before pushing,** run `npm run check` (validation, build, file rules). Fix any failure, or explain it.
- **One request, one pull request,** with the template filled in: what changed, which pages, files added, and whether it is a design change.

**The session's environment.** Cloud sessions clone the repository, so they load `CLAUDE.md` and `.claude/settings.json`.
- A `SessionStart` hook in `.claude/settings.json` runs `npm ci`, so the checks work in every session. The default network level allows the npm registry.
- **Node version.** Astro 7 needs Node 22.23.4 or later. Cloud sessions document "Node 22" without the patch level, so the hook installs a newer Node if the session's is older (A11).
- The repository pins its Node version for Cloudflare's builds too. P2 confirms the build uses it.

### 6.3 Checks (GitHub Actions, on every pull request)

| Check | Required | Fails when |
|---|---|---|
| `build` | Yes | `astro check && astro build` fails. `astro build` alone does not type-check; a content file that breaks its schema raises a content-data error (A3 proves it fails the check) |
| `links` | Yes | An internal link or anchor in the built site does not resolve |
| `files` | Yes | A file is over its limit (§4), a video file is outside `public/hero/`, a download is not a PDF, or an image sits in `public/` outside `hero/`, `brand/` and the favicon |
| `scope` | No (never fails) | Labels the pull request `design-change` when it touches anything outside the content paths |

**Dependencies stay few:** Astro, its sitemap integration, the self-hosted fonts and the Markdown sanitizer. Dependabot security alerts are on. Version updates are the owner's pull requests.

## 7. Review gate (W3)

**The ruleset is the only thing between a session and production.**
- Claude's GitHub proxy "doesn't limit which branches a push can update". Its documentation points to rulesets for that.
- On a personal account, rulesets on a **private** repository need **GitHub Pro** ($4/month). On GitHub Free they apply to public repositories only.
- The account appears to have Pro (Inferred, strong): reading branch protection on an existing private repository returns "Branch not protected", where a Free account gets an upgrade prompt.
- A5 proves the rule holds against the editor's account before she makes her first change. If it does not, the editor gets no access until it does.

### 7.1 At launch

A ruleset on `main`:
- a pull request is required, with **1 approval** and **review from Code Owners**;
- approvals are dismissed when new commits are pushed;
- `build`, `links` and `files` must pass;
- no force-push or deletion;
- **Bypass:** the repository admin role (the owner) only, because the owner's own pull requests have no one else to approve them. The write role is never on the bypass list, since the editor holds it. Which bypass actors GitHub offers on a personal-account repository is unstated; P2 confirms the admin role is offered.

`CODEOWNERS` holds one line: `* @arclightintel-dev`.

**What this gives:**
- A pull request's author cannot approve it. Who authors a pull request made in a cloud session is not documented (Inferred: the editor's own account, marked as via the app). Either way, only the owner is a code owner, so the gate holds.
- Once the owner has approved, the editor may press merge herself. Any later push dismisses the approval.

### 7.2 After the W3 revisit

This waits for the owner's decision, after 30 days or 10 merged changes.

- `CODEOWNERS` narrows to the structure paths.
- Required approvals drop to 0. Review from Code Owners stays on.

**Result:** a pull request that only touches content merges once the checks pass, and the editor presses merge herself. Any pull request touching structure still waits for the owner. The change is two lines, reviewed like any other.

**To check at the revisit:** that GitHub still requires Code Owner review when required approvals are 0. The documentation does not say so directly. If it does not, content-only merges are not possible without weakening the gate, and the owner keeps approving.

## 8. Hosting (Overcast)

### 8.1 Product: a Worker with static assets, not Pages

**Why Workers:**
- **Cloudflare's guidance.** The Pages overview says "Start new projects with Workers", and Astro's Cloudflare guide says the same.
- **Previews.** Worker Previews give each branch its own preview. They launched 2026-09-22 and are the default for new Workers. Cloudflare comments the preview link on the pull request and adds a check run.
- **Access in one setting.** "Protect this Worker behind Access" with the **Previews only** scope covers the previews. Pages' built-in policy covers previews too, but its production `pages.dev` address stays public unless a two-application workaround is set up. That address is how today's third copy exists.
- **Same limits, no cost.**
  - Files: 25 MiB each and 20,000 per version on the free plan.
  - Requests for static files are free and unlimited.
  - Workers Builds on the free plan: 3,000 build minutes a month, one build at a time, 20-minute timeout.

**What is new or unstated:**
- Worker Previews are about eight weeks old.
- The Workers Builds documentation does not say it supports private repositories. The Pages documentation does, and both use the same GitHub App.

**So P2 starts with four tests, before anything else is built:**

| # | Test |
|---|---|
| T1 | The Worker connects to the private repository and builds `main` |
| T2 | A push to another branch produces a preview, and its link appears on the pull request |
| T3 | Opening a preview without signing in is refused by Access, including the per-version addresses |
| T4 | Previews still work with the production `workers.dev` address turned off |

**If T1 or T3 fails,** the site uses Pages with Cloudflare's documented Access workaround, and no other section changes. **If T4 fails,** the production `workers.dev` address gets its own Access application (§8.4).

### 8.2 Configuration

- **Worker:** `arclightlabs-site` in account CF-01, assets only. No Worker script, and no `@astrojs/cloudflare` adapter, which is only needed for on-demand rendering.
- **Builds:**
  - production branch `main`;
  - build command `npm run build`;
  - deploy command `npx wrangler deploy`;
  - preview builds on, using the default preview command.
- **`wrangler.jsonc`:**
  - `name`, `compatibility_date`;
  - `assets.directory: "./dist"`;
  - `not_found_handling: "404-page"`;
  - `workers_dev: false`, subject to T4.
- **Build marker:** each page's metadata carries the commit it was built from, so verification can tell which deploy is live (§10). P2 picks the variable Cloudflare's build provides.

### 8.3 Headers (`public/_headers`)

**Caching** keeps today's intent:
- the hero files revalidate daily, since their names stay the same when the loop is regenerated;
- `brand/` files are cached for a week;
- Astro's hashed files under `/_astro/` are immutable for a year;
- downloads are cached for an hour;
- pages use the platform default, which revalidates.

When two rules set the same header, Cloudflare joins their values, so `Cache-Control` rules must not overlap.

**Security headers on every path:**
- `Content-Security-Policy`:
  - `default-src 'self'`, `img-src 'self' data:`, `font-src 'self'`, `script-src 'self'`;
  - `style-src 'self' 'unsafe-inline'`;
  - `frame-src https://www.youtube-nocookie.com`;
  - `object-src 'none'`, `base-uri 'self'`, `frame-ancestors 'none'`.
- `X-Content-Type-Options: nosniff`.
- `Referrer-Policy: strict-origin-when-cross-origin`.
- `Permissions-Policy: camera=(), microphone=(), geolocation=()`.
- `Strict-Transport-Security: max-age=31536000`, with no `includeSubDomains`, because the zone also carries mail-related names.

**Fonts are self-hosted.** The site stops calling Google Fonts, so a page load makes no third-party request (A8).

### 8.4 Addresses (R9)

**Today the site is public at three addresses**, read 2026-11-16:
- `arclightlabs.io` and `www`;
- `arclight-labs.pages.dev`, the Pages project's own address;
- the GitHub Pages address.

**From P2 until cutover**, the Worker has no public address:
- no custom domain;
- the production `workers.dev` address off (T4);
- previews behind Access.

**At cutover** the two domains attach (§10). The other two copies go: GitHub Pages at cutover, and the Pages project at P5.

**Access policy:** one reusable Zero Trust policy that admits the owner's and the editor's email addresses, by one-time PIN. It moves to Entra when Entra becomes an Access identity provider. The addresses live in the Cloudflare dashboard, never in a repository.

**`www`:**
- Default: both domains are Custom Domains on the Worker (Q3).
- Cloudflare's documentation shows several Custom Domains per Worker, but not an apex and `www` pair. It recommends a redirect rule for `www` instead.
- If the pair is refused, `www` redirects to the apex.

### 8.5 Undoing a bad change after launch

- **The normal path:** revert the pull request, which redeploys.
- **The fast path, for the owner:** Worker → Deployments → Rollback in the dashboard, or `wrangler rollback`. Any of the last 100 versions can be restored.

## 9. Request Access (W5)

- **The form:** a Microsoft Forms form in the editor's Microsoft 365 account, set to "anyone can respond". It is shared with the owner as a co-author, so the responses survive either person's absence.
- **Fields:** the editor decides. Suggested: name, organisation, work email, what they want access to, and consent to be contacted.
- **The button links to the form** through `requestAccessUrl`. Nothing is embedded, so the site loads no third-party frame.
- **Notification:** an email to the editor on each response (a Forms setting).
- **Approved requests** for gated material get a Bandersnatch share (W4).

## 10. Cutover and rollback (P4)

**Preconditions:**
- A1-A9, A11 and A12 pass, and the pilot (P3) is done;
- the owner says go;
- a quiet hour is chosen.

The owner does the dashboard steps, because the Cloudflare tokens cannot reach Pages or this zone. Overcast prepares the checklist and does the verification.

1. **Back up DNS.** Export the `arclightlabs.io` zone's DNS and keep the file outside this public repository. Note the apex and `www` records.
2. **Release the domains from Pages.** Following Cloudflare's order, delete the apex and `www` CNAMEs to `arclight-labs.pages.dev`, then use "Remove domain" for both in the Pages project. Nothing else in the zone is touched.
3. **Attach the domains to the Worker.** Add Custom Domains `arclightlabs.io` and `www.arclightlabs.io` (or the `www` redirect, §8.4). Cloudflare creates the records and certificates itself.
4. **Verify (Overcast).**
   - Both domains return 200, and the page carries the deployed commit (a build marker).
   - A fresh DNS export differs from the backup only in the apex and `www` web records. MX, SPF, DKIM, DMARC and the other mail records are unchanged.
   - The owner sends and receives one email at an `arclightlabs.io` address.
5. **Turn off GitHub Pages** on this repository (DR-5). Overcast does this on the owner's go.
6. **Freeze `gh-pages`.** Tag it as `site-archive-<date>` and leave the branch frozen until P5.

**Interruption:** the site may be unreachable for a few minutes between steps 2 and 3. Cloudflare does not document how long. Mail is never affected.

**Rollback,** available for two weeks:
- remove the Worker's Custom Domains;
- recreate the two CNAMEs from the backup;
- add the domains back to the Pages project, which stays untouched until P5.

The trigger: any step-4 check still failing 30 minutes after cutover.

**P5:**
- delete the Pages project, which also removes `arclight-labs.pages.dev`;
- decide whether to delete the `gh-pages` branch (the tag keeps its history);
- record the result in the service registry and close DR-5 and DR-6.

## 11. Acceptance

| # | Test | When |
|---|---|---|
| A1 | The home page matches the live page at 1440×900, 768×1024, 390×844 and 844×390, with motion reduced so the poster frame compares. The automated screenshot diff shows only font anti-aliasing differences, and the owner signs off side by side | P2 |
| A2 | Every page type renders with sample content on the preview, and the owner signs off | P2 |
| A3 | A deliberately broken content file (a missing alt text, an over-long headline) fails `build` with a message naming the file and the field | P2 |
| A4 | A pull request touching `src/layouts/` gets the `design-change` label | P2 |
| A5 | From the editor's account, a direct push to `main` is rejected, and her pull request cannot merge without the owner's approval. This runs before her first real change; she gets no further access until it passes | P2, at her onboarding |
| A6 | Preview addresses ask for an Access sign-in. No address other than the two domains serves the site publicly (§8) | P2, P4 |
| A7 | The security headers in §8.3 are present, and the browser console shows no policy violations on any page type | P2 |
| A8 | Loading any page makes no third-party request, except the YouTube frame on entries with a video | P2 |
| A9 | A test photo with location metadata comes out of the build without it | P2 |
| A10 | After cutover: both domains serve the new site, the mail records are unchanged against the backup, and the old copies are gone (§10) | P4 |
| A11 | A new Claude Code on the web session on the repository installs dependencies and passes `npm run check` without help (Node version, network) | P2 |
| A12 | The owner's dry run: in a cloud session, attach a photo and a PDF and ask for a news post. Both files are committed in the pull request, and the preview shows them. Documentation says only that attachments are saved in the session's environment. If this fails, the fallback is uploading the file to the pull request's branch on GitHub's web page | P2, before the pilot |

## 12. Questions settled at approval

The owner took the defaults on 2026-11-16 ("Approve with defaults").

| # | Question | Decision |
|---|---|---|
| Q1 | The hero paragraph renders in the browser's default serif because no font is set (§5.1). Keep it, or set one? And which body font do reading pages use? | The port keeps the hero as is. Reading pages use Jost 300/400, already a brand font |
| Q2 | Where do navigation links go on the home page? | In the HUD's bottom bar, in the same mono labels, shown only once there is something to link to. The owner approves on the preview |
| Q3 | `www`: keep serving the site, or redirect to the apex? | Keep serving both, with the canonical address on the apex |
| Q4 | Once the form collects contact details, does the site need a privacy notice? | The editor writes one as a standard page if the owner wants it. Legal wording is outside this spec |

## 13. Prerequisites

| When | Who | What |
|---|---|---|
| Before P2 | Owner | Go for P2. Create the repository (or approve its creation). Install Cloudflare's and Claude's GitHub Apps on it only ("Only select repositories"). Connect the Worker in the dashboard (§8). Confirm the account's GitHub plan is Pro (§7) |
| Before P3 | Editor | A GitHub account with two-factor sign-in, a Claude seat (seat type confirmed by the owner), the collaborator invitation accepted, and her address admitted to preview Access |
| First video | Editor | A Google account made with a company address, and the company YouTube channel |
| P2 and P4 | Overcast | Service registry rows for the repository, the Cloudflare project and the GitHub Apps; DR-5, DR-6 and DR-14 updated |

## 14. Evidence

**Repository and account reads,** 2026-11-16:
- `git ls-tree` and `git show` of `origin/gh-pages` at `99dad57`: the inventory, `index.html`, `_headers`, `tools/prerender/`.
- Public HTTP reads: `arclight-labs.pages.dev` and `arclightintel-dev.github.io/arclight-overcast/` both return 200 with the site.
- `gh api` on an existing private repository: its branch-protection read returns 404 "Branch not protected", not an upgrade prompt, and its rulesets are active.

**Vendor documentation,** read 2026-11-16. The dates in brackets are each page's last update.

Cloudflare:
- [Pages overview](https://developers.cloudflare.com/pages/) (2026-08-25)
- [Worker Previews](https://developers.cloudflare.com/workers/previews/) (2026-09-24)
- [Builds configuration](https://developers.cloudflare.com/workers/ci-cd/builds/configuration/) (2026-11-08)
- [GitHub integration](https://developers.cloudflare.com/workers/ci-cd/builds/git-integration/github-integration/) (2026-11-10)
- [Builds limits](https://developers.cloudflare.com/workers/ci-cd/builds/limits-and-pricing/) (2026-10-28)
- [Workers and Access](https://developers.cloudflare.com/workers/configuration/cloudflare-access/) (2026-11-02)
- [Pages preview deployments](https://developers.cloudflare.com/pages/configuration/preview-deployments/) (2026-10-12)
- [Pages known issues](https://developers.cloudflare.com/pages/platform/known-issues/) (2026-11-06)
- [`_headers`](https://developers.cloudflare.com/workers/static-assets/headers/) (2026-11-12)
- [Workers limits](https://developers.cloudflare.com/workers/platform/limits/) (2026-11-13)
- [Workers pricing](https://developers.cloudflare.com/workers/platform/pricing/) (2026-11-13)
- [Custom Domains](https://developers.cloudflare.com/workers/configuration/routing/custom-domains/) (2026-11-12)
- [Pages custom domains](https://developers.cloudflare.com/pages/configuration/custom-domains/) (2026-11-11)
- [Rollbacks](https://developers.cloudflare.com/workers/configuration/versions-and-deployments/rollbacks/) (2026-11-12)

Astro:
- [Install and setup](https://docs.astro.build/en/install-and-setup/) (Node floor)
- [Content collections](https://docs.astro.build/en/guides/content-collections/)
- [Images](https://docs.astro.build/en/guides/images/)
- [Cloudflare deploy guide](https://docs.astro.build/en/guides/deploy/cloudflare/)
- [TypeScript](https://docs.astro.build/en/guides/typescript/), on `astro check`

GitHub:
- [About rulesets](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/about-rulesets) (plan availability)
- [Available rules](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/available-rules-for-rulesets)
- [Code owners](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/about-code-owners)
- [Personal-account permission levels](https://docs.github.com/en/account-and-profile/reference/permission-levels-for-a-personal-account-repository)

Claude Code:
- [On the web](https://code.claude.com/docs/en/claude-code-on-the-web)
- [Cloud environments](https://code.claude.com/docs/en/cloud-environments)
- [Mobile](https://code.claude.com/docs/en/mobile)
- [The `.claude` directory](https://code.claude.com/docs/en/claude-directory), on attachments

Other:
- [YouTube privacy-enhanced mode](https://support.google.com/youtube/answer/171780)
