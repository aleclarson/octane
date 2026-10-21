---
"octane": minor
"@octanejs/lynx": minor
---

Export `Children` (`toArray`/`map`) and `descriptorChildren` from `octane/universal` and `octane/universal/native`, and accept them in universal renderer modules, so shared `.tsrx` components that enumerate their children compile for universal targets. `@octanejs/lynx/main-renderer` (the one-shot first-screen runtime) now exports `Children` and `descriptorChildren` for those shared components.
