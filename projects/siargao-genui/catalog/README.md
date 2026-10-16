# Siargao catalog

This folder is the **single source of truth** for the widget catalog. The agent, the MCP server, the fixtures and the Flutter app all read from here. Do not copy component schemas anywhere else by hand: the app gets them through the generated `app/lib/catalog/catalog_schemas.g.dart`, and the agent loads `siargao_catalog.json` directly.

| File | What it is |
| --- | --- |
| `siargao_catalog.json` | The A2UI v0.9 catalog (same shape as the spec's basic catalog). catalogId `https://siargao-genui.example/catalogs/v1/catalog.json`. |
| `rules.txt` | Short rules appended to the model prompt. |
| `images.json` | The image keys components may use, with alt text. |
| `spec/v0_9/` | Vendored A2UI v0.9 `server_to_client.json` and `common_types.json` (see `SOURCE.txt`). |
| `tools/validate_fixtures.py` | Validates every fixture (JSON Schema, a2ui SDK, semantic checks). |
| `tools/gen_dart.py` | Generates the Dart schema file for the app. |
| `tests/` | pytest suite for all of the above. |

## Components

| Component | Use it for |
| --- | --- |
| `Stack` | Vertical layout. Always the root (id `root`). Groups sections with a `gap`. |
| `Heading` | Page or section header: `title`, optional `eyebrow`, `subtitle`, and a 16:9 hero `image`. |
| `ItineraryDay` | One day of a plan (`day`, `title`, timeline `items` of `{time, activity, note?}`). Also good for any timed list, like flights. |
| `CostBreakdown` | A list of `{label, amount}` lines in a `currency`. The app computes the total. |
| `StayCard` | One bookable option: `image`, `name`, `area`, `note`, `pricePerNight` (with an optional `priceUnit`, default "per night"), `rating`, and a button `action`. |
| `BudgetSlider` | Two-way budget input bound to a data model number. |
| `ChipRow` | Two-way single or multi select chips bound to a data model string array. |
| `LocalNote` | Callout for a `tip`, a `heads_up` warning, or a `local` insider note. |
| `FlexGrid` | Responsive grid of cards; columns are at least `minItemWidth` logical pixels wide. |
| `Actions` | Row of next-step buttons, each with a `style` and an event `action`. |

Every component accepts the common `id` and `accessibility` properties from the spec, plus `weight`. Text and number properties use the spec's `DynamicString` and `DynamicNumber`, so they take a literal or a `{"path": "/..."}` binding. There are no client functions.

## Setup

```sh
cd projects/siargao-genui
python3.12 -m venv catalog/.venv
catalog/.venv/bin/pip install -r catalog/requirements.txt
```

## Commands

Run from `projects/siargao-genui`:

```sh
catalog/.venv/bin/python catalog/tools/validate_fixtures.py   # validate all fixtures
catalog/.venv/bin/python catalog/tools/gen_dart.py            # regenerate the Dart schemas
catalog/.venv/bin/pytest catalog/tests                        # run the tests
catalog/.venv/bin/ruff check catalog && catalog/.venv/bin/ruff format --check catalog
```

## Adding or changing a component

1. Edit `siargao_catalog.json`. Copy an existing component: keep the `allOf` with the `ComponentCommon` and `CatalogComponentCommon` refs, `"component": {"const": "<Name>"}`, a `required` list that starts with `component`, and `"unevaluatedProperties": false`. Write a `description` on the component and on every property. The model reads them to decide what to emit.
2. Only reference the spec's common types by absolute URL (`https://a2ui.org/specification/v0_9/common_types.json#/$defs/...`). Do not add local `$defs` refs inside a component: the generated Dart maps must stand on their own.
3. Add the component to `$defs/anyComponent`.
4. If it uses images, add new keys to `images.json`.
5. Update `rules.txt` if the model needs a new rule, and `tests/test_catalog.py` (the expected component list).
6. Run `gen_dart.py`, `validate_fixtures.py` and the tests. Commit the catalog and the regenerated Dart file together.
7. The app still needs a widget builder for the new component (in `app/lib/catalog/`).
