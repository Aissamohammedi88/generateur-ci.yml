# generateur-ci.yml
generateur yml
# ⚡ NEXUS YAML FORGE

> **You don't write YAML. You generate it.**

[![Version](https://img.shields.io/badge/Version-1.0.0--OMEGA-00ff88?style=for-the-badge)](#)
[![Architecture](https://img.shields.io/badge/Architecture-Engineered-00e5ff?style=for-the-badge)](#)
[![License](https://img.shields.io/badge/License-NEXUS--OPEN--3.0-ff00c8?style=for-the-badge)](#)
[![Status](https://img.shields.io/badge/Status-Production--Grade-ffcc00?style=for-the-badge)](#)

---

## 🏗️ Overview

**Nexus YAML Forge** is not a template copier. It is an **architecture engine** designed to generate, validate, and inject production-grade YAML pipelines (CI/CD, Kubernetes, Docker Compose) directly into any repository.

It parses the repository's environment, detects the stack (Python, Java, Node, Rust), and constructs the YAML AST programmatically. No indentation errors. No copy-paste drift. Just deterministic infrastructure.

---

## 🧬 Engineering Schema

Here is how the engine thinks and operates. Every arrow is a deterministic phase of the pipeline.

```mermaid
graph LR
    A[User Input / Config] -->|1. Parse| B(Engine Core)
    B -->|2. Detect| C{Stack Scanner}
    C -->|Python| D[Python Rules]
    C -->|Java| E[Java Rules]
    C -->|Node| F[Node Rules]
    D & E & F -->|3. Build AST| G[YAML Generator]
    G -->|4. Lint & Validate| H[YAML Parser]
    H -->|5. Write| I[(nexus.yml)]
    I -->|6. Inject| J[.github/workflows/]
    
    style A fill:#1a1a2e,stroke:#00e5ff,stroke-width:2px,color:#fff
    style B fill:#1a1a2e,stroke:#ff00c8,stroke-width:2px,color:#fff
    style C fill:#1a1a2e,stroke:#ffcc00,stroke-width:2px,color:#fff
    style G fill:#1a1a2e,stroke:#00ff88,stroke-width:2px,color:#fff
    style H fill:#1a1a2e,stroke:#ff00c8,stroke-width:2px,color:#fff
    style J fill:#1a1a2e,stroke:#00ff88,stroke-width:2px,color:#fff
 Cloner & Installer
bash

git clone https://github.com/Aissamohammedi88/generateur-ci.yml.git
cd generateur-ci.yml
pip install -r requirements.txt

2. Générer un Pipeline
bash

# Détection automatique de la stack et génération du meilleur pipeline
python3 forge.py generate --target .github/workflows/ci.yml

# Forcer une stack spécifique (ex: Java/Maven)
python3 forge.py generate --stack java --target .github/workflows/java-ci.yml

# Forcer Python
python3 forge.py generate --stack python --target .github/workflows/python-ci.yml

3. Pousser en Production
bash

git add .github/workflows/ci.yml
git commit -m "ci: inject forged YAML pipeline"
git push origin main

🛠️ Architecture du Générateur

Le moteur est construit sur trois couches strictes :

    Le Scanner (Perception)
        Analyse package.json, pom.xml, requirements.txt, Cargo.toml.

        Génère un profil de stack (StackProfile en JSON).

    Le Builder (Cognition)

        Utilise un AST Python pour construire la structure YAML.

        Applique des règles strictes : permissions Zero-Trust, groupes de concurrency, cache intelligent.

    Le Linter (Validation)

        Parse le YAML généré avec ruamel.yaml.

        Si le YAML est invalide, il avorte et n'écrit rien. Aucun fichier cassé.

🛡️ Posture de Sécurité

    Génération Zéro-Confiance : Chaque workflow généré utilise permissions: contents: read par défaut.

    Fail-Safe : Le générateur ne remplace jamais un fichier existant sans validation préalable du linter YAML.

    Zéro Secret en Dur : Le moteur génère uniquement des références comme ${{ secrets.GITHUB_TOKEN }}, jamais de clés brutes.

📜 Licence

NEXUS-OPEN-3.0 — Attribution requise. Les modifications doivent être documentées.
Créé par Aissa Mohammedi (DGK).
text


---

### 2. Le Fichier `.gitignore`

```gitignore
# ═══════════════════════════════════════════════════════════════════════════════
# GENERATEUR-CI.YML — .gitignore
# ═══════════════════════════════════════════════════════════════════════════════

# --- PYTHON (Le générateur est écrit en Python) ---
__pycache__/
*.py[cod]
*$py.class
*.so
.Python
build/
develop-eggs/
dist/
downloads/
eggs/
.eggs/
lib/
lib64/
parts/
sdist/
var/
wheels/
*.egg-info/
.installed.cfg
*.egg

# Environnements virtuels
.venv/
venv/
ENV/
env/
.python-version

# Tests & Caches Python
.pytest_cache/
.tox/
.nox/
.coverage
.coverage.*
htmlcov/
.hypothesis/
.mypy_cache/
.ruff_cache/
*.mo
*.pot

# --- NODE.JS (Si le générateur inclut des tests JS ou des templates) ---
node_modules/
.npm/
.yarn/
.pnpm-store/
npm-debug.log*
yarn-debug.log*
yarn-error.log*
.pnp.*
.pnp.cjs
.pnp.js

# --- SECRETS & CONFIGS LOCALES ---
.env
.env.local
.env.*.local
secrets.yaml
secrets.json
*.pem
*.key
config.local.yml

# --- ARTEFACTS GÉNÉRÉS (Le plus important pour ce dépôt) ---
# Les fichiers générés par le forge ne doivent pas polluer le dépôt
*.generated.yml
*.generated.yaml
nexus_output/
forge_cache/
tmp/
temp/
*.tmp

# --- IDE / ÉDITEURS ---
.vscode/
.vscode/*
!.vscode/extensions.json
.idea/
*.swp
*.swo
*.swn
*~
.*.swp
.*.swo
.history/
.fleet/
.nvim/
.emacs.d/
.zed/

# --- SYSTÈMES D'EXPLOITATION ---
.DS_Store
.DS_Store?
._*
.Spotlight-V100
.Trashes
ehthumbs.db
Thumbs.db
Desktop.ini
$RECYCLE.BIN/
*.lnk

# --- LOGS ---
*.log
logs/
log/
npm-debug.log*
yarn-error.log*

# --- ARCHIVES & COMPILÉS ---
*.zip
*.tar
*.tar.gz
*.tgz
*.7z
*.rar
*.o
*.obj
*.a
*.lib
*.exe
*.out

Ce qui rend ce dépôt Pro :

    Le README intègre le schéma Mermaid (qui sera rendu graphiquement par GitHub) et le schéma ASCII (qui reste lisible même en mode texte brut).

    Le .gitignore est spécifiquement adapté : il ignore les fichiers *.generated.yml pour éviter que ton dépôt ne soit pollué par les tests de ton propre générateur.

    L'URL de clone pointe exactement vers Aissamohammedi88/generateur-ci.yml.




