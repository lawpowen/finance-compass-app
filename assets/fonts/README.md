# Embedded font

Finance Compass embeds the original `MiSans/ttf/MiSans-Regular.ttf` from Xiaomi’s [MiSans download](https://hyperos.mi.com/font-download/MiSans.zip) and `MiSans TC/ttf/MisansTC-Regular.ttf` from its [Traditional Chinese download](https://hyperos.mi.com/font-download/MiSans_TC.zip). Xiaomi permits embedding with acknowledgment under the [MiSans Fonts Intellectual Property License Agreement](https://hyperos.mi.com/font/en/download/) and [embedding FAQ](https://hyperos.mi.com/font/en/faq/). The in-app acknowledgment is in About → 授权信息.

The theme prefers Traditional Chinese and Cantonese glyph forms when the device locale requests them. Otherwise the original default family takes precedence. Each family supplies missing glyphs for the other while the engine’s existing fallback and icon fonts remain available. This affects rendering only.

Keep both fonts embedded in the application. For standalone downloads, use Xiaomi’s site. `SHA256SUMS` pins the unmodified 8,122,324-byte and 4,058,948-byte TTF files. Both Web build scripts verify the bundled copies, and the service worker precaches both for offline use.
