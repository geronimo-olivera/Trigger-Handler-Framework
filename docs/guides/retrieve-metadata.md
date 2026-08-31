# Retrieving metadata

`manifest/package.xml` lists the metadata types to pull from an org. Edit it to add/remove `<types>` entries as the project grows — don't leave `*` wildcards for types you don't actually need, they slow down retrieves and pull unrelated org clutter.

## Retrieve

```bash
sf project retrieve start -x manifest/package.xml -o <org-alias-or-username>
```

## Regenerate the manifest from an org

Useful when you want to see everything that currently exists in a specific org before trimming it down:

```bash
sf project generate manifest --from-org <org-alias-or-username>
```

## Reference

- [Metadata Coverage Report](https://developer.salesforce.com/docs/metadata-coverage) — confirm a type name before adding it to the manifest.
