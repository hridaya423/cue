# Decision-model landscape sweep — 2026-10-09

Goal: find every new "decision model" published on Hugging Face and update
Cue's local model catalogue (`ModelCatalog`) for open-source download/local
download. Method: `hf` CLI org sweeps (37 publishers) + keyword searches
(decision/router/guard/reranker/systemone/jev…) + the **Jev Decision Index**
leaderboard (`multimodalart/jev-decision-index`), which currently lists **121
systems** — the "hundreds" is literal.

## What the wave is

"System One" / typed-decision models: a state + a schema of typed questions
(`choice`, `noul`, `score`) → a probability per option in **one forward pass**,
no generated text, no output parsing. The contract is the TypeSafe `/v1/systemone`
shape Cue already speaks. Since Jev (TypeSafe, 2026) every lab ships a repro or
an alternative — Cloudflare, Perplexity, InternLM, vLLM's semantic router,
plus dozens of community fine-tunes.

## Added to the catalogue (installable on Apple Silicon)

| Entry | Weights (license) | Serve path | Tier |
|---|---|---|---|
| `jevstyle` | chaoliangUNSW/Jev-Style-{0.8B,2B}-Decision-v3 (Apache-2.0) | `pip install jev-style[mlx]` + `jev-style serve --release …` — native CLI, MLX-first | experimental |
| `jevk5` | alibiserikbay/JevK5-GGUF (Apache-2.0) — #2 of 76 on JevBench v1.4 | `llama-cpp-python` backend spawned by `Scripts/jevk5_server.py` + `jevk5` logprob client (v0.3.2) | experimental |
| `startlux` | startlux-models/StartLux-Decision-{0.8B,2B,4B,9B} (CC BY-NC-4.0 — non-commercial) | repo ships `startlux_decision.server` — auto MLX backend on Apple Silicon | experimental |
| `vsr` | vllm-sr/Decision-2.0-{Eos-0.8B,Kai-0.6B,Sol-2B,Nox-4B,Lux-9B} (Apache-2.0) | `AutoModel.from_pretrained(…, trust_remote_code=True).system_one()` via `Scripts/vsr_server.py` | experimental |
| `clef` | Cloudflare/clef-flash 9B, Cloudflare/clef 27B (Apache-2.0) — multimodal, DI-top | snapshot ships `joint_schema_model.systemone()`; `Scripts/clef_server.py` wraps it (mps→cpu) | experimental |
| `intern` | internlm/Intern-Decision-{0.8B,2B,4B} (Apache-2.0) — multimodal | snapshot ships `inference.py DecisionEngine`; `Scripts/intern_server.py` wraps `predict()` | experimental |
| `jevnano` | tasksource/tasksource-jev-nano-v1 (Apache-2.0) — 149M ColBERT | `pylate` + `Scripts/nano_server.py` (MaxSim late-interaction, T=0.3168 from `decision_meta.json`) | experimental |
| `s1lite` | dwidlee/systemone-lite-0.5b (MIT) | `github.com/fritzprix/systemone-lite` repo → `systemone-lite` CLI | experimental |
| `kev-27b` | jaredpalmer/kev-27b (Apache-2.0) — new variant on the existing kev recipe | `kev.serve` unchanged | (inherits kev's supported tier) |

## Listed but not installable on macOS (honest `.unsupported`)

| Entry | Repo | Why |
|---|---|---|
| `decider` | Mapika/decider-{2b,4b,35b-a3b} | `decider-ai` hard-depends `flash-linear-attention` (Triton, no macOS wheels) |
| `pplxdecider` | perplexity-ai/pplx-decider-v1(.1)-27b | CUDA-only `autojev` runtime, ~49 GiB bf16; DI 61.56 — top open score |
| `gliner` | fastino/GLiNER2.5-Decide | argmax-only output — no per-option probabilities; the chooser needs calibrated scores |
| `scorer` | pngwn/system-one-qwen3.5-4b-scorer | CC BY-NC-4.0 + no published server |
| `openthai` | iapp/OpenThai-SystemOne | Thai-optimized; only an Ollama build published |

## Install mechanics added

`ModelSpec.Kind.shim` gained `(script, downloadsSnapshot)`:
`Scripts/<script>` is bundled into the app and run as
`python <script> <port> <hfRepo> <serveModel> <snapshot>` inside the model's
venv; `downloadsSnapshot` additionally runs `hf download <hfRepo>` into
`snapshot/` and installs its `requirements.txt` (StartLux/Clef/Intern-Decision
ship serving code inside the weight repo). `{serveModel}`/`{snapshot}` are new
argv substitutions available to every kind. `Scripts/eval_servers.sh` launches
the new installable families for CueEval.

## The full Decision Index enumeration (121 systems, grouped)

Publishers of **native decision models** (speak the typed-decision contract
with probability output; whether or not a server ships):

- **TypeSafe ecosystem**: Jev (hosted), JevK5 (kev/jpt lineage)
- **Cloudflare**: `Cloudflare/clef`, `Cloudflare/clef-flash` (+`clef-omni`)
- **Perplexity**: `perplexity-ai/pplx-decider-v1-27b`, `pplx-decider-v1.1-27b`
- **StartLux**: `startlux-models/StartLux-Decision-{0.8B,2B,4B,9B,27B,35B-A3B}`
  (+ GGUF builds of every size)
- **vLLM semantic router**: `vllm-sr/Decision-2.0-{Eos,Kai,Sol,Nox,Lux,Vega}`,
  v1 under `llm-semantic-router/Decision-1.0-*`
- **InternLM**: `internlm/Intern-Decision-{0.8B,2B,4B}` (+ GitHub runtime)
- **Mapika**: `Mapika/decider-{2b,4b,35b-a3b}` (+`decider-ai` PyPI)
- **JevK5**: `alibiserikbay/JevK5{,-2B,-9B,-GGUF,-Lite}` (Lite = 437M DeBERTa CPU classifier)
- **Jev-Style**: `chaoliangUNSW/Jev-Style-*` (v1 2B, v2 2B, v3 0.8B/2B; MLX+GGUF+torch builds)
- **community/native**: `tasksource/tasksource-jev-nano-v1` (149M ColBERT),
  `dwidlee/systemone-lite-0.5b`, `iapp/OpenThai-SystemOne` (Thai),
  `pngwn/system-one-qwen3.5-4b-scorer(-v2b)`, `fastino/GLiNER2.5-Decide(-1B)`
  (+base/small/multi), `AlexWortega/openjev`, `C-Tianyu/NanoJev`,
  `akhilaaa3/Jev-Omni`, `interfaze-ai/lev`, `theaviv/Lev1-3.7B`,
  `michaljach/jet`, `moganai/lavoir`, `MoLeMo-Lab/mojev`,
  `everettjf/ezjev-4b-s2`, `TokenRhythm/NeoHorse-Jev-4B`,
  `wayfind/metask-jev-4b-policy-mix`, `UserMoonlight/intelif-qwen3-4b`,
  `kirp/jpt-{0.8b,4b,9b,35b-a3b}`, `eljiwo/jiwo-{0.8b,4b}`,
  `davidburhans/gevva-{e2b,e4b}`, `juspay/xor`, `juspay/Xor-26B-A4B`,
  `surogate/rune-26b-a4b-GGUF`, `PixilabAI/Blink-v0.3-26B-A4B-NVFP4`,
  `frontier-infra/jebadiah-27b`, `caiovicentino1/Eikos-27B-FP8`,
  `autotrust/{JEV-9B,JEV-27B,GEV-26B-Decide}`,
  `andyzhang232/ajev-gemma4-12b-lora5`, `AmirBraham/jevstral-8b`,
  `carrtesy/EXAONE-4.0-1.2B-JEV`, `shgao/rsi-jev-v5.0-vl-3b`,
  `sthanika-ai/{sieve-2b,Sieve-9B}`, `cortex-agent-llc/kodiak-v0.2-1b-accuracy`,
  `EldanRing/{Winnow-12B,Winnow-E4B}`, `bespokelabs/Bespoke-Nimble-9B{,-v2,-v3}`,
  `Hanno-Labs/bosun-v3.1-{0.6b,1.7b}`, `SupersonicLabs/Julia-1`,
  `OmniJev/OneJev-0.8B`, `mohamedlotfy50/sifr-0.8b-v3`,
  `hotchpotch/bekko-system-one-v0-{17m,68m,400m}` (tiny BERT class),
  `hotchpotch` also has `bekko` ONNX builds, `DangerLabs/DM-JEPA`,
  `torchcast-ai/torchcast-decision-27b`, `chinhnc/Quyet-1.0-Large`,
  `kpiya/kas-4b`, `Lukitaduarte/dinah-0`, `GhostScientist/jev-decisions-v{1,2}`,
  `DavidHatley/system-one-mini`, `systemonedev/kenning-xl-v0.6`,
  `stephenlb/system-one-model`, `mpuig/system-one-minicpm5-2b-q8`,
  `oomu/OOMU-SystemOne-0.6B-GGUF`, `abidlabs/jev-typed-decisions-causal-0.6b`,
  `MSGEncrypted/ocf-typed-decisions-mbert-base`,
  `convaiinnovations/laya{,-typed-decisions}` (existing `laya` family),
  `wfzyx/von` (existing `von`), `jaredpalmer/kev-{0.8b,4b,8b,9b,27b}` (existing `kev`),
  `harshatheg/Qwen-2.5-1B-RLCD`, `heman10x/rlcd-modernbert-151m`,
  `monotykamary/LFM2.5-2.6B-RLCD`, `notnotsamuel/LFM2.5-350M-RLCD`,
  `Manav2op/verdict-small`, `knowledgator/gliformer-large-v1`,
  `flock-io/this-that-model-{1.0,1.2}`, `HopitAI/hopper(-g)`,
  `DeepMostInnovations/sales-conversion-model-reinf-learning`,
  `DoccyHealth/Solomon`, `FrontiersMind/Lumma-fev-{0.1b,0.6b}`,
  `runanywhere/decision-models-stable-fork` (curated mirror set),
  plus base-model reference entries (Qwen3.x, gemma-4, diffusiongemma).

Untested community builds exist in GGUF/MLX/ONNX for most families above
(`mradermacher/*`, `vinci00/*`, `jacksodj/*`, `onnx-community/*` mirrors).

## Adjacent decision-adjacent models — reviewed, not catalogue entries

These are published "decision" models in the loose sense but do **not** emit
per-option probability distributions for the `/v1/systemone` contract, so a
catalogue entry would be dishonest:

- **LLM routers**: `katanemo/Arch-Router-1.5B`,
  `LiquidAI/LFM2.5-Encoder-350M-Prompt-Router`, `chopratejas/technique-router`,
  `SupraLabs/Supra-Router-51M`, `RinggAI/ringg-router-e2b` — route prompts to
  models; fixed label space, not caller-supplied options.
- **Guards/safety**: `meta-llama/Llama-Guard-3-1B`, `Llama-Prompt-Guard-2-86M`,
  `Qwen/Qwen3Guard-Gen-{0.6B,4B,8B}`, `google/shieldgemma-{2b,9b}`,
  `ibm-granite/granite-guardian-4.1-8b`, `mistralai/Shieldstral-1.0-3B`,
  `openai/gpt-oss-safeguard-20b`, `allenai/wildguard`,
  `perplexity-ai/browsesafe` (Qwen3-MoE prompt-injection guard) —
  classification over a fixed safety taxonomy.
- **Judges/reward**: `PatronusAI/glider`, `flowaicom/Flow-Judge-v0.1`,
  `prometheus-eval/*`, `Skywork/Skywork-Reward-V2-Qwen3-0.6B`,
  `AtlaAI/Selene-*` — rubric scoring, not option decisions.
- **Rerankers/embedders**: `BAAI/bge-reranker-*`, `Qwen/Qwen3-Reranker-*`,
  `zeroentropy/zerank-{1,2}`, `jinaai/jina-reranker-v3`,
  `nvidia/llama-nemotron-rerank-1b-v2`, `google/embeddinggemma-300m`,
  `perplexity-ai/pplx-embed-v1-*` — retrieval ranking, not typed answers.
- **PII extractors**: `perplexity-ai/PII-Tracer{,-MLX,-GGUF}` (MIT, Apple-Silicon
  MLX build — a candidate upgrade for the Redact redactor, not a decider),
  `iiiorg/piiranha-v1`, `urchade/gliner_multi_pii-v1`,
  `knowledgator/gliner-pii-*`, `knowledgator/opir-edge-*` — token
  classification.
- **Function calling**: `google/functiongemma-270m-it`,
  `Salesforce/xLAM-{1b,3b,8b}-fc-r` — tool-call emission, not probabilities.
- **Zero-shot NLI**: `MoritzLaurer/*`, `tasksource/*-nli`,
  `answerdotai/ModernBERT-*` fine-tunes — single-label classifiers.
- **Generic small instruct LLMs** (Qwen3-0.6B, gemma-4-E2B, phi-4-mini,
  MiniCPM5, LFM2.5, SmolLM2/3, OpenELM, Zamba2, EXAONE-1.2B, GLM-Edge,
  tiny-aya, Hunyuan-smalls, gpt-oss-20b, Hermes-3B, Ling-mini, MiniCPM-VL,
  DeepSeek-R1-Distill-1.5B…) — generate text; they cannot produce the
  calibrated per-option distribution the contract requires.

## Provenance notes

- Benchmark numbers quoted are the publishers' own (Decision Index, JevBench
  v1.4, vendor tables) — **not** CueEval measurements. New catalogue entries
  carry no benchmark rows; their rank/meters are declared estimates until
  `Scripts/eval_run.sh` measures them.
- `ModelRoles` roles (Most accurate / Best balance / Fastest) remain driven
  exclusively by `Resources/benchmarks.json` — new models cannot take a role
  until measured.
- Gated check: none of the catalogued repos are gated (`gemma-3n-E4B-it`,
  used by jevlite's *adapter* family vagmi/jev-lite, is the only gated repo
  in the landscape and stays out).
- `runanywhere/decision-models-stable-fork` is a curated mirror of the models
  above, not a separate family.
