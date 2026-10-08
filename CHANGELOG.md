# Changelog

## [0.7.0-beta.33](https://github.com/LorcanChinnock/shot/compare/v0.7.0-beta.32...v0.7.0-beta.33) (2026-10-08)


### ⚠ BREAKING CHANGES

* ship for Apple Silicon only, dropping Intel Macs ([#269](https://github.com/LorcanChinnock/shot/issues/269))

### Features

* ship for Apple Silicon only, dropping Intel Macs ([#269](https://github.com/LorcanChinnock/shot/issues/269)) ([fbb1afe](https://github.com/LorcanChinnock/shot/commit/fbb1afe30c2f05a6889ae64bcadd2549f643d89b))

## [0.7.0-beta.32](https://github.com/LorcanChinnock/shot/compare/v0.7.0-beta.31...v0.7.0-beta.32) (2026-10-08)


### Features

* **menu:** remove the camera bubble toggle from the menu bar ([#266](https://github.com/LorcanChinnock/shot/issues/266)) ([82593cd](https://github.com/LorcanChinnock/shot/commit/82593cd33d361b3c011b0c6c0c789476d56e5cbe))

## [0.7.0-beta.31](https://github.com/LorcanChinnock/shot/compare/v0.7.0-beta.30...v0.7.0-beta.31) (2026-10-08)


### Features

* **editor:** layers that respect order, pick-up reordering, timeline stacking and image import ([#257](https://github.com/LorcanChinnock/shot/issues/257)) ([3ba3f37](https://github.com/LorcanChinnock/shot/commit/3ba3f37453435dafb33c9ffff24234059546ded4))
* **editor:** let imported clips stack among annotation lanes ([#260](https://github.com/LorcanChinnock/shot/issues/260)) ([0fc142d](https://github.com/LorcanChinnock/shot/commit/0fc142df59de67955444d943282dc584b17fc414))

## [0.7.0-beta.30](https://github.com/LorcanChinnock/shot/compare/v0.7.0-beta.29...v0.7.0-beta.30) (2026-10-08)


### Features

* **design:** animate and scale the glass window backdrop ([#253](https://github.com/LorcanChinnock/shot/issues/253)) ([61770dc](https://github.com/LorcanChinnock/shot/commit/61770dc22ddbc03ac37206747276c898ba5427fa))

## [0.7.0-beta.29](https://github.com/LorcanChinnock/shot/compare/v0.7.0-beta.28...v0.7.0-beta.29) (2026-10-08)


### Features

* **editor:** layers panel for photo and video editors ([#251](https://github.com/LorcanChinnock/shot/issues/251)) ([cd936f6](https://github.com/LorcanChinnock/shot/commit/cd936f648015c50d8c02a2a50a1f064c57ab594e))

## [0.7.0-beta.28](https://github.com/LorcanChinnock/shot/compare/v0.7.0-beta.27...v0.7.0-beta.28) (2026-10-08)


### Features

* **export:** cancel a running export ([#247](https://github.com/LorcanChinnock/shot/issues/247)) ([0b3bf10](https://github.com/LorcanChinnock/shot/commit/0b3bf105ea583d641b11a418278a0e13ae5ce995))


### Bug Fixes

* **export:** stream GIF frames to disk so memory stays flat ([#245](https://github.com/LorcanChinnock/shot/issues/245)) ([eee98f1](https://github.com/LorcanChinnock/shot/commit/eee98f17c555093eda95a4ba1b0eba4fcff751e1))
* **export:** update the GIF progress toast in place, once per percent ([#241](https://github.com/LorcanChinnock/shot/issues/241)) ([ce2a32c](https://github.com/LorcanChinnock/shot/commit/ce2a32c353551c5b99de8ee5fd8b39ff3f6a7848))
* **gallery:** bound thumbnail memory and stop decoding tiles scrolled past ([#239](https://github.com/LorcanChinnock/shot/issues/239)) ([5b701c9](https://github.com/LorcanChinnock/shot/commit/5b701c9ef6ceea10b2a25dd9b732c3ce2313c2ff))
* **ui:** make the glass backdrop static so closed windows stop using CPU ([#234](https://github.com/LorcanChinnock/shot/issues/234)) ([836e99c](https://github.com/LorcanChinnock/shot/commit/836e99cabff6d6bf083a7383c15f2f680896cfc6))


### Performance Improvements

* **capture:** stop redrawing the frozen screen on every pointer move ([#243](https://github.com/LorcanChinnock/shot/issues/243)) ([b28e14e](https://github.com/LorcanChinnock/shot/commit/b28e14ee4df96085a8137e89aa6fdf5bf1af3f86))
* **editor:** cache blurs, pixelates and soft spotlights between redraws ([#235](https://github.com/LorcanChinnock/shot/issues/235)) ([38b2c26](https://github.com/LorcanChinnock/shot/commit/38b2c26b8d85b12c1a268a1fcc5bf83289ba9ad8))
* **editor:** flatten and encode Save and Copy off the main thread ([#246](https://github.com/LorcanChinnock/shot/issues/246)) ([48c1162](https://github.com/LorcanChinnock/shot/commit/48c1162848de3a8655b97c5003ee29914362fdda))
* **editor:** skip padding re-layout when there's nothing to shrink ([#248](https://github.com/LorcanChinnock/shot/issues/248)) ([724fa62](https://github.com/LorcanChinnock/shot/commit/724fa622aa928a75811cd4c818a86cffd37a0cdd))
* **gallery:** group by date without per-item formatters and skip unchanged reloads ([#236](https://github.com/LorcanChinnock/shot/issues/236)) ([691da06](https://github.com/LorcanChinnock/shot/commit/691da068a94cc0db0211a17f2ec3b582b77665d3))
* **quick-access:** keep a 480 px thumbnail per card instead of the full capture ([#242](https://github.com/LorcanChinnock/shot/issues/242)) ([44b2700](https://github.com/LorcanChinnock/shot/commit/44b2700ac7b190c8dc04204330292f653fec1351))
* **shortcuts:** don't block launch waiting on activateSettings ([#244](https://github.com/LorcanChinnock/shot/issues/244)) ([27f7ebf](https://github.com/LorcanChinnock/shot/commit/27f7ebf1f8dec97c3121f820a76580adf0e917c4))
* **video-editor:** debounce and cache timeline thumbnails ([#240](https://github.com/LorcanChinnock/shot/issues/240)) ([9ab6187](https://github.com/LorcanChinnock/shot/commit/9ab6187fa218acc266b385d8217a6236c4464b18))
* **video-editor:** only the playhead redraws during playback ([#237](https://github.com/LorcanChinnock/shot/issues/237)) ([1d03ed8](https://github.com/LorcanChinnock/shot/commit/1d03ed873a63370a9d020f96c7ed74cd1769c38e))
* **video-editor:** reuse annotation overlays that don't change between frames ([#238](https://github.com/LorcanChinnock/shot/issues/238)) ([a3d6be3](https://github.com/LorcanChinnock/shot/commit/a3d6be3f493a1c8e9512c41f6627fd8ef3d90bdd))

## [0.7.0-beta.27](https://github.com/LorcanChinnock/shot/compare/v0.7.0-beta.26...v0.7.0-beta.27) (2026-10-08)


### Bug Fixes

* **capture:** ratio-locked area selection tracks the pointer ([#215](https://github.com/LorcanChinnock/shot/issues/215)) ([2ede877](https://github.com/LorcanChinnock/shot/commit/2ede877570eca4f2941ebd6b025b9d45c2a6a72b))

## [0.7.0-beta.26](https://github.com/LorcanChinnock/shot/compare/v0.7.0-beta.25...v0.7.0-beta.26) (2026-10-08)


### Features

* **capture:** aspect ratio presets for area selection ([#213](https://github.com/LorcanChinnock/shot/issues/213)) ([afede72](https://github.com/LorcanChinnock/shot/commit/afede72073fb1293498f1828532e8b3d9bbed187))

## [0.7.0-beta.25](https://github.com/LorcanChinnock/shot/compare/v0.7.0-beta.24...v0.7.0-beta.25) (2026-10-07)


### Features

* **editor:** change the recording's own sound volume and keyframes ([#207](https://github.com/LorcanChinnock/shot/issues/207)) ([cfe9a8b](https://github.com/LorcanChinnock/shot/commit/cfe9a8bf32b4d6cfa2f3a53d951471f631057fc3))
* **recording:** magnifier in the record area overlay ([#202](https://github.com/LorcanChinnock/shot/issues/202)) ([4802b09](https://github.com/LorcanChinnock/shot/commit/4802b09e04fc97f9e2990c6d8e8ef6951d512896))
* **recording:** Record Window records the window itself ([#204](https://github.com/LorcanChinnock/shot/issues/204)) ([e96270e](https://github.com/LorcanChinnock/shot/commit/e96270e569e34e60656cbd936eb75897fbe444c2))
* **video:** lock, hide and mute buttons on track lanes ([#206](https://github.com/LorcanChinnock/shot/issues/206)) ([f6697e8](https://github.com/LorcanChinnock/shot/commit/f6697e8ad0f75cecd3c6a9addd9eac602c810efb))


### Bug Fixes

* **editor:** canvas handles and Inspector SCALE slider share one scale range ([#199](https://github.com/LorcanChinnock/shot/issues/199)) ([98d50ec](https://github.com/LorcanChinnock/shot/commit/98d50ec4edd4076219c3a49866ed714a956d1d36))
* **editor:** paste and duplicate keep fill, bend, alignment and corner radius ([#201](https://github.com/LorcanChinnock/shot/issues/201)) ([0694fd9](https://github.com/LorcanChinnock/shot/commit/0694fd90cb9744bce084cb41790b973610f9bda6))
* **recording:** follow Save to folder and Show Quick Access ([#209](https://github.com/LorcanChinnock/shot/issues/209)) ([66de74e](https://github.com/LorcanChinnock/shot/commit/66de74ee5308a083d5b86603fda3d101664b2cc4))
* **recording:** keep the camera bubble inside the recorded region ([#203](https://github.com/LorcanChinnock/shot/issues/203)) ([e9e8691](https://github.com/LorcanChinnock/shot/commit/e9e8691f427cdb26e453025c8fd266bb3cf0cfae))
* **recording:** mute silences only the microphone, not system audio ([#208](https://github.com/LorcanChinnock/shot/issues/208)) ([a70520a](https://github.com/LorcanChinnock/shot/commit/a70520adca124d221d72ad0ddca042c22297ac4b))
* **recording:** setup toggles apply to this recording only ([#211](https://github.com/LorcanChinnock/shot/issues/211)) ([30413f8](https://github.com/LorcanChinnock/shot/commit/30413f82d6f0dc18b28822eb79459f42da00099c))
* **recording:** toast when the area is too small for the camera bubble ([#200](https://github.com/LorcanChinnock/shot/issues/200)) ([3d2d6d9](https://github.com/LorcanChinnock/shot/commit/3d2d6d9bf2d6c07884019f87ef5a13cffc0aacda))
* **recording:** undo window before a discarded recording is deleted ([#205](https://github.com/LorcanChinnock/shot/issues/205)) ([178a6c9](https://github.com/LorcanChinnock/shot/commit/178a6c971b0242316f699e37f65056f532732406))

## [0.7.0-beta.24](https://github.com/LorcanChinnock/shot/compare/v0.7.0-beta.23...v0.7.0-beta.24) (2026-10-07)


### Features

* **design:** custom brutal-styled dropdown to replace system menus ([#182](https://github.com/LorcanChinnock/shot/issues/182)) ([42ce4eb](https://github.com/LorcanChinnock/shot/commit/42ce4eba9f09af2b3113b55d2fc84ba2b6c15721))
* **design:** longer tooltip delay with warm-up ([#178](https://github.com/LorcanChinnock/shot/issues/178)) ([af7c929](https://github.com/LorcanChinnock/shot/commit/af7c9297c24361e931f4bac3d2ca0ec80744a238))
* **editor:** amount slider for blur and pixelate ([#185](https://github.com/LorcanChinnock/shot/issues/185)) ([559981d](https://github.com/LorcanChinnock/shot/commit/559981db71c19208dbb943a8a87fc7bb17c3f730))
* **editor:** corner-radius handles on rounded rectangles ([#175](https://github.com/LorcanChinnock/shot/issues/175)) ([d359038](https://github.com/LorcanChinnock/shot/commit/d35903802ba550331068041858c01fd18334d7e5))
* **editor:** hand tool (H) for panning, and middle-click drag to pan ([#177](https://github.com/LorcanChinnock/shot/issues/177)) ([183528c](https://github.com/LorcanChinnock/shot/commit/183528c071b2522d3f364dee5827901d87437d79))
* **editor:** highlighter becomes a freehand marker with colour and size (M) ([#183](https://github.com/LorcanChinnock/shot/issues/183)) ([e609e23](https://github.com/LorcanChinnock/shot/commit/e609e23170f1c29072c33b1ff59daf51f05fa2db))
* **editor:** one custom colour swatch per slot, drop recent colours ([#180](https://github.com/LorcanChinnock/shot/issues/180)) ([9b03fae](https://github.com/LorcanChinnock/shot/commit/9b03fae41fc087fc895c843f051710dbb9874e23))
* **editor:** optional soft edge for spotlights ([#184](https://github.com/LorcanChinnock/shot/issues/184)) ([e4edc54](https://github.com/LorcanChinnock/shot/commit/e4edc543e8ba1d8b37879ddf902011d7be9c33d3))
* **editor:** spotlight strength as a slider instead of three presets ([#179](https://github.com/LorcanChinnock/shot/issues/179)) ([05317fd](https://github.com/LorcanChinnock/shot/commit/05317fd38f0b5abb253129b8a6bcb15441355a37))
* **editor:** text alignment for text and sticky notes ([#176](https://github.com/LorcanChinnock/shot/issues/176)) ([8d3e2de](https://github.com/LorcanChinnock/shot/commit/8d3e2de87dd3f63ace2e038374d79f652b4348fc))
* **settings:** hidden party mode easter egg ([#181](https://github.com/LorcanChinnock/shot/issues/181)) ([2e42037](https://github.com/LorcanChinnock/shot/commit/2e4203723c609692305e06fbc74c830534f9e6c0))

## [0.7.0-beta.23](https://github.com/LorcanChinnock/shot/compare/v0.7.0-beta.22...v0.7.0-beta.23) (2026-10-07)


### Features

* **editor:** keep the annotation just drawn selected so the toolbar can fix it ([#159](https://github.com/LorcanChinnock/shot/issues/159)) ([a9928e3](https://github.com/LorcanChinnock/shot/commit/a9928e38cfc48637c0202595963f2e2406474741))


### Bug Fixes

* **editor:** clicking the canvas while typing text only commits it ([#162](https://github.com/LorcanChinnock/shot/issues/162)) ([06d3767](https://github.com/LorcanChinnock/shot/commit/06d3767b0d24031d2f70ada0a24e618803a405ad))

## [0.7.0-beta.22](https://github.com/LorcanChinnock/shot/compare/v0.7.0-beta.21...v0.7.0-beta.22) (2026-10-07)


### Features

* **recording:** show recording controls in the notch and add an exclude menu bar setting ([#156](https://github.com/LorcanChinnock/shot/issues/156)) ([ceb3005](https://github.com/LorcanChinnock/shot/commit/ceb3005fdc8e053b4e132f555a2b414fa554066b))

## [0.7.0-beta.21](https://github.com/LorcanChinnock/shot/compare/v0.7.0-beta.20...v0.7.0-beta.21) (2026-10-07)


### Features

* **gallery:** add selection checkboxes and select/deselect all ([#154](https://github.com/LorcanChinnock/shot/issues/154)) ([c86b69c](https://github.com/LorcanChinnock/shot/commit/c86b69c50b39bf4522661879f7267a4e504f28cb))

## [0.7.0-beta.20](https://github.com/LorcanChinnock/shot/compare/v0.7.0-beta.19...v0.7.0-beta.20) (2026-10-07)


### Features

* **app:** show the gallery as a section of one main window ([#146](https://github.com/LorcanChinnock/shot/issues/146)) ([151f989](https://github.com/LorcanChinnock/shot/commit/151f989b80e8e2697ce5b31035b895dd0aed8721))

## [0.7.0-beta.19](https://github.com/LorcanChinnock/shot/compare/v0.7.0-beta.18...v0.7.0-beta.19) (2026-10-07)


### Features

* **editor:** shape and redact tools with options, spotlight styles, bendable lines, live text size ([#144](https://github.com/LorcanChinnock/shot/issues/144)) ([8a63b0e](https://github.com/LorcanChinnock/shot/commit/8a63b0e72610f1b0469041f5efd020e9a7ca8203))

## [0.7.0-beta.18](https://github.com/LorcanChinnock/shot/compare/v0.7.0-beta.17...v0.7.0-beta.18) (2026-10-07)


### Features

* **editor:** show tool options in context, explain tools on hover, remove auto-redact ([#142](https://github.com/LorcanChinnock/shot/issues/142)) ([54bc6aa](https://github.com/LorcanChinnock/shot/commit/54bc6aaccee6066a7fb8aa33c95f062dbc17c662))

## [0.7.0-beta.17](https://github.com/LorcanChinnock/shot/compare/v0.7.0-beta.16...v0.7.0-beta.17) (2026-10-07)


### Bug Fixes

* **ui:** drop hard shadows and thin outlines on image and video previews ([#140](https://github.com/LorcanChinnock/shot/issues/140)) ([1ecbd62](https://github.com/LorcanChinnock/shot/commit/1ecbd62c94ebccd56ea801cc636639cb78ca264c))

## [0.7.0-beta.16](https://github.com/LorcanChinnock/shot/compare/v0.7.0-beta.15...v0.7.0-beta.16) (2026-10-07)


### Bug Fixes

* **ui:** convert zoom to CGFloat explicitly so CI's Xcode compiles TracksView ([#138](https://github.com/LorcanChinnock/shot/issues/138)) ([32c8c99](https://github.com/LorcanChinnock/shot/commit/32c8c99519c45d2d6636775a6ff5e35ce9d72ed2))

## [0.7.0-beta.15](https://github.com/LorcanChinnock/shot/compare/v0.7.0-beta.14...v0.7.0-beta.15) (2026-10-07)


### Bug Fixes

* **ui:** hide the clip inspector by default and fill its empty state ([#135](https://github.com/LorcanChinnock/shot/issues/135)) ([114113a](https://github.com/LorcanChinnock/shot/commit/114113a78f3b1bf1011c78c06899a99919db3197))
* **ui:** keep trim handles under the pointer and show trimmed footage greyed ([#137](https://github.com/LorcanChinnock/shot/issues/137)) ([f62ed9d](https://github.com/LorcanChinnock/shot/commit/f62ed9d56d8a928a3cbdf3c2828af8c885deefe4))

## [0.7.0-beta.14](https://github.com/LorcanChinnock/shot/compare/v0.7.0-beta.13...v0.7.0-beta.14) (2026-10-07)


### Bug Fixes

* **ui:** host SwiftUI below each panel's content view to stop the layout crash after capture ([#133](https://github.com/LorcanChinnock/shot/issues/133)) ([a4e0fae](https://github.com/LorcanChinnock/shot/commit/a4e0faee11ef533c5576a94f0acac35bd285db50))

## [0.7.0-beta.13](https://github.com/LorcanChinnock/shot/compare/v0.7.0-beta.12...v0.7.0-beta.13) (2026-10-07)


### Bug Fixes

* **ui:** stop SwiftUI managing window size limits to avoid layout crash after capture ([#127](https://github.com/LorcanChinnock/shot/issues/127)) ([88befe8](https://github.com/LorcanChinnock/shot/commit/88befe8a2ee3b669d32c1a18894f026b27d9d61c))

## [0.7.0-beta.12](https://github.com/LorcanChinnock/shot/compare/v0.7.0-beta.11...v0.7.0-beta.12) (2026-10-07)


### Bug Fixes

* UX/QA sweep findings ([#110](https://github.com/LorcanChinnock/shot/issues/110)-[#121](https://github.com/LorcanChinnock/shot/issues/121), [#123](https://github.com/LorcanChinnock/shot/issues/123)) ([#125](https://github.com/LorcanChinnock/shot/issues/125)) ([916c1fe](https://github.com/LorcanChinnock/shot/commit/916c1fed879fdacf6abf28a113d12a939c45ab9e))

## [0.7.0-beta.11](https://github.com/LorcanChinnock/shot/compare/v0.7.0-beta.10...v0.7.0-beta.11) (2026-10-06)


### Bug Fixes

* **editor:** align the play button, keep the preview usable on short screens, fix GIF timing; add ux-qa skill ([#107](https://github.com/LorcanChinnock/shot/issues/107)) ([9f32268](https://github.com/LorcanChinnock/shot/commit/9f322683d07066b69db810980709753aa92d0ff1))

## [0.7.0-beta.10](https://github.com/LorcanChinnock/shot/compare/v0.7.0-beta.9...v0.7.0-beta.10) (2026-10-06)


### Bug Fixes

* **ui:** honour system double-click title bar action on glass windows ([#105](https://github.com/LorcanChinnock/shot/issues/105)) ([1255f53](https://github.com/LorcanChinnock/shot/commit/1255f53d26ee1c6c84f2a0c17e4b0913b238c078))

## [0.7.0-beta.9](https://github.com/LorcanChinnock/shot/compare/v0.7.0-beta.8...v0.7.0-beta.9) (2026-10-06)


### Features

* **editor:** multi-track video timeline with imports, annotations and keyframes ([#103](https://github.com/LorcanChinnock/shot/issues/103)) ([67fc9dd](https://github.com/LorcanChinnock/shot/commit/67fc9dd5948ba50df6729c8be1a862688c7e84ae))

## [0.7.0-beta.8](https://github.com/LorcanChinnock/shot/compare/v0.7.0-beta.7...v0.7.0-beta.8) (2026-10-06)


### Features

* **gallery:** browse, search and edit every capture in one window ([#102](https://github.com/LorcanChinnock/shot/issues/102)) ([9ecf97e](https://github.com/LorcanChinnock/shot/commit/9ecf97e50cf802960be1afe29ff7466c582cfb15))


### Bug Fixes

* **ui:** only the title strip drags glass windows ([#99](https://github.com/LorcanChinnock/shot/issues/99)) ([21c67c2](https://github.com/LorcanChinnock/shot/commit/21c67c27e5dc16601ced4bfa9b8a2f83cd9254a9))

## [0.7.0-beta.7](https://github.com/LorcanChinnock/shot/compare/v0.7.0-beta.6...v0.7.0-beta.7) (2026-10-06)


### Features

* **editor:** live canvas, standard zoom and drawing modifiers ([#96](https://github.com/LorcanChinnock/shot/issues/96)) ([55151e1](https://github.com/LorcanChinnock/shot/commit/55151e183422a203977ee015355ae2d01840b932))

## [0.7.0-beta.6](https://github.com/LorcanChinnock/shot/compare/v0.7.0-beta.5...v0.7.0-beta.6) (2026-10-06)


### Features

* **ui:** animate quick access in and out, drift the backdrop colours ([#93](https://github.com/LorcanChinnock/shot/issues/93)) ([88bf138](https://github.com/LorcanChinnock/shot/commit/88bf138e7fb910c802093edd99bd53c15db9d891))


### Bug Fixes

* **ui:** use circular corners so borders have no stray steps ([#92](https://github.com/LorcanChinnock/shot/issues/92)) ([16add21](https://github.com/LorcanChinnock/shot/commit/16add21cc66026ad83713b191d936b44cb694e8e))

## [0.7.0-beta.5](https://github.com/LorcanChinnock/shot/compare/v0.7.0-beta.4...v0.7.0-beta.5) (2026-10-06)


### Features

* **editor:** drag an arrow's midpoint to bend it ([#90](https://github.com/LorcanChinnock/shot/issues/90)) ([c9fa6eb](https://github.com/LorcanChinnock/shot/commit/c9fa6ebe53331f82e16029eb59e4545dd2519b0b))
* **editor:** live note colour, canvas retracts, standard zoom and drawing modifiers ([#88](https://github.com/LorcanChinnock/shot/issues/88)) ([42144b4](https://github.com/LorcanChinnock/shot/commit/42144b4b7df576b2f7f840e161d05c77cd47a5c9))

## [0.7.0-beta.4](https://github.com/LorcanChinnock/shot/compare/v0.7.0-beta.3...v0.7.0-beta.4) (2026-10-06)


### Bug Fixes

* **quick-access:** letterbox extreme-aspect thumbnails instead of zooming ([#86](https://github.com/LorcanChinnock/shot/issues/86)) ([7ab9c90](https://github.com/LorcanChinnock/shot/commit/7ab9c90388e61d9f38a6ec83d5635eade06a6934))

## [0.7.0-beta.3](https://github.com/LorcanChinnock/shot/compare/v0.7.0-beta.2...v0.7.0-beta.3) (2026-10-06)


### Bug Fixes

* mark each published release as latest ([#84](https://github.com/LorcanChinnock/shot/issues/84)) ([9a325fd](https://github.com/LorcanChinnock/shot/commit/9a325fd36b73fe3890fd4b455d70decbec17edaa))

## [0.7.0-beta.2](https://github.com/LorcanChinnock/shot/compare/v0.7.0-beta.1...v0.7.0-beta.2) (2026-10-06)


### Bug Fixes

* drop release-as now that 0.7.0-beta.1 is out ([#81](https://github.com/LorcanChinnock/shot/issues/81)) ([1026d79](https://github.com/LorcanChinnock/shot/commit/1026d79b60aed05155102abcbf9023c8e16a302a))
* keep the beta suffix when release-please bumps the version ([#83](https://github.com/LorcanChinnock/shot/issues/83)) ([1ad398d](https://github.com/LorcanChinnock/shot/commit/1ad398d9b6b9e733f5b0a142fd803c95e9b51dc9))

## [0.7.0-beta.1](https://github.com/LorcanChinnock/shot/compare/v0.6.3...v0.7.0-beta.1) (2026-10-06)


### Features

* tag the app, README and releases as beta ([#78](https://github.com/LorcanChinnock/shot/issues/78)) ([36c0587](https://github.com/LorcanChinnock/shot/commit/36c05878c990c5ba0b1ac63540ed890567d31132))


### Bug Fixes

* start the beta series at 0.7.0-beta.1 ([#80](https://github.com/LorcanChinnock/shot/issues/80)) ([d3c8645](https://github.com/LorcanChinnock/shot/commit/d3c8645b1128aac364805439483b47f5d3bee24e))

## [0.6.3](https://github.com/LorcanChinnock/shot/compare/v0.6.2...v0.6.3) (2026-10-06)


### Bug Fixes

* **ui:** keep the glass fill off the border's outer edge ([#76](https://github.com/LorcanChinnock/shot/issues/76)) ([b0bfd7f](https://github.com/LorcanChinnock/shot/commit/b0bfd7f6afdc9a4b3331b3160cf27f0881a0b8f2))

## [0.6.2](https://github.com/LorcanChinnock/shot/compare/v0.6.1...v0.6.2) (2026-10-06)


### Bug Fixes

* **editor:** in-app custom colour picker, no shadow seam ([#74](https://github.com/LorcanChinnock/shot/issues/74)) ([bc30b94](https://github.com/LorcanChinnock/shot/commit/bc30b944791b7d7cc067a5b02a012b2e21e23e20))

## [0.6.1](https://github.com/LorcanChinnock/shot/compare/v0.6.0...v0.6.1) (2026-10-06)


### Bug Fixes

* repair the editor build and tests broken on main by [#69](https://github.com/LorcanChinnock/shot/issues/69) ([#72](https://github.com/LorcanChinnock/shot/issues/72)) ([13e172a](https://github.com/LorcanChinnock/shot/commit/13e172a950899487183a19a92426e3536ece95c8))
* **ui:** sweep the hard shadow so its corners join the border ([#71](https://github.com/LorcanChinnock/shot/issues/71)) ([067ef57](https://github.com/LorcanChinnock/shot/commit/067ef5791832b06905c0cc73cc7289347261806b))

## [0.6.0](https://github.com/LorcanChinnock/shot/compare/v0.5.3...v0.6.0) (2026-10-06)


### Features

* **editor:** fill rectangles and ellipses, custom colours with recents ([#69](https://github.com/LorcanChinnock/shot/issues/69)) ([fd06635](https://github.com/LorcanChinnock/shot/commit/fd06635e13c6b63d269e37459db66c304788b09d))

## [0.5.3](https://github.com/LorcanChinnock/shot/compare/v0.5.2...v0.5.3) (2026-10-06)


### Bug Fixes

* **editor:** include text being typed in copy/save; save as new versions ([#67](https://github.com/LorcanChinnock/shot/issues/67)) ([225a61d](https://github.com/LorcanChinnock/shot/commit/225a61da19d0f91e6de62f7c5613b82bc5c59dc2))

## [0.5.2](https://github.com/LorcanChinnock/shot/compare/v0.5.1...v0.5.2) (2026-10-06)


### Bug Fixes

* **ui:** clean up window border, card shadows and sidebar icons ([#65](https://github.com/LorcanChinnock/shot/issues/65)) ([c8872ed](https://github.com/LorcanChinnock/shot/commit/c8872edcceeb5decd014bbaa50eb981f0edf5129))

## [0.5.1](https://github.com/LorcanChinnock/shot/compare/v0.5.0...v0.5.1) (2026-10-05)


### Bug Fixes

* **release:** keep the release a draft until its assets are attached ([#63](https://github.com/LorcanChinnock/shot/issues/63)) ([b748cfe](https://github.com/LorcanChinnock/shot/commit/b748cfe5ae7689d8afa52d50759a7eb0313b80bd))

## [0.5.0](https://github.com/LorcanChinnock/shot/compare/v0.4.0...v0.5.0) (2026-10-05)


### Features

* **recording:** copy recordings to the clipboard ([#62](https://github.com/LorcanChinnock/shot/issues/62)) ([49d83ee](https://github.com/LorcanChinnock/shot/commit/49d83ee5adbb30ec4979870ab410760f8f4e8341))
* **recording:** mic meter, mute, and mic/camera pickers with previews ([#60](https://github.com/LorcanChinnock/shot/issues/60)) ([0eb7776](https://github.com/LorcanChinnock/shot/commit/0eb7776c97b26f2455f88e3642aa1c1e60bf0823))

## [0.4.0](https://github.com/LorcanChinnock/shot/compare/v0.3.0...v0.4.0) (2026-10-05)


### Features

* **icon:** redraw the app icon in the modern macOS style ([#54](https://github.com/LorcanChinnock/shot/issues/54)) ([a945601](https://github.com/LorcanChinnock/shot/commit/a945601f51663b9cc24b8ffb795b0de6b87cdc0f))


### Bug Fixes

* **hotkeys:** give the macOS screenshot keys back when Shot quits ([#50](https://github.com/LorcanChinnock/shot/issues/50)) ([b6bf679](https://github.com/LorcanChinnock/shot/commit/b6bf6791ff171f1c14421d155d61f04965234608))

## [0.3.0](https://github.com/LorcanChinnock/shot/compare/v0.2.0...v0.3.0) (2026-10-04)


### Features

* **app:** show Shot in the Dock and ⌘-Tab while a window is open ([#29](https://github.com/LorcanChinnock/shot/issues/29)) ([b2a489e](https://github.com/LorcanChinnock/shot/commit/b2a489e75f74b6884e9be7069de4c4033318ace3))
* **app:** show Shot in the Dock and ⌘-Tab while a window is open ([#31](https://github.com/LorcanChinnock/shot/issues/31)) ([83dee13](https://github.com/LorcanChinnock/shot/commit/83dee132e8c0a3ed410f2007912f46dc01429c7a))
* **editor:** add a blur tool and auto-redact ([#39](https://github.com/LorcanChinnock/shot/issues/39)) ([0c4f2ef](https://github.com/LorcanChinnock/shot/commit/0c4f2efadc61766ebb5b39f2784a3148b75b7bba))
* **editor:** add a freehand pen tool ([#42](https://github.com/LorcanChinnock/shot/issues/42)) ([4aed772](https://github.com/LorcanChinnock/shot/commit/4aed772cc70bb82d1aea01573199cf00c195580c))
* **editor:** add a spotlight tool ([#41](https://github.com/LorcanChinnock/shot/issues/41)) ([599cae3](https://github.com/LorcanChinnock/shot/commit/599cae34979c878f32ada9eb81a6c4240a6be01c))
* **editor:** add sticky notes ([#35](https://github.com/LorcanChinnock/shot/issues/35)) ([cd6d4aa](https://github.com/LorcanChinnock/shot/commit/cd6d4aa2268e800e9c0df3023875ea9c894e813f))
* **editor:** combine images on one canvas ([#46](https://github.com/LorcanChinnock/shot/issues/46)) ([33ab823](https://github.com/LorcanChinnock/shot/commit/33ab8231d0daeebfadf91caeb385987c84adad58))
* **editor:** copy, paste, duplicate and nudge annotations ([#40](https://github.com/LorcanChinnock/shot/issues/40)) ([4dd7a97](https://github.com/LorcanChinnock/shot/commit/4dd7a97e35248a040adde026752a9b203f1fe3c1))
* **editor:** let annotations extend beyond the screenshot ([#33](https://github.com/LorcanChinnock/shot/issues/33)) ([8cf6c2b](https://github.com/LorcanChinnock/shot/commit/8cf6c2b73c87b528f4f40a5e2edf95f70fcc6a7c))
* **editor:** remember the last tool, colour and width ([#44](https://github.com/LorcanChinnock/shot/issues/44)) ([ae15ee8](https://github.com/LorcanChinnock/shot/commit/ae15ee8070e2b973b12024c7eb78c58ef092c552))
* **editor:** resize, recolour and re-edit placed annotations ([#37](https://github.com/LorcanChinnock/shot/issues/37)) ([6ff9960](https://github.com/LorcanChinnock/shot/commit/6ff9960608cac5de9c209ea7c53d7d9c7ae5231c))
* **editor:** zoom and pan the canvas ([#43](https://github.com/LorcanChinnock/shot/issues/43)) ([d9aaa50](https://github.com/LorcanChinnock/shot/commit/d9aaa505c2dbc317be93d79e5e7052eed0f11c10))
* **hotkeys:** take over the macOS screenshot keys by default ([#11](https://github.com/LorcanChinnock/shot/issues/11)) ([d126f94](https://github.com/LorcanChinnock/shot/commit/d126f940a83a9485129d5dbcbfb8376d1b23749f))
* **video:** cut sections out of a recording ([#38](https://github.com/LorcanChinnock/shot/issues/38)) ([ae23269](https://github.com/LorcanChinnock/shot/commit/ae232692837d528b701e4df3d317ec81ee9f97dc))
* **video:** export options for MP4 and GIF ([#36](https://github.com/LorcanChinnock/shot/issues/36)) ([1f55e10](https://github.com/LorcanChinnock/shot/commit/1f55e10e6ceb6318d1fe2f2f76bbbd429872e5c5))
* **video:** trim recordings in a video editor ([#34](https://github.com/LorcanChinnock/shot/issues/34)) ([1cb8a90](https://github.com/LorcanChinnock/shot/commit/1cb8a902e0c3f25bb2747e32358d8894683cbe9e))


### Bug Fixes

* **app:** close any Shot window with ⌘W ([#45](https://github.com/LorcanChinnock/shot/issues/45)) ([7a27bcd](https://github.com/LorcanChinnock/shot/commit/7a27bcd0f46de0d5e21d7f0d3d2d509c18f40b08))
* **quick-access:** slide cards in from the right in the bottom-right corner ([#28](https://github.com/LorcanChinnock/shot/issues/28)) ([fcdc8ef](https://github.com/LorcanChinnock/shot/commit/fcdc8efa898002adc89e91ea4b3d5078e53d58f0))
* **settings:** show the GIF settings Quick Access actually uses ([#48](https://github.com/LorcanChinnock/shot/issues/48)) ([2d8e097](https://github.com/LorcanChinnock/shot/commit/2d8e09759d5fa3cf082fdce79d43a3e2a6acffe6))

## [0.2.0](https://github.com/LorcanChinnock/shot/compare/v0.1.0...v0.2.0) (2026-10-04)


### Features

* **update:** update Shot automatically with Sparkle ([#9](https://github.com/LorcanChinnock/shot/issues/9)) ([22e7d29](https://github.com/LorcanChinnock/shot/commit/22e7d297c1b8bd97153e946d41df3b23c85e14d9))


### Bug Fixes

* **build:** ship a universal binary that runs on Intel Macs ([#4](https://github.com/LorcanChinnock/shot/issues/4)) ([7fe227d](https://github.com/LorcanChinnock/shot/commit/7fe227d9b21d57a084947cb48ba30c40cea44a6e))
* **capture:** move text capture off the number row and label its overlay ([#8](https://github.com/LorcanChinnock/shot/issues/8)) ([3554d87](https://github.com/LorcanChinnock/shot/commit/3554d87bac2fa0bef9eee6160c01fc353e17bb00))
* **quick-access:** close stacked cards after hover instead of pausing forever ([#7](https://github.com/LorcanChinnock/shot/issues/7)) ([359d1f8](https://github.com/LorcanChinnock/shot/commit/359d1f86bb4d40fa25b16d4c2f4b42908baefb3e))

## 0.1.0 (2026-10-03)

First public release.
