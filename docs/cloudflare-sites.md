# Cloudflare sites guide

How a site that `husterk` hosts on Cloudflare is built, deployed and measured.
It adds to the [public](public-repos.md) and [private](private-repos.md) repo
guides, which still apply in full.

## 1. Deploy a static site as a Worker with static assets

When every route is prerendered, build static output and deploy it as a
Worker that has only static assets and no script.

- **Not Cloudflare Pages.** A Pages project keeps its compatibility date and
  flags in the dashboard, separately for production and preview, and the
  repository cannot see or change them. Cloudflare directs new projects to
  Workers.
- **No script means no runtime.** Compatibility dates and flags stop
  affecting responses, and requests for static assets are free and do not
  count against Worker request limits.
- **A route that needs a server** brings back the framework's Cloudflare
  adapter and a `main` entry in `wrangler.jsonc`. Every request that matches
  no asset then runs the Worker, 404s and bot probes included.

`wrangler.jsonc` is the only Cloudflare configuration:

```jsonc
{
    "$schema": "node_modules/wrangler/config-schema.json",
    "name": "example-site",
    "compatibility_date": "2026-09-26",
    "workers_dev": true,
    "preview_urls": true,
    "routes": [
        { "pattern": "example.com", "custom_domain": true },
        { "pattern": "www.example.com", "custom_domain": true },
    ],
    "assets": {
        "directory": "./dist",
        "not_found_handling": "404-page",
    },
}
```

`/about` and `/about/` both serve `about/index.html`, which is the default
`html_handling`.

## 2. Headers

`public/_headers` applies to every static asset response, the 404 page
included. Set the security headers on `/*` and the cache policy per path.

Keep the workers.dev hosts out of search indexes:

```text
https://:worker.:account.workers.dev/*
  X-Robots-Tag: noindex
```

A host placeholder matches one DNS label (verified in wrangler's rule
matcher), so the rule needs one placeholder for the Worker or preview name and
one for the account subdomain. It covers production
(`<name>.<account>.workers.dev`) and previews
(`<alias>-<name>.<account>.workers.dev`).

`_headers` matches paths, not status codes, so the 404 page keeps the default
`Cache-Control: public, max-age=0, must-revalidate`.

## 3. CI jobs

| Job     | Runs on                                                                                                                                                | Does                                                                                                                                                                              |
| ------- | ------------------------------------------------------------------------------------------------------------------------------------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Deploy  | Push to `main`, and `workflow_dispatch` from `main` only                                                                                               | Builds, runs `wrangler deploy`, and fails unless the output contains `Current Version ID`. Uses `environment: production` with the site URL.                                      |
| Preview | Pull requests where `github.event.pull_request.head.repo.full_name == github.repository` and `github.event.pull_request.user.login != 'renovate[bot]'` | Builds, runs `wrangler versions upload --preview-alias "pr-<number>" --tag "pr-<number>"`, and comments the preview URL on the PR. Production keeps serving the deployed version. |

`wrangler versions upload` fails for a Worker that does not exist yet ("You
cannot upload a new version of a Worker that does not yet exist"), so the
first deploy from `main` must come before any preview.

`husterk/keith-huster-dot-com-site` runs both jobs.

## 4. API token and preview credentials

The deploy token needs:

| Scope                       | Permission             | Why                                                             |
| --------------------------- | ---------------------- | --------------------------------------------------------------- |
| Account                     | Workers Scripts: Edit  | Upload and deploy versions                                      |
| Account                     | Account Settings: Read | Wrangler resolves the account                                   |
| Zone (the site's zone only) | Workers Routes: Edit   | `wrangler deploy` re-applies the custom domains on every deploy |

Preview jobs use the same 1Password service account and token as the deploy
job, not a separate one. A preview upload needs Account `Workers Scripts:
Edit`, and that permission also deploys to production, so a separate preview
token would not keep a leaked credential away from production. What keeps the
token from untrusted code:

- GitHub gives fork PRs no secrets, and the preview job's fork guard skips
  them.
- The preview job skips Renovate's PRs, whose dependency updates would run
  before the token loads.
- Only the owner pushes branches. Revisit this section if anyone else gets
  push access.

The service account token is therefore a repository secret, readable from
PR branches, and the audit lists it as information. The deploy job still runs
in a `production` environment limited to `main`.

## 5. Moving a custom domain

A hostname can belong to only one Pages project or Worker, and an existing
DNS record for it blocks a Worker custom domain. To move a domain from Pages:

1. Deploy the Worker on workers.dev first, and compare it with production:
   status codes, headers and page content.
2. Remove the custom domains from the Pages project. This also removes their
   DNS records, and the site is down from here.
3. Deploy with the `routes` above. The deploy output lists each hostname as
   `(custom domain)`.
4. Delete the Pages project once the live checks pass.

Expect a few minutes of downtime between steps 2 and 3. Resolvers that query
during the gap cache the "not found" answer, so check with `dig @1.1.1.1` and
`curl --resolve` rather than the local resolver. On macOS,
`sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder` clears it.

## 6. Web Analytics

| Site                                                         | Setting                                                                   | Why                                                                        |
| ------------------------------------------------------------ | ------------------------------------------------------------------------- | -------------------------------------------------------------------------- |
| Served from a zone in this account, as a Worker or otherwise | "Enable" (automatic setup)                                                | Cloudflare injects the beacon into browser requests                        |
| Hosted elsewhere, with its DNS pointing at the provider      | "Enable with JS Snippet installation", and the snippet in the site's code | This account's zone never handles the pages, so nothing injects the beacon |

- Inferred: a site left on automatic setup ignores beacons from a manually
  installed snippet. A site recorded nothing from its snippet until it was
  switched to snippet installation.
- The CSP must allow `https://static.cloudflareinsights.com` in
  `script-src` and `https://cloudflareinsights.com` in `connect-src`.
- Cloudflare injects only into requests that look like a browser. Check with
  browser headers, or the result is a false negative:

    ```bash
    curl -s -A 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0 Safari/537.36' \
      -H 'Accept: text/html' --compressed https://example.com/ | grep -o 'data-cf-beacon=[^>]*'
    ```

- A Web Analytics site that a Pages project created can only be managed from
  that project. After the project is deleted, the dashboard offers no delete,
  but the API does: `DELETE /accounts/{account_id}/rum/site_info/{site_tag}`
  (`cf rum site-info delete <site_tag>` in Cloudflare's `cf` CLI).
