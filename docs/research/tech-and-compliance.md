# AI Photo App (SwiftUI, iOS 17+) — Technical & Compliance Research

Research date: **2026-10-11**. Scope: (a) text-to-image, (b) prompt-based photo editing, (c) enhance / upscale / face restoration, (d) background removal, (e) brush-mask object removal, (f) one-tap style templates.

## How to read this report

Every non-trivial claim carries a confidence tag:

- **[V] Verified.** Checked during this research against a primary or official source: vendor code or docs, Apple developer docs/JSON, the App Review Guidelines page, EUR-Lex, a state legislature, or govinfo. The URL is given.
- **[R] Reported.** Found through web search in secondary coverage, or in a vendor page snippet, but not opened directly. Confirm before you commit money.
- **[U] Unverified.** Prior knowledge or my own estimate. Treat it as a placeholder.

Limits of this research:
- Direct fetches to fal.ai, ai.google.dev, OpenAI, BFL, Replicate, Supabase, Cloudflare and Vercel sites were blocked. To get official material I used:
  - the **official fal JS client package** (`@fal-ai/client` 1.11.0-alpha.5, published 2026-10-06). Its `src/types/endpoints.d.ts` is generated from fal's endpoint OpenAPI schemas and lists **1,486 endpoints** with exact input and output types.
  - the official GitHub doc sources for Supabase, Cloudflare and OpenAI (`openai/openai-openapi`), plus Google `python-genai`, `contentauth/c2pa-*` and Apple's `app-store-server-library-node`.
  - Apple's documentation JSON and developer-news RSS.
  - the Legal Data Hunter database for EU and US statutes.
- **The web-search quota ran out partway through.** These items are therefore marked [U]: RevenueCat's current pricing, Vercel's maxDuration, the per-image prices of fal "utility" endpoints (BiRefNet, ESRGAN, CodeFormer, erasers), BFL's direct-API shape, and most latency figures. Check them on the vendor pages before launch.

---

## 0. TL;DR — recommended MVP stack

| Layer | Recommendation | Why |
|---|---|---|
| Primary model aggregator | **fal.ai, queue API with webhooks** | Widest catalogue: Google Nano Banana family; OpenAI GPT Image 2/2.5 (fal was reported as an official GPT Image 2 launch partner [R]); FLUX.2; Seedream 5; Qwen; Ideogram v4; Recraft v4; Bria; Topaz; Clarity; plus utility models. One durable queue with automatic retries, Ed25519-signed webhooks, and per-request storage lifecycle and "don't store I/O" controls. [V]/[R] |
| (a) Text→image | `fal-ai/nano-banana-2`. Cheap previews: `google/nano-banana-2-lite`. Premium: `openai/gpt-image-2.5/flare/text-to-image` or `fal-ai/nano-banana-pro` | Best price/quality. GPT Image 2.5 leads the current leaderboards [R]. |
| (b) Prompt edit | `fal-ai/nano-banana-2/edit`. A/B for identity-critical edits ("put me in a suit"): `bytedance/seedream/v5/pro/edit`. Precision/mask: `openai/gpt-image-2.5/sunburst/edit` | Seedream 5.0 Pro ranks #1 for identity-preserving edits on Artificial Analysis [R]. |
| (c) Enhance | On device: Core Image auto-adjust, plus VideoToolbox super-resolution on iOS 26+. Server: `fal-ai/seedvr/upscale/image`, `fal-ai/codeformer` for faces, `fal-ai/esrgan` for cheap upscales | On-device costs nothing. Use a generative upscaler only when needed. |
| (d) Background removal | **On device:** Vision `VNGenerateForegroundInstanceMaskRequest`. Server fallback: `fal-ai/birefnet/v2` or `fal-ai/bria/background/remove` | Free, private and instant for most subjects. |
| (e) Object removal | `fal-ai/object-removal/mask`. Alternatives: `fal-ai/bria/eraser`, `fal-ai/flux-pro/v1/erase`, `fal-ai/finegrain-eraser/mask` | Built for brush masks (white = erase). |
| (f) Templates | Prompt presets kept **server-side** (template id → model, prompt, params), mostly on NB2-edit or Seedream 5. Optional turnkey endpoints: `fal-ai/image-apps-v2/headshot-photo` and `.../style-transfer` | Lets you hot-swap models and A/B test without an app release. |
| Backend / proxy | **Supabase**: Edge Functions (Deno), Postgres credit ledger, anonymous Auth, private Storage, Realtime for job push | All-in-one. Anonymous sign-in built in. $2 per 1M invocations above quota [V]. |
| Abuse prevention | App Attest assertions on paid calls; DeviceCheck bits for the free tier; `AppTransaction.appTransactionID` to bind free credits per Apple Account; per-user, device and IP rate limits | [V] Apple docs |
| Purchases | StoreKit 2 (`SubscriptionStoreView`, `appAccountToken`). Server verifies JWS with Apple's App Store Server Library and consumes Notifications V2. RevenueCat is optional. | You need a server-side ledger anyway. |
| Provenance (EU AI Act Art. 50(2), CA AI Transparency Act) | IPTC `DigitalSourceType` XMP on every export (ImageIO), plus a C2PA manifest (c2pa-swift or server-side c2pa-rs). Keep upstream watermarks such as SynthID. | Art. 50 applies from 2 Aug 2026; the app launches after that, so it applies from day 1. [V] |
| Safety | Prompt filter → model safety checker (strict `safety_tolerance`) → output NSFW check → "Report" button → ban list. Block sexualised edits of real people outright. | EU AI Act **new Art. 5(1)(ba)** bans tools that can produce non-consensual intimate imagery without adequate safeguards **from 2 Dec 2026** [V]. App Review Guidelines 1.1.4 and 1.2. |

---

## 1. Models and APIs by capability (late 2026)

### 1.1 Market snapshot and important changes since mid-2025

- **Google "Nano Banana" family**
  - **Nano Banana 2** = Gemini 3.1 Flash Image. Announced 26 Feb 2026 as `gemini-3.1-flash-image-preview` [R]. On Vertex AI it went **GA as `gemini-3.1-flash-image` on 28 May 2026**, with retirement no earlier than 28 May 2027 [R: Google Cloud docs via search].
  - **Nano Banana 2 Lite** = `gemini-3.1-flash-lite-image`, launched 30 Jun 2026, about **$0.034** per 1K image and about 4 s [R]. The model id appears in Google's official python-genai README [V].
  - **Nano Banana Pro** = Gemini 3 Pro Image, still `gemini-3-pro-image-preview` (public preview since 20 Nov 2025) [R].
  - **Original Nano Banana** (`gemini-2.5-flash-image`) is "legacy". It was reportedly **shut down on 2 Oct 2026** [R]. **Do not build on `fal-ai/nano-banana` or `fal-ai/gemini-25-flash-image`.**
- **OpenAI**
  - `gpt-image-2` (snapshot `gpt-image-2-2026-04-21`).
  - **`gpt-image-2.5-flare`** (speed) and **`gpt-image-2.5-sunburst`** (precision), snapshots `-2026-09-08`. These add `xhigh` and `max` quality.
  - `dall-e-2` and `dall-e-3` were **retired 12 May 2026**. [V: openai/openai-openapi spec]
- **ByteDance Seedream 5.0** comes in **Pro, Lite and Flash** (on fal under `bytedance/seedream/v5/...`) [V endpoint list].
- **BFL FLUX.2** comes in [pro], [flex], [max], [dev], [klein] 4B/9B, flash and turbo. FLUX.1 Kontext is still listed. [V endpoint list]
- **Microsoft MAI-Image**:
  - 2.5 and 2.5-pro are on fal (`microsoft/mai-image-2.5[-pro][/edit]`) [V].
  - MAI-Image-2.6 went to Foundry public preview on 4 Sep 2026 at about $0.039 per image [R].
- **Leaderboards (they change weekly):**
  - Artificial Analysis AA-Image-Editing v2.0: **GPT Image 2.5 Sunburst (max) #1, Elo 1184**; GPT Image 2.5 Flare (max) 1164; MAI-Image-2.6 1140.
  - Open-weights editing: Qwen-Image-2.1 (1074), HunyuanImage 3.0 Instruct (1068), Qwen Image Edit Plus 2511 (1020).
  - Seedream 5.0 Pro is #1 on the identity-preserving edit sub-board.
  - GPT Image 2 (high) debuted #1 on text-to-image in April 2026, ahead of NB2, FLUX.2 [max] and Seedream 4.0. [R]
  - Sources: https://artificialanalysis.ai/image/leaderboard/editing, https://alphasignal.ai/news/artificial-analysis-rebuilds-its-image-editing-arena-across-17-specialized, https://x.com/ArtificialAnlys/status/2047184062012706980
- **Replicate.** Cloudflare announced its acquisition of Replicate on 17 Nov 2025, expected to close within about 2 months. Whether it has closed was not confirmed [R]: https://www.businesswire.com/news/home/20251117400765/en/

### 1.2 (a) Text-to-image

| Model (fal endpoint id [V]) | Price per image | Indicative latency [U] | Notes |
|---|---|---|---|
| **Nano Banana 2** `fal-ai/nano-banana-2` (direct: `gemini-3.1-flash-image[-preview]`) | Google list price **$0.045 (0.5K) / $0.067 (1K) / $0.101 (2K) / $0.151 (4K)** [R: deeplearning.ai; benchlm read of Google pricing page 2026-09-11]. fal's price is not verified [U]. | 5–15 s | `resolution` 0.5K–4K; extreme aspect ratios (4:1, 8:1); `thinking_level` minimal or high; `enable_web_search`; `safety_tolerance` "1"–"6" (default "4") [V]. Strong text rendering and world knowledge. Google adds SynthID [U]. |
| **Nano Banana 2 Lite** `google/nano-banana-2-lite` (direct: `gemini-3.1-flash-lite-image`) | about **$0.034** per 1K (1,120 output tokens) [R] | about 4 s (Google claim) [R] | Focused on 1K output. Best for previews and the free tier. |
| **Nano Banana Pro** `fal-ai/nano-banana-pro` | fal **$0.15** (1K/2K), **$0.30** (4K), web search +$0.015 [R: fal model page/guide]. Google direct **$0.134** (1K/2K), **$0.24** (4K) [R] | 15–40 s (reasoning) | Best for complex compositions and typography. Still preview. |
| **GPT Image 2** `openai/gpt-image-2` | Token-billed. fal page: text $5/M in, $10/M out; **image $8/M in, $30/M out** [R: fal llms.txt via search]. Estimates for 1024²: **~$0.006 low / ~$0.05 medium / ~$0.21 high** [R, third-party] | 10–60 s depending on `quality` | `image_size` up to 3840 px edge, multiples of 16 [V]. `quality` low, medium, high or auto [V]. |
| **GPT Image 2.5 Flare** `openai/gpt-image-2.5/flare/text-to-image` (Sunburst: `.../sunburst/...`) | Token-billed; rates reported as $5 text in, $8 image in, $30 image out per 1M [R] | 10–90 s | `quality` adds `xhigh` and `max` [V]. Current leaderboard leader [R]. |
| **Seedream 5.0 Lite** `bytedance/seedream/v5/lite/text-to-image` | about **$0.035 flat** on fal for 2K–4K output [R: Moda] | 5–15 s | Output must be between 2560×1440 and 4096² pixels [V]. Good value for high resolution. |
| Seedream 5.0 Pro / Flash `bytedance/seedream/v5/{pro,flash}/text-to-image` | Pro $0.045 (1K) / $0.09 (2K) on OpenRouter; fal reportedly about $0.068. Flash about **$0.018** [R] | — | Pro/Flash output is capped at 2048² [V]. |
| **FLUX.2 [pro]** `fal-ai/flux-2-pro` ([max]: `fal-ai/flux-2-max`) | [pro]: about $0.03 for the first megapixel + $0.015 for each further MP. [max]: about $0.07 + $0.03/MP [R: Moda] | 5–10 s | `safety_tolerance` "1"–"5" (default "2"). `enable_safety_checker` [V]. |
| FLUX.2 [klein] 4B/9B `fal-ai/flux-2/klein/{4b,9b}` | not verified [U]; expected to be cheap | about 1–3 s [U] | 4-step distilled open weights. Also `/realtime`. |
| **Ideogram v4** `ideogram/v4` (+`/fast`, `/instant`) | not verified [U] | — | `expansion_model` None/Medium/Large (Magic Prompt), `rendering_speed` [V]. Use for typography and posters. |
| **Recraft V4 / V4.1** `fal-ai/recraft/v4/text-to-image`, `recraft/v4.1/flash/text-to-image`, `.../text-to-vector` | not verified [U] | — | Design, illustration and **vector (SVG)** output. Good for sticker or logo templates. |
| Open weights: Qwen-Image-2512 `fal-ai/qwen-image-2512`, HunyuanImage 3 `fal-ai/hunyuan-image/v3/text-to-image` | not verified [U] | — | LoRA support and self-hostable. |

**Pick:** NB2 at 1K by default. NB2 Lite for previews and the free tier. GPT Image 2.5 Flare (medium) or NB Pro as a "Pro quality" toggle.

### 1.3 (b) Prompt-based photo editing

| Model (fal endpoint id [V]) | Price | Inputs [V] | Notes |
|---|---|---|---|
| **Nano Banana 2 Edit** `fal-ai/nano-banana-2/edit` | same as NB2 (1K **$0.067** direct [R]) | `image_urls[]` (can be optional if `video_url`, `audio_url` or `pdf_url` is given), `prompt`, `aspect_ratio` "auto", `resolution`, `safety_tolerance` | The general-purpose default. Multi-image composition. |
| **Seedream 5.0 Pro Edit** `bytedance/seedream/v5/pro/edit` | about $0.045–0.068 [R] | up to **10** reference images; `image_size` `auto_1K`/`auto_2K` | **#1 on identity-preserving edits** [R]. A/B this for "put me in a suit". |
| Seedream 5.0 Lite Edit `bytedance/seedream/v5/lite/edit` | about $0.035 [R] | up to 10 images; 2K–4K output | Budget, high resolution. |
| **GPT Image 2 Edit** `openai/gpt-image-2/edit` | token-billed [R] | `image_urls[]` (max **16**), optional **`mask_url`**, `quality`, `background` | Strong at object-level edits [R]. For gpt-image-2, OpenAI says **omit `input_fidelity`** [V]. |
| **GPT Image 2.5 Sunburst Edit** `openai/gpt-image-2.5/sunburst/edit` (Flare: `.../flare/edit`) | token-billed [R] | as above, plus `output_compression`, `quality` up to `max` | Top of AA-Image-Editing v2.0 [R]. Expensive at `max`. |
| FLUX.2 [pro] Edit `fal-ai/flux-2-pro/edit` | $0.03 for the first output MP, $0.015 per extra MP, **plus $0.015/MP for input references** [R] | `image_urls[]` | Good photographic fidelity. |
| FLUX.1 Kontext [pro]/[max] `fal-ai/flux-pro/kontext[/max]` | not verified [U] | single `image_url` | Previous generation. Still solid for local edits. |
| **Qwen-Image-Edit-2511** `fal-ai/qwen-image-edit-2511` | about **$0.03/MP** (about $0.031 for 1024²) [R] | `image_urls[]`, `negative_prompt`, `num_inference_steps` (28), `acceleration` | Open weights (self-hostable later). Large LoRA ecosystem (`.../lora`, lora-gallery). |
| Qwen Image 3 / Max Edit `alibaba/qwen-image-3/edit`, `fal-ai/qwen-image-max/edit` | not verified [U] | 1–3 images, each 384–2048 px, ≤10 MB, **PNG without alpha** [V] | Built-in prompt rewriting (`enable_prompt_expansion`). |
| MAI-Image-2.5-pro Edit `microsoft/mai-image-2.5-pro/edit` | not verified [U] | single `image_url` (http or data URL) [V] | MAI-Image-2.6 is not on fal yet (as of the 2026-10-06 types). |

**Pick:** NB2-edit as the default, with a server-side A/B against Seedream 5 Pro on person/identity templates. Expose a premium "precision" mode on GPT Image 2.5 Sunburst (medium/high).

### 1.4 (c) AI enhance, upscale and face restoration

| Option | Endpoint / API | Price | Notes |
|---|---|---|---|
| On-device auto-enhance | Core Image `CIImage.autoAdjustmentFilters(options:)` (iOS 5+) [V] | $0 | Red-eye, face balance, vibrance, tone curve, highlight/shadow. Instant. Not AI generation, so Art. 50(2) marking is not required (standard editing). |
| On-device super-resolution | VideoToolbox `VTSuperResolutionScalerConfiguration` with `InputType.image` (**iOS 26+**) [V] | $0 | Check `isSupported` and `configurationModelStatus`. The model may need downloading first (`downloadConfigurationModel`) [V]. |
| **SeedVR2 upscale** | `fal-ai/seedvr/upscale/image` (+`/seamless`) [V] | not verified [U] | `upscale_mode` factor or target (720p–2160p), `noise_scale`. Faithful generative restoration. |
| Real-ESRGAN | `fal-ai/esrgan` [V] | not verified [U] (cheap, GPU-seconds) | Models `RealESRGAN_x4plus`, `x2plus`, anime variants; `face: true` (Real-ESRGAN's face-enhance option; on fal it presumably uses GFPGAN [U]); `tile`. Deterministic and cheap. |
| **CodeFormer** | `fal-ai/codeformer` [V] | not verified [U] | `fidelity` 0–1 (higher keeps more of the original identity), `upscale_factor`, `face_upscale`, `only_center_face`. |
| GFPGAN | Not a standalone fal endpoint (absent from the 1,486-endpoint list) [V]. Possibly inside `fal-ai/esrgan` `face:true` [U]. On Replicate as `tencentarc/gfpgan` [U]. | — | CodeFormer is generally preferred for identity control [U]. |
| Clarity upscaler | `fal-ai/clarity-upscaler` [V]. Also `clarityai/crystal-upscaler` [V] | not verified [U] | SD-based **creative** upscaler (`creativity` 0.35, `resemblance` 0.6). It can change faces, so **do not use it for "restore my photo" of real people**. |
| Topaz | `topaz/upscale/image/precision`, `.../generative`, `topaz/restore/image` (models "Recover 3", "Dust-Scratch V2", "Faces") [V] | not verified [U] | Premium. Has `face_enhancement` controls. |
| Recraft crisp / creative upscale | `fal-ai/recraft/upscale/crisp` (PNG input only) [V] | not verified [U] | Crisp is non-generative-ish. Creative is expensive [U]. |
| Turnkey "portrait/photo restoration" | `fal-ai/image-apps-v2/portrait-enhance`, `fal-ai/image-apps-v2/photo-restoration`, `fal-ai/image-editing/face-enhancement` [V] | not verified [U] | Black-box prompts. Fine for templates. |

**Pick for one-tap "Enhance":** on-device auto-adjust → (if a face is found and resolution is low) CodeFormer at `fidelity` 0.6–0.8 → SeedVR2 ×2. Offer a "4K" paid upgrade (SeedVR2 to 2160p, or Topaz).

### 1.5 (d) Background removal

| Option | API | Price | Notes |
|---|---|---|---|
| **On-device subject lift** | Vision `VNGenerateForegroundInstanceMaskRequest` (iOS 17) → `VNInstanceMaskObservation.generateMaskedImage(ofInstances:from:croppedToInstancesExtent:)`. Swift-native `GenerateForegroundInstanceMaskRequest` on iOS 18 [V] | $0 | Multiple instances: let the user tap to pick. Works for people, pets and objects. Weaker on hair/fur than BiRefNet-Matting [U]. Test on device; simulator support is not guaranteed [U]. |
| **BiRefNet v2** | `fal-ai/birefnet/v2` [V] | not verified [U] (very cheap) | `model`: General Use Light / Light 2K / Heavy / **Matting** / **Portrait** / Dynamic. `operating_resolution` up to 2304² (Dynamic). `output_mask`, `mask_only`, `refine_foreground`. MIT-licensed weights (self-hostable) [U]. |
| **BRIA RMBG 2.0** | `fal-ai/bria/background/remove` [V] | not verified [U] (historically about $0.018 [U]) | Trained on licensed data (commercial safety). The open RMBG-2.0 weights are non-commercial, CC BY-NC [U], so use the API. |
| Others | `pixelcut/background-removal` (`output_format` rgba, alpha or zip; **`sync_mode` defaults to true**) [V], `fal-ai/imageutils/rembg` (`crop_to_bbox`) [V], `fal-ai/ideogram/remove-background` [V] | [U] | rembg is the cheapest. Quality varies. |

**Pick:** on-device first. Use server BiRefNet v2 (Matting/Portrait) as the "HD cut-out" fallback.

### 1.6 (e) Object removal with a brush mask

| Option | Endpoint [V] | Mask semantics [V] | Notes |
|---|---|---|---|
| **fal object removal** | `fal-ai/object-removal/mask` (also `/bbox`, and prompt-based `fal-ai/object-removal`) | `mask_url`: **white (255) = remove**; `mask_expansion` 0–50 (default 15); `model` low → best_quality | Built-in mask dilation. Output `{images:[…]}`. |
| **Bria Eraser** | `fal-ai/bria/eraser` | binary `mask_url`; `mask_type` **"manual"** for brush masks; `preserve_alpha` | Licensed-data model. Output `{image:{…}}`. |
| **FLUX.1 erase (BFL)** | `fal-ai/flux-pro/v1/erase` | white = erase; must **match the input dimensions**; `dilate_pixels` (10) | Output includes `has_nsfw_concepts`. |
| **Finegrain Eraser** | `fal-ai/finegrain-eraser/mask` (also `/bbox`, and prompt-based) | white = erase; `mode` express, standard or premium | Premium quality [U]. |
| Prompted fill (replace, not erase) | `fal-ai/flux-pro/v1/fill` (`prompt` + `mask_url`), `fal-ai/ideogram/v3/edit`, GPT Image 2 Edit (`mask_url`) | dimensions must match | Use for "replace with …". |
| LaMa | **No named LaMa endpoint on fal** [V: absent from list]. LaMa itself is Apache-2.0 [U] and can be self-hosted or converted to Core ML [U]. | — | An optional free on-device eraser later. |

Prices for the eraser endpoints are not verified [U]. Expect a few cents per image.

**Pick:** `fal-ai/object-removal/mask` at `best_quality`, falling back to `fal-ai/bria/eraser`. Render the brush stroke into a same-size 8-bit PNG (white = erase), dilate it slightly on device, and upload it alongside the image.

### 1.7 (f) One-tap style templates (anime, 3D figurine, pro headshot, …)

- **Implement templates as server-side recipes**, not app code. A template is:
  - `template_id` → `{endpoint, prompt template, params, credit cost, safety profile, allowed for minors?}`.
  - The app sends only `template_id`, the image path and optional user text. You can then switch models (NB2 ↔ Seedream ↔ GPT Image) without an app update. Describe this in Review Notes (Guideline 2.3.1(a)).
- General editors give the best quality: NB2-edit (the "3D figurine" look is a known NB-family strength [U]), Seedream 5 Pro (identity-sensitive templates such as headshots), and GPT Image 2.5.
- Turnkey fal endpoints [V]:
  - `fal-ai/image-apps-v2/headshot-photo` (`background_style`: professional, corporate, clean, gradient).
  - `fal-ai/image-apps-v2/style-transfer` (`target_style` enum: anime_character, cartoon_3d, pixel_art, claymation, cyberpunk_future, photorealistic, … plus `style_reference_image_url`).
  - `fal-ai/image-editing/{cartoonify,plushie-style,professional-photo,…}`.
  - LoRA galleries: `fal-ai/qwen-image-edit-2509-lora-gallery/*`, `fal-ai/flux-2-lora-gallery/*`.
- **IP and likeness caution.** fal hosts endpoints such as `fal-ai/ghiblify`. Avoid templates named after studios, brands or artists (Guideline 5.2.1; IP risk). Never offer templates that undress, sexualise, "age down" or put real people in compromising scenes (see §5–6).

### 1.8 Routing matrix (MVP)

| Op | Default | Fallback (5xx, timeout, safety false-positive) | Free tier | Credit weight (suggestion) |
|---|---|---|---|---|
| Text→image | NB2 1K | Seedream 5 Lite | NB2 Lite | 4 |
| Edit | NB2-edit 1K | Seedream 5 Pro edit, then GPT Image 2 edit (medium) | `google/nano-banana-lite/edit` [V endpoint]. Its relationship to NB2 Lite is unverified: `google/nano-banana-2-lite` is text→image only, and the types alias its input to `NanoBananaLiteInput`. Alternatively use Seedream 5 Lite edit. | 4 |
| Premium edit | GPT Image 2.5 Sunburst (high) or NB Pro 2K | NB2 2K | — | 12–20 |
| Enhance | device + CodeFormer + SeedVR2 ×2 | ESRGAN ×2 | device only | 2 |
| Background removal | device (Vision) | BiRefNet v2 | device | 0–1 |
| Erase | object-removal/mask (best) | bria/eraser | — | 2 |
| Template | per recipe | per recipe | 1–2 templates per day | 4–6 |

---

## 2. Aggregator choice

### 2.1 Comparison

| | **fal.ai** | **Replicate** | **Direct providers** (Google, OpenAI, BFL, BytePlus, …) |
|---|---|---|---|
| Catalogue | 1,486 endpoints in the official client types (2026-10-06) [V]. Includes Google `google/*`, `openai/*`, `bytedance/*`, `alibaba/*`, `ideogram/*`, `recraft/*`, `topaz/*`, `clarityai/*`, `pixelcut/*`, `microsoft/*` [V] | Very large community catalogue plus "official" models [R] | One vendor at a time |
| Pricing | Output-based: per image, per megapixel or per token. Partner models are at or near list price. Example: NB Pro $0.15 on fal vs $0.134 at Google (+12%) [R] | Per output for official models; per GPU-second for community models, with cold starts [R/U] | Lowest unit price. Batch discounts (Gemini batch about 50% for NB1 [R]). |
| Sync call | `POST https://fal.run/{endpoint_id}`: no queue, no retries [R] | `Prefer: wait` holds up to 60 s, then returns an incomplete prediction [R] | Gemini `generateContent` and OpenAI `images/*` are synchronous HTTP |
| Async call | `POST https://queue.fal.run/{endpoint_id}` → `request_id` plus `status_url`, `response_url`, `cancel_url` [V]. Durable queue, automatic re-queue up to 10× on runner failure [R] | `POST /v1/models/{owner}/{name}/predictions`, then poll or webhook [V README] | BFL is async with polling [U]. Others vary. |
| Webhooks | `?fal_webhook=<url>`. **Ed25519 signature**, keys at `https://rest.fal.ai/.well-known/jwks.json`, ±300 s window [R: fal docs] | `webhook` + `webhook_events_filter` (start, output, logs, completed). HMAC signing secret (`Webhook-Id`, `Webhook-Timestamp`, `Webhook-Signature`) [V: replicate-javascript README] | Varies; often none |
| Auth | `Authorization: Key $FAL_KEY` [V: client source] | `Authorization: Bearer $REPLICATE_API_TOKEN` [V] | Gemini `x-goog-api-key`; OpenAI `Authorization: Bearer` [U/V] |
| Data handling | `X-Fal-Object-Lifecycle-Preference` sets output expiry [V]. `X-Fal-Store-IO: 0` disables the 30-day request I/O history [R]. `sync_mode:true` returns a data URI that is not kept in history [V]. CDN media defaults to ≥7 days if not set [R] | API prediction data and file URLs are removed after about 1 hour by default [R] | Vendor DPAs and enterprise zero-data-retention (ZDR) options [U] |
| Reliability features | Latest client fails over to backup hosts (`fal.run`→`falrun.com`, `queue.fal.run`→`queue.falrun.com`) on connection errors [V: alpha client source] | Cloudflare acquisition (roadmap change) [R] | Strongest SLAs, but N integrations to run |
| Swift client | `fal-ai/fal-swift` (`FalClient`, `.withProxy(...)`) [V] | community | Google/OpenAI Swift SDKs exist [U] |

### 2.2 Recommendation: **fal.ai as the single primary aggregator**

- One auth scheme, one queue/webhook pattern and one image-URL convention covers all six capabilities, including Google and OpenAI partner models.
- Plan to **go direct for the 1–2 highest-volume models** once volume is proven (for example NB2 through the Gemini API). Keep the provider choice behind your own `op → provider` router so the switch is a config change.
- **Do not** expose fal's generic proxy (`@fal-ai/server-proxy`, `x-fal-target-url`) to the iOS app. It forwards to *any* fal endpoint on your bill [V: proxy README]. Build an **allowlisted operations API** instead (§3).

### 2.3 fal HTTP pattern (from the official client source [V] plus docs [R])

```
Submit (async, recommended)
POST https://queue.fal.run/{endpoint_id}?fal_webhook={urlencoded https callback}
Authorization: Key <FAL_KEY>
Content-Type: application/json
X-Fal-Object-Lifecycle-Preference: {"expiration_duration_seconds":3600}   # output media expiry [V]
X-Fal-Store-IO: 0                                                          # don't keep request I/O history [R]
X-Fal-Queue-Priority: normal                                               # optional: "low" | "normal" (default) [V client types]
{ ...model input JSON... }

→ 200 { "status":"IN_QUEUE", "request_id":"…", "queue_position":0,
        "status_url":"https://queue.fal.run/{owner}/{alias}/requests/{id}/status",
        "response_url":"https://queue.fal.run/{owner}/{alias}/requests/{id}",
        "cancel_url":"https://queue.fal.run/{owner}/{alias}/requests/{id}/cancel" }
```

- **Gotcha [V].** Status, result and cancel URLs use only `{owner}/{alias}`. The sub-path is dropped, so `fal-ai/nano-banana-2/edit` polls at `…/fal-ai/nano-banana-2/requests/{id}`. Store and use the returned URLs.
- **Status:** `GET {status_url}?logs=1` returns `IN_QUEUE` (+`queue_position`), `IN_PROGRESS` (+`logs`) or `COMPLETED` (+`metrics.inference_time`). There is also an SSE stream at `…/status/stream` [V].
- **Result:** `GET {response_url}` returns the model output JSON. **Cancel:** `PUT {cancel_url}` [V].
- **Sync:** `POST https://fal.run/{endpoint_id}` with the same body; the output JSON comes back on the same connection. No retries. Use it only for fast utilities [R].
- **Webhook POST body** (type `WebHookResponse` [V]): `{ "request_id": "...", "status": "OK" | "ERROR", "payload": { ...model output... }, "error": "..." }`.
  - Headers [R]: `X-Fal-Webhook-Request-Id`, `X-Fal-Webhook-User-Id`, `X-Fal-Webhook-Timestamp`, `X-Fal-Webhook-Signature` (hex).
  - Message = request-id, user-id, timestamp and the SHA-256 of the **raw body**, joined by newlines, then Ed25519-verified against the JWKS. Do not cache keys for more than 24 h.
  - Confirm the exact hash encoding on the docs page: https://fal.ai/docs/documentation/model-apis/inference/webhooks
- **Inputs.**
  - Pass any **public or presigned URL**. Private URLs that need auth headers do not work [R].
  - Many endpoints also accept **base64 data URIs**. fal's CDN doc says URLs work with every model, so keep data URIs for small files only [R]. Some schemas say so explicitly, for example MAI-Image ("http(s) or data: URL") and NB2 `audio_url`/`video_url` [V].
  - fal's own upload (`POST https://rest.fal.ai/storage/upload/initiate?storage_type=fal-cdn-v3`) produces **public** CDN URLs [V]. For user photos, prefer your **private bucket plus a ≤10-minute signed URL**.
- **Outputs.** `images[].url` or `image.url` are **public fal CDN URLs** (typically `*.fal.media`), alive until their expiry. Copy them immediately or let the device download them; then they expire. With `sync_mode:true` the media comes back inline as a data URI and is not stored in history [V].
- **Safety knobs [V].** `enable_safety_checker` (default true; turning it off needs account authorization, and flagged images come back black or blocked). `safety_tolerance` (Gemini endpoints "1"–"6", default "4"; FLUX "1"–"5"/"6", default "2"). Several outputs include `has_nsfw_concepts[]`.

### 2.4 Exact endpoint IDs and JSON shapes by capability

All shapes come from `@fal-ai/client@1.11.0-alpha.5 src/types/endpoints.d.ts` [V]. Only key fields are shown; `?` means optional.

**Shared output image object**: `{ "url": "https://…", "content_type?": "image/png", "file_name?": "…", "file_size?": 123, "width?": 1024, "height?": 1024 }`

#### (a) Text→image — `fal-ai/nano-banana-2`
```json
// request
{ "prompt": "a cozy reading nook at golden hour, 35mm photo",
  "aspect_ratio": "3:4",            // auto|21:9|16:9|3:2|4:3|5:4|1:1|4:5|3:4|2:3|9:16|4:1|1:4|8:1|1:8
  "resolution": "1K",               // 0.5K|1K|2K|4K
  "num_images": 1,
  "output_format": "jpeg",          // jpeg|png|webp (default png)
  "safety_tolerance": "2",          // "1" strict … "6" permissive (default "4")
  "thinking_level": "minimal",      // optional: minimal|high
  "limit_generations": true }
// response payload
{ "images": [ { "url": "https://…", "width": 896, "height": 1200, "content_type": "image/jpeg" } ],
  "description": "…model text…" }
```
Same shape for: `fal-ai/nano-banana-pro` (resolution 1K/2K/4K) and `google/nano-banana-2-lite` (no resolution field).
- `openai/gpt-image-2`: `{prompt, image_size: "auto"|preset|{width,height}, quality: "low"|"medium"|"high"|"auto", background, output_format, num_images}` → `{ "images":[…] }`.
- `bytedance/seedream/v5/lite/text-to-image`: `{prompt, image_size: "auto_2K"|"auto_3K"|"auto_4K"|{w,h}, num_images, enable_safety_checker}` → `{ "images":[…], "seed": n }` (Lite) or `{images}` (Pro).

#### (b) Prompt edit — `fal-ai/nano-banana-2/edit`
```json
{ "prompt": "Replace the outfit with a tailored navy suit and white shirt. Keep the face, hair, pose, lighting and background unchanged.",
  "image_urls": ["https://<project>.supabase.co/storage/v1/object/sign/inputs/u/123.jpg?token=…"],
  "aspect_ratio": "auto", "resolution": "1K", "output_format": "jpeg", "safety_tolerance": "2" }
// → { "images":[{ "url":"https://…" }], "description":"…" }
```
- `bytedance/seedream/v5/pro/edit`: `{ "prompt", "image_urls":[…≤10], "image_size":"auto_2K", "output_format":"jpeg", "num_images":1 }` → `{ "images":[…] }`.
- `openai/gpt-image-2/edit`: `{ "prompt", "image_urls":[…≤16], "mask_url?":"…", "quality":"medium", "image_size":"auto", "output_format":"jpeg" }` → `{ "images":[…] }`.
- `fal-ai/qwen-image-edit-2511`: `{ "prompt", "image_urls":[…], "negative_prompt?":"", "num_inference_steps?":28, "guidance_scale?":4.5, "acceleration?":"regular" }` → `{ "images":[…], "seed", "has_nsfw_concepts":[bool], "prompt", "timings" }`.

#### (c) Enhance / upscale / face restoration
```json
// fal-ai/seedvr/upscale/image
{ "image_url": "https://…", "upscale_mode": "factor", "upscale_factor": 2, "output_format": "jpg", "noise_scale": 0.1 }
// → { "image": { "url": "https://…" }, "seed": 123 }

// fal-ai/codeformer
{ "image_url": "https://…", "fidelity": 0.7, "upscale_factor": 2, "face_upscale": true, "only_center_face": false }
// → { "image": { "url": "https://…" }, "seed": 123 }

// fal-ai/esrgan
{ "image_url": "https://…", "model": "RealESRGAN_x4plus", "scale": 2, "face": false, "output_format": "png" }
// → { "image": { "url": "https://…" } }

// fal-ai/clarity-upscaler (creative; avoid on faces)
{ "image_url": "https://…", "upscale_factor": 2, "creativity": 0.35, "resemblance": 0.6 }
// → { "image": { "url": "…" }, "seed": 1, "timings": {…} }
```

#### (d) Background removal — `fal-ai/birefnet/v2`
```json
{ "image_url": "https://…", "model": "General Use (Heavy)",   // or "Matting" | "Portrait" | "General Use (Dynamic)"
  "operating_resolution": "2048x2048", "output_format": "png", "refine_foreground": true, "output_mask": true }
// → { "image": { "url": "https://….png" }, "mask_image": { "url": "https://…" } }
```
`fal-ai/bria/background/remove`: `{ "image_url": "…" }` → `{ "image": { "url": "…" } }`.

#### (e) Object removal — `fal-ai/object-removal/mask`
```json
{ "image_url": "https://…/photo.jpg", "mask_url": "https://…/mask.png",   // white(255) = remove
  "model": "best_quality", "mask_expansion": 15 }
// → { "images": [ { "url": "https://…" } ] }
```
- `fal-ai/bria/eraser`: `{ "image_url", "mask_url", "mask_type":"manual", "preserve_alpha?":false }` → `{ "image": {…} }`.
- `fal-ai/flux-pro/v1/erase`: `{ "image_url", "mask_url", "dilate_pixels":10, "output_format":"jpeg" }` → `{ "images":[{url,width,height}], "has_nsfw_concepts":[…], "seed", "prompt", "timings" }`.

#### (f) Templates
```json
// generic: server expands template_id "figurine_v3" into a prompt on fal-ai/nano-banana-2/edit
{ "prompt": "Turn the subject into a 1/7 scale collectible PVC figure on a desk, product photo…",
  "image_urls": ["https://…"], "aspect_ratio": "auto", "resolution": "1K" }

// turnkey: fal-ai/image-apps-v2/headshot-photo
{ "image_url": "https://…", "background_style": "professional", "aspect_ratio": { "ratio": "3:4" } }
// → { "images": [ { "url": "https://…" } ] }

// turnkey: fal-ai/image-apps-v2/style-transfer
{ "image_url": "https://…", "target_style": "anime_character", "aspect_ratio": { "ratio": "1:1" } }
```

#### Moderation helpers on fal [V]
- `fal-ai/imageutils/nsfw`: `{ "image_url" }` → `{ "nsfw_probability": 0.03 }`.
- `fal-ai/x-ailab/nsfw`: `{ "image_urls":[…≤10] }` → `{ "has_nsfw_concepts":[false] }`.

### 2.5 Direct-provider shapes (for a later migration)

- **OpenAI Images** [V: openai-openapi `master/openapi.yaml`]:
  - Endpoints: `POST https://api.openai.com/v1/images/generations` and `POST /v1/images/edits`.
  - Edits accept multipart (`image` binary, up to 16 images, ≤50 MB each, plus `mask` PNG whose **alpha=0 areas are edited**). They also accept **JSON** with `images:[{"image_url":"https://…"}]` or file ids.
  - Params: `model` (`gpt-image-2`, `gpt-image-2.5-flare`, `gpt-image-2.5-sunburst`, dated snapshots, `gpt-image-1.5`, `gpt-image-1-mini`, `chatgpt-image-latest`), `quality` low/medium/high (+xhigh/max on 2.5), `size` "auto" or "WxH" (multiples of 16, ratio 1:3–3:1, max 3840×2160; above 2560×1440 is experimental), `background`, `output_format`, `output_compression`, `moderation` "auto"|"low", `stream` + `partial_images`, `user` (safety identifier).
  - Response `data[].b64_json`: GPT image models **always return base64**, never a URL.
- **Gemini API** [V: google python-genai types/README]:
  - Endpoint: `POST https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent`, header `x-goog-api-key` [U for REST path/header; standard].
  - Body: `contents[].parts[]` with text and `inline_data{mime_type,data}`, plus `generationConfig: { responseModalities:["IMAGE"], imageConfig:{ aspectRatio:"3:4", imageSize:"1K"|"2K"|"4K" } }`. `personGeneration` (ALLOW_ALL, ALLOW_ADULT, ALLOW_NONE) exists in the type, but some fields are Vertex-only.
  - Output is in `candidates[0].content.parts[].inline_data` (base64).
- **Replicate** [V: replicate-javascript README]:
  - Base `https://api.replicate.com/v1`; `POST /models/{owner}/{name}/predictions` with `{ "input":{…}, "webhook":"…", "webhook_events_filter":["completed"] }`; optional `Prefer: wait`.
  - Output file URLs live on `replicate.delivery`. Copy them quickly (about 1 h retention [R]).
- **BFL direct**: async submit → polling URL → short-lived signed result URL [U]. The docs were not reachable during this research.

---

## 3. Secure backend architecture

### 3.1 Proxy platform comparison

| | **Supabase Edge Functions (Deno)** | **Cloudflare Workers** | **Vercel Functions** |
|---|---|---|---|
| Limits | 256 MB memory; **2 s CPU per request** (async I/O excluded); wall clock **150 s free / 400 s paid**; **request idle timeout 150 s** (then 504); bundle 20 MB; no `sharp`/libvips [V: supabase docs source] | 128 MB per isolate; CPU default **30 s, up to 5 min**; **no duration limit while the client stays connected**; `waitUntil` adds up to 30 s; 10,000 subrequests per invocation on paid [V: cloudflare-docs] | Fluid compute; maxDuration up to about 800 s on Pro [U] |
| Price | Pro $25/mo; **2M invocations included, then $2 per 1M** (Free: 500k) [V]. Storage $0.0213/GB-mo above 100 GB [V]. MAU above quota $0.00325 [V] | Paid $5/mo: **10M requests, then $0.30/M; 30M CPU-ms, then $0.02/M CPU-ms**; no egress charges [V]. R2 storage $0.015/GB-mo, **free egress** [V] | Active CPU about $0.128/h, memory about $0.0106/GB-h (iad1); $0.60/M invocations beyond 1M (Pro) [R]. Hobby is non-commercial [U] |
| Built-ins | **Postgres (ledger, RLS), Auth with anonymous sign-ins, Storage with signed URLs, Realtime, pg_cron** | **Rate-limit binding** (`limit()`, period 10 or 60 s, eventually consistent) [V]; Durable Objects, D1, R2, Queues, Turnstile | Marketplace (Neon, Upstash, …); full Node (Apple and npm libraries just work) |
| Auth for anonymous users | `signInAnonymously()`; JWT claim `is_anonymous`; link identities later; 30 anonymous sign-ins per hour per IP by default; CAPTCHA/Turnstile recommended [V] | Build your own (issue a JWT after App Attest) | Build your own or use a vendor |
| Fit | **Best all-in-one MVP.** Long jobs must be async (queue + webhook), which you want anyway | Cheapest at scale and best for rate limiting, but you assemble DB and auth yourself | Good if you already have a Next.js backend |

**Recommendation: Supabase.** Run Edge Functions as the proxy, with Postgres, Auth, Storage and Realtime alongside. If abuse or traffic grows, put Cloudflare (WAF and rate limiting) in front.

Design around the limits: never hold an HTTP request open for a generation. Submit to the fal queue and return a `jobId` in under 1 s. Results arrive by webhook, and the client is notified through Supabase Realtime (with polling as a fallback). Never base64 images through the function; pass signed URLs.

### 3.2 Architecture and request flow

```
iOS app (SwiftUI)                                   Supabase                                   fal.ai
───────────────────                                 ─────────────────────────────────────      ─────────────
1 signInAnonymously()  ───────────────────────────► Auth (JWT, is_anonymous)
2 App Attest: get challenge → attestKey → register ► fn attest-register (verify, store pubkey+receipt)
3 PhotosPicker → downscale ≤2048px, strip GPS EXIF
4 upload to Storage via signed upload URL ────────► Storage bucket "inputs" (private, TTL purge 24h)
5 POST fn create-job {op|template_id, input_path,  ► fn create-job:
    mask_path?, prompt?} + App Attest assertion        a verify JWT + assertion (counter↑, nonce)
                                                       b rate-limit (user, device, IP)
                                                       c prompt policy check / template expansion
                                                       d reserve credits (tx) → jobs row
                                                       e signed URL (10 min) for input        ──► POST queue.fal.run/{endpoint}?fal_webhook=…
6 subscribe Realtime on jobs[jobId] ◄──────────────                                               (X-Fal-Object-Lifecycle-Preference,
                                                                                                    X-Fal-Store-IO: 0)
                                                    fn fal-webhook ◄───────────────────────────── signed webhook (Ed25519)
                                                       verify sig → idempotent by request_id
                                                       OK: output moderation → capture credits
                                                       ERROR/blocked: release credits
                                                       update jobs row (result_url, expires_at)
7 download result → embed IPTC/C2PA → show/save
8 StoreKit 2 purchase(appAccountToken=userId) ──► fn verify-transaction (JWS) → grant credits
  App Store Server Notifications V2 ─────────────► fn asn-v2 (renew/refund/revoke → ledger)
```

### 3.3 Identity

- Start every user with **Supabase anonymous auth**. This satisfies Guideline 5.1.1(v): apps without significant account features must work without login.
- Offer "Sign in with Apple" later to sync history and purchases: `signInWithIdToken`, or link the identity to the anonymous user (enable manual linking) [V].
- If you ever add Google or another social login, Guideline **4.8** requires an equivalent privacy-preserving option; Sign in with Apple qualifies [V].
- Account creation means **in-app account deletion** is required (5.1.1(v)) [V].
- Sign in with Apple relay addresses move to `private.icloud.com`. Accept both domains [V: Apple news 2026-08-24].
- Purge stale anonymous users, for example after 30 days of inactivity with no purchases. The Supabase docs give a SQL example [V]. Anonymous users count toward MAU billing [U].

### 3.4 Abuse prevention: App Attest, DeviceCheck, appTransactionID

- **App Attest** (`DCAppAttestService`, iOS 14+) [V]:
  - The app generates a Secure Enclave key, gets a one-time challenge from the server (≥16 bytes), calls `attestKey(keyId, clientDataHash: SHA256(challenge))` and sends the attestation plus `keyId`.
  - The server checks the x5c chain against Apple's App Attest root; nonce = SHA256(authData ‖ SHA256(challenge)), matched against cert extension OID 1.2.840.113635.100.8.2; rpId = SHA256(TeamID.bundleID); counter = 0; aaguid = `appattest` (prod) or `appattestdevelop`; credentialId = keyId.
  - **New in the current docs:** also check `apple_validation_category_01` (4 = App Store, 2 = TestFlight, 3 = development) and `apple_bundle_version_01` in the authenticator extensions [V].
  - Store the public key and receipt per (user, device).
  - On each paid request, the app sends `generateAssertion(keyId, SHA256(clientData))`, where clientData includes a server nonce and the request digest. The server verifies the signature and that the **counter is strictly increasing**.
  - Optional: refresh the receipt at `https://data.appattest.apple.com/v1/attestationData` to read the **risk metric** (number of attested keys per device) [V].
  - `isSupported` can be false (simulator, some extensions). Fall back to stricter rate limits and a smaller free tier.
  - Ramping guidance applies for very large DAU [V].
  - Server libraries to evaluate: `appattest-checker-node` (1.0.3, 2024-10) and `node-app-attest` (1.0.1, 2026-02) [V npm existence; quality not evaluated].
- **DeviceCheck** `DCDevice` (2 bits per device per developer team, which survive reinstall) [V]. Use bit 0 = "free starter credits granted" and bit 1 = "abuse flag". This stops reinstall-farming of free credits.
- **`AppTransaction.appTransactionID`**: a globally unique, stable value per Apple Account per app. It survives redownloads, refunds and storefront changes, and is available without any IAP; it is back-deployed to iOS 16 [V]. Have the app send `AppTransaction.shared` JWS. The server verifies it (App Store Server Library `verifyAndDecodeAppTransaction` [U name]) and grants free credits **once per appTransactionID**.
- **Rate limits** (§3.6), **velocity rules** (for example more than X ops per hour, or many keys per appTransactionID), and **ban keys**: user id + App Attest key id + DeviceCheck bit + appTransactionID.

```swift
import DeviceCheck
import CryptoKit
import StoreKit

/// Client side of App Attest (Apple flow per "Establishing your app's integrity" [V]).
actor Attestor {
    private let service = DCAppAttestService.shared
    private var keyId: String? = KeychainStore.read("appAttestKeyId")       // your keychain helper

    func ensureAttestedKey(api: API) async throws -> String {
        if let keyId { return keyId }
        guard service.isSupported else { throw AttestError.unsupported }      // server applies stricter limits
        let newKey = try await service.generateKey()
        let challenge = try await api.attestChallenge()                       // ≥16 random bytes, single use
        let attestation = try await service.attestKey(newKey, clientDataHash: Data(SHA256.hash(data: challenge)))
        try await api.registerAttestation(keyId: newKey, attestation: attestation, challenge: challenge)
        KeychainStore.write(newKey, for: "appAttestKeyId"); keyId = newKey
        return newKey
    }

    /// clientData = JSON of the request + server nonce; server recomputes SHA256(clientData) and checks counter.
    func assertion(for clientData: Data, keyId: String) async throws -> Data {
        try await service.generateAssertion(keyId, clientDataHash: Data(SHA256.hash(data: clientData)))
    }
}

/// Free-tier binding: send the signed AppTransaction to the server once (appTransactionID is stable per Apple Account).
func appTransactionJWS() async throws -> String {
    let result = try await AppTransaction.shared        // VerificationResult<AppTransaction>
    return result.jwsRepresentation                     // server verifies, reads appTransactionID
}
```

### 3.5 Server-side credits ledger (Postgres)

```sql
create table credit_buckets (            -- allowance resets each period; packs never expire (Guideline 3.1.1)
  user_id uuid primary key references auth.users(id) on delete cascade,
  allowance int not null default 0 check (allowance >= 0),
  allowance_period_end timestamptz,
  packs int not null default 0 check (packs >= 0)
);
create table credit_ledger (             -- append-only audit trail
  id bigserial primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  delta int not null,
  kind text not null check (kind in ('grant_free','grant_sub','grant_pack','hold','release','refund_apple','admin')),
  job_id uuid,
  source_ref text,                       -- Apple transactionId / notificationUUID → idempotency
  created_at timestamptz not null default now(),
  unique (kind, source_ref)
);
create table jobs (
  id uuid primary key, user_id uuid not null, op text not null, endpoint text not null,
  cost int not null, fal_request_id text unique, status text not null default 'queued',
  result_url text, result_expires_at timestamptz, safety_flags jsonb, created_at timestamptz default now()
);

create or replace function reserve_credits(p_user uuid, p_cost int, p_job uuid)
returns void language plpgsql security definer set search_path = public as $$
declare a int; p int;
begin
  select allowance, packs into a, p from credit_buckets where user_id = p_user for update;
  if coalesce(a,0) + coalesce(p,0) < p_cost then raise exception 'INSUFFICIENT_CREDITS'; end if;
  update credit_buckets
     set allowance = greatest(a - p_cost, 0),
         packs     = p - greatest(p_cost - a, 0)       -- spend allowance first
   where user_id = p_user;
  insert into credit_ledger(user_id, delta, kind, job_id) values (p_user, -p_cost, 'hold', p_job);
end $$;
revoke execute on function reserve_credits(uuid,int,uuid) from public, anon, authenticated;  -- service role only

-- Refund a failed/blocked job exactly once (credited back to non-expiring packs for simplicity).
create or replace function release_credits(p_job uuid)
returns void language plpgsql security definer set search_path = public as $$
declare u uuid; c int;
begin
  select user_id, -delta into u, c from credit_ledger where job_id = p_job and kind = 'hold';
  if u is null then return; end if;
  insert into credit_ledger(user_id, delta, kind, job_id, source_ref)
       values (u, c, 'release', p_job, p_job::text)
  on conflict (kind, source_ref) do nothing;          -- idempotent
  if found then update credit_buckets set packs = packs + c where user_id = u; end if;
end $$;
revoke execute on function release_credits(uuid) from public, anon, authenticated;
```

- Release credits on an `ERROR` webhook, a safety block, or no webhook within N minutes (a pg_cron sweeper that polls `status_url`, then releases).
- Make everything idempotent on `fal_request_id` and Apple `transactionId` / `notificationUUID`.
- Keep RLS on all tables. Clients read only their own `jobs` and balances.

### 3.6 Rate limiting

- Edge (Supabase): Upstash Redis with `@upstash/ratelimit` (2.2.0) is Supabase's documented pattern [V]. Alternatively, use a Postgres token-bucket table (no extra vendor).
- Suggested keys: `user:{id}`, `device:{appAttestKeyId}`, `ip:{/24}`, `acct:{appTransactionID}`. Example limits: free tier 3 jobs/min and 10/day; paid 10/min and 300/day; plus a global spend circuit breaker (alert if hourly fal spend exceeds the threshold).
- With Cloudflare in front: the `ratelimits` binding, `{ simple: { limit, period: 10|60 } }`, `env.RL.limit({ key })`. It is per-location and eventually consistent, so it is not exact accounting [V].

### 3.7 Purchases: native StoreKit 2 + server vs RevenueCat

**Native (recommended):**
- App: `SubscriptionStoreView` (iOS 17) or a custom paywall.
- `product.purchase(options: [.appAccountToken(userUUID)])` makes the App Store echo your user id in every transaction [V].
- After a purchase, send `verificationResult.jwsRepresentation` to the server. It is the same JWS that the App Store Server API and Notifications return, plus device-verification fields [V].
- Server:
  - Verify with Apple's **App Store Server Library** (`@apple/app-store-server-library` 3.1.0, 2026-05-06): `new SignedDataVerifier(appleRootCAs, enableOnlineChecks, environment, bundleId, appAppleId)` then `verifyAndDecodeTransaction`, `verifyAndDecodeNotification` [V README].
  - JWTs for the App Store Server API come from App Store Connect keys. Sandbox base URL `https://api.storekit-sandbox.apple.com/` [V].
  - Endpoints: Get All Subscription Statuses, Get Transaction Info/History, Get App Transaction Info, Notification History (180 days prod, 30 days sandbox) [V].
  - Consume **App Store Server Notifications V2**: `SUBSCRIBED`, `DID_RENEW` (grant the allowance), `DID_FAIL_TO_RENEW`, `GRACE_PERIOD_EXPIRED`, `EXPIRED`, `REFUND`, `REVOKE` (claw back), `ONE_TIME_CHARGE` (consumable credit packs), `CONSUMPTION_REQUEST` (send consumption info) [V]. V1 is deprecated [V].
  - **Deno compatibility of the App Store Server Library on Supabase Edge is not verified [U].** If it fails, verify JWS with `jose` (6.2.x supports Deno/Workers [V]) plus x5c chain validation to Apple Root CA G3, or host this one webhook on a Node runtime.

```swift
// Purchase → server-side verification → finish only after the server has granted credits.
func buy(_ product: Product, userId: UUID, api: API) async throws {
    let result = try await product.purchase(options: [.appAccountToken(userId)])      // [V]
    guard case .success(let verification) = result else { return }                   // .pending / .userCancelled
    try await api.verifyTransaction(jws: verification.jwsRepresentation)             // App Store Server Library on server
    if case .verified(let transaction) = verification { await transaction.finish() }
}
// Also listen to Transaction.updates at launch for renewals/refunds made outside the app.
```

- **RevenueCat** (optional): paywall experiments, analytics and webhooks into your ledger. Pricing has historically been free up to $2.5k MTR, then 1% [U]. A server ledger is still required to enforce credit spend on your proxy.
- New in 2026 [V: Apple news]:
  - Monthly subscriptions with a 12-month commitment (iOS 26.4+, not in the US or Singapore).
  - Multiseat (Volume Purchasing from 22 Oct 2026).
  - Bundles and Suites (iOS 27).
  - EU single business terms from 1 Oct 2026 (alternative payments allowed alongside IAP).

### 3.8 Edge-function sketches (TypeScript, Deno)

```ts
// supabase/functions/create-job/index.ts
import { createClient } from "npm:@supabase/supabase-js@2";
const FAL_KEY = Deno.env.get("FAL_KEY")!;                       // never shipped to the app
const HOOK = Deno.env.get("FAL_WEBHOOK_URL")!;                  // https://<ref>.supabase.co/functions/v1/fal-webhook
const OPS: Record<string, { endpoint: string; cost: number }> = {   // allowlist: client never names an endpoint
  t2i:      { endpoint: "fal-ai/nano-banana-2",          cost: 4 },
  edit:     { endpoint: "fal-ai/nano-banana-2/edit",     cost: 4 },
  upscale:  { endpoint: "fal-ai/seedvr/upscale/image",   cost: 2 },
  cutout:   { endpoint: "fal-ai/birefnet/v2",            cost: 1 },
  erase:    { endpoint: "fal-ai/object-removal/mask",    cost: 2 },
};
Deno.serve(async (req) => {
  const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
  const jwt = req.headers.get("Authorization")?.replace(/^Bearer /, "") ?? "";
  const { data: { user } } = await db.auth.getUser(jwt);
  if (!user) return new Response("unauthorized", { status: 401 });
  const body = await req.json();             // { op, inputPath, maskPath?, prompt?, templateId?, attest:{keyId, assertion, clientData} }
  // TODO verifyAssertion(body.attest) ; rateLimit(user.id, body.attest.keyId) ; policyCheck(body.prompt)
  const op = OPS[body.op]; if (!op) return new Response("bad op", { status: 400 });
  const jobId = crypto.randomUUID();
  const { error } = await db.rpc("reserve_credits", { p_user: user.id, p_cost: op.cost, p_job: jobId });
  if (error) return new Response("insufficient credits", { status: 402 });
  const { data: s } = await db.storage.from("inputs").createSignedUrl(body.inputPath, 600);
  const input = body.op === "edit"
    ? { prompt: body.prompt, image_urls: [s!.signedUrl], aspect_ratio: "auto", resolution: "1K", safety_tolerance: "2" }
    : { image_url: s!.signedUrl };            // build per-op payloads exactly as in §2.4
  const r = await fetch(`https://queue.fal.run/${op.endpoint}?fal_webhook=${encodeURIComponent(HOOK)}`, {
    method: "POST",
    headers: { Authorization: `Key ${FAL_KEY}`, "Content-Type": "application/json",
               "X-Fal-Object-Lifecycle-Preference": JSON.stringify({ expiration_duration_seconds: 3600 }),
               "X-Fal-Store-IO": "0" },
    body: JSON.stringify(input),
  });
  if (!r.ok) { await db.rpc("release_credits", { p_job: jobId }); return new Response("upstream", { status: 502 }); }
  const q = await r.json();                  // { request_id, status_url, response_url, cancel_url, ... }
  await db.from("jobs").insert({ id: jobId, user_id: user.id, op: body.op, endpoint: op.endpoint,
                                 cost: op.cost, fal_request_id: q.request_id, status: "queued" });
  return Response.json({ jobId });
});
```

```ts
// supabase/functions/fal-webhook/index.ts — Ed25519 verification (per fal docs; confirm encoding on the docs page)
let cache: { keys: CryptoKey[]; at: number } | null = null;
async function falKeys() {
  if (cache && Date.now() - cache.at < 6 * 3_600_000) return cache.keys;           // docs: never cache > 24h
  const { keys } = await (await fetch("https://rest.fal.ai/.well-known/jwks.json")).json();
  const k = await Promise.all(keys.map((j: { x: string }) => crypto.subtle.importKey(
    "jwk", { kty: "OKP", crv: "Ed25519", x: j.x }, { name: "Ed25519" }, false, ["verify"])));
  cache = { keys: k, at: Date.now() }; return k;
}
const hex = (b: ArrayBuffer) => [...new Uint8Array(b)].map(x => x.toString(16).padStart(2, "0")).join("");
const unhex = (s: string) => new Uint8Array(s.match(/../g)!.map(h => parseInt(h, 16)));
Deno.serve(async (req) => {
  const h = (n: string) => req.headers.get(n);
  const [rid, uid, ts, sig] = ["x-fal-webhook-request-id", "x-fal-webhook-user-id",
                               "x-fal-webhook-timestamp", "x-fal-webhook-signature"].map(h);
  if (!rid || !uid || !ts || !sig) return new Response("missing", { status: 400 });
  if (Math.abs(Date.now() / 1000 - Number(ts)) > 300) return new Response("stale", { status: 400 });
  const raw = new Uint8Array(await req.arrayBuffer());                      // hash RAW bytes before JSON.parse
  const msg = new TextEncoder().encode([rid, uid, ts, hex(await crypto.subtle.digest("SHA-256", raw))].join("\n"));
  const ok = (await Promise.all((await falKeys()).map(k => crypto.subtle.verify("Ed25519", k, unhex(sig), msg)))).some(Boolean);
  if (!ok || uid !== Deno.env.get("FAL_USER_ID")) return new Response("bad sig", { status: 401 });
  const evt = JSON.parse(new TextDecoder().decode(raw));                    // { request_id, status, payload, error? }
  // idempotent: update jobs where fal_request_id = evt.request_id and status = 'queued'
  // OK  → run output moderation (e.g. fal-ai/x-ailab/nsfw) → set result_url/result_expires_at → capture
  // ERROR or flagged → status='failed' → release_credits(job)
  return new Response("ok");
});
```

### 3.9 Rough cost per active user

Unit costs used (see §1 tags):
- NB2 1K about **$0.067** [R]. Assume about $0.07 on fal [U].
- NB2 Lite about $0.034 [R].
- Seedream 5 Lite about $0.035 [R].
- Server upscale or erase about $0.01–0.05 [U].
- On-device cut-out and enhance cost $0.

**Blended cost per operation** for a paid user:

| Mix | Share | Unit | Contribution |
|---|---|---|---|
| Prompt edits (NB2) | 40% | $0.070 | $0.028 |
| Templates (NB2/Seedream) | 20% | $0.070 | $0.014 |
| Text→image (NB2 Lite/NB2) | 15% | $0.034 | $0.005 |
| Upscale/restore | 10% | $0.030 | $0.003 |
| Background removal (device) | 10% | $0 | $0 |
| Erase | 5% | $0.040 | $0.002 |
| **Subtotal** | | | **≈ $0.052** |
| + retries, regenerations, safety-blocked calls that still bill (+15%) [U] | | | **≈ $0.06 per op** |

**Infrastructure** at MVP scale, using Supabase Pro ($25/mo base + compute) [V for unit prices]:
- About 5–10 function invocations per op (create, webhook, a few polls). With 2M included, that covers roughly 200k–400k ops per month; above that it is $2/M, about **$0.00001–0.00002 per op**.
- Storage: inputs purged within 24 h, outputs kept 0–30 days at about 1.5 MB each, so about $0.001 per paid user per month at $0.0213/GB-mo [V]. Egress is not verified [U].
- App Attest and DeviceCheck are free.
- **Total infrastructure ≲ $0.01 per MAU** at 10k–100k MAU.

| Persona / month | Ops | AI cost | Infra | Total | Comment |
|---|---|---|---|---|---|
| Free (NB2 Lite, 3 ops) | 3 | $0.10 | <$0.01 | **≈ $0.11** | Gate with DeviceCheck and appTransactionID |
| Light subscriber | 30 | $1.80 | ~$0.01 | **≈ $1.8** | |
| Heavy subscriber | 150 | $9.00 | ~$0.03 | **≈ $9** | Must be capped by the allowance |
| Abuser (uncapped) | 1000+ | $60+ | — | — | Prevented by credits, rate limits and App Attest |

**Revenue side.**
- Apple's commission is 15% (Small Business Program / year-2 subscriptions) or 30% [U standard rates]. EU terms change from 1 Oct 2026 [V].
- **Rule of thumb:** monthly allowance × worst-case $/op ≤ about 50% of net subscription revenue. For example, at $9.99/mo with 15% commission (net about $8.49), allow ≤60 NB2-class ops (≈$4.2 worst case).
- Charge premium models (NB Pro, GPT Image 2.5 high/max, 4K) at 3–5× credits.

---

## 4. On-device Apple frameworks

### 4.1 Vision subject lift and background removal (iOS 17+) [V]

```swift
import Vision
import CoreImage

/// Returns the image with everything except the chosen instances made transparent.
func liftSubject(_ cgImage: CGImage, orientation: CGImagePropertyOrientation = .up) throws -> CIImage? {
    let request = VNGenerateForegroundInstanceMaskRequest()                 // iOS 17 / macOS 14
    let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation)
    try handler.perform([request])
    guard let obs = request.results?.first else { return nil }             // nil → no salient subject
    let buffer = try obs.generateMaskedImage(ofInstances: obs.allInstances, // or one instance picked by tap
                                             from: handler,
                                             croppedToInstancesExtent: false)
    return CIImage(cvPixelBuffer: buffer)
    // Mask only (e.g. to build an erase mask): obs.generateScaledMaskForImage(forInstances:from:)
    // Hit-testing a tap: read obs.instanceMask (label per pixel) at the tapped point.
}
```

On iOS 18+ you can use the Swift-native `GenerateForegroundInstanceMaskRequest` (async `perform(on:)`) [V].

### 4.2 Core Image auto-enhance and filters [V]

```swift
func autoEnhance(_ input: CIImage) -> CIImage {
    input.autoAdjustmentFilters(options: [.redEye: false]).reduce(input) { img, filter in
        filter.setValue(img, forKey: kCIInputImageKey)
        return filter.outputImage ?? img
    }
}
```

- Options: `.enhance`, `.redEye`, `.features`, `.crop`, `.level` [U exact set; standard keys]. Pass `.features` / orientation for face-aware filters [V doc note].
- Other useful built-ins: `CIFilter.personSegmentation` (iOS 15), `CILanczosScaleTransform` (resize before upload), `CIHighlightShadowAdjust` [U availability details].
- **Super-resolution on device:** VideoToolbox `VTSuperResolutionScalerConfiguration(frameWidth:frameHeight:scaleFactor:inputType: .image, …)` on **iOS 26+**. Check `isSupported`, `supportedScaleFactors` and `configurationModelStatus`, and download the model with user awareness [V].

### 4.3 Image Playground `ImageCreator` (programmatic, iOS 18.4+) [V]

```swift
import ImagePlayground

@available(iOS 18.4, *)
func generateOnDevice(_ prompt: String) async -> [CGImage] {
    do {
        let creator = try await ImageCreator()                     // throws ImageCreator.Error.notSupported on ineligible devices
        guard let style = creator.availableStyles.first else { return [] }   // .animation / .illustration / .sketch (+ .emoji)
        var out: [CGImage] = []
        for try await image in creator.images(for: [.text(prompt)], style: style, limit: 2) {   // system max 4
            out.append(image.cgImage)
        }
        return out
    } catch { return [] }   // .unavailable, .creationCancelled, .unsupportedLanguage, .faceInImageTooSmall,
                            // .unsupportedInputImage, .backgroundCreationForbidden (must be foreground), .creationFailed
}
```

- **Capabilities.**
  - Styles are animation, illustration, sketch and emoji (iOS 18.4).
  - `externalProvider` (iOS 26) generates images in a style from an external provider (the ChatGPT integration) [V symbol; provider identity U].
  - `any` (iOS 27) infers the style from the prompt [V].
  - Concepts: `.text`, `.extracted(from:title:)`, `.drawing`, `.image` [V].
  - `ImagePlaygroundOptions` (iOS 26.4): `creationVariety`, `personalization`; `sizeSpecification.closest(to:)` and `creationStrategy` (`editExisting` / `generateNew`) need **iOS 27** [V].
  - New error `conceptsRequirePersonIdentity` (iOS 26) [V].
- **Limits.**
  - The device must support Apple Intelligence: iPhone 15 Pro and later, M-series / A17 Pro iPads, M-series Macs [U list]. Apple Intelligence must be enabled, in a supported language and region.
  - Generation must run in the **foreground** [V].
  - Output is stylised, not photoreal, so it is not a replacement for (a). Use it as a **free / offline "fun" tier**.
  - There is no server cost, but no IPTC/C2PA marking is added by you automatically [U]. Mark exports yourself.

### 4.4 Foundation Models (on-device LLM, iOS 26+) for prompt enhancement [V]

```swift
import FoundationModels

@available(iOS 26.0, *)
@Generable
struct EditPlan {
    @Guide(description: "Precise, self-contained instruction for an image-editing model. Preserve identity, pose, lighting and background unless the user asks otherwise.")
    var instruction: String
    @Guide(description: "true if the request involves nudity, sexual content, minors, violence, weapons or a real public figure")
    var needsReview: Bool
}

@available(iOS 26.0, *)
func enhance(_ userText: String) async throws -> EditPlan? {
    let model = SystemLanguageModel.default
    switch model.availability {
    case .available: break
    case .unavailable(.deviceNotEligible), .unavailable(.appleIntelligenceNotEnabled), .unavailable(.modelNotReady):
        return nil                                                            // fall back to server-side rewriting
    case .unavailable: return nil
    }
    let session = LanguageModelSession(instructions: """
        Rewrite short photo-edit requests into one clear English instruction for an image model. \
        Never add sexual or violent content.
        """)
    return try await session.respond(to: userText, generating: EditPlan.self).content
}
```

- **Facts [V]:**
  - `UnavailableReason` = `deviceNotEligible`, `appleIntelligenceNotEnabled`, `modelNotReady`.
  - There are three model versions: 26.0–26.3, 26.4 and 27.0. Re-test prompts after OS updates.
  - `Guardrails` has `.default` and `.permissiveContentTransformations`; errors include `guardrailViolation`.
  - `contextSize` is back-deployed to 26.4.
- **iOS 27 additions [V]:**
  - **Image attachments** (multimodal prompts: `Attachment(cgImage)`). The on-device model can *look at the photo* to write better edit instructions or pre-screen content.
  - `PrivateCloudComputeLanguageModel` needs a **managed entitlement** (`com.apple.developer.private-cloud-compute`).
  - Dynamic profiles and custom model providers.
- **Acceptable-use requirements [V].** They prohibit using the framework for adult/sexual content, CSAM, biometric classification for sensitive attributes, IP/publicity-rights infringement, and "removing watermarks or other content credentials … to label content as AI-generated".
- The on-device check is advisory. **Always re-check on the server** (a client can be modified).

### 4.5 Sensitive Content Analysis: useful but not a universal NSFW gate [V]

- `SCSensitivityAnalyzer` (iOS 17) detects nudity **only if** the user enabled Sensitive Content Warning or Communication Safety (`analysisPolicy != .disabled`). It requires the entitlement `com.apple.developer.sensitivecontentanalysis.client`. The June 2026 Developer Program License Agreement (DPLA) clarified its usage terms [V].
- Use it to blur results for users who opted in (for example teens). Use server-side moderation for everyone.

### 4.6 SDK and Xcode matrix

| Feature | Min OS | SDK / Xcode |
|---|---|---|
| Vision `VNGenerateForegroundInstanceMaskRequest` | iOS 17 | iOS 17 SDK (Xcode 15+) |
| Vision `GenerateForegroundInstanceMaskRequest` (Swift API) | iOS 18 | Xcode 16+ |
| Core Image `autoAdjustmentFilters` | iOS 5 | any |
| VideoToolbox super-resolution (`.image`) | iOS 26 | Xcode 26 |
| `ImageCreator` | iOS 18.4 | iOS 18.4 SDK (Xcode 16.3 [U]) |
| `ImagePlaygroundOptions` variety / personalization | iOS 26.4 | Xcode 26.4 [U] |
| Image Playground `sizeSpecification`, `creationStrategy`, style `.any` | iOS 27 | Xcode 27 |
| Foundation Models (text) | iOS 26 | Xcode 26 |
| Foundation Models image attachments, PCC model | iOS 27 | Xcode 27 (PCC entitlement) |
| App Attest | iOS 14 | — |
| `AppTransaction.appTransactionID` | iOS 16 (back-deployed) | Xcode 16.3+ [U] |
| **App Store upload requirement** | — | **Since 28 Apr 2026: iOS 26 SDK**. **From Apr 2027: iOS 27 SDK.** Xcode 27 RC available since 9 Sep 2026 [V: Apple news] |

Practical setup: deployment target iOS 17, built with Xcode 27 (iOS 27 SDK), with `if #available(iOS 26, *)` / `(iOS 27, *)` gates.

---

## 5. App Store Review Guidelines relevant to AI photo apps

The guidelines page shows **"Last Updated: June 8, 2026"** [V]: https://developer.apple.com/app-store/review/guidelines/

| Rule | What it says (quoted or condensed) [V] | What to do |
|---|---|---|
| **5.1.2(i)** (revised 13 Nov 2025 [V news]) | "You must clearly disclose where personal data will be shared with third parties, **including with third-party AI**, and obtain **explicit permission** before doing so." | Before the first upload, show a consent sheet. Name the processors (fal.ai and the model vendors, e.g. Google, OpenAI, ByteDance), what is sent (the photo, prompt), why, and retention. Add an explicit "Agree" button (not pre-checked), a link to the privacy policy, and a way to withdraw (5.1.1(ii)). Re-prompt when you add a new vendor. Keep on-device features usable without consent. |
| 5.1.1(i)–(iii) | Privacy policy covering data, third parties and retention/deletion. Consent for collection. Data minimisation; "use the out-of-process picker". | Use `PhotosPicker` (no library permission needed); request only `NSPhotoLibraryAddUsageDescription` for saving. Strip GPS EXIF before upload. |
| 5.1.2(vi) | Data from "facial mapping tools (e.g. … Camera APIs, or Photo APIs) may not be used for marketing, advertising or use-based data mining". | Never reuse user photos or faces for ads, analytics or training. |
| **1.1** Objectionable | 1.1.1 defamatory/mean-spirited; 1.1.4 "Overtly sexual or pornographic material"; 1.1.6 false information / trick functionality. | Block sexual content and harassment edits (for example "make her look fat", "put X in jail"). Satirical public-figure edits are risky; block them by default. |
| **1.2** UGC | Requires filtering objectionable material, a report mechanism with timely response, blocking abusive users, and published contact info. **June 2026: new paragraph** — "It is your responsibility to remove content that violates this guideline…" Apple may require a compliance plan, then removal [V]. Feb 2026: random or anonymous chat is explicitly in scope [V]. | Even without a social feed, generative output is often treated like UGC in review [U]. Ship a prompt/output filter, a **"Report this image"** button, a user ban mechanism and a support contact. If you add sharing or a feed, implement full 1.2 (and the TAKE IT DOWN Act, §6.4). |
| **4.3 Spam** (clarified 8 Jun 2026 with examples [V]) | (a) no duplicate bundle IDs; (b) "Don't submit apps that are indistinguishable from what's already widely available… we will not accept new submissions unless they offer a meaningfully different or improved experience." | Many AI photo apps look alike. Differentiate (on-device features, a unique template system, quality), avoid template-farm clones, and describe what is unique in Review Notes. |
| **4.1(c)** (Nov 2025) and **2.3.7** | You cannot use another developer's icon, brand or product name in your icon or name without approval. Don't pack metadata with trademarked terms. | Don't call the app "Nano Banana …", "ChatGPT …" or "Gemini …", or use their logos. In the description, "powered by" mentions only if accurate and permitted. |
| 5.2.1 IP | No unlicensed third-party IP. | No "Ghibli / Pixar / Disney style" templates; no celebrity templates. |
| **3.1.1** IAP | Digital features need IAP. "Any credits … purchased via in-app purchase **may not expire**"; provide restore. | Credit packs are consumables that never expire. Subscription allowances reset monthly; label them as "N generations per month". Provide Restore Purchases. |
| **3.1.2** Subscriptions | (a) ≥7-day period, works across the user's devices, no tricks (scams removed); (c) "Before asking a customer to subscribe, you should clearly describe what the user will get for the price" + **Schedule 2** disclosures. | The paywall must show the subscription name, duration, **price per period** (and trial terms with what happens after), what is included (e.g. "100 edits/month, 4K export"), auto-renew wording, **Terms (EULA) and Privacy links**, a restore button and a visible close. Avoid a fake-discount "anchor" price [U enforcement]. `SubscriptionStoreView` handles much of this. |
| **Age rating** (system since 24 Jul 2025; responses required by **31 Jan 2026**) [V] | Ratings 4+, 9+, **13+, 16+, 18+**. New questions on in-app controls, **capabilities**, medical/wellness and violent themes. Apple: "consider how all app features, **including AI assistants and chatbot functionality**, impact the frequency of sensitive content." Social media capability questions were **required from Sep 2026** [V]. | With strict NSFW blocking, aim for 13+ or 16+ and answer honestly. **Avoid 18+**: from 24 Feb 2026 Apple blocks 18+ downloads in Australia, Brazil and Singapore unless the user is age-confirmed [V]. |
| Age-assurance laws [V Apple news] | Texas SB 2420 applies to new Texas Apple Accounts **from 4 Jun 2026**; Utah from 6 May 2026; Louisiana from 1 Jul 2026. Tools: Declared Age Range API, Significant Change API (PermissionKit), StoreKit age-rating property, consent-revocation server notification. | Integrate the **Declared Age Range API**. Disable person-editing templates (or apply a stricter policy) for under-18 users. Handle consent revocation. |
| **Privacy manifest / required-reason APIs** (enforced since **1 May 2024**) [V] | `NSPrivacyAccessedAPITypes` entries are needed for: **UserDefaults → `CA92.1`** (app-only) or `1C8F.1` (App Group); file timestamps → `C617.1` (own container) or `3B52.1` (user-picked files) or `DDA9.1` (display only); disk space → `E174.1`; boot time → `35F9.1`; active keyboards → `54BD.1`. | Also declare `NSPrivacyCollectedDataTypes`: `NSPrivacyCollectedDataTypePhotosorVideos` (App Functionality), `…UserID`, `…PurchaseHistory`, `…OtherUserContent` (prompts), `…CrashData`. Set `NSPrivacyTracking` = false. Every third-party SDK must bring its own manifest. |
| **4.8 Login Services** | Using a third-party/social login for the primary account requires an equivalent option that limits data to name and email, allows a private email, and doesn't track. | Anonymous-first plus Sign in with Apple needs nothing more. If you add Google login, keep Sign in with Apple. |
| 5.1.1(v) | Allow use without login when there are no significant account features; offer **in-app account deletion** if accounts exist. | — |
| Developer Program License Agreement §3.3.11(A) (Jun 2026) | Updated requirements for the Foundation Models framework; acceptable-use page [V]. | Follow the AUP in §4.4. |

**Deepfake, likeness and NSFW moderation approach (layered):**

1. **Policy.** Terms of service: users must own or have consent for the photos they upload. No sexual content; no nudity or "undress"; no minors in suggestive edits; no impersonation, harassment or political deception; no real public figures in deceptive contexts.
2. **Input checks.**
   - Prompt filter: a blocklist plus classifier (on-device FM `needsReview` as an advisory signal, and a server LLM or moderation model).
   - Optional check on the uploaded photo (NSFW detector: `fal-ai/imageutils/nsfw` / `fal-ai/x-ailab/nsfw`).
   - Optional minor-likelihood check before person-editing templates [U accuracy].
3. **Model-level.** Keep `enable_safety_checker` on and use strict `safety_tolerance` (Gemini "2", FLUX "2"); OpenAI `moderation:"auto"` [V params].
4. **Output check.** An NSFW classifier on every output before delivery. Release credits on a block.
5. **Product.** "Report this image", user ban (user + device + appTransactionID), a human review queue, and an abuse email. Keep flagged-event metadata (hashes, not images) for 90 days [U suggestion].
6. **Provenance.** Embed AI disclosure (§6.2). Never offer watermark or credential removal.

---

## 6. Regulation

### 6.1 EU AI Act, Article 50, plus the July 2026 amendments [V]

- **Article 50(2)** (Regulation (EU) 2024/1689) [V]: "Providers of AI systems … generating synthetic audio, image, video or text content, shall ensure that the outputs … are **marked in a machine-readable format and detectable as artificially generated or manipulated**." Solutions must be "effective, interoperable, robust and reliable as far as … technically feasible."
  - **Exemption:** systems that "perform an assistive function for standard editing or do not substantially alter the input data". This plausibly covers auto-enhance, crop, background cut-out and non-generative upscale.
- **Article 50(4)** [V]: *deployers* of deep fakes must disclose that content is AI-generated or manipulated, with a lighter regime for evidently artistic or satirical work.
  - Your end users are deployers only when acting professionally. Art. 3(4) defines a deployer as someone using an AI system "except where the AI system is used in the course of a personal non-professional activity" [V].
  - Make disclosure easy: offer an optional visible "AI-edited" label on export.
- **Article 50(5)** [V]: information must be given "at the latest at the time of the first interaction or exposure" and be accessible.
- **Dates.**
  - Article 50 applies from **2 Aug 2026** (Art. 113 general date) [V].
  - **Regulation (EU) 2026/1744 of 8 Jul 2026** (OJ 24 Jul 2026, the "Digital Omnibus" amendment) [V] adds Art. 111(4): systems **placed on the market before 2 Aug 2026** must comply with Art. 50(2) by **2 Dec 2026**.
  - **A new app launching now is covered from launch.**
- **Who is the provider?** Art. 3(3) defines a provider as a person who "develops an AI system … or that has an AI system … developed and places it on the market or puts the AI system into service **under its own name or trademark**" [V]. Your app plus server pipeline, offered under your brand, fits that even though it wraps third-party models. Treat yourself as the **provider** for Art. 50(2) [U legal interpretation; get counsel].
- **Code of Practice** (Art. 50(7), as amended by 2026/1744 [V]): the Commission now assesses whether codes are adequate (no implementing-act approval), and can adopt common rules if they are not. Whether the code on marking and labelling is final in Oct 2026 was not verified [U]. Monitor it, because it will define "state of the art" (metadata plus watermark plus fingerprinting/logging).
- **NEW prohibited practice: Art. 5(1)(ba)/(bb), applicable from 2 Dec 2026** [V: 2026/1744].
  - Prohibited: AI systems that generate or manipulate **realistic images … of an identifiable natural person's intimate parts or … sexually explicit activities without … explicit consent**, and CSAM.
  - For providers, the ban covers systems whose "intended purpose" is this, **or** where such output is a "reasonably foreseeable and reproducible outcome … and the system does not have reasonable and adequate technical safety measures … to reliably prevent" it, taking misuse into account and "to correct observed or reported misuse" (Art. 5(1a)).
  - **Directly relevant to a prompt-based editor of real-person photos:** your layered safeguards in §5 are your compliance evidence. Document them; keep red-team test logs.
- **Penalties (Art. 99):** prohibited practices (Art. 5) up to **€35M or 7%** of worldwide turnover [V, Art. 99(3)]. Other operator obligations up to **€15M or 3%** [V, Art. 99(4)]. That Art. 50 sits in the 99(4) list is [U]; the list was truncated in the excerpt. 2026/1744 adds SME/SMC fine caps [V].

### 6.2 Machine-readable marking in practice: IPTC, C2PA and watermarks

1. **IPTC DigitalSourceType (XMP `Iptc4xmpExt:DigitalSourceType`)**. Values [V: c2pa-rs `actions.rs` mirrors the IPTC vocabulary]:
   - `http://cv.iptc.org/newscodes/digitalsourcetype/trainedAlgorithmicMedia` — fully generated (text→image, full restyles).
   - `…/compositeWithTrainedAlgorithmicMedia` — "Augmentation, correction or enhancement using a Generative AI model, such as with inpainting or outpainting". Use it for prompt edits, object removal, templates on a user photo, and generative upscale or face restoration.
   - `…/algorithmicallyEnhanced` — "Modification or correction by algorithm without changing the main content", e.g. sharpening or noise reduction. Use it for auto-enhance and ESRGAN.
   - (`minorHumanEdits`, `softwareImage` and `digitalArt` are deprecated in the IPTC vocabulary [V].)
2. **C2PA manifest** (signed provenance; spec **v2.4** referenced by c2pa-rs [V]).
   - Actions `c2pa.created` (new asset) or `c2pa.opened` + `c2pa.edited` with `digitalSourceType` [V: c2pa-swift README].
   - iOS SDK: **`contentauth/c2pa-swift`**, formerly c2pa-ios (iOS 16+, Secure Enclave signing, Builder/Reader APIs) [V].
   - Signing needs an X.509 certificate. A self-signed certificate shows as an untrusted signer, so for production obtain a certificate from a CA on the C2PA trust list [U process].
   - It is simpler to sign **server-side** with c2pa-rs / c2pa-node.
   - When re-encoding, **don't drop upstream credentials**. Keep the original bytes or add the upstream asset as an ingredient [U]. Google adds SynthID to Gemini images and OpenAI adds C2PA to GPT image outputs [U for current models].
3. **Invisible watermark** for robustness, because metadata is stripped by many share targets.
   - Provider watermarks (SynthID) survive re-encoding [U].
   - For other models consider **Adobe TrustMark** (open source CAI watermark; Python, Rust and JS decode) [V repo] and reference it in the C2PA manifest.
4. **Save path.** Write the encoded `Data` (with XMP) via `PHAssetCreationRequest.addResource(with: .photo, data:)`. Saving a `UIImage` drops metadata [U].

**Swift sketch: ImageIO XMP (IPTC Extension namespace constants are built in since iOS 11.3 [V])**

```swift
import ImageIO
import UniformTypeIdentifiers

enum DigitalSource: String {
    case trainedAlgorithmicMedia, compositeWithTrainedAlgorithmicMedia, algorithmicallyEnhanced
    var uri: String { "http://cv.iptc.org/newscodes/digitalsourcetype/\(rawValue)" }
}

/// Encodes `image` as JPEG with AI-provenance XMP. Use the result for share/save/export (all paths).
func encodeWithAIProvenance(_ image: CGImage, source: DigitalSource,
                            creatorTool: String = "MyApp 1.0 (fal-ai/nano-banana-2)") -> Data? {
    let md = CGImageMetadataCreateMutable()
    // Register defensively; standard namespaces usually need no registration (Apple doc) — ignore the Bool.
    _ = CGImageMetadataRegisterNamespaceForPrefix(md, kCGImageMetadataNamespaceIPTCExtension,
                                                  kCGImageMetadataPrefixIPTCExtension, nil)
    let ext = kCGImageMetadataPrefixIPTCExtension as String                 // "Iptc4xmpExt"
    guard CGImageMetadataSetValueWithPath(md, nil, "\(ext):DigitalSourceType" as CFString, source.uri as CFString),
          CGImageMetadataSetValueWithPath(md, nil, "xmp:CreatorTool" as CFString, creatorTool as CFString)
    else { return nil }
    let data = NSMutableData()
    guard let dest = CGImageDestinationCreateWithData(data as CFMutableData, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
    CGImageDestinationAddImageAndMetadata(dest, image, md,
        [kCGImageDestinationLossyCompressionQuality: 0.92] as CFDictionary)
    return CGImageDestinationFinalize(dest) ? data as Data : nil
}
// To add tags to an existing file without re-encoding: CGImageDestinationCopyImageSource(dest, src,
//   [kCGImageDestinationMetadata: md, kCGImageDestinationMergeMetadata: true] as CFDictionary, nil)  [V]
```

**Swift sketch: C2PA via c2pa-swift (API per README [V]; production certificate and key handling are up to you)**

```swift
import C2PA
let manifest = """
{ "claim_generator": "MyApp/1.0", "format": "image/jpeg",
  "assertions": [ { "label": "c2pa.actions", "data": { "actions": [
     { "action": "c2pa.created",
       "digitalSourceType": "http://cv.iptc.org/newscodes/digitalsourcetype/trainedAlgorithmicMedia" } ] } } ] }
"""
let signer = try Signer(info: SignerInfo(algorithm: .es256, certificatePEM: certPEM, privateKeyPEM: keyPEM, tsaURL: nil))
let builder = try Builder(manifestJSON: manifest)
_ = try builder.sign(format: "image/jpeg", source: try Stream(data: jpegData),
                     destination: try Stream(fileURL: outURL), signer: signer)
```

### 6.3 GDPR: face photos and data retention

- **Are face photos special-category data?** Photographs are biometric data **only when** "processed through a specific technical means allowing the unique identification or authentication of a natural person" (Recital 51; Art. 4(14)) [V].
  - Editing, restoring or stylising a face is generally **not** identification.
  - Avoid building or storing face embeddings or templates, face matching or "find this person" features. Otherwise you trigger Art. 9 (explicit consent) [V Art. 9] and, in the US, BIPA-style laws [U].
- **Roles and contracts.** You are the controller. fal and the model vendors are processors or sub-processors (Art. 28 DPAs, sub-processor list). US transfers need the EU-US Data Privacy Framework or SCCs [U per vendor]. If you have no EU establishment, appoint an Art. 27 representative [U].
- **Lawful basis.** Contract (Art. 6(1)(b)) to perform the requested edit, plus the **explicit 5.1.2(i) consent screen** for third-party AI sharing (an Apple requirement). Do not use photos for training. Run a DPIA (large-scale processing of images of people with novel technology) [U recommendation].
- **Third parties and minors.** The terms must require rights or consent for other people in photos. Apply extra safeguards for minors; Art. 8 digital-consent age is 13–16 depending on member state [U]. Use the Declared Age Range API to adapt.

**Recommended retention policy:**

| Data | Retention |
|---|---|
| Original uploads (your Storage) | Delete on job completion; hard TTL **24 h** (cron purge) |
| Provider side | fal output expiry 1 h via header; `X-Fal-Store-IO: 0` (no 30-day I/O history) [V/R]. Direct vendors: enable zero/short retention where available [U] |
| Outputs (server copy, if any) | 0 days by default (history on device / iCloud). Opt-in cloud history ≤30 days, deletable |
| Prompts | Store hashed or truncated for abuse analytics ≤30 days. Flagged items: metadata + hashes ≤90 days (legal hold exception) |
| Account, ledger, purchases | Lifetime of the account. Purchase records kept per tax/accounting law [U]. Delete or anonymise everything else on account deletion |
| Logs | ≤30 days, no image URLs that don't expire |

### 6.4 United States (state and federal)

- **TAKE IT DOWN Act** (S.146, enrolled) [V text]:
  - Federal crimes for knowingly publishing non-consensual intimate depictions, including AI "digital forgeries".
  - **Covered platforms** (public sites and apps that "primarily provide a forum for user-generated content") must provide a notice-and-removal process and remove within **48 hours** of a valid request. The process was due within 1 year of enactment; enactment was 19 May 2025 [U date], so the process was due by about May 2026. Enforced by the FTC.
  - A private editor without public sharing is likely not "covered" [U]. Adding a feed changes that.
- **California AI Transparency Act** (Bus. & Prof. Code §22757 et seq.; SB 942 as amended by AB 853), **operative 2 Aug 2026** [V]:
  - "Covered provider" = a GenAI system with **over 1,000,000 monthly visitors or users**, publicly accessible in California.
  - It must offer a **manifest** (visible) disclosure option and embed a **latent disclosure**: provider name, system name and version, creation/alteration time, unique ID; detectable, consistent with industry standards, hard to remove. It must also provide a free AI-detection tool [U, from §22757.2 not fetched].
  - Not applicable at launch, but design for it (C2PA covers the latent fields).
- **Washington ESHB 1170** (Ch. 167, Laws of 2026), **effective 1 Feb 2027** [V]:
  - Covered providers with over 1M monthly users must embed provenance data in content created or **materially altered**.
  - **C2PA is deemed compliant.**
  - Brightness/contrast/filters/resizing/denoising are not material, and **systems used solely for upscaling, noise reduction or compression are excluded**.
  - AG enforcement under the CPA.
- **Age assurance:** Texas SB 2420 (from 4 Jun 2026 for new accounts), Utah, Louisiana; see §5 [V Apple news].
- **Biometric privacy:** Illinois BIPA (740 ILCS 14) covers "scan of face geometry" with written release, retention schedule and a private right of action; Texas CUBI and Washington have similar laws. Avoid face templates and recognition [U, not re-fetched].
- **Right of publicity / digital replicas** (state laws such as Tennessee's ELVIS Act; the federal NO FAKES bill status is unverified) [U]: avoid celebrity and "real person" templates and impersonation.

---

## 7. Open items to confirm before build or launch

1. fal per-image prices for NB2 / NB2-edit, Seedream 5, Ideogram v4, Recraft v4, and **all utility endpoints** (BiRefNet, Bria RMBG, SeedVR2, ESRGAN, CodeFormer, object-removal, Bria eraser, FLUX erase, Finegrain). Check the model pages or your fal dashboard [U].
2. Exact webhook signature message encoding (hex of SHA-256 of the raw body?) on fal's webhooks page [R].
3. `X-Fal-Store-IO` header scope (queue vs sync) and the default CDN media retention [R].
4. Whether OpenAI and Google outputs delivered via fal still carry C2PA/SynthID after fal's re-encoding (`output_format`) [U].
5. App Store Server Library running under Supabase Edge (Deno npm compatibility) [U]. Otherwise use `jose` plus chain validation.
6. RevenueCat pricing (if used), Vercel limits, Supabase egress price [U].
7. Final status of the EU Code of Practice on marking and labelling, and any Commission guidelines on Art. 50 [U].
8. Measure p50 and p95 latency per endpoint from your region. All latency figures here are indicative [U].

---

## 8. Sources

**Official / primary (fetched during this research):**
- fal client package with generated endpoint types: https://registry.npmjs.org/@fal-ai/client (1.11.0-alpha.5, `src/types/endpoints.d.ts`, `queue.js`, `request.js`, `storage.js`, `backup-domain.js`); proxy README https://github.com/fal-ai/fal-js/blob/main/libs/proxy/README.md; Swift client https://github.com/fal-ai/fal-swift
- OpenAI OpenAPI spec: https://github.com/openai/openai-openapi (`master/openapi.yaml`: CreateImageEditRequest, CreateImageRequest, InputFidelity, Image)
- Google GenAI SDK: https://github.com/googleapis/python-genai (README model `gemini-3.1-flash-lite-image`; `types.py` ImageConfig)
- Replicate JS client README: https://github.com/replicate/replicate-javascript
- Supabase docs source: https://github.com/supabase/supabase/tree/master/apps/docs/content (functions/limits.mdx; manage-your-usage/edge-function-invocations.mdx; _partials/billing/pricing/*; auth/auth-anonymous.mdx; functions/examples/rate-limiting.mdx)
- Cloudflare docs source: https://github.com/cloudflare/cloudflare-docs (workers/platform/pricing.mdx, limits.mdx, runtime-apis/bindings/rate-limit.mdx, r2/pricing.mdx)
- Apple App Review Guidelines (Last Updated 8 Jun 2026): https://developer.apple.com/app-store/review/guidelines/
- Apple developer news (RSS): https://developer.apple.com/news/ — items `?id=ey6d8onl` (Nov 2025 guidelines), `?id=d75yllv4` (Feb 2026), `?id=a233fmpw` (Jun 2026 DPLA + guidelines), `?id=ks775ehf` (age ratings), `?id=tlur8uvi` (social media questions), `?id=f5zj08ey` and `?id=sg176nne` (age assurance), `?id=ueeok6yw` and `?id=k1mtkt1k` (SDK minimums, Xcode 27), `?id=likeohx4`, `?id=agq42lxe`, `?id=gmws0jgp`, `?id=1ptvdtcm`
- Apple docs: DeviceCheck/App Attest https://developer.apple.com/documentation/devicecheck/validating-apps-that-connect-to-your-server, …/establishing-your-app-s-integrity, …/assessing-fraud-risk, …/dcdevice; Vision https://developer.apple.com/documentation/vision/vngenerateforegroundinstancemaskrequest; Core Image https://developer.apple.com/documentation/coreimage/ciimage/autoadjustmentfilters(options:); Image Playground https://developer.apple.com/documentation/imageplayground/imagecreator; Foundation Models https://developer.apple.com/documentation/foundationmodels and …/systemlanguagemodel, …/privatecloudcomputelanguagemodel, …/attachment, …/analyzing-images-with-multimodal-prompting; VideoToolbox https://developer.apple.com/documentation/videotoolbox/vtsuperresolutionscalerconfiguration; Sensitive Content Analysis https://developer.apple.com/documentation/sensitivecontentanalysis; ImageIO https://developer.apple.com/documentation/imageio (CGImageMetadataSetValueWithPath, kCGImageMetadataNamespaceIPTCExtension, kCGImageDestinationMergeMetadata); StoreKit https://developer.apple.com/documentation/storekit/apptransaction/apptransactionid, …/product/purchaseoption/appaccounttoken(_:); App Store Server API https://developer.apple.com/documentation/appstoreserverapi; Notifications https://developer.apple.com/documentation/appstoreservernotifications/notificationtype; Required-reason API https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api; FM acceptable use https://developer.apple.com/support/terms/acceptable-use-requirements-for-the-foundation-models-framework
- Apple App Store Server Library (Node): https://github.com/apple/app-store-server-library-node
- EU AI Act Art. 50: https://eur-lex.europa.eu/legal-content/EN/TXT/?uri=CELEX:32024R1689; amending Regulation (EU) 2026/1744: https://eur-lex.europa.eu/legal-content/EN/TXT/?uri=CELEX:32026R1744; GDPR (Art. 4(14), Art. 9, Recital 51): https://eur-lex.europa.eu/legal-content/EN/TXT/?uri=CELEX:32016R0679
- TAKE IT DOWN Act (enrolled S.146): https://www.govinfo.gov/bulkdata/BILLS/119/1/s/BILLS-119s146enr.xml
- California AI Transparency Act: https://leginfo.legislature.ca.gov/faces/codes_displaySection.xhtml?lawCode=BPC&sectionNum=22757.1. (also §22757, §22757.3)
- Washington ESHB 1170 (Ch. 167, Laws of 2026): http://lawfilesext.leg.wa.gov/biennium/2025-26/Htm/Bills/Session%20Laws/House/1170-S2.SL.htm
- C2PA: https://github.com/contentauth/c2pa-swift (README), https://github.com/contentauth/c2pa-rs (`sdk/src/assertions/actions.rs`); TrustMark https://github.com/adobe/trustmark
- npm metadata: @apple/app-store-server-library 3.1.0, jose 6.2.12, @upstash/ratelimit 2.2.0, appattest-checker-node 1.0.3, node-app-attest 1.0.1 (https://registry.npmjs.org/)

**Secondary / reported (via web search):**
- fal docs (queue, webhooks, media expiration, data retention, CDN, client setup): https://fal.ai/docs/documentation/model-apis/inference/queue, https://fal.ai/docs/documentation/model-apis/inference/webhooks, https://fal.ai/docs/documentation/model-apis/media-expiration, https://fal.ai/docs/model-apis/data-retention, https://fal.ai/docs/documentation/model-apis/fal-cdn, https://fal.ai/docs/documentation/model-apis/inference/client-setup
- fal pricing pages: https://fal.ai/models/fal-ai/gemini-3-pro-image-preview/edit, https://fal.ai/learn/tools/how-to-use-nano-banana-pro, https://fal.ai/models/openai/gpt-image-2/edit/llms.txt, https://fal.ai/gpt-image-2.5
- Nano Banana pricing and launches: https://www.deeplearning.ai/the-batch/nano-banana-2-aka-gemini-3-1-flash-image-makes-edits-easier-and-faster, https://benchlm.ai/media-pricing/nano-banana, https://docs.cloud.google.com/vertex-ai/generative-ai/docs/models/gemini/3-1-flash-image, https://docs.cloud.google.com/vertex-ai/generative-ai/docs/models/gemini/3-pro-image, https://www.eesel.ai/blog/nano-banana-2-lite-pricing, https://letsdatascience.com/news/google-launches-nano-banana-2-lite-image-model-7908b46a, https://releases.sh/release/rel_7AB-2f7vDUz7kcHHVo6FW
- OpenAI pricing estimates: https://enter.converge.ai/page/en-US/news/gpt-image-2-pricing-cost-breakdown, https://www.teamday.ai/models/gpt-image-2-5, https://www.cometapi.com/gpt-image-2-5-price-api-cost-per-image/
- FLUX.2, Seedream, Qwen, MAI pricing: https://moda.app/resources/models/flux-2-pro, https://openrouter.ai/black-forest-labs/flux.2-pro/providers, https://moda.app/resources/models/seedream, https://openrouter.ai/bytedance-seed/seedream-5-0-pro, https://openrouter.ai/bytedance-seed/seedream-5-0-flash, https://aident.ai/blog/fal-ai-image-pricing-per-image-vs-megapixel, https://runtimewire.com/article/microsoft-mai-image-2-6-foundry-four-cents-image
- Leaderboards: https://artificialanalysis.ai/image/leaderboard/editing, https://alphasignal.ai/news/artificial-analysis-rebuilds-its-image-editing-arena-across-17-specialized, https://x.com/ArtificialAnlys/status/2047184062012706980
- Replicate: https://replicate.com/docs/topics/predictions/create-a-prediction.md; Cloudflare acquisition https://www.businesswire.com/news/home/20251117400765/en/Cloudflare-to-Acquire-Replicate-to-Build-the-Most-Seamless-AI-Cloud-for-Developers
- Vercel Fluid pricing: https://vercel.com/docs/fluid-compute/pricing
- 5.1.2(i) commentary: https://www.igeeksblog.com/apple-app-store-ai-data-disclosure-guidelines
