# Prompt: Per-Fork Owner-Aware Links for the ai-workbench Pages Site

Paste the section under "PROMPT FOR CLAUDE" into a Claude session inside the
`ai-workbench` repo. Adjust the owner list at the top if `ai-workbench` is
mirrored to additional GitHub orgs beyond `amit-t` and
`Invenco-Cloud-Systems-ICS`.

The mechanism mirrors what `ai-devkit` ships under `docs/`, except the link
bundle does NOT include `ai-ralph` (the workbench docs do not link to it).

---

## PROMPT FOR CLAUDE

> You are working in the `ai-workbench` repo. There is a Jekyll site under
> `docs/` (or wherever GitHub Pages reads from — confirm the source path
> before editing). The site is published from two forks:
>
> - `amit-t/ai-workbench`           → Pages: `https://amit-t.github.io/ai-workbench/`
> - `Invenco-Cloud-Systems-ICS/ai-workbench` → Pages: `https://Invenco-Cloud-Systems-ICS.github.io/ai-workbench/`
>
> Today the docs hardcode `amit-t/...` URLs (links to `ai-devkit`,
> `ai-workbench`, GitHub source, Pages cross-links). When the inv fork
> publishes Pages, those links wrongly send readers to `amit-t`. Same source
> file must produce the right links per fork — no branch divergence.
>
> Implement an owner-aware Liquid resolver that keys off
> `site.github.owner_name` (auto-set by the `jekyll-github-metadata` plugin
> from `PAGES_REPO_NWO` at deploy time). Add a regression guard so future
> edits cannot reintroduce hardcoded owner URLs.
>
> ## Required outputs
>
> 1. `docs/_data/orgs.yml` (adapt path if site root differs):
>
>    ```yaml
>    # Per-owner link map for GitHub Pages.
>    # Resolved at build time using site.github.owner_name.
>    # ai-workbench does NOT link to ai-ralph — keep this map workbench-scoped.
>
>    amit-t:
>      ai_workbench_repo:   https://github.com/amit-t/ai-workbench
>      ai_workbench_pages:  https://amit-t.github.io/ai-workbench/
>      ai_workbench_clone:  https://github.com/amit-t/ai-workbench.git
>      ai_devkit_repo:      https://github.com/amit-t/ai-devkit
>      ai_devkit_pages:     https://amit-t.github.io/ai-devkit/
>
>    Invenco-Cloud-Systems-ICS:
>      ai_workbench_repo:   https://github.com/Invenco-Cloud-Systems-ICS/ai-workbench
>      ai_workbench_pages:  https://Invenco-Cloud-Systems-ICS.github.io/ai-workbench/
>      ai_workbench_clone:  https://github.com/Invenco-Cloud-Systems-ICS/ai-workbench.git
>      ai_devkit_repo:      https://github.com/Invenco-Cloud-Systems-ICS/ai-devkit
>      ai_devkit_pages:     https://Invenco-Cloud-Systems-ICS.github.io/ai-devkit/
>    ```
>
>    Add other orgs only if `ai-workbench` actually publishes from them.
>
> 2. `docs/_includes/links.html`:
>
>    ```liquid
>    {%- assign owner = site.github.owner_name | default: site.fallback_owner | default: 'amit-t' -%}
>    {%- assign links = site.data.orgs[owner] -%}
>    {%- if links == nil -%}
>      {%- assign links = site.data.orgs[site.fallback_owner | default: 'amit-t'] -%}
>    {%- endif -%}
>    ```
>
> 3. Update `docs/_config.yml`:
>    - add `repository: amit-t/ai-workbench` (local-build fallback for the
>      github-metadata plugin; Pages overrides via `PAGES_REPO_NWO` env)
>    - add `fallback_owner: amit-t`
>    - ensure `plugins:` includes both `jekyll-seo-tag` and
>      `jekyll-github-metadata`
>
> 4. Add a `docs/Gemfile` (only if missing):
>
>    ```ruby
>    source 'https://rubygems.org'
>    gem 'github-pages', group: :jekyll_plugins
>    ```
>
> 5. Sweep every page/layout under the docs source. Replace each hardcoded
>    `amit-t/...` URL with the matching `{{ links.* }}` lookup. Add
>    `{% include links.html %}` after the front-matter block of each `.md`
>    page that references links. Layouts can include it once at the top.
>
>    Do NOT introduce ai-ralph keys or links — `ai-workbench` docs do not
>    reference `ai-ralph`.
>
> 6. Regression guard `scripts/check-docs-links.sh` (executable):
>
>    - Scan `docs/*.md`, `docs/_layouts/*.html`, `docs/_includes/*.html`.
>    - Allowlist: `docs/_data/orgs.yml`, `docs/_includes/links.html`,
>      `docs/_config.yml`.
>    - Fail (exit 1) on any match for
>      `https?://(github\.com/(amit-t|Invenco-Cloud-Systems-ICS)/|(amit-t|Invenco-Cloud-Systems-ICS)\.github\.io/)`.
>    - Print offending file/line + remediation hint.
>    - Verify by injecting a fake hardcoded URL into a docs page, confirming
>      the script exits 1, then reverting.
>
> 7. CI workflow `.github/workflows/docs-links.yml`:
>
>    - Trigger on push/PR touching `docs/**`,
>      `scripts/check-docs-links.sh`, or the workflow itself.
>    - Job 1 `audit`: run the script.
>    - Job 2 `build` (needs: audit): set up Ruby 3.3 with `bundler-cache`
>      pointed at `docs`, build twice:
>      - default build → assert rendered `index.html` contains
>        `github.com/amit-t/ai-workbench` and contains no unresolved
>        `links.` placeholders.
>      - rebuild with `env: PAGES_REPO_NWO: Invenco-Cloud-Systems-ICS/ai-workbench`
>        → assert rendered output contains `Invenco-Cloud-Systems-ICS/ai-workbench`
>        and contains no `github.com/amit-t/`.
>
> 8. `.gitignore` additions for Jekyll local artifacts:
>
>    ```
>    docs/_site/
>    docs/_site_local/
>    docs/_site_inv/
>    docs/_site_default/
>    docs/.jekyll-cache/
>    docs/.bundle/
>    docs/vendor/
>    docs/Gemfile.lock
>    ```
>
> ## Verification (must run before reporting done)
>
> Use `docker run --rm -v "$PWD/docs:/srv/jekyll" -w /srv/jekyll jekyll/jekyll:4 sh -c "bundle install && bundle exec jekyll build --destination /srv/jekyll/_site_local"`
> to confirm:
>
> - default build resolves to `amit-t/...` URLs throughout the rendered HTML
> - rebuild with `-e PAGES_REPO_NWO=Invenco-Cloud-Systems-ICS/ai-workbench`
>   resolves to `Invenco-Cloud-Systems-ICS/...` URLs throughout
> - `scripts/check-docs-links.sh` passes
> - artificial violation (e.g. add a hardcoded `amit-t/...` URL to a
>   docs page) makes the guard exit 1; revert after testing
>
> ## Branch handling
>
> Same source on every fork — never branch the docs per owner. The
> resolver flips at build time from a single committed file set.
> If `inv` and `origin` have diverged via separate PR merges, merge them
> together once before the rollout commit so both forks land the change
> on top of the same tip; push the same merge SHA to both remotes.
>
> ## Out of scope
>
> - Do not add `ai-ralph` keys, links, or references — `ai-workbench`
>   docs intentionally do not link to `ai-ralph`.
> - Do not change copy/wording beyond URL replacements.
> - Do not move the docs source path or rename pages.
>
> Report back with: file list changed, both Docker build outputs
> (truncated to the link grep), guard pass + injected-failure proof, and
> the commit SHA.
