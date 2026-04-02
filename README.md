# Liquify

A CLI tool that detects N+1 database query patterns in Shopify Liquid templates and suggests AI-powered fixes — all running locally on your machine.

## How it works

```
your_template.liquid
        ↓
C++ parser (fast static analysis)
        ↓
N+1 patterns detected
        ↓
AI provider (Claude / GPT-4.5 / Gemini)
        ↓
Optimized Liquid code suggested in your terminal
```

Your Liquid code **never leaves your machine**. Only the flagged snippet is sent to your chosen AI provider using **your own API key** — Liquify never sees it.

---

## What is an N+1 query?

In Shopify Liquid, some object properties are **lazily loaded** — they aren't fetched from the database until you access them in the template. If you access a lazy property inside a loop, Shopify fires a separate database query **per iteration**.

**Problem:**
```liquid
{% for product in collection.products %}
  {% for metafield in product.metafields %}
    {{ metafield.value }}
  {% endfor %}
{% endfor %}
```

With 50 products this fires **51 database queries** instead of 2. Your storefront slows down silently and you won't notice it just by reading the template.

**AI-suggested fix:**
```liquid
{% assign all_metafields = collection.products | map: 'metafields' %}
{% for product in collection.products %}
  {% assign metafields = all_metafields[forloop.index0] %}
  {% for metafield in metafields %}
    {{ metafield.value }}
  {% endfor %}
{% endfor %}
```

---

## Requirements

- **Ruby 3.0+** — [rubyinstaller.org](https://rubyinstaller.org) (Windows) or `brew install ruby` (Mac)
- **g++** — for compiling the C++ parser on first run
  - Mac: `xcode-select --install`
  - Linux: `sudo apt install g++`
  - Windows: included with RubyInstaller+Devkit (select it during Ruby installation)

---

## Installation

```bash
git clone https://github.com/zen-karia/Liquify.git
cd Liquify
bundle install
```

The C++ parser compiles automatically the first time you run the tool. No manual steps needed.

---

## Setting up your API key

Liquify supports three AI providers. You only need **one**. Set whichever API key you have.

### Get an API key

| Provider | Where to get it |
|---|---|
| Anthropic (Claude) | platform.anthropic.com → API Keys |
| OpenAI (GPT-4.5) | platform.openai.com → API Keys |
| Google (Gemini) | aistudio.google.com → Get API Key |

---

### Set the key on Mac / Linux

**Option 1 — Temporary** (only lasts for the current terminal session):
```bash
export ANTHROPIC_API_KEY=sk-ant-your-key-here
```

**Option 2 — Permanent** (persists across sessions):
```bash
# Open your shell config file
nano ~/.zshrc      # Mac (zsh is default)
nano ~/.bashrc     # Linux (bash is default)

# Add this line at the bottom
export ANTHROPIC_API_KEY=sk-ant-your-key-here

# Save and reload
source ~/.zshrc
```

---

### Set the key on Windows

**Option 1 — Temporary** (current PowerShell session only):
```powershell
$env:ANTHROPIC_API_KEY="sk-ant-your-key-here"
```

**Option 2 — Permanent** (persists across sessions):
```
1. Press Win + S and search "Environment Variables"
2. Click "Edit the system environment variables"
3. Click the "Environment Variables" button
4. Under "User variables" click "New"
5. Variable name:  ANTHROPIC_API_KEY
   Variable value: sk-ant-your-key-here
6. Click OK → OK → OK
7. Restart your terminal
```

---

## Usage

```bash
# Scan a single file
ruby bin/liquify path/to/template.liquid

# Scan multiple files
ruby bin/liquify templates/*.liquid

# Show help
ruby bin/liquify --help

# Show version
ruby bin/liquify --version
```

No API key set? Liquify still runs — it detects and flags all N+1 issues, just without the AI-generated fix.

---

## Example output

```
╔══════════════════════════════════════════════════════════╗
║          LIQUIFY — Shopify Liquid N+1 Analyzer           ║
╚══════════════════════════════════════════════════════════╝

  Scanning : templates/product.liquid
  Provider : Anthropic (claude-opus-4-6)

──────────────────────────────────────────────────────────
  ISSUE #1  —  Line 9
──────────────────────────────────────────────────────────

  ⚠  N+1 query detected
  ↳  {% for metafield in product.metafields %}

  ✦  Optimized Code:
     {% assign metafields = product.metafields %}
     {% for metafield in metafields %}
       {{ metafield.value }}
     {% endfor %}

──────────────────────────────────────────────────────────
  1 issue(s) found.
══════════════════════════════════════════════════════════
```

---

## AI Providers

Liquify auto-detects which key you have set. Priority order: Anthropic → OpenAI → Gemini.

| Provider | Environment Variable | Model |
|---|---|---|
| Anthropic | `ANTHROPIC_API_KEY` | claude-opus-4-6 |
| OpenAI | `OPENAI_API_KEY` | gpt-4.5-preview |
| Google | `GEMINI_API_KEY` | gemini-2.5-pro |

---

## Project structure

```
Liquify/
├── bin/liquify              # CLI entry point
├── lib/liquify/
│   ├── analyzer.rb          # Bridges Ruby → C++ binary
│   ├── ai.rb                # AI provider integrations
│   ├── formatter.rb         # Colored terminal output
│   └── cli.rb               # Argument parsing
├── cpp_engine/
│   └── analyzer.cpp         # High-speed Liquid parser (C++)
└── liquify.gemspec
```

---

## License

MIT
