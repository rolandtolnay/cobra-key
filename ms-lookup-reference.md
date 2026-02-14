ms-lookup Summary for Subagent Context

What it is: A Python CLI tool that provides two research capabilities:

1. docs — Query library documentation via Context7 (authoritative, version-aware API docs)
2. deep — Perform multi-source research via Perplexity's reasoning model

How to invoke from a subagent:

# Library documentation (Context7)
~/.claude/mindsystem/scripts/ms-lookup-wrapper.sh docs <library> "<query>" [--max-tokens N]

# Deep research (Perplexity)
~/.claude/mindsystem/scripts/ms-lookup-wrapper.sh deep "<query>"

Key details:
- The wrapper (ms-lookup-wrapper.sh) handles uv sync automatically — no setup needed
- Output is JSON to stdout with success, results[], and metadata fields
- Results are cached on disk (~/.cache/ms-lookup/): docs=24h, deep=6h. Use --no-cache to bypass
- --max-tokens N controls response size for docs (default 2000). Not available for deep
- -p flag pretty-prints JSON (useful for debugging, not needed for programmatic consumption)
- Requires CONTEXT7_API_KEY (for docs) and PERPLEXITY_API_KEY (for deep) in the environment — these are already set in the user's shell profile
- Exit code 1 on failure, with success: false and error.code/error.message/error.suggestions in JSON

Output structure:

```json
{
  "success": true,
  "command": "docs",
  "query": "...",
  "library": "nextjs",          // docs only
  "results": [
    { "title": "...", "content": "...", "source_url": "...", "type": "code|info|research", "tokens": 450 }
  ],
  "metadata": {
    "library_id": "/vercel/next.js",   // docs only
    "tokens_used": 830,
    "cache_hit": false,
    "confidence": "HIGH",              // HIGH for docs, MEDIUM-HIGH for deep
    "backend": "context7|perplexity-reasoning",
    "citations": ["url1", "url2"]      // deep only
  }
}
```

When to use which:
- docs — "How does X API work?", "What are the params for Y method?", version-specific questions
- deep — Broader technical questions, architecture patterns, comparing approaches, anything requiring multi-source synthesis (~$0.005/query)

Error handling: Parse success field first. On failure, error.suggestions provides actionable recovery hints (missing API key, library not found, rate limited).
