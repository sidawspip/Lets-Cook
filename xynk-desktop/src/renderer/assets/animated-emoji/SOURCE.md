Animated emoji artwork from Microsoft's Fluent Emoji Animated repository:
https://github.com/microsoft/fluentui-emoji-animated

Restored from repository checkpoint acb94eb. Eight APNG sources were previously
converted to 96px animated WebP while retaining frame animation. The accompanying
LICENSE applies. Bundled artwork: heart, fire, laugh, love, clap, surprise, cry,
thumbs. These eight animations are bundled for offline use. Other catalog animations load remotely as described below.

Windows renderer: components/ui/AnimatedEmoji.tsx. Reduced-motion preference and
failed image loads use static Unicode glyphs. Unsupported emoji remain Unicode.

Extended animation catalog restored from repository checkpoint acb94eb:
881 Noto and 2109 Fluent sequences (overlapping). Assets beyond the bundled eight
load on demand, with no-referrer; failure tries the next catalog source then a
Unicode glyph animation. Reduced motion always renders static Unicode.

Noto artwork: Google Noto Emoji, CC BY 4.0
https://googlefonts.github.io/noto-emoji-files/?view=docs
https://creativecommons.org/licenses/by/4.0/
Images: https://fonts.gstatic.com/s/e/notoemoji/latest/
Fluent artwork: Microsoft Fluent Emoji Animated, MIT (LICENSE accompanies this folder).
Additional APNG mirror: https://github.com/bignutty/fluent-emoji/tree/main/animated

Not every Unicode sequence has frame artwork. All emoji remain renderable;
unsupported sequences use glyph motion, not invented frame artwork. Skin tones,
flags, keycaps, and joined sequences are segmented with Intl.Segmenter.
