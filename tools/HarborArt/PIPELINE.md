# Harbor Jam — sprite pipeline

**Decision: SVG in the asset catalog — CONFIRMED WORKING.** No rasterizer, no PNG fallback.

Verified 2026-08-03 on this machine (Xcode toolchain shipping iOS 26.4/26.5 simulators, deployment
target 15.6) by building Debug for `iPhone 17` and screenshotting the running app: a 300 pt
`hull_4` renders with its cyan outline, three deck cells and bow chevron intact.

Two independent proofs, both required — a green build alone proves nothing, because `actool` drops
an SVG it cannot parse with only a warning:

```
xcrun --sdk iphoneos assetutil --info "<built>.app/Assets.car" | grep -A2 hull_4
    "Name" : "hull_4",
    "Preserved Vector Representation" : true,
    "AssetType" : "Vector",
```

plus the screenshot.

## Layout

Each sprite is `Harbor Jam/Assets.xcassets/<name>.imageset/` containing `<name>.svg` and:

```json
{
  "images" : [ { "filename" : "<name>.svg", "idiom" : "universal" } ],
  "info" : { "author" : "xcode", "version" : 1 },
  "properties" : { "preserves-vector-representation" : true }
}
```

`Assets.xcassets` is a `folder.assetcatalog` reference in the pbxproj, so **adding sprites needs no
project edit** — unlike every `.swift` file in this app, which needs four.

## What the SVG may contain

Keep to `path`, `rect`, `circle`, `polygon`, `fill`, `stroke`, `stroke-width`, `rx`, and simple
`transform`. Authored at the intended point size so the natural size is right.

Not supported — these are what make `actool` drop a file:

- `<text>` (draw dynamic numbers with SwiftUI `Text` on top instead, which is what the game needs anyway)
- filters, masks, clip paths
- gradients
- external references

## Name safety

`HJSprite` is the only place a sprite name appears as a string. A `#if DEBUG` check
(`HJSprite.missing`) asserts at launch that every case resolves to a real asset, because a missing
image renders as empty space with no error at all.
