#!/usr/bin/env bash
# Installs Antigravity CLI skills/plugins for PharmaSphere. Run from repo root.
set -euo pipefail

command -v agy >/dev/null || curl -fsSL https://antigravity.google/cli/install.sh | bash
command -v node >/dev/null || { echo "Install Node.js 20+ (needed for npx skills)"; exit 1; }

# 1. Workflow discipline (brainstorm -> plan -> TDD -> debug -> review)
agy plugin install https://github.com/obra/superpowers

# 2. Database + multi-tenancy
npx skills add supabase/agent-skills -a antigravity
npx skills add sickn33/agentic-awesome-skills --skill saas-multi-tenant -a antigravity

# 3. Backend (FastAPI). If this repo name 404s, try sickn33/antigravity-awesome-skills
npx skills add sickn33/agentic-awesome-skills --skill fastapi-pro -a antigravity

# 4. Mobile (Flutter/Dart official)
npx skills add flutter/agent-plugins --skill '*' --agent universal
npx skills add dart-lang/skills --skill '*' --agent universal

# 5. Admin web (React). Run `npx skills add vercel-labs/agent-skills --list` to see more.
npx skills add vercel-labs/agent-skills --skill frontend-design -a antigravity

echo "Done. Start 'agy', run /skills, and confirm the custom skills in .agents/skills are listed."
