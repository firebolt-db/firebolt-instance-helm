# Documentation style

Follow this guidance when writing or editing documentation in this folder, especially MDX files. These docs are authored as Mintlify MDX and are intended for integration into the [packdb documentation site](https://docs.firebolt.io/). Style alignment with packdb is required.

## Brand and naming

- Use **"the chart"** or **"the `firebolt-instance` Helm chart"** when referring to this project. Avoid bare "the Helm chart" (ambiguous since multiple Firebolt charts exist) and any vendor-style label like "the Firebolt Helm chart".
- Use **"the Firebolt Kubernetes Operator"** when introducing the sibling project. On second mention in the same section, "the operator" is acceptable; never use bare "the operator" without first establishing which one.
- Do not use internal codenames for services or subsystems in user-facing docs. This covers the Metadata Service (use **"Metadata Service"** Title Case as a brand name) and every engine subsystem name (no Pensieve, no aragog, no shufflepuff, no storage-manager, no storage-agent, no Diagon, no Ollivanders, no Fawkes, and so on). Describe the function instead: "metadata service", "internal coordination between engine replicas", "distributed query execution". The literal codename may appear inside fenced code blocks that quote runtime output (engine error messages, config schema keys) so users can grep their logs for the exact string.
- Capitalize Firebolt Instance, Instance (when referring to Firebolt Instance) Engine, Firebolt Engine, Metadata Service, Gateway, Postgres

## Source of truth

- Component port numbers, container security contexts, label selectors, and other chart-runtime facts must match `helm/templates/` and `helm/values.yaml`. When the chart changes, update the affected docs in the same change.
- Value documentation (defaults, types, descriptions) is rendered into `helm/README.md` by `helm-docs` from the inline annotations in `helm/values.yaml`. Edit the annotations, then run `make docs`. Do not hand-edit `helm/README.md`.
- The chart's user-facing JSON Schema lives in `helm/values.schema.json` and is enforced at install and upgrade time. Document the schema's pattern constraints (for example, `postgresql.host`) where they affect user-supplied input.

## Comparisons with the Firebolt Kubernetes Operator

When a capability is present in the operator but not in the chart, do not write side-by-side comparisons in usage or reference pages. State what the chart does (or does not do), then add a brief `<Note>` callout pointing at [`operator-upgrade-path`](operator-upgrade-path) so the reader knows where the gap is filled. The dedicated `operator-upgrade-path` page is the only place a feature-comparison list belongs.

## Canonical style source

The authoritative style guide is packdb's `docs/.cursor/rules/docs-style.mdc`. The headlines:

- Google developer documentation style guide and Mintlify writing principles.
- Second person ("you"), active voice.
- Sentence case for document titles and section headings.
- Conditions before instructions.
- Strong, SEO-loaded `description` frontmatter (Mintlify search and AI bot use it).

## Frontmatter and lead sentence

Every `.mdx` in this folder has frontmatter in alphabetical order:

```mdx
---
description: <one sentence listing the functional topics the page addresses>
sidebarTitle: <short label for the sidebar>
title: <page title>
---
```

The `description` is rendered by Mintlify as the page subtitle, so it should name the functional topics the page covers (for example, "Engine and gateway Prometheus metrics endpoints, the gateway stats listener, and optional PodMonitor resources for the Prometheus Operator.") rather than repeat the page title.

The body opens with one KISS sentence stating what the page documents (for example, "This page documents the chart's Prometheus metrics surface."). Do not repeat the description in the body. Substantive context (architecture, component lists, code examples) belongs in the sections that follow.

## Tooling

- Navigation lives in `docs/docs.json`. Every page registered in `docs.json` must exist as `.mdx` on disk. Every `.mdx` on disk must be registered in `docs.json` (packdb enforces this with `make check-lost-pages`).
- When you **rename or remove** a page, add a redirect to the `docs.json` `redirects` array (old slug → new slug, leading slash, no prefix) and run `make -C docs check-lost-redirects-regenerate` to refresh `docs/known_pages.json`. packdb prefixes and propagates these redirects into the published site so old URLs keep working; skipping it fails `make docs-check`.
- Internal links use the page slug without an extension. Prefix same-folder and subfolder targets with `./` (for example, `./prerequisites`, `./usage/object-storage/amazon-s3`). Use `../` for parent-folder targets from inside `docs/usage/`. At packdb-integration time those links convert to absolute paths under the eventual subtree (for example, `/firebolt-core/firebolt-instance-helm/prerequisites`).
- Links to files outside `docs/` (`helm/README.md`, `helm/CHANGELOG.md`, `docs-internal/`) use a full `https://github.com/firebolt-db/firebolt-instance-helm/blob/main/...` URL, because Mintlify does not serve files outside `docs/`.
- `docs-internal/` is Firebolt-internal and stays as plain `.md`. Do not move anything from `docs-internal/` into `docs/` without confirming it is suitable for external readers.

## Tone and content

- Be conversational and friendly without being frivolous.
- Don't pre-announce features or roadmap items.
- Use descriptive link text. Avoid "click here".
- Write for a global audience.

## Language and grammar

- Use second person ("you"), not "we".
- Use active voice and make clear who is performing the action.
- Use standard American spelling and punctuation.
- Put conditions before instructions, not after.
- Use terms consistently throughout the docs. Do not switch between "Helm value" and "Helm parameter", between "engine pod" and "core pod", or between "PodMonitor" and "pod monitor".

## Formatting, punctuation, and organization

- Use sentence case for document titles and section headings.
- Use numbered lists for sequences.
- Use bulleted lists for most other lists.
- Use serial commas.
- Put code-related text in code font.
- Put UI elements in bold.
- Do not use em-dashes. Prefer two short sentences over one long one joined by a semicolon.
- Use periods over semicolons.
- Use block-style YAML instead of inline braces.

## Commands and code blocks

- Every command block has a one-sentence prose lead-in that says what the command does. When multiple commands are stacked, use inline `# comment` lines so each individual command is explained.
- Quote literal engine or controller error messages verbatim inside fenced code blocks. Keep the codename intact in the literal even when the surrounding prose has been scrubbed, because users will grep their pod logs for the exact string.

## Callouts

Prefer prose over callouts. When a callout is warranted, use `<Note>` (packdb's convention). Reserve callouts for non-obvious information the reader risks missing, including the operator-comparison pattern described above.

## Images

- Provide alt text for every image.
- Provide high-resolution or vector images when practical.

## Common writing mistakes

- Avoid "Duh" documentation. Don't tell users "Click Save to save."
- Avoid inconsistent terminology, such as switching between "API key" and "API token" or between "managed storage" and "object storage".
- Avoid product-centric terminology. Orient language around the reader's familiarity with Kubernetes and Helm, not around chart internals.
- Avoid colloquialisms and idioms. They hurt clarity and localization.
- Don't have spelling or grammar mistakes. They erode trust in the project.

## Mintlify writing principles

- Be concise. People read docs to achieve a goal, so cut unnecessary words.
- Choose clarity over cleverness. Be simple, direct, and avoid jargon or complex sentence structure.
- Make content skimmable with headings and short paragraphs.

## Pull-request flow into packdb

When these docs are merged into `firebolt-db/packdb`:

1. Move every `.mdx` into the agreed subtree of `docs/docs-mdx/`.
2. Convert internal links from relative slugs to absolute paths under that subtree.
3. Register every page in `docs/docs-mdx/docs.json`.
4. Run packdb's `make check-all` to validate navigation, broken links, and SQL examples.
