#!/usr/bin/env bash
# ============================================================================
#  ███  NEXUS CI GENERATOR v2.0.0  ███
#  Générateur de pipelines GitHub Actions — prêts pour la production
# ============================================================================
#  Auteur   : DGK — Aissa Mohammedi (protocole PROTON)
#  Origine  : NEXUS CI GENERATOR skeleton v1 — noms de fonctions préservés
#             verbatim : usage, check_env, inject_aegis, inject_java,
#             inject_python, inject_node, main
#  Licence  : MIT
# ----------------------------------------------------------------------------
#  SYNOPSIS
#      nexus-ci-generator.sh <commande> [options]
#      nexus-ci-generator.sh <type>     [options]   # raccourci de génération
#
#  DESCRIPTION
#      Génère des workflows GitHub Actions de qualité production dans
#      .github/workflows/. Chaque YAML produit est validé syntaxiquement
#      ET structurellement AVANT installation : le générateur n'installe
#      JAMAIS un fichier cassé. Si la validation échoue, le fichier
#      temporaire est détruit et tout workflow existant reste intact.
#      La génération est atomique (écriture en tmp + mv) et idempotente
#      avec --force.
#
#  COMMANDES / TYPES DE WORKFLOW
#      aegis      Pipeline sécurité & qualité Next.js (skeleton corrigé)
#      java       Pipeline Maven multi-JDK + OWASP dependency-check
#      python     Pipeline ruff + pytest + coverage + mypy + pip-audit
#      node       Pipeline npm multi-runtime + audit
#      docker     Pipeline image multi-arch + hadolint + Trivy + SBOM
#      go         Pipeline golangci-lint + tests -race + goreleaser
#      rust       Pipeline fmt + clippy + test + cargo-audit
#      release    Pipeline release sur tag v* + changelog + SLSA
#      nightly    Pipeline cron : scan nocturne complet
#      php        Pipeline composer + php-cs-fixer + phpunit + audit
#      dotnet     Pipeline .NET restore/build/test + pack NuGet
#      cpp        Pipeline cmake multi-compilateur + sanitizers
#      android    Pipeline gradle + lint + tests + APK debug/release
#      list       Liste les types supportés avec description
#      explain    Documentation opérationnelle d'un type
#      validate   Valide la syntaxe/structure d'un fichier workflow
#      doctor     Diagnostic complet de l'environnement
#      uninstall  Supprime un workflow généré (avec confirmation)
#      selftest   Test de bout en bout : génère et valide les 9 types
#      manual     Manuel complet intégré
#      changelog  Historique des versions
#
#  OPTIONS
#      --dir <chemin>       Répertoire du dépôt cible (défaut : .)
#      --branch <branche>   Branche déclencheuse (défaut : main)
#      --node <version>    Version Node.js (défaut : 22)
#      --java <version>    Version JDK (défaut : 21)
#      --python <version>  Version Python (défaut : 3.12)
#      --go <version>      Version Go (défaut : 1.23)
#      --php <version>     Version PHP (défaut : 8.3)
#      --dotnet <version>  Version .NET SDK (défaut : 9.0)
#      --registry <hote>   Registre conteneurs (défaut : ghcr.io)
#      --cron <expr>       Cron 5 champs (défaut : 0 3 * * *)
#      --force              Écrase un workflow existant
#      --dry-run            Génère sans écrire (sortie stdout)
#      --skip-validation   Saute la validation YAML (déconseillé)
#      --no-color           Désactive les couleurs ANSI
#      --quiet, -q          Seules les erreurs s'affichent
#      -h, --help           Aide courte
#
#  EXEMPLES
#      ./nexus-ci-generator.sh aegis --node 22
#      ./nexus-ci-generator.sh python --dir ~/projets/api --python 3.11
#      ./nexus-ci-generator.sh nightly --cron '30 2 * * 1'
#      ./nexus-ci-generator.sh selftest
#      ./nexus-ci-generator.sh validate .github/workflows/nexus-aegis.yml
#
#  CODES DE RETOUR
#      0  succès
#      1  erreur générique
#      2  usage incorrect
#      3  environnement invalide (pas un dépôt git, outils absents)
#      4  collision de fichier (workflow déjà présent, sans --force)
#      5  validation YAML échouée
#
#  CONFORMITÉ PROTON (appliquée à ce livrable)
#      1. Rien n'est affirmé sans preuve exécutable -> sous-commande selftest
#      2. Pas de livraison sans testbench            -> validation YAML
#                                                      intégrée au pipeline
#      3. Chaque écart a une preuve d'exécution      -> logs + codes retour
#      4. Réparation chirurgicale                    -> bug YAML du skeleton
#                                                      aegis corrigé (voir
#                                                      inject_aegis)
#      5. Spec d'origine préservée                   -> fonctions du skeleton
#                                                      conservées verbatim
# ============================================================================
set -euo pipefail

# ============================================================================
# SECTION 1 — GARDE-FOU RUNTIME ET PRÉ-SCAN
# ============================================================================
# bash >= 4 requis : le générateur utilise des tableaux associatifs
# (declare -A) pour le registre des types de workflows.
if [ "${BASH_VERSINFO[0]:-0}" -lt 4 ]; then
    printf 'ERREUR FATALE: bash >= 4.0 requis (tableaux associatifs). Version actuelle: %s\n' \
        "${BASH_VERSION:-inconnue}" >&2
    exit 3
fi

# --no-color doit agir même pour les erreurs d'usage : on l'extrait de "$@"
# AVANT tout affichage. On respecte aussi la convention NO_COLOR=1 et on
# coupe les couleurs quand stdout n'est pas un terminal (pipes, logs CI).
USE_COLOR=1
if [ "${NO_COLOR:-}" = "1" ] || [ "${TERM:-}" = "dumb" ] || [ ! -t 1 ]; then
    USE_COLOR=0
fi
for __arg in "$@"; do
    case "$__arg" in
        --no-color) USE_COLOR=0 ;;
    esac
done
unset __arg

# ============================================================================
# SECTION 2 — COULEURS ANSI
# ============================================================================
C_RESET=""; C_BOLD=""; C_DIM=""
C_RED=""; C_GREEN=""; C_YELLOW=""; C_CYAN=""; C_MAGENTA=""; C_BLUE=""

init_colors() {
    if [ "$USE_COLOR" -ne 1 ]; then
        return 0
    fi
    C_RESET=$'\033[0m'
    C_BOLD=$'\033[1m'
    C_DIM=$'\033[2m'
    C_RED=$'\033[31m'
    C_GREEN=$'\033[32m'
    C_YELLOW=$'\033[33m'
    C_CYAN=$'\033[36m'
    C_MAGENTA=$'\033[35m'
    C_BLUE=$'\033[34m'
}
init_colors

# ============================================================================
# SECTION 3 — JOURNALISATION
# ============================================================================
# NEXUS_QUIET=1 supprime les messages d'information (log_info, log_ok,
# log_step) mais JAMAIS les avertissements ni les erreurs (stderr).
NEXUS_QUIET=0

log_info() {
    if [ "$NEXUS_QUIET" -eq 1 ]; then
        return 0
    fi
    printf '%s\n' "${C_CYAN}[INFO]${C_RESET} $*"
}

log_ok() {
    if [ "$NEXUS_QUIET" -eq 1 ]; then
        return 0
    fi
    printf '%s\n' "${C_GREEN}[OK]${C_RESET}   $*"
}

log_warn() {
    printf '%s\n' "${C_YELLOW}[ATT]${C_RESET}  $*" >&2
}

log_err() {
    printf '%s\n' "${C_RED}[ERR]${C_RESET}  $*" >&2
}

# Étape majeure : séparateur visible pour les phases du pipeline.
log_step() {
    if [ "$NEXUS_QUIET" -eq 1 ]; then
        return 0
    fi
    printf '\n%s\n' "${C_BOLD}${C_MAGENTA}>>> $*${C_RESET}"
}

# Sortie d'échec immédiat avec message + code de retour documenté.
die() {
    local msg="$1"
    local code="${2:-1}"
    log_err "$msg"
    log_err "code de retour: $code (voir section CODES DE RETOUR, --help)"
    exit "$code"
}

# Ligne de séparation visuelle pour les rapports.
hr() {
    if [ "$NEXUS_QUIET" -eq 1 ]; then
        return 0
    fi
    printf '%s\n' "${C_DIM}------------------------------------------------------------${C_RESET}"
}

banner() {
    if [ "$NEXUS_QUIET" -eq 1 ]; then
        return 0
    fi
    printf '%s\n' "${C_BOLD}${C_CYAN}"
    printf '%s\n' '  == NEXUS CI GENERATOR v2.0.0 =='
    printf '%s\n' '  Pipelines GitHub Actions prets pour la production'
    printf '%s\n' "${C_RESET}"
}

# ============================================================================
# SECTION 4 — FICHIERS TEMPORAIRES ET NETTOYAGE
# ============================================================================
# Tout fichier temporaire passe par le registre NEXUS_TMPFILES : le trap
# EXIT garantit qu'aucun .nexus-tmp ne survit à une interruption (Ctrl-C,
# erreur set -e, fin normale). Double sécurité : cleanup est idempotent.
NEXUS_TMPFILES=()
NEXUS_TMPDIRS=()

nexus_tmp_new() {
    local t
    t="$(mktemp "${1:-/tmp}/.nexus-tmp.XXXXXX")"
    NEXUS_TMPFILES+=("$t")
    printf '%s' "$t"
}

nexus_tmpdir_new() {
    local d
    d="$(mktemp -d "${1:-/tmp}/nexus-dir.XXXXXX")"
    NEXUS_TMPDIRS+=("$d")
    printf '%s' "$d"
}

cleanup() {
    local f d
    for f in "${NEXUS_TMPFILES[@]}"; do
        if [ -e "$f" ]; then
            rm -f "$f"
        fi
    done
    for d in "${NEXUS_TMPDIRS[@]}"; do
        if [ -d "$d" ]; then
            rm -rf "$d"
        fi
    done
    return 0
}
trap cleanup EXIT
trap 'exit 130' INT

# ============================================================================
# SECTION 5 — CHEMIN DU SCRIPT ET HORODATAGE
# ============================================================================
# NEXUS_SCRIPT_PATH : chemin absolu fiable, utilisé par cmd_selftest pour
# relancer le générateur comme un vrai utilisateur (sous-processus bash).
NEXUS_SCRIPT_PATH="${BASH_SOURCE[0]}"
case "$NEXUS_SCRIPT_PATH" in
    /*) ;;
    */*) NEXUS_SCRIPT_PATH="$PWD/${NEXUS_SCRIPT_PATH#./}" ;;
    *)  NEXUS_SCRIPT_PATH="$PWD/$NEXUS_SCRIPT_PATH" ;;
esac

# Horodatage UTC injecté dans l'en-tête de chaque workflow généré.
NEXUS_GEN_DATE="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# Raccourci pratique pour les rapports : date humaine.
nexus_date_human() {
    date -u +%Y-%m-%d
}
# ============================================================================
# SECTION 6 — CONSTANTES ET REGISTRE DES TYPES
# ============================================================================
NEXUS_VERSION="2.0.0"

DEFAULT_DIR="."
DEFAULT_BRANCH="main"
DEFAULT_NODE="22"
DEFAULT_JAVA="21"
DEFAULT_PYTHON="3.12"
DEFAULT_GO="1.23"
DEFAULT_PHP="8.3"
DEFAULT_DOTNET="9.0"
DEFAULT_REGISTRY="ghcr.io"
DEFAULT_CRON="0 3 * * *"

# Codes de retour (contrat public documenté dans l'en-tête)
EXIT_OK=0
EXIT_ERR=1
EXIT_USAGE=2
EXIT_ENV=3
EXIT_COLLISION=4
EXIT_YAML=5

# Ordre canonique d'affichage et de génération (selftest inclus)
TYPES_ORDER=(aegis java python node docker go rust release nightly php dotnet cpp android)

# Fichier YAML cible pour chaque type (dans .github/workflows/)
declare -A WORKFLOW_FILE=(
    [aegis]="nexus-aegis.yml"
    [java]="nexus-java.yml"
    [python]="nexus-python.yml"
    [node]="nexus-node.yml"
    [docker]="nexus-docker.yml"
    [go]="nexus-go.yml"
    [rust]="nexus-rust.yml"
    [release]="nexus-release.yml"
    [nightly]="nexus-nightly.yml"
    [php]="nexus-php.yml"
    [dotnet]="nexus-dotnet.yml"
    [cpp]="nexus-cpp.yml"
    [android]="nexus-android.yml"
)

# Description courte affichée par la commande list
declare -A WORKFLOW_DESC=(
    [aegis]="Securite & qualite Next.js: gitleaks, lint, tsc, tests, build, CodeQL, Trivy, SLSA"
    [java]="Maven multi-JDK 17/21: verify, OWASP dependency-check, artefacts JAR, CodeQL"
    [python]="ruff, pytest+coverage, mypy, pip-audit, multi-interpreteur 3.10-3.13, CodeQL"
    [node]="npm multi-runtime 20/22: ci, lint, test, build, audit, artefacts"
    [docker]="Image multi-arch amd64/arm64: hadolint, buildx, Trivy, SBOM, push ghcr"
    [go]="golangci-lint, vet, tests -race + coverage, goreleaser sur tag"
    [rust]="fmt, clippy -D warnings, test --all-features, cargo-audit, release sur tag"
    [release]="Release sur tag v*: changelog automatique, artefacts, SLSA provenance"
    [nightly]="Scan nocturne cron: gitleaks full-history, CodeQL, Trivy complet, deps"
    [php]="composer + php-cs-fixer + phpunit bloquant + composer audit, matrice PHP 8.2-8.4"
    [dotnet]="SDK [8.0.x,<dotnet>]: restore/build/test --no-restore, pack NuGet, CodeQL csharp"
    [cpp]="cmake [gcc,clang] -Werror, ctest, sanitizers ASan+UBSan, cppcheck"
    [android]="gradlew lint + tests + assembleDebug, APK artefact, release unsigned sur tag"
)

# Marqueur posé dans les 3 premières lignes de chaque workflow généré.
# uninstall refuse de supprimer un fichier qui ne porte PAS ce marqueur :
# on ne touche jamais à un workflow écrit à la main par quelqu'un d'autre.
NEXUS_MARKER="Généré par NEXUS CI GENERATOR"

# ============================================================================
# SECTION 7 — AIDE (usage)
# ============================================================================
usage() {
    cat <<'NEXUS_USAGE'
NEXUS CI GENERATOR v2.0.0
Générateur de pipelines GitHub Actions prêts pour la production.

USAGE:
    nexus-ci-generator.sh <commande> [options]
    nexus-ci-generator.sh <type>     [options]    # raccourci de génération

TYPES DE WORKFLOW:
    aegis      Securité & qualite Next.js complet (skeleton corrigé)
    java       Maven multi-JDK 17/21 + OWASP dependency-check
    python     ruff + pytest + coverage + mypy + pip-audit
    node       npm multi-runtime 20/22 + audit
    docker     image multi-arch + hadolint + Trivy + SBOM
    go         golangci-lint + tests -race + goreleaser
    rust       fmt + clippy + test + cargo-audit
    release    release sur tag v* + changelog + SLSA
    nightly    scan nocturne cron complet
    php        composer + php-cs-fixer + phpunit + audit
    dotnet     .NET restore/build/test + pack NuGet
    cpp        cmake multi-compilateur + sanitizers + cppcheck
    android    gradle + lint + tests + APK debug/release

COMMANDES:
    list       Liste les types supportés
    explain    Documentation opérationnelle détaillée d'un type
    validate   Valide la syntaxe/structure d'un fichier workflow
    doctor     Diagnostic de l'environnement
    uninstall  Supprime un workflow généré (confirmation requise)
    selftest   Test e2e: génère + valide les 9 types + tests négatifs
    manual     Manuel complet intégré
    changelog  Historique des versions

OPTIONS (génération):
    --dir <chemin>       Répertoire du dépôt cible (défaut: .)
    --branch <branche>   Branche déclencheuse (défaut: main)
    --node <version>     Version Node.js (défaut: 22)
    --java <version>     Version JDK (défaut: 21)
    --python <version>   Version Python (défaut: 3.12)
    --go <version>       Version Go (défaut: 1.23)
    --php <version>      Version PHP (défaut: 8.3)
    --dotnet <version>   Version .NET SDK (défaut: 9.0)
    --registry <hote>    Registre conteneurs (défaut: ghcr.io)
    --cron <expr>        Cron 5 champs (défaut: 0 3 * * *)
    --force              Écrase un workflow existant
    --dry-run            Génère sans écrire (sortie stdout)
    --skip-validation    Saute la validation YAML (DÉCONSEILLÉ)
    --no-color           Désactive les couleurs ANSI
    --quiet, -q          Seules les erreurs s'affichent
    -h, --help           Affiche cette aide

EXEMPLES:
    ./nexus-ci-generator.sh aegis --node 22
    ./nexus-ci-generator.sh python --dir ~/projets/api --python 3.11
    ./nexus-ci-generator.sh docker --registry ghcr.io --force
    ./nexus-ci-generator.sh nightly --cron '30 2 * * 1'
    ./nexus-ci-generator.sh validate .github/workflows/nexus-aegis.yml
    ./nexus-ci-generator.sh explain aegis
    ./nexus-ci-generator.sh selftest

CODES DE RETOUR:
    0  succès
    1  erreur générique
    2  usage incorrect
    3  environnement invalide (pas un dépôt git, outils absents)
    4  collision de fichier (workflow déjà présent, sans --force)
    5  validation YAML échouée

ENVIRONNEMENT:
    bash >= 4, git, python3 + module PyYAML (validation YAML).
    La variable NO_COLOR=1 est respectée (convention no-color.org).

NEXUS_USAGE
}

# ============================================================================
# SECTION 8 — UTILITAIRES GÉNÉRAUX
# ============================================================================
# Vérifie qu'un type fait partie du registre officiel.
is_known_type() {
    local t
    for t in "${TYPES_ORDER[@]}"; do
        if [ "$t" = "$1" ]; then
            return 0
        fi
    done
    return 1
}

# Vérifie qu'une commande externe existe, sinon message + échec.
require_cmd() {
    if command -v "$1" >/dev/null 2>&1; then
        return 0
    fi
    log_err "commande requise absente: $1"
    return 1
}

# Confirmation interactive. Règles de sécurité:
#   - OPT_FORCE=1 -> oui sans question (mode script/selftest)
#   - stdin non interactif (pipe, CI) -> REFUS: on ne supprime rien en
#     aveugle; l'utilisateur doit passer --force explicitement.
confirm() {
    local reply
    if [ "${OPT_FORCE:-0}" -eq 1 ]; then
        return 0
    fi
    if [ ! -t 0 ]; then
        log_warn "stdin non interactif -> refus automatique (utilise --force)"
        return 1
    fi
    printf '%s [y/N] ' "$1"
    read -r reply
    case "$reply" in
        y|Y|yes|oui|o|O) return 0 ;;
        *) return 1 ;;
    esac
}

# Conseils post-installation affichés après chaque génération réussie.
# Contenu réel et actionnable : commit, secrets éventuels, prochaines
# étapes spécifiques au type généré.
print_next_steps() {
    local type="$1"
    local target="$2"
    if [ "$NEXUS_QUIET" -eq 1 ]; then
        return 0
    fi
    printf '\n'
    log_info "prochaines étapes:"
    printf '  %s\n' "1. inspecter le fichier   : ${C_BOLD}less $target${C_RESET}"
    printf '  %s\n' "2. committer             : git add $target && git commit -m 'ci: add nexus $type workflow'"
    printf '  %s\n' "3. pousser et observer   : la première exécution partira au prochain push"
    case "$type" in
        aegis|node)
            printf '  %s\n' "4. le workflow exige 'npm test' -> sinon adapte la step test (voir --explain $type)"
            ;;
        python)
            printf '  %s\n' "4. pytest doit exister -> sinon: pip install pytest pytest-cov (voir --explain $type)"
            ;;
        java)
            printf '  %s\n' "4. le workflow exige pom.xml a la racine (voir --explain $type)"
            ;;
        docker)
            printf '  %s\n' "4. le workflow exige un Dockerfile a la racine (voir --explain $type)"
            ;;
        go)
            printf '  %s\n' "4. le workflow exige go.mod a la racine (voir --explain $type)"
            ;;
        php)
            printf '  %s\n' "4. le workflow exige composer.json + phpunit.xml (voir --explain $type)"
            ;;
        dotnet)
            printf '  %s\n' "4. le workflow exige un .sln ou .csproj a la racine (voir --explain $type)"
            ;;
        cpp)
            printf '  %s\n' "4. le workflow exige CMakeLists.txt + tests CTest (voir --explain $type)"
            ;;
        android)
            printf '  %s\n' "4. le workflow exige gradlew executable commite (voir --explain $type)"
            ;;
        rust)
            printf '  %s\n' "4. le workflow exige Cargo.toml a la racine (voir --explain $type)"
            ;;
        release)
            printf '  %s\n' "4. trigger: git tag v1.0.0 && git push --tags"
            ;;
        nightly)
            printf '  %s\n' "4. le cron tourne a l'heure UTC configuree (defaut: 03:00)"
            ;;
    esac
}
# ============================================================================
# SECTION 9 — OPTIONS ET PARSING
# ============================================================================
# Toutes les options ont une valeur par défaut assignée AVANT parse_args :
# set -u ne pardonne pas la variable non initialisée.
OPT_DIR="$DEFAULT_DIR"
OPT_BRANCH="$DEFAULT_BRANCH"
OPT_NODE="$DEFAULT_NODE"
OPT_JAVA="$DEFAULT_JAVA"
OPT_PYTHON="$DEFAULT_PYTHON"
OPT_GO="$DEFAULT_GO"
OPT_PHP="$DEFAULT_PHP"
OPT_DOTNET="$DEFAULT_DOTNET"
OPT_REGISTRY="$DEFAULT_REGISTRY"
OPT_CRON="$DEFAULT_CRON"
OPT_FORCE=0
OPT_DRYRUN=0
OPT_SKIP_VALIDATION=0
OPT_QUIET=0
OPT_HELP=0
OPT_POSITIONAL=()

# parse_args : consomme "$@" (après extraction de la commande principale).
# Les valeurs manquantes et options inconnues sont des erreurs d'usage
# (exit 2) — jamais de comportement implicite.
parse_args() {
    while [ $# -gt 0 ]; do
        case "$1" in
            --dir)
                if [ $# -lt 2 ]; then die "option --dir requiert une valeur" "$EXIT_USAGE"; fi
                OPT_DIR="$2"; shift 2 ;;
            --branch)
                if [ $# -lt 2 ]; then die "option --branch requiert une valeur" "$EXIT_USAGE"; fi
                OPT_BRANCH="$2"; shift 2 ;;
            --node)
                if [ $# -lt 2 ]; then die "option --node requiert une valeur" "$EXIT_USAGE"; fi
                OPT_NODE="$2"; shift 2 ;;
            --java)
                if [ $# -lt 2 ]; then die "option --java requiert une valeur" "$EXIT_USAGE"; fi
                OPT_JAVA="$2"; shift 2 ;;
            --python)
                if [ $# -lt 2 ]; then die "option --python requiert une valeur" "$EXIT_USAGE"; fi
                OPT_PYTHON="$2"; shift 2 ;;
            --go)
                if [ $# -lt 2 ]; then die "option --go requiert une valeur" "$EXIT_USAGE"; fi
                OPT_GO="$2"; shift 2 ;;
            --php)
                if [ $# -lt 2 ]; then die "option --php requiert une valeur" "$EXIT_USAGE"; fi
                OPT_PHP="$2"; shift 2 ;;
            --dotnet)
                if [ $# -lt 2 ]; then die "option --dotnet requiert une valeur" "$EXIT_USAGE"; fi
                OPT_DOTNET="$2"; shift 2 ;;
            --registry)
                if [ $# -lt 2 ]; then die "option --registry requiert une valeur" "$EXIT_USAGE"; fi
                OPT_REGISTRY="$2"; shift 2 ;;
            --cron)
                if [ $# -lt 2 ]; then die "option --cron requiert une valeur" "$EXIT_USAGE"; fi
                OPT_CRON="$2"; shift 2 ;;
            --force)
                OPT_FORCE=1; shift ;;
            --dry-run)
                OPT_DRYRUN=1; shift ;;
            --skip-validation)
                OPT_SKIP_VALIDATION=1; shift ;;
            --no-color)
                shift ;;
            --quiet|-q)
                OPT_QUIET=1
                NEXUS_QUIET=1
                shift ;;
            -h|--help)
                OPT_HELP=1; shift ;;
            --)
                shift
                while [ $# -gt 0 ]; do
                    OPT_POSITIONAL+=("$1"); shift
                done
                break ;;
            -*)
                die "option inconnue: $1 (voir --help)" "$EXIT_USAGE" ;;
            *)
                OPT_POSITIONAL+=("$1"); shift ;;
        esac
    done
}

# Si -h/--help est présent n'importe où : on affiche l'aide et on sort 0.
handle_help_flag() {
    if [ "$OPT_HELP" -eq 1 ]; then
        usage
        exit "$EXIT_OK"
    fi
}

# ============================================================================
# SECTION 10 — VALIDATEURS D'ENTRÉES
# ============================================================================
# Aucune valeur fournie par l'utilisateur n'atteint sed sans validation :
# les placeholders sont substitués via `s|__X__|v|g` (délimiteur |), donc
# tout caractère hostile dans v casserait la commande sed ET le YAML.

# Versions: 22, 3.12, 1.23, 21, 17 (chiffres et points, max 4 segments)
valid_version() {
    if [[ "$1" =~ ^[0-9]+(\.[0-9]+){0,3}$ ]]; then
        return 0
    fi
    return 1
}

# Branches: lettres, chiffres, . _ / - (ex: main, develop, release/1.2,
# feature/new-login). Les '..' et espaces sont interdits.
valid_branch() {
    if [[ "$1" =~ ^[A-Za-z0-9._/-]+$ ]] && [[ "$1" != *..* ]]; then
        return 0
    fi
    return 1
}

# Cron GitHub Actions: exactement 5 champs, caractères autorisés par la
# syntaxe POSIX cron étendue (pas de @units ici, GH les supporte mais on
# reste sur 5 champs pour des schedules auditéables).
valid_cron() {
    local -a fields
    read -ra fields <<<"$1"
    if [ "${#fields[@]}" -ne 5 ]; then
        return 1
    fi
    local f
    for f in "${fields[@]}"; do
        if ! [[ "$f" =~ ^[0-9*/,-]+$ ]]; then
            return 1
        fi
    done
    return 0
}

# Registre: hôte[:port]/chemin optionnel (ghcr.io, registry.local:5000/team)
valid_registry() {
    if [[ "$1" =~ ^[A-Za-z0-9._-]+(:[0-9]+)?(/[A-Za-z0-9._/-]*)?$ ]]; then
        return 0
    fi
    return 1
}

# Matrice par type: on ne valide QUE les options pertinentes au type
# demandé — les autres gardent leur valeur par défaut et ne sont pas
# injectées dans le template (elles seraient du bruit).
validate_generation_options() {
    local type="$1"
    log_step "Validation des options pour le type '$type'"
    if ! valid_branch "$OPT_BRANCH"; then
        die "branche invalide: '$OPT_BRANCH' (autorisé: A-Za-z0-9._/- , pas de ..)" "$EXIT_USAGE"
    fi
    case "$type" in
        aegis|node)
            if ! valid_version "$OPT_NODE"; then
                die "version Node invalide: '$OPT_NODE' (attendu: 22, 20, 18.19...)" "$EXIT_USAGE"
            fi
            ;;
        java)
            if ! valid_version "$OPT_JAVA"; then
                die "version JDK invalide: '$OPT_JAVA' (attendu: 21, 17, 11...)" "$EXIT_USAGE"
            fi
            ;;
        python)
            if ! valid_version "$OPT_PYTHON"; then
                die "version Python invalide: '$OPT_PYTHON' (attendu: 3.12, 3.11...)" "$EXIT_USAGE"
            fi
            ;;
        go)
            if ! valid_version "$OPT_GO"; then
                die "version Go invalide: '$OPT_GO' (attendu: 1.23, 1.22...)" "$EXIT_USAGE"
            fi
            ;;
        php)
            if ! valid_version "$OPT_PHP"; then
                die "version PHP invalide: '$OPT_PHP' (attendu: 8.3, 8.2...)" "$EXIT_USAGE"
            fi
            ;;
        dotnet)
            if ! valid_version "$OPT_DOTNET"; then
                die "version .NET SDK invalide: '$OPT_DOTNET' (attendu: 9.0, 8.0...)" "$EXIT_USAGE"
            fi
            ;;
        docker)
            if ! valid_registry "$OPT_REGISTRY"; then
                die "registre invalide: '$OPT_REGISTRY' (attendu: hôte[:port]/chemin)" "$EXIT_USAGE"
            fi
            ;;
        nightly)
            if ! valid_cron "$OPT_CRON"; then
                die "cron invalide: '$OPT_CRON' (attendu: 5 champs, ex: 0 3 * * *)" "$EXIT_USAGE"
            fi
            ;;
    esac
    log_ok "options valides (branch=$OPT_BRANCH)"
}

# ============================================================================
# SECTION 11 — CHECK ENVIRONNEMENT (fonction du skeleton, conservée)
# ============================================================================
# Contrats vérifiés, dans l'ordre du moins coûteux au plus coûteux:
#   1. le répertoire cible existe
#   2. c'est un dépôt git (.git ou rev-parse) — un workflow hors dépôt
#      n'a aucun sens et GitHub ne le lira jamais
#   3. python3 + PyYAML présents si la validation est demandée
#   4. le répertoire .github/workflows est créé proprement
check_env() {
    local dir="$OPT_DIR"
    if [ ! -d "$dir" ]; then
        die "répertoire cible inexistant: $dir" "$EXIT_ENV"
    fi
    if ! git -C "$dir" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        die "$dir n'est pas un dépôt git (check_env exige un dépôt avec .git)" "$EXIT_ENV"
    fi
    if [ "$OPT_SKIP_VALIDATION" -eq 0 ]; then
        if ! require_cmd python3; then
            die "python3 requis pour la validation YAML (ou --skip-validation, déconseillé)" "$EXIT_ENV"
        fi
        if ! python3 -c "import yaml" >/dev/null 2>&1; then
            die "module python 'yaml' (PyYAML) introuvable -> pip install pyyaml, ou --skip-validation" "$EXIT_ENV"
        fi
    fi
    if [ "$OPT_DRYRUN" -eq 0 ]; then
        if ! mkdir -p "$dir/.github/workflows" 2>/dev/null; then
            die "impossible de créer $dir/.github/workflows (permissions ?)" "$EXIT_ENV"
        fi
    fi
    log_ok "environnement OK (dépôt git: $dir)"
}

# ============================================================================
# SECTION 12 — VALIDATEUR YAML (syntaxe + structure)
# ============================================================================
# Le validateur ne se contente pas de "ça parse" : il impose une structure
# de workflow GitHub Actions réelle :
#   - racine = mapping
#   - déclencheur présent ('on' — PyYAML 1.1 le parse parfois en clé True,
#     on gère les deux formes explicitement, quirk documenté)
#   - jobs non vide, chaque job a runs-on
#   - anti-bug skeleton : AUCUNE ligne `run: actions/...` (une action
#     GitHub n'est PAS une commande shell — PROTON ④)
#   - clés dupliquées rejetées : PyYAML standard les ignore (dernière
#     gagne, silencieusement) mais GitHub Actions les refuse au parse.
#     Un loader custom rend le bug visible AVANT l'installation.
validate_yaml_file() {
    local target="$1"
    if [ "$OPT_SKIP_VALIDATION" -eq 1 ]; then
        log_warn "validation YAML sautée (--skip-validation) — $target NON vérifié"
        return 0
    fi
    if [ ! -f "$target" ]; then
        log_err "fichier introuvable: $target"
        return 1
    fi
    if grep -qE '^[[:space:]]*run:.*actions/' "$target"; then
        log_err "YAML ILLÉGAL détecté: une action GitHub est exécutée comme du shell"
        log_err "pattern interdit trouvé: 'run: actions/...' dans $target"
        return 1
    fi
    python3 - "$target" <<'NEXUS_PY'
import sys
import yaml

class DuplicateKeyLoader(yaml.SafeLoader):
    """SafeLoader + rejet des clés dupliquées.
    PyYAML standard garde la derniere valeur sans erreur ; GitHub
    Actions, lui, refuse le fichier. On aligne le validateur sur la
    realite de GitHub : un doublon est une ERREUR, pas un choix."""
    pass

def _no_dupes(loader, node, deep=False):
    mapping = {}
    for key_node, value_node in node.value:
        key = loader.construct_object(key_node, deep=deep)
        if key in mapping:
            raise yaml.constructor.ConstructorError(
                "doublon",
                None,
                f"clé dupliquée: {key!r}",
                key_node.start_mark,
            )
        mapping[key] = loader.construct_object(value_node, deep=deep)
    return mapping

DuplicateKeyLoader.add_constructor(
    yaml.resolver.BaseResolver.DEFAULT_MAPPING_TAG, _no_dupes
)

path = sys.argv[1]
try:
    with open(path, "r", encoding="utf-8") as fh:
        data = yaml.load(fh, Loader=DuplicateKeyLoader)
except yaml.YAMLError as exc:
    print(f"YAML_SYNTAXE_INVALIDE: {exc}")
    sys.exit(5)
except OSError as exc:
    print(f"YAML_ILLISIBLE: {exc}")
    sys.exit(5)

if not isinstance(data, dict):
    print("YAML_STRUCTURE_INVALIDE: la racine n'est pas un mapping")
    sys.exit(5)

# Quirk PyYAML (spec YAML 1.1) : la clé 'on' est parsée en booléen True.
# GitHub Actions accepte les deux formes d'écriture dans le fichier.
has_trigger = ("on" in data) or (True in data)
if not has_trigger:
    print("YAML_STRUCTURE_INVALIDE: déclencheur 'on' absent")
    sys.exit(5)

jobs = data.get("jobs")
if not isinstance(jobs, dict) or len(jobs) == 0:
    print("YAML_STRUCTURE_INVALIDE: 'jobs' absent ou vide")
    sys.exit(5)

for name, job in jobs.items():
    if not isinstance(job, dict) or "runs-on" not in job:
        print(f"YAML_STRUCTURE_INVALIDE: job '{name}' sans 'runs-on'")
        sys.exit(5)

print("YAML_VALIDE")
sys.exit(0)
NEXUS_PY
}

# ============================================================================
# SECTION 13 — SUBSTITUTION DES PLACEHOLDERS ET ÉCRITURE ATOMIQUE
# ============================================================================
# Les templates YAML sont écrits dans des heredocs QUOTÉS (<<'NEXUS_YAML')
# pour que bash n'interprète RIEN : les expressions GitHub ${{ ... }} sont
# neutres. Les valeurs utilisateur entrent APRÈS coup par substitution de
# placeholders __X__ via sed avec délimiteur | (tolère les / des branches).
apply_placeholders() {
    local file="$1"
    NODE_MATRIX="[$(printf '%s\n' "$OPT_NODE" 20 22 | awk '!seen[$0]++' | paste -sd, - | sed 's/,/, /g')]"
    PHP_MATRIX="[$(printf "'%s'\n" '8.2' '8.3' "$OPT_PHP" | awk '!seen[$0]++' | paste -sd, - | sed 's/,/, /g')]"
    sed -i \
        -e "s|__BRANCH__|$OPT_BRANCH|g" \
        -e "s|__NODE__|$OPT_NODE|g" -e "s|__NODE_MATRIX__|$NODE_MATRIX|g" \
        -e "s|__JAVA__|$OPT_JAVA|g" \
        -e "s|__PYTHON__|$OPT_PYTHON|g" \
        -e "s|__GO__|$OPT_GO|g" \
        -e "s|__PHP__|$OPT_PHP|g" -e "s|__PHP_MATRIX__|$PHP_MATRIX|g" \
        -e "s|__DOTNET__|$OPT_DOTNET|g" \
        -e "s|__REGISTRY__|$OPT_REGISTRY|g" \
        -e "s|__CRON__|$OPT_CRON|g" \
        -e "s|__DATE__|$NEXUS_GEN_DATE|g" \
        -e "s|__GENVER__|$NEXUS_VERSION|g" \
        -e "s|__WORKFLOW_FILE__|$(basename "$file")|g" \
        "$file"
}

# Pipeline de génération complet pour un type donné :
#   inject_<type> > tmp -> placeholders -> validation -> installation.
# Contrats PROTON :
#   - jamais de YAML cassé installé (validation avant mv)
#   - installation atomique (mv sur le même filesystem)
#   - collision = exit 4 sauf --force ; --dry-run n'écrit jamais
generate_workflow() {
    local type="$1"
    local file="${WORKFLOW_FILE[$type]}"
    local target_dir="$OPT_DIR/.github/workflows"
    local target="$target_dir/$file"
    local tmp

    check_env

    if [ "$OPT_DRYRUN" -eq 0 ]; then
        if [ -e "$target" ] && [ "$OPT_FORCE" -eq 0 ]; then
            die "collision: $target existe déjà (utilise --force pour écraser)" "$EXIT_COLLISION"
        fi
    fi

    log_step "Génération du workflow '$type' -> $file"
    tmp="$(nexus_tmp_new "$target_dir")"
    "inject_${type}" >"$tmp"
    apply_placeholders "$tmp"

    if ! validate_yaml_file "$tmp"; then
        rm -f "$tmp"
        die "validation YAML échouée pour '$type' — fichier NON installé" "$EXIT_YAML"
    fi

    if [ "$OPT_DRYRUN" -eq 1 ]; then
        printf '%s\n' "${C_DIM}--- dry-run: $file (${NEXUS_GEN_DATE}) ---${C_RESET}"
        cat "$tmp"
        printf '%s\n' "${C_DIM}--- fin dry-run: rien n'a été écrit ---${C_RESET}"
        rm -f "$tmp"
        return 0
    fi

    mv -f "$tmp" "$target"
    chmod 0644 "$target"
    log_ok "workflow installé: $target ($(wc -l <"$target") lignes)"
    print_next_steps "$type" "$target"
}
# ============================================================================
# SECTION 14 — TEMPLATE aegis (Next.js) — BUG DU SKELETON CORRIGÉ (PROTON ④)
# ============================================================================
# PROTON ④ — Réparation chirurgicale, documentée :
#   Dans le skeleton v1, le job de setup contenait :
#       - name: Setup Environment
#         run: actions/setup-node@v4        <- ILLÉGAL
#   Une action GitHub s'invoque avec `uses:`, JAMAIS via `run:` (run =
#   commande shell). Résultat dans le skeleton : la ligne était exécutée
#   comme du shell par GitHub et le workflow plantait à chaque run.
#   Version corrigée ici :
#       - name: Setup Environment
#         uses: actions/setup-node@v4
#         with:
#           node-version: '__NODE__'
#           cache: 'npm'
#   Preuve d'exécution : cmd_selftest génère ce fichier, le valide en YAML,
#   ET vérifie qu'aucune ligne `run: actions/` n'existe (validate_yaml_file).
inject_aegis() {
    cat <<'NEXUS_YAML'
# =============================================================================
# NEXUS AEGIS — pipeline sécurité & qualité Next.js
# Généré par NEXUS CI GENERATOR v__GENVER__ le __DATE__ (type: aegis)
# Fichier: __WORKFLOW_FILE__ | Branche: __BRANCH__ | Node: __NODE__
# -----------------------------------------------------------------------------
# Chaîne de contrôle (fail fast : les étapes peu coûteuses d'abord) :
#   1. changes   : filtre les jobs sur les fichiers réellement touchés
#   2. secrets   : gitleaks — scan des secrets committés (bloquant)
#   3. lint      : ESLint zéro tolérance (--max-warnings=0)
#   4. typecheck : tsc --noEmit (sanction OMEGA R4 — pas de build sans types)
#   5. test      : suite de tests avec cache npm
#   6. build     : next build — preuve que le projet compile
#   7. codeql    : analyse statique de sécurité (SARIF -> onglet Security)
#   8. trivy     : scan CVE filesystem (SARIF -> onglet Security)
#   9. slsa      : attestation de provenance du build (supply chain)
# Secrets requis : aucun (GITHUB_TOKEN auto suffit).
# =============================================================================
name: 'NEXUS AEGIS (securite & qualite)'
on:
  push:
    branches: [__BRANCH__]
  pull_request:
    branches: [__BRANCH__]
  workflow_dispatch:

permissions:
  contents: read

concurrency:
  group: 'nexus-aegis-${{ github.ref }}'
  cancel-in-progress: true

jobs:
  # -------------------------------------------------------------------
  # JOB 1/9 : changes — détection des fichiers modifiés (paths-filter).
  # But : ne pas faire tourner lint/test/build si seul un README a bougé.
  # -------------------------------------------------------------------
  changes:
    name: 'Detection des fichiers modifies'
    runs-on: ubuntu-latest
    permissions:
      contents: read
      pull-requests: read
    outputs:
      src: ${{ steps.filter.outputs.src }}
    steps:
      - name: 'Checkout'
        uses: actions/checkout@v4
      - name: 'Filtrer par chemin'
        id: filter
        uses: dorny/paths-filter@v3
        with:
          filters: |
            src:
              - 'src/**'
              - 'app/**'
              - 'pages/**'
              - 'components/**'
              - 'lib/**'
              - 'package.json'
              - 'package-lock.json'
              - 'tsconfig.json'
              - 'next.config.*'

  # -------------------------------------------------------------------
  # JOB 2/9 : secrets — gitleaks sur l'historique complet du dépôt.
  # Toujours actif (même sur doc) : un secret commité reste un incident.
  # -------------------------------------------------------------------
  secrets:
    name: 'Gitleaks — scan de secrets'
    runs-on: ubuntu-latest
    steps:
      - name: 'Checkout (historique complet)'
        uses: actions/checkout@v4
        with:
          fetch-depth: 0
      - name: 'Gitleaks'
        uses: gitleaks/gitleaks-action@v2
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}

  # -------------------------------------------------------------------
  # JOB 3/9 : lint — ESLint strict. Zéro warning toléré : un warning
  # laissé passer aujourd'hui, c'est une erreur ignorée demain.
  # -------------------------------------------------------------------
  lint:
    name: 'ESLint (zero warning)'
    needs: changes
    if: needs.changes.outputs.src == 'true'
    runs-on: ubuntu-latest
    steps:
      - name: 'Checkout'
        uses: actions/checkout@v4
      - name: 'Setup Environment'
        uses: actions/setup-node@v4
        with:
          node-version: '__NODE__'
          cache: 'npm'
      - name: 'Installer les dependances (lockfile requis)'
        run: npm ci
      - name: 'ESLint — max-warnings=0'
        run: npx eslint . --max-warnings=0

  # -------------------------------------------------------------------
  # JOB 4/9 : typecheck — tsc --noEmit. Le type est un test gratuit :
  #   il attrape la classe entière des bugs "undefined is not a function".
  # -------------------------------------------------------------------
  typecheck:
    name: 'TypeScript (tsc --noEmit)'
    needs: changes
    if: needs.changes.outputs.src == 'true'
    runs-on: ubuntu-latest
    steps:
      - name: 'Checkout'
        uses: actions/checkout@v4
      - name: 'Setup Environment'
        uses: actions/setup-node@v4
        with:
          node-version: '__NODE__'
          cache: 'npm'
      - name: 'Installer les dependances (lockfile requis)'
        run: npm ci
      - name: 'tsc --noEmit'
        run: npx tsc --noEmit

  # -------------------------------------------------------------------
  # JOB 5/9 : test — suite de tests (vitest/jest selon package.json).
  # Adapter le script 'test' dans package.json si besoin.
  # -------------------------------------------------------------------
  test:
    name: 'Tests unitaires'
    needs: changes
    if: needs.changes.outputs.src == 'true'
    runs-on: ubuntu-latest
    steps:
      - name: 'Checkout'
        uses: actions/checkout@v4
      - name: 'Setup Environment'
        uses: actions/setup-node@v4
        with:
          node-version: '__NODE__'
          cache: 'npm'
      - name: 'Installer les dependances (lockfile requis)'
        run: npm ci
      - name: 'Jouer la suite de tests'
        run: npm test -- --ci --coverage
      - name: 'Uploader le rapport de coverage'
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: nexus-coverage
          path: coverage/
          retention-days: 7
          if-no-files-found: ignore

  # -------------------------------------------------------------------
  # JOB 6/9 : build — next build. Un projet qui ne build pas en CI ne
  #   build nulle part. Produit un artefact consommé par le job SLSA.
  # -------------------------------------------------------------------
  build:
    name: 'Build production'
    needs: changes
    if: needs.changes.outputs.src == 'true'
    runs-on: ubuntu-latest
    steps:
      - name: 'Checkout'
        uses: actions/checkout@v4
      - name: 'Setup Environment'
        uses: actions/setup-node@v4
        with:
          node-version: '__NODE__'
          cache: 'npm'
      - name: 'Installer les dependances (lockfile requis)'
        run: npm ci
      - name: 'Build production (next build)'
        run: npm run build
        env:
          NEXT_TELEMETRY_DISABLED: '1'
      - name: 'Uploader l artefact de build'
        uses: actions/upload-artifact@v4
        with:
          name: nexus-build
          path: .next/
          retention-days: 7

  # -------------------------------------------------------------------
  # JOB 7/9 : codeql — analyse statique orientée sécurité (queries
  #   security-extended). Remonte en SARIF dans l'onglet Security.
  # -------------------------------------------------------------------
  codeql:
    name: 'CodeQL (securite statique)'
    needs: changes
    if: needs.changes.outputs.src == 'true'
    runs-on: ubuntu-latest
    permissions:
      contents: read
      security-events: write
    strategy:
      matrix:
        language: [javascript-typescript]
    steps:
      - name: 'Checkout'
        uses: actions/checkout@v4
      - name: 'Initialisation CodeQL'
        uses: github/codeql-action/init@v3
        with:
          languages: ${{ matrix.language }}
          queries: security-extended
      - name: 'Autobuild'
        uses: github/codeql-action/autobuild@v3
      - name: 'Analyse CodeQL'
        uses: github/codeql-action/analyze@v3
        with:
          category: '/language:${{ matrix.language }}'

  # -------------------------------------------------------------------
  # JOB 8/9 : trivy — scan CVE du filesystem (dépendances incluses).
  #   exit-code 1 sur HIGH/CRITICAL : fail ferme, pas de CVE ignorée.
  # -------------------------------------------------------------------
  trivy:
    name: 'Trivy (CVE filesystem)'
    runs-on: ubuntu-latest
    permissions:
      contents: read
      security-events: write
    steps:
      - name: 'Checkout'
        uses: actions/checkout@v4
      - name: 'Trivy filesystem scan'
        uses: aquasecurity/trivy-action@0.28.0
        with:
          scan-type: fs
          severity: HIGH,CRITICAL
          exit-code: '1'
          ignore-unfixed: true
          format: sarif
          output: trivy-results.sarif
      - name: 'Uploader le SARIF'
        uses: github/codeql-action/upload-sarif@v3
        with:
          sarif_file: trivy-results.sarif

  # -------------------------------------------------------------------
  # JOB 9/9 : slsa — attestation de provenance du build (supply chain).
  #   La pièce jointe .buildprovenance permet d'auditer QUI a buildé
  #   QUOI, sur quelle infra, avec quel commit — sans confiance aveugle.
  # -------------------------------------------------------------------
  slsa:
    name: 'SLSA (attestation provenance)'
    needs: [changes, build]
    if: needs.changes.outputs.src == 'true'
    runs-on: ubuntu-latest
    permissions:
      id-token: write
      attestations: write
      contents: read
    steps:
      - name: 'Recuperer l artefact de build'
        uses: actions/download-artifact@v4
        with:
          name: nexus-build
          path: .next-attest
      - name: 'Attestation SLSA build provenance'
        uses: actions/attest-build-provenance@v1
        with:
          subject-path: '.next-attest/**'

NEXUS_YAML
}
# ============================================================================
# SECTION 15 — TEMPLATE java (Maven multi-JDK)
# ============================================================================
# Pipeline Maven complet : la matrice JDK [17, __JAVA__] prouve la
# compatibilité LTS au lieu de la supposer. OWASP dependency-check tourne
# en job séparé (lourd) et ne bloque pas la matrice rapide.
inject_java() {
    cat <<'NEXUS_YAML'
# =============================================================================
# NEXUS JAVA — pipeline Maven multi-JDK
# Généré par NEXUS CI GENERATOR v__GENVER__ le __DATE__ (type: java)
# Fichier: __WORKFLOW_FILE__ | Branche: __BRANCH__ | JDK: __JAVA__
# -----------------------------------------------------------------------------
# Chaîne de contrôle :
#   1. build      : matrice JDK [17, __JAVA__] — compile + tests + package
#   2. owasp      : dependency-check CVE sur les dépendances Maven
#   3. codeql     : analyse statique de sécurité (language: java-kotlin)
# Exige : pom.xml à la racine du dépôt.
# Secrets requis : aucun (GITHUB_TOKEN auto suffit).
# =============================================================================
name: 'NEXUS JAVA (maven multi-jdk)'
on:
  push:
    branches: [__BRANCH__]
  pull_request:
    branches: [__BRANCH__]
  workflow_dispatch:

permissions:
  contents: read

concurrency:
  group: 'nexus-java-${{ github.ref }}'
  cancel-in-progress: true

jobs:
  # -------------------------------------------------------------------
  # JOB 1/3 : build — matrice JDK. fail-fast désactivé : on veut voir
  #   les DEUX JDK échouer indépendamment, sinon le 17 cache le 21.
  # -------------------------------------------------------------------
  build:
    name: 'Maven (JDK ${{ matrix.java }})'
    runs-on: ubuntu-latest
    strategy:
      fail-fast: false
      matrix:
        java: [17, __JAVA__]
    steps:
      - name: 'Checkout'
        uses: actions/checkout@v4
      - name: 'Setup JDK ${{ matrix.java }} (temurin, cache maven)'
        uses: actions/setup-java@v4
        with:
          distribution: temurin
          java-version: ${{ matrix.java }}
          cache: maven
      - name: 'Vérifier la structure du projet'
        run: |
          test -f pom.xml || {
            echo "ERREUR: pom.xml manquant a la racine du dépôt"
            exit 1
          }
      - name: 'Compiler sans tests (fail fast sur la compilation)'
        run: mvn -B -ntp -DskipTests clean compile
      - name: 'Tests + vérification complète (mvn verify)'
        run: mvn -B -ntp verify
      - name: 'Uploader les JAR produits'
        uses: actions/upload-artifact@v4
        with:
          name: nexus-java-jdk${{ matrix.java }}
          path: target/*.jar
          retention-days: 7
          if-no-files-found: ignore

  # -------------------------------------------------------------------
  # JOB 2/3 : owasp — dependency-check-maven. Lourd (télécharge la base
  #   NVD) donc isolé de la matrice. Le rapport est un artefact, jamais
  #   perdu, même si le job échoue (always()).
  # -------------------------------------------------------------------
  owasp:
    name: 'OWASP dependency-check'
    needs: build
    if: github.ref == 'refs/heads/__BRANCH__'
    runs-on: ubuntu-latest
    steps:
      - name: 'Checkout'
        uses: actions/checkout@v4
      - name: 'Setup JDK (temurin, cache maven)'
        uses: actions/setup-java@v4
        with:
          distribution: temurin
          java-version: __JAVA__
          cache: maven
      - name: 'Dependency-check (CVE des dépendances)'
        run: mvn -B -ntp org.owasp:dependency-check-maven:check -DskipTests
      - name: 'Uploader le rapport OWASP'
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: nexus-owasp-report
          path: target/dependency-check-report.html
          retention-days: 14
          if-no-files-found: ignore

  # -------------------------------------------------------------------
  # JOB 3/3 : codeql — analyse statique de sécurité Java.
  # -------------------------------------------------------------------
  codeql:
    name: 'CodeQL (securite statique)'
    needs: build
    runs-on: ubuntu-latest
    permissions:
      contents: read
      security-events: write
    strategy:
      matrix:
        language: [java-kotlin]
    steps:
      - name: 'Checkout'
        uses: actions/checkout@v4
      - name: 'Initialisation CodeQL'
        uses: github/codeql-action/init@v3
        with:
          languages: ${{ matrix.language }}
      - name: 'Autobuild (Maven)'
        uses: github/codeql-action/autobuild@v3
      - name: 'Analyse CodeQL'
        uses: github/codeql-action/analyze@v3
        with:
          category: '/language:${{ matrix.language }}'

NEXUS_YAML
}

# ============================================================================
# SECTION 16 — TEMPLATE python (ruff + pytest + mypy + pip-audit)
# ============================================================================
# Pipeline qualité Python moderne : ruff (lint+format, remplace flake8/
# isort), pytest avec coverage XML, mypy tolérant par défaut (à durcir
# progressivement), pip-audit bloquant sur les CVE connues.
inject_python() {
    cat <<'NEXUS_YAML'
# =============================================================================
# NEXUS PYTHON — pipeline qualité et sécurité
# Généré par NEXUS CI GENERATOR v__GENVER__ le __DATE__ (type: python)
# Fichier: __WORKFLOW_FILE__ | Branche: __BRANCH__ | Python: __PYTHON__
# -----------------------------------------------------------------------------
# Chaîne de contrôle :
#   1. quality : matrice 3.10→3.13 — ruff, pytest+coverage, mypy
#   2. audit   : pip-audit — CVE des dépendances installées
#   3. codeql  : analyse statique de sécurité (language: python)
# Le job quality installe requirements.txt s'il existe, plus les outils
# de qualité en versions pinnées par le lockfile s'il y en a un.
# Secrets requis : aucun.
# =============================================================================
name: 'NEXUS PYTHON (qualite & securite)'
on:
  push:
    branches: [__BRANCH__]
  pull_request:
    branches: [__BRANCH__]
  workflow_dispatch:

permissions:
  contents: read

concurrency:
  group: 'nexus-python-${{ github.ref }}'
  cancel-in-progress: true

jobs:
  # -------------------------------------------------------------------
  # JOB 1/3 : quality — matrice d'interpréteurs. La valeur --python est
  #   TOUJOURS dans la matrice : votre version cible est testée en
  #   premier, les autres garantissent la compatibilité descendante.
  # -------------------------------------------------------------------
  quality:
    name: 'Qualite (py${{ matrix.python }})'
    runs-on: ubuntu-latest
    strategy:
      fail-fast: false
      matrix:
        python: [__PYTHON__, '3.10', '3.11', '3.13']
    steps:
      - name: 'Checkout'
        uses: actions/checkout@v4
      - name: 'Setup Python ${{ matrix.python }} (cache pip)'
        uses: actions/setup-python@v5
        with:
          python-version: ${{ matrix.python }}
          cache: pip
      - name: 'Installer les dépendances du projet'
        run: |
          python -m pip install --upgrade pip
          if [ -f requirements.txt ]; then
            pip install -r requirements.txt
          fi
          if [ -f requirements-dev.txt ]; then
            pip install -r requirements-dev.txt
          fi
          pip install ruff pytest pytest-cov mypy
      - name: 'Ruff — lint (bloquant)'
        run: ruff check .
      - name: 'Ruff — format (bloquant)'
        run: ruff format --check .
      - name: 'Pytest — tests + coverage'
        run: pytest --cov=. --cov-report=xml --cov-report=term -q
      - name: 'Mypy — types (tolérant par défaut, à durcir)'
        run: mypy . --ignore-missing-imports
      - name: 'Uploader le rapport de coverage'
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: nexus-coverage-py${{ matrix.python }}
          path: coverage.xml
          retention-days: 7
          if-no-files-found: ignore

  # -------------------------------------------------------------------
  # JOB 2/3 : audit — pip-audit sur l'environnement résolu. Ne tourne
  #   que sur la version cible (une seule passe suffit pour les CVE).
  # -------------------------------------------------------------------
  audit:
    name: 'pip-audit (CVE dépendances)'
    needs: quality
    runs-on: ubuntu-latest
    steps:
      - name: 'Checkout'
        uses: actions/checkout@v4
      - name: 'Setup Python (cache pip)'
        uses: actions/setup-python@v5
        with:
          python-version: '__PYTHON__'
          cache: pip
      - name: 'Installer et auditer'
        run: |
          python -m pip install --upgrade pip pip-audit
          if [ -f requirements.txt ]; then
            pip install -r requirements.txt
          fi
          pip-audit --strict

  # -------------------------------------------------------------------
  # JOB 3/3 : codeql — analyse statique de sécurité Python.
  # -------------------------------------------------------------------
  codeql:
    name: 'CodeQL (securite statique)'
    needs: quality
    runs-on: ubuntu-latest
    permissions:
      contents: read
      security-events: write
    strategy:
      matrix:
        language: [python]
    steps:
      - name: 'Checkout'
        uses: actions/checkout@v4
      - name: 'Initialisation CodeQL'
        uses: github/codeql-action/init@v3
        with:
          languages: ${{ matrix.language }}
      - name: 'Autobuild'
        uses: github/codeql-action/autobuild@v3
      - name: 'Analyse CodeQL'
        uses: github/codeql-action/analyze@v3
        with:
          category: '/language:${{ matrix.language }}'

NEXUS_YAML
}
# ============================================================================
# SECTION 17 — TEMPLATE node (npm multi-runtime)
# ============================================================================
# Pipeline npm : la matrice projet+LTS 20/22 (doublons auto-retirés)
# LTS. npm ci échoue sans lockfile — refus explicite plutôt qu'un build
# irreproductible. L'audit npm est bloquant au niveau HIGH.
inject_node() {
    cat <<'NEXUS_YAML'
# =============================================================================
# NEXUS NODE — pipeline npm multi-runtime
# Généré par NEXUS CI GENERATOR v__GENVER__ le __DATE__ (type: node)
# Fichier: __WORKFLOW_FILE__ | Branche: __BRANCH__ | Node: __NODE__
# -----------------------------------------------------------------------------
# Chaîne de contrôle :
#   1. build  : matrice Node — npm ci, lint, test, build, artefacts
#   2. audit  : npm audit --audit-level=high (bloquant)
# Exige : package.json + package-lock.json (npm ci est strict à dessein).
# Secrets requis : aucun.
# =============================================================================
name: 'NEXUS NODE (npm multi-runtime)'
on:
  push:
    branches: [__BRANCH__]
  pull_request:
    branches: [__BRANCH__]
  workflow_dispatch:

permissions:
  contents: read

concurrency:
  group: 'nexus-node-${{ github.ref }}'
  cancel-in-progress: true

jobs:
  # -------------------------------------------------------------------
  # JOB 1/2 : build — matrice de runtimes. fail-fast off : chaque
  #   runtime rapporte son verdict indépendamment.
  # -------------------------------------------------------------------
  build:
    name: 'npm (Node ${{ matrix.node }})'
    runs-on: ubuntu-latest
    strategy:
      fail-fast: false
      matrix:
        node: __NODE_MATRIX__
    steps:
      - name: 'Checkout'
        uses: actions/checkout@v4
      - name: 'Setup Node ${{ matrix.node }} (cache npm)'
        uses: actions/setup-node@v4
        with:
          node-version: '${{ matrix.node }}'
          cache: 'npm'
      - name: 'Installer les dépendances (lockfile requis)'
        run: |
          test -f package-lock.json || {
            echo "ERREUR: package-lock.json manquant — commitez le lockfile"
            exit 1
          }
          npm ci
      - name: 'Lint (si le script existe)'
        run: npm run lint --if-present
      - name: 'Tests'
        run: npm test --if-present
      - name: 'Build'
        run: npm run build --if-present
        env:
          NODE_ENV: production
      - name: 'Uploader les sorties de build'
        uses: actions/upload-artifact@v4
        with:
          name: nexus-node-${{ matrix.node }}
          path: |
            dist/
            build/
            .next/
          retention-days: 7
          if-no-files-found: ignore

  # -------------------------------------------------------------------
  # JOB 2/2 : audit — npm audit bloquant au niveau HIGH. Un CVE HIGH
  #   dans les dépendances directes arrête le pipeline : on patche
  #   d'abord, on shippe ensuite.
  # -------------------------------------------------------------------
  audit:
    name: 'npm audit (CVE HIGH+)'
    needs: build
    runs-on: ubuntu-latest
    steps:
      - name: 'Checkout'
        uses: actions/checkout@v4
      - name: 'Setup Node (cache npm)'
        uses: actions/setup-node@v4
        with:
          node-version: '__NODE__'
          cache: 'npm'
      - name: 'Audit des dépendances (bloquant HIGH/CRITICAL)'
        run: npm audit --audit-level=high

NEXUS_YAML
}

# ============================================================================
# SECTION 18 — TEMPLATE docker (image multi-arch + sécurité conteneur)
# ============================================================================
# Pipeline conteneur complet : hadolint sur le Dockerfile, buildx
# multi-arch (amd64+arm64), Trivy sur l'IMAGE construite (pas juste le
# filesystem), SBOM SPDX joint, push vers __REGISTRY__ hors PR.
inject_docker() {
    cat <<'NEXUS_YAML'
# =============================================================================
# NEXUS DOCKER — pipeline image multi-arch
# Généré par NEXUS CI GENERATOR v__GENVER__ le __DATE__ (type: docker)
# Fichier: __WORKFLOW_FILE__ | Branche: __BRANCH__ | Registre: __REGISTRY__
# -----------------------------------------------------------------------------
# Chaîne de contrôle :
#   1. lint   : hadolint sur le Dockerfile (best practices officielles)
#   2. image  : buildx linux/amd64 + linux/arm64, cache gha, push hors PR
#   3. scan   : Trivy sur l'IMAGE (exit 1 sur HIGH/CRITICAL)
#   4. sbom   : SBOM SPDX de l'image (traçabilité supply chain)
# Le push utilise GITHUB_TOKEN vers __REGISTRY__ : aucun secret manuel.
# =============================================================================
name: 'NEXUS DOCKER (image multi-arch)'
on:
  push:
    branches: [__BRANCH__]
    tags: ['v*']
  pull_request:
    branches: [__BRANCH__]
  workflow_dispatch:

permissions:
  contents: read

concurrency:
  group: 'nexus-docker-${{ github.ref }}'
  cancel-in-progress: true

env:
  REGISTRY: __REGISTRY__
  IMAGE_NAME: ${{ github.repository }}

jobs:
  # -------------------------------------------------------------------
  # JOB 1/4 : lint — hadolint. Un Dockerfile sale aujourd'hui, c'est
  #   une image de 900 Mo et une attaque de surface demain.
  # -------------------------------------------------------------------
  lint:
    name: 'Hadolint (Dockerfile)'
    runs-on: ubuntu-latest
    steps:
      - name: 'Checkout'
        uses: actions/checkout@v4
      - name: 'Hadolint'
        uses: hadolint/hadolint-action@v3.1.0
        with:
          dockerfile: Dockerfile
          failure-threshold: warning

  # -------------------------------------------------------------------
  # JOB 2/4 : image — build multi-arch. metadata-action génère les
  #   tags (sha, semver sur tag v*, latest sur release) et les labels
  #   OCI (source, revision) pour une image traçable.
  # -------------------------------------------------------------------
  image:
    name: 'Buildx multi-arch (amd64+arm64)'
    needs: lint
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: write
    steps:
      - name: 'Checkout'
        uses: actions/checkout@v4
      - name: 'QEMU (émulation arm64)'
        uses: docker/setup-qemu-action@v3
      - name: 'Buildx'
        uses: docker/setup-buildx-action@v3
      - name: 'Login au registre (hors PR)'
        if: github.event_name != 'pull_request'
        uses: docker/login-action@v3
        with:
          registry: ${{ env.REGISTRY }}
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}
      - name: 'Tags et labels OCI'
        id: meta
        uses: docker/metadata-action@v5
        with:
          images: ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}
          tags: |
            type=ref,event=branch
            type=sha,prefix=sha-
            type=semver,pattern={{version}}
            type=semver,pattern={{major}}.{{minor}}
            type=raw,value=latest,enable={{is_default_branch}}
      - name: 'Build (et push hors PR)'
        uses: docker/build-push-action@v6
        with:
          context: .
          platforms: linux/amd64,linux/arm64
          push: ${{ github.event_name != 'pull_request' }}
          tags: ${{ steps.meta.outputs.tags }}
          labels: ${{ steps.meta.outputs.labels }}
          cache-from: type=gha
          cache-to: type=gha,mode=max

  # -------------------------------------------------------------------
  # JOB 3/4 : scan — Trivy sur l'image produite. Plus fort qu'un scan
  #   filesystem : il voit les CVE du runtime de l'image elle-même.
  # -------------------------------------------------------------------
  scan:
    name: 'Trivy (CVE image)'
    needs: image
    runs-on: ubuntu-latest
    permissions:
      contents: read
      security-events: write
    steps:
      - name: 'Checkout'
        uses: actions/checkout@v4
      - name: 'Trivy image scan (SARIF, bloquant)'
        uses: aquasecurity/trivy-action@0.28.0
        with:
          image-ref: ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:sha-${{ github.sha }}
          severity: HIGH,CRITICAL
          exit-code: '1'
          ignore-unfixed: true
          format: sarif
          output: trivy-image.sarif
      - name: 'Uploader le SARIF'
        if: always()
        uses: github/codeql-action/upload-sarif@v3
        with:
          sarif_file: trivy-image.sarif

  # -------------------------------------------------------------------
  # JOB 4/4 : sbom — inventaire SPDX de l'image. Sans SBOM, impossible
  #   de répondre à "quelles versions de log4j on shippe ?" en 2026.
  # -------------------------------------------------------------------
  sbom:
    name: 'SBOM (SPDX)'
    needs: image
    runs-on: ubuntu-latest
    permissions:
      contents: read
    steps:
      - name: 'Checkout'
        uses: actions/checkout@v4
      - name: 'Générer le SBOM de l image'
        uses: anchore/sbom-action@v0
        with:
          image: ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:sha-${{ github.sha }}
          format: spdx-json
          artifact-name: nexus-sbom.spdx.json

NEXUS_YAML
}
# ============================================================================
# SECTION 19 — TEMPLATE go (lint + tests race + goreleaser)
# ============================================================================
# Pipeline Go : golangci-lint (le standard de facto), tests avec détection
# de race conditions (-race), coverage atomique, goreleaser sur tag.
inject_go() {
    cat <<'NEXUS_YAML'
# =============================================================================
# NEXUS GO — pipeline qualité et release
# Généré par NEXUS CI GENERATOR v__GENVER__ le __DATE__ (type: go)
# Fichier: __WORKFLOW_FILE__ | Branche: __BRANCH__ | Go: __GO__
# -----------------------------------------------------------------------------
# Chaîne de contrôle :
#   1. quality : golangci-lint, vet, tests -race + coverage, build
#   2. release : goreleaser UNIQUEMENT sur tag v* (sinon skip)
# Exige : go.mod à la racine du dépôt.
# Secrets requis : aucun (GITHUB_TOKEN suffit pour goreleaser).
# =============================================================================
name: 'NEXUS GO (qualite & release)'
on:
  push:
    branches: [__BRANCH__]
    tags: ['v*']
  pull_request:
    branches: [__BRANCH__]
  workflow_dispatch:

permissions:
  contents: read

concurrency:
  group: 'nexus-go-${{ github.ref }}'
  cancel-in-progress: true

jobs:
  # -------------------------------------------------------------------
  # JOB 1/2 : quality — lint ET tests dans le même job : le runner est
  #   déjà payé, on évite de le gaspiller en deux jobs parallèles.
  # -------------------------------------------------------------------
  quality:
    name: 'Qualite (go __GO__)'
    runs-on: ubuntu-latest
    steps:
      - name: 'Checkout'
        uses: actions/checkout@v4
      - name: 'Setup Go (cache modules)'
        uses: actions/setup-go@v5
        with:
          go-version: '__GO__'
          cache: true
      - name: 'Vérifier la structure du projet'
        run: |
          test -f go.mod || {
            echo "ERREUR: go.mod manquant a la racine du dépôt"
            exit 1
          }
      - name: 'Golangci-lint'
        uses: golangci/golangci-lint-action@v6
        with:
          version: latest
      - name: 'Vet (analyse statique standard)'
        run: go vet ./...
      - name: 'Tests avec détection de race conditions'
        run: go test -race -covermode=atomic -coverprofile=coverage.out ./...
      - name: 'Build'
        run: go build ./...
      - name: 'Uploader le profil de coverage'
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: nexus-go-coverage
          path: coverage.out
          retention-days: 7
          if-no-files-found: ignore

  # -------------------------------------------------------------------
  # JOB 2/2 : release — goreleaser. if: startsWith(github.ref, 'refs/tags/')
  #   = le job apparaît skipped sur les push normaux, et tourne SEULEMENT
  #   sur tag. C'est le pattern officiel goreleaser.
  # -------------------------------------------------------------------
  release:
    name: 'Goreleaser (sur tag v*)'
    needs: quality
    if: startsWith(github.ref, 'refs/tags/')
    runs-on: ubuntu-latest
    permissions:
      contents: write
    steps:
      - name: 'Checkout'
        uses: actions/checkout@v4
        with:
          fetch-depth: 0
      - name: 'Setup Go (cache modules)'
        uses: actions/setup-go@v5
        with:
          go-version: '__GO__'
          cache: true
      - name: 'Goreleaser release'
        uses: goreleaser/goreleaser-action@v6
        with:
          version: latest
          args: release --clean
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}

NEXUS_YAML
}

# ============================================================================
# SECTION 20 — TEMPLATE rust (fmt + clippy + test + audit)
# ============================================================================
# Pipeline Rust : fmt sur nightly (le composant rustfmt), clippy
# -D warnings (zéro tolérance), tests toutes features, cargo-audit.
inject_rust() {
    cat <<'NEXUS_YAML'
# =============================================================================
# NEXUS RUST — pipeline qualité et sécurité
# Généré par NEXUS CI GENERATOR v__GENVER__ le __DATE__ (type: rust)
# Fichier: __WORKFLOW_FILE__ | Branche: __BRANCH__ | Toolchain: stable
# -----------------------------------------------------------------------------
# Chaîne de contrôle :
#   1. fmt     : cargo fmt --check (sur nightly, où vit rustfmt)
#   2. quality : clippy -D warnings, tests --all-features, audit
#   3. release : build --release + artefact, UNIQUEMENT sur tag v*
# Exige : Cargo.toml à la racine du dépôt.
# Secrets requis : aucun.
# =============================================================================
name: 'NEXUS RUST (qualite & securite)'
on:
  push:
    branches: [__BRANCH__]
    tags: ['v*']
  pull_request:
    branches: [__BRANCH__]
  workflow_dispatch:

permissions:
  contents: read

concurrency:
  group: 'nexus-rust-${{ github.ref }}'
  cancel-in-progress: true

jobs:
  # -------------------------------------------------------------------
  # JOB 1/3 : fmt — format séparé du build : le composant rustfmt vit
  #   sur nightly, le build vit sur stable. Deux jobs = zéro compromis.
  # -------------------------------------------------------------------
  fmt:
    name: 'cargo fmt --check'
    runs-on: ubuntu-latest
    steps:
      - name: 'Checkout'
        uses: actions/checkout@v4
      - name: 'Toolchain nightly (rustfmt)'
        uses: dtolnay/rust-toolchain@nightly
        with:
          components: rustfmt
      - name: 'Vérifier le formatage'
        run: cargo fmt --all --check

  # -------------------------------------------------------------------
  # JOB 2/3 : quality — clippy avec -D warnings : tout warning EST une
  #   erreur. Le compilateur sait des choses que vous ne savez pas encore.
  # -------------------------------------------------------------------
  quality:
    name: 'clippy + tests + audit'
    runs-on: ubuntu-latest
    steps:
      - name: 'Checkout'
        uses: actions/checkout@v4
      - name: 'Toolchain stable'
        uses: dtolnay/rust-toolchain@stable
      - name: 'Cache cargo (Sarshal cache-action)'
        uses: Swatinem/rust-cache@v2
      - name: 'Clippy (zero warning toléré)'
        run: cargo clippy --all-targets -- -D warnings
      - name: 'Tests (toutes features)'
        run: cargo test --all-features
      - name: 'cargo-audit (CVE des crates)'
        uses: rustsec/audit-check@v2
        with:
          token: ${{ secrets.GITHUB_TOKEN }}

  # -------------------------------------------------------------------
  # JOB 3/3 : release — build --release sur tag uniquement. L'artefact
  #   binaire est join à la release GitHub (draft), jamais direct en
  #   prod sans revue humaine.
  # -------------------------------------------------------------------
  release:
    name: 'Build release (sur tag v*)'
    needs: [fmt, quality]
    if: startsWith(github.ref, 'refs/tags/')
    runs-on: ubuntu-latest
    permissions:
      contents: write
    steps:
      - name: 'Checkout'
        uses: actions/checkout@v4
      - name: 'Toolchain stable'
        uses: dtolnay/rust-toolchain@stable
      - name: 'Cache cargo'
        uses: Swatinem/rust-cache@v2
      - name: 'Build release'
        run: cargo build --release
      - name: 'Uploader le binaire'
        uses: actions/upload-artifact@v4
        with:
          name: nexus-rust-release
          path: target/release/
          retention-days: 14
          if-no-files-found: error

NEXUS_YAML
}
# ============================================================================
# SECTION 21 — TEMPLATE release (release GitHub sur tag v*)
# ============================================================================
# Release déclenchée par git tag v* : changelog construit depuis les PR
# merged, artefacts joints, release GitHub publiée, SLSA sur les binaires.
inject_release() {
    cat <<'NEXUS_YAML'
# =============================================================================
# NEXUS RELEASE — release GitHub sur tag v*
# Généré par NEXUS CI GENERATOR v__GENVER__ le __DATE__ (type: release)
# Fichier: __WORKFLOW_FILE__
# -----------------------------------------------------------------------------
# Déclencheur : git tag v1.2.3 && git push --tags
# Chaîne de contrôle :
#   1. build     : build via script du projet (build.sh/Makefile/package.json)
#   2. changelog : release-changelog-builder (depuis les PR merged)
#   3. publish   : gh-release avec artefacts + changelog
# Permissions minimales : contents:write (creation de la release).
# =============================================================================
name: 'NEXUS RELEASE (tag v*)'
on:
  push:
    tags: ['v*']
  workflow_dispatch:

permissions:
  contents: write

jobs:
  # -------------------------------------------------------------------
  # JOB 1/3 : build — tente build.sh, puis make, puis npm run build.
  #   --if-present en bash : aucun de ces mécanismes n'est imposé.
  # -------------------------------------------------------------------
  build:
    name: 'Build des artefacts de release'
    runs-on: ubuntu-latest
    steps:
      - name: 'Checkout'
        uses: actions/checkout@v4
      - name: 'Build du projet (script détecté automatiquement)'
        run: |
          if [ -x ./build.sh ]; then
            ./build.sh
          elif [ -f Makefile ]; then
            make build
          elif [ -f package.json ]; then
            npm ci && npm run build --if-present
          elif [ -f Cargo.toml ]; then
            cargo build --release
          elif [ -f go.mod ]; then
            go build ./...
          else
            echo "AVERTISSEMENT: aucun mécanisme de build détecté"
            echo "artefacts vides — adaptez ce job a votre projet"
          fi
      - name: 'Collecter les artefacts'
        run: |
          mkdir -p dist
          for d in dist build target/release .next out; do
            if [ -d "$d" ]; then
              cp -r "$d"/* dist/ 2>/dev/null || true
            fi
          done
      - name: 'Uploader en attente de publication'
        uses: actions/upload-artifact@v4
        with:
          name: nexus-release-dist
          path: dist/
          retention-days: 7
          if-no-files-found: ignore

  # -------------------------------------------------------------------
  # JOB 2/3 : changelog — construit depuis les PR merged entre le tag
  #   précédent et le tag courant. Configuration inline : categories par
  #   label, mention des contributeurs.
  # -------------------------------------------------------------------
  changelog:
    name: 'Changelog (PR merged)'
    needs: build
    outputs:
      changelog: ${{ steps.changelog.outputs.changelog }}
    runs-on: ubuntu-latest
    steps:
      - name: 'Checkout'
        uses: actions/checkout@v4
      - name: 'Construire le changelog'
        id: changelog
        uses: mikepenz/release-changelog-builder-action@v4
        with:
          configuration: |
            {
              "categories": [
                { "title": "Ajouts", "labels": ["feature", "enhancement"] },
                { "title": "Corrections", "labels": ["fix", "bug"] },
                { "title": "Securite", "labels": ["security"] },
                { "title": "Autres changements", "labels": [] }
              ]
            }
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}

  # -------------------------------------------------------------------
  # JOB 3/3 : publish — création de la release GitHub avec les artefacts
  #   du job build et le changelog du job précédent.
  # -------------------------------------------------------------------
  publish:
    name: 'Publication de la release'
    needs: [build, changelog]
    runs-on: ubuntu-latest
    steps:
      - name: 'Récupérer les artefacts'
        uses: actions/download-artifact@v4
        with:
          name: nexus-release-dist
          path: dist
      - name: 'Publier la release GitHub'
        uses: softprops/action-gh-release@v2
        with:
          files: dist/**
          body: ${{ needs.changelog.outputs.changelog }}
          draft: false
          generate_release_notes: true

NEXUS_YAML
}

# ============================================================================
# SECTION 22 — TEMPLATE nightly (scan nocturne complet)
# ============================================================================
# Le nightly fait ce qu'un pipeline sur push ne peut PAS faire : scanner
# sur schedule, avec l'historique complet et sans pression de temps.
# Les jobs gitleaks/codeql/trivy réexaminent TOUT le dépôt à 03:00 UTC.
inject_nightly() {
    cat <<'NEXUS_YAML'
# =============================================================================
# NEXUS NIGHTLY — scan nocturne complet
# Généré par NEXUS CI GENERATOR v__GENVER__ le __DATE__ (type: nightly)
# Fichier: __WORKFLOW_FILE__ | Cron: __CRON__ (UTC)
# -----------------------------------------------------------------------------
# Pourquoi un nightly alors que le pipeline push scanne déjà ?
#   1. Les CVE sont publiées TOUS LES JOURS : le code n'a pas bougé,
#      mais le monde a changé autour de lui.
#   2. Le scan nightly tourne sur l'historique complet sans urgencer
#      le cycle de push (gitleaks full-history, NVD à jour).
#   3. dependency full: voit les dépendances transitives ignorées en
#      quick-check.
# Sécurité anti-dérive : pas de continue-on-error sur les CVE.
# =============================================================================
name: 'NEXUS NIGHTLY (scan nocturne)'
on:
  schedule:
    - cron: '__CRON__'
  workflow_dispatch:

permissions:
  contents: read

concurrency:
  group: nexus-nightly
  cancel-in-progress: false

jobs:
  # -------------------------------------------------------------------
  # JOB 1/4 : secrets — gitleaks sur l'historique COMPLET (fetch-depth 0).
  #   Le push ne scannait que la diff ; ici on audite tout le dépôt.
  # -------------------------------------------------------------------
  secrets:
    name: 'Gitleaks (historique complet)'
    runs-on: ubuntu-latest
    steps:
      - name: 'Checkout (historique complet)'
        uses: actions/checkout@v4
        with:
          fetch-depth: 0
      - name: 'Gitleaks'
        uses: gitleaks/gitleaks-action@v2
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}

  # -------------------------------------------------------------------
  # JOB 2/4 : codeql — analyse de sécurité en mode schedule. GitHub
  #   documente ce mode pour les analyses périodiques.
  # -------------------------------------------------------------------
  codeql:
    name: 'CodeQL (analyse périodique)'
    runs-on: ubuntu-latest
    permissions:
      contents: read
      security-events: write
    strategy:
      matrix:
        language: [javascript-typescript, python]
    steps:
      - name: 'Checkout'
        uses: actions/checkout@v4
      - name: 'Initialisation CodeQL'
        uses: github/codeql-action/init@v3
        with:
          languages: ${{ matrix.language }}
          queries: security-extended
      - name: 'Autobuild'
        uses: github/codeql-action/autobuild@v3
      - name: 'Analyse CodeQL'
        uses: github/codeql-action/analyze@v3
        with:
          category: '/language:${{ matrix.language }}'

  # -------------------------------------------------------------------
  # JOB 3/4 : vulns — Trivy filesystem complet. exit-code 1 : un nightly
  #   qui ne fait rien échouer n'est qu'un rapport ignoré.
  # -------------------------------------------------------------------
  vulns:
    name: 'Trivy (filesystem complet)'
    runs-on: ubuntu-latest
    permissions:
      contents: read
      security-events: write
    steps:
      - name: 'Checkout'
        uses: actions/checkout@v4
      - name: 'Trivy scan complet'
        uses: aquasecurity/trivy-action@0.28.0
        with:
          scan-type: fs
          scan-ref: .
          severity: HIGH,CRITICAL
          exit-code: '1'
          ignore-unfixed: true
          format: sarif
          output: trivy-nightly.sarif
      - name: 'Uploader le SARIF'
        if: always()
        uses: github/codeql-action/upload-sarif@v3
        with:
          sarif_file: trivy-nightly.sarif

  # -------------------------------------------------------------------
  # JOB 4/4 : deps — audit des gestionnaires détectés. best-effort par
  #   écosystème (un dépôt peut n'avoir ni package-lock ni Cargo.lock),
  #   MAIS chaque audit détecté est bloquant.
  # -------------------------------------------------------------------
  deps:
    name: 'Audit dépendances (écosystèmes détectés)'
    runs-on: ubuntu-latest
    steps:
      - name: 'Checkout'
        uses: actions/checkout@v4
      - name: 'npm audit (si lockfile npm)'
        if: hashFiles('package-lock.json') != ''
        run: |
          npm ci --ignore-scripts || true
          npm audit --audit-level=high
      - name: 'pip-audit (si requirements.txt)'
        if: hashFiles('requirements.txt') != ''
        run: |
          python -m pip install --upgrade pip pip-audit
          pip install -r requirements.txt
          pip-audit --strict
      - name: 'cargo audit (si Cargo.lock)'
        if: hashFiles('Cargo.lock') != ''
        run: |
          cargo install cargo-audit --locked || true
          cargo audit

NEXUS_YAML
}

# ============================================================================
# SECTION 22b — TEMPLATE php (composer + phpunit + audit)
# ============================================================================
# Pipeline PHP moderne : setup-php officiel, matrice 8.2-8.4, code style
# via php-cs-fixer, phpunit bloquant si phpunit.xml existe, composer audit.
inject_php() {
    cat <<'NEXUS_YAML'
# =============================================================================
# NEXUS PHP — pipeline composer & qualité
# Généré par NEXUS CI GENERATOR v__GENVER__ le __DATE__ (type: php)
# Fichier: __WORKFLOW_FILE__ | Branche: __BRANCH__ | PHP: __PHP__
# -----------------------------------------------------------------------------
# Chaîne de contrôle :
#   1. quality : matrice PHP __PHP_MATRIX__ — install, style, tests
#   2. audit   : composer audit (CVE des dépendances packagist)
# Exige : composer.json à la racine.
# Secrets requis : aucun.
# =============================================================================
name: 'NEXUS PHP (composer & qualite)'
on:
  push:
    branches: [__BRANCH__]
  pull_request:
    branches: [__BRANCH__]
  workflow_dispatch:

permissions:
  contents: read

concurrency:
  group: 'nexus-php-${{ github.ref }}'
  cancel-in-progress: true

jobs:
  # -------------------------------------------------------------------
  # JOB 1/2 : quality — la matrice prouve la compatibilité des versions
  #   PHP supportées actives. php-cs-fixer en --dry-run : il ne réécrit
  #   JAMAIS le code en CI, il constate. Si le style est cassé, c'est au
  #   développeur de corriger, pas à la machine de maquiller.
  # -------------------------------------------------------------------
  quality:
    name: 'Qualite (PHP ${{ matrix.php }})'
    runs-on: ubuntu-latest
    strategy:
      fail-fast: false
      matrix:
        php: __PHP_MATRIX__
    steps:
      - name: 'Checkout'
        uses: actions/checkout@v4
      - name: 'Setup PHP ${{ matrix.php }} (extensions: intl, mbstring)'
        uses: shivammathur/setup-php@v2
        with:
          php-version: '${{ matrix.php }}'
          extensions: intl, mbstring, xml
          tools: php-cs-fixer
          coverage: none
      - name: 'Vérifier la structure du projet'
        run: |
          test -f composer.json || {
            echo "ERREUR: composer.json manquant a la racine"
            exit 1
          }
          composer validate --strict
      - name: 'Installer les dépendances (lockfile requis)'
        run: composer install --prefer-dist --no-progress
      - name: 'Style de code (php-cs-fixer --dry-run)'
        run: |
          if [ -f .php-cs-fixer.dist.php ] || [ -f .php-cs-fixer.php ]; then
            PHP_CS_FIXER_IGNORE_ENV=1 php-cs-fixer fix --dry-run --diff
          else
            echo "pas de config php-cs-fixer détectée — style non vérifié"
          fi
      - name: 'Tests (phpunit, bloquant si config présente)'
        run: |
          if [ -f phpunit.xml ] || [ -f phpunit.xml.dist ]; then
            vendor/bin/phpunit --configuration phpunit.xml
          else
            echo "ERREUR: phpunit.xml absent — un projet PHP sans tests"
            echo "n'est pas un projet, c'est un prototype. Ajoutez phpunit."
            exit 1
          fi

  # -------------------------------------------------------------------
  # JOB 2/2 : audit — composer audit scanne les dépendances déclarées
  #   dans composer.lock contre l'advisory database Packagist.
  # -------------------------------------------------------------------
  audit:
    name: 'Composer audit (CVE dépendances)'
    needs: quality
    runs-on: ubuntu-latest
    steps:
      - name: 'Checkout'
        uses: actions/checkout@v4
      - name: 'Setup PHP'
        uses: shivammathur/setup-php@v2
        with:
          php-version: '__PHP__'
          coverage: none
      - name: 'Audit des dépendances'
        run: |
          test -f composer.lock || {
            echo "ERREUR: composer.lock absent — commitez le lockfile"
            exit 1
          }
          composer audit

NEXUS_YAML
}

# ============================================================================
# SECTION 22c — TEMPLATE dotnet (restore/build/test/pack)
# ============================================================================
# Pipeline .NET : matrice SDK, restore explicite (cache NuGet), build et
# test --no-restore (le restore est déjà fait), pack sur la branche main.
inject_dotnet() {
    cat <<'NEXUS_YAML'
# =============================================================================
# NEXUS DOTNET — pipeline build/test/pack
# Généré par NEXUS CI GENERATOR v__GENVER__ le __DATE__ (type: dotnet)
# Fichier: __WORKFLOW_FILE__ | Branche: __BRANCH__ | SDK: __DOTNET__
# -----------------------------------------------------------------------------
# Chaîne de contrôle :
#   1. build  : matrice SDK [8.0, __DOTNET__] — restore, build, test
#   2. pack   : dotnet pack sur la branche principale, artefact .nupkg
#   3. codeql : analyse statique csharp
# Exige : un .sln ou .csproj détectable par dotnet CLI.
# Secrets requis : aucun.
# =============================================================================
name: 'NEXUS DOTNET (build/test/pack)'
on:
  push:
    branches: [__BRANCH__]
  pull_request:
    branches: [__BRANCH__]
  workflow_dispatch:

permissions:
  contents: read

concurrency:
  group: 'nexus-dotnet-${{ github.ref }}'
  cancel-in-progress: true

jobs:
  # -------------------------------------------------------------------
  # JOB 1/3 : build — chaque step --no-restore : le restore est fait
  #   UNE fois, explicitement, avec cache. Repeter le restore par step
  #   est le pattern qui rend les pipelines .NET lents et flous.
  # -------------------------------------------------------------------
  build:
    name: 'Build & Test (SDK ${{ matrix.dotnet }})'
    runs-on: ubuntu-latest
    strategy:
      fail-fast: false
      matrix:
        dotnet: ['8.0.x', '__DOTNET__']
    steps:
      - name: 'Checkout'
        uses: actions/checkout@v4
      - name: 'Setup .NET SDK ${{ matrix.dotnet }} (cache nuget)'
        uses: actions/setup-dotnet@v4
        with:
          dotnet-version: '${{ matrix.dotnet }}'
          cache: true
          cache-dependency-path: '**/packages.lock.json'
      - name: 'Vérifier la structure du projet'
        run: |
          ls *.sln */*.csproj *.csproj 2>/dev/null | head -n 1 | grep -q . || {
            echo "ERREUR: aucun .sln/.csproj détecté a la racine"
            exit 1
          }
      - name: 'Restore (explicite, une seule fois)'
        run: dotnet restore
      - name: 'Build (release, sans re-restore)'
        run: dotnet build --no-restore --configuration Release
      - name: 'Tests (sans re-restore, coverage XPlat)'
        run: dotnet test --no-restore --collect:"XPlat Code Coverage"

  # -------------------------------------------------------------------
  # JOB 2/3 : pack — nuget packé UNIQUEMENT sur la branche principale :
  #   les PR ne produisent pas de paquet, elles produisent du code relu.
  # -------------------------------------------------------------------
  pack:
    name: 'Pack (nuget)'
    needs: build
    if: github.ref == 'refs/heads/__BRANCH__'
    runs-on: ubuntu-latest
    steps:
      - name: 'Checkout'
        uses: actions/checkout@v4
      - name: 'Setup .NET SDK (cache nuget)'
        uses: actions/setup-dotnet@v4
        with:
          dotnet-version: '__DOTNET__'
          cache: true
          cache-dependency-path: '**/packages.lock.json'
      - name: 'Restore + Pack'
        run: |
          dotnet restore
          dotnet pack --configuration Release --output ./artifacts
      - name: 'Uploader les .nupkg'
        uses: actions/upload-artifact@v4
        with:
          name: nexus-dotnet-nupkg
          path: artifacts/*.nupkg
          retention-days: 7
          if-no-files-found: error

  # -------------------------------------------------------------------
  # JOB 3/3 : codeql — analyse statique de sécurité C#.
  # -------------------------------------------------------------------
  codeql:
    name: 'CodeQL (securite statique)'
    needs: build
    runs-on: ubuntu-latest
    permissions:
      contents: read
      security-events: write
    strategy:
      matrix:
        language: [csharp]
    steps:
      - name: 'Checkout'
        uses: actions/checkout@v4
      - name: 'Setup .NET SDK'
        uses: actions/setup-dotnet@v4
        with:
          dotnet-version: '__DOTNET__'
      - name: 'Initialisation CodeQL'
        uses: github/codeql-action/init@v3
        with:
          languages: ${{ matrix.language }}
      - name: 'Autobuild'
        uses: github/codeql-action/autobuild@v3
      - name: 'Analyse CodeQL'
        uses: github/codeql-action/analyze@v3
        with:
          category: '/language:${{ matrix.language }}'

NEXUS_YAML
}

# ============================================================================
# SECTION 22d — TEMPLATE cpp (cmake multi-compilateur + sanitizers)
# ============================================================================
# Pipeline C/C++ : matrice gcc/clang, build Release via CMake, ctest,
# job sanitizers séparé (AddressSanitizer + UndefinedBehaviorSanitizer),
# analyse statique cppcheck.
inject_cpp() {
    cat <<'NEXUS_YAML'
# =============================================================================
# NEXUS CPP — pipeline cmake & sanitizers
# Généré par NEXUS CI GENERATOR v__GENVER__ le __DATE__ (type: cpp)
# Fichier: __WORKFLOW_FILE__ | Branche: __BRANCH__
# -----------------------------------------------------------------------------
# Chaîne de contrôle :
#   1. build     : matrice [gcc, clang] — cmake configure, build, ctest
#   2. sanitize  : ASan + UBSan (les bugs mémoire reproduits en CI)
#   3. analyse   : cppcheck (warning+style bloquants)
# Exige : CMakeLists.txt à la racine + CTest enregistré.
# Secrets requis : aucun.
# =============================================================================
name: 'NEXUS CPP (cmake & sanitizers)'
on:
  push:
    branches: [__BRANCH__]
  pull_request:
    branches: [__BRANCH__]
  workflow_dispatch:

permissions:
  contents: read

concurrency:
  group: 'nexus-cpp-${{ github.ref }}'
  cancel-in-progress: true

jobs:
  # -------------------------------------------------------------------
  # JOB 1/3 : build — la matrice gcc/clang n'est pas du luxe : un code
  #   qui ne passe que sous gcc cache des UB que clang attrape (et
  #   réciproquement). Les deux verdicts, indépendants (fail-fast off).
  # -------------------------------------------------------------------
  build:
    name: 'Build & Test (${{ matrix.compiler }})'
    runs-on: ubuntu-latest
    strategy:
      fail-fast: false
      matrix:
        compiler: [gcc, clang]
    steps:
      - name: 'Checkout'
        uses: actions/checkout@v4
      - name: 'Vérifier la structure du projet'
        run: |
          test -f CMakeLists.txt || {
            echo "ERREUR: CMakeLists.txt manquant a la racine"
            exit 1
          }
      - name: 'Configurer (cmake, Release, Werror — warnings bloquants)'
        run: |
          mkdir -p build && cd build
          if [ "${{ matrix.compiler }}" = "gcc" ]; then
            CC=gcc CXX=g++ cmake -DCMAKE_BUILD_TYPE=Release \
              -DCMAKE_C_FLAGS="-Werror" -DCMAKE_CXX_FLAGS="-Werror" ..
          else
            CC=clang CXX=clang++ cmake -DCMAKE_BUILD_TYPE=Release \
              -DCMAKE_C_FLAGS="-Werror" -DCMAKE_CXX_FLAGS="-Werror" ..
          fi
      - name: 'Compiler (parallel)'
        run: cmake --build build --parallel "$(nproc)"
      - name: 'Tests (ctest, échec détaillé)'
        run: ctest --test-dir build --output-on-failure

  # -------------------------------------------------------------------
  # JOB 2/3 : sanitize — ASan et UBSan dans le même build : le coût
  #   d'un job séparé par sanitizer dépasse le bénéfice pour 95% des
  #   projets. ctest rejoué sous sanitizers = les bugs mémoire qui ne
  #   se voient QUE sous instrumentation.
  # -------------------------------------------------------------------
  sanitize:
    name: 'Sanitizers (ASan + UBSan)'
    runs-on: ubuntu-latest
    steps:
      - name: 'Checkout'
        uses: actions/checkout@v4
      - name: 'Configurer avec sanitizers'
        run: |
          mkdir -p build-san && cd build-san
          cmake -DCMAKE_BUILD_TYPE=Debug \
            -DCMAKE_C_FLAGS="-fsanitize=address,undefined -fno-omit-frame-pointer" \
            -DCMAKE_CXX_FLAGS="-fsanitize=address,undefined -fno-omit-frame-pointer" ..
      - name: 'Compiler (sanitize)'
        run: cmake --build build-san --parallel "$(nproc)"
      - name: 'Tests sous sanitizers'
        run: ctest --test-dir build-san --output-on-failure

  # -------------------------------------------------------------------
  # JOB 3/3 : analyse — cppcheck indépendant de la compilation : il
  #   voit des patterns que le compilateur accepte silencieusement.
  # -------------------------------------------------------------------
  analyse:
    name: 'Cppcheck (statique)'
    runs-on: ubuntu-latest
    steps:
      - name: 'Checkout'
        uses: actions/checkout@v4
      - name: 'Installer cppcheck'
        run: sudo apt-get update -qq && sudo apt-get install -y -qq cppcheck
      - name: 'Analyse statique (warning + style bloquants)'
        run: |
          cppcheck --enable=warning,style --inconclusive \
            --error-exitcode=1 --suppress=missingIncludeSystem \
            --inline-suppr -I . .

NEXUS_YAML
}

# ============================================================================
# SECTION 22e — TEMPLATE android (gradle + lint + tests + APK)
# ============================================================================
# Pipeline Android : wrapper gradlew exécutable (jamais un gradle système
# — la version du wrapper EST la version du projet), lint + tests unitaires
# + assembleDebug, APK joint en artefact, release unsigned sur tag.
inject_android() {
    cat <<'NEXUS_YAML'
# =============================================================================
# NEXUS ANDROID — pipeline gradle & APK
# Généré par NEXUS CI GENERATOR v__GENVER__ le __DATE__ (type: android)
# Fichier: __WORKFLOW_FILE__ | Branche: __BRANCH__
# -----------------------------------------------------------------------------
# Chaîne de contrôle :
#   1. quality : gradlew lint + testDebugUnitTest + assembleDebug
#   2. release : assembleRelease (unsigned) sur tag v* uniquement
# Exige : gradlew à la racine + JDK 17 (imposé par AGP moderne).
# Secrets requis : aucun — la release produite est UNSIGNED : la signature
# est un acte humain (keystore), jamais un job automatisé.
# =============================================================================
name: 'NEXUS ANDROID (gradle & apk)'
on:
  push:
    branches: [__BRANCH__]
    tags: ['v*']
  pull_request:
    branches: [__BRANCH__]
  workflow_dispatch:

permissions:
  contents: read

concurrency:
  group: 'nexus-android-${{ github.ref }}'
  cancel-in-progress: true

jobs:
  # -------------------------------------------------------------------
  # JOB 1/2 : quality — ./gradlew EXÉCUTABLE requis : un wrapper non
  #   exécutable committé est une erreur de dépôt, le job le prouve
  #   avec un message explicite plutôt qu'un Permission denied obscur.
  # -------------------------------------------------------------------
  quality:
    name: 'Lint + Tests + Debug APK'
    runs-on: ubuntu-latest
    steps:
      - name: 'Checkout'
        uses: actions/checkout@v4
      - name: 'Vérifier le wrapper gradle'
        run: |
          test -f gradlew || {
            echo "ERREUR: gradlew manquant a la racine"
            exit 1
          }
          test -x gradlew || {
            echo "ERREUR: gradlew n'est pas exécutable (chmod +x gradlew)"
            exit 1
          }
      - name: 'Setup JDK 17 (imposé par AGP)'
        uses: actions/setup-java@v4
        with:
          distribution: temurin
          java-version: 17
      - name: 'Setup gradle (cache build)'
        uses: gradle/actions/setup-gradle@v4
      - name: 'Lint'
        run: ./gradlew lint --no-daemon
      - name: 'Tests unitaires'
        run: ./gradlew testDebugUnitTest --no-daemon
      - name: 'Assemble debug APK'
        run: ./gradlew assembleDebug --no-daemon
      - name: 'Uploader l APK debug'
        uses: actions/upload-artifact@v4
        with:
          name: nexus-android-debug
          path: app/build/outputs/apk/debug/*.apk
          retention-days: 7
          if-no-files-found: warn

  # -------------------------------------------------------------------
  # JOB 2/2 : release — assembleRelease sur tag. UNSIGNED par principe :
  #   la signature avec un keystore en secret de CI transforme le
  #   keystore en single point of failure. Le keystore reste sur la
  #   machine d'un humain responsable, ou dans un dédié signing job
  #   avec HSM — pas dans un secret GitHub.
  # -------------------------------------------------------------------
  release:
    name: 'Release APK (unsigned, sur tag v*)'
    needs: quality
    if: startsWith(github.ref, 'refs/tags/')
    runs-on: ubuntu-latest
    steps:
      - name: 'Checkout'
        uses: actions/checkout@v4
      - name: 'Setup JDK 17'
        uses: actions/setup-java@v4
        with:
          distribution: temurin
          java-version: 17
      - name: 'Setup gradle (cache build)'
        uses: gradle/actions/setup-gradle@v4
      - name: 'Assemble release (unsigned)'
        run: ./gradlew assembleRelease --no-daemon
      - name: 'Uploader l APK release'
        uses: actions/upload-artifact@v4
        with:
          name: nexus-android-release-unsigned
          path: app/build/outputs/apk/release/*.apk
          retention-days: 14
          if-no-files-found: error

NEXUS_YAML
}
# ============================================================================
# SECTION 23 — EXPLAIN : DOCUMENTATION OPÉRATIONNELLE PAR TYPE
# ============================================================================
# explain_type : documente ce que le workflow fait DANS VOTRE DÉPÔT, avec
# les informations qu'on oublie toujours : secrets, permissions, durée
# estimée, artefacts produits, et comment l'adapter. Contenu = ce que le
# YAML généré contient réellement, rien d'inventé.
explain_type() {
    case "$1" in
        aegis)         explain_aegis ;;
        java)          explain_java ;;
        python)        explain_python ;;
        node)          explain_node ;;
        docker)        explain_docker ;;
        go)            explain_go ;;
        rust)          explain_rust ;;
        release)       explain_release ;;
        nightly)       explain_nightly ;;
        php)           explain_php ;;
        dotnet)        explain_dotnet ;;
        cpp)           explain_cpp ;;
        android)       explain_android ;;
        *) die "type inconnu pour explain: $1" "$EXIT_USAGE" ;;
    esac
}

explain_aegis() {
    cat <<'NEXUS_EXPLAIN'
TYPE: aegis — pipeline sécurité & qualité Next.js
FICHIER GÉNÉRÉ: .github/workflows/nexus-aegis.yml

DÉCLENCHEURS:
  - push et pull_request sur la branche configurée (défaut: main)
  - workflow_dispatch (déclenchement manuel depuis l'onglet Actions)

JOBS (9), DANS L'ORDRE DE COMPRÉHENSION:
  1. changes    - détecte si des fichiers sources ont bougé (paths-filter).
                  Sinon, lint/typecheck/test/build sautent : pas de CI
                  inutile pour un commit de documentation.
  2. secrets   - gitleaks, historique complet, TOUJOURS actif.
  3. lint      - npx eslint . --max-warnings=0 (zéro tolérance).
  4. typecheck - npx tsc --noEmit (les types sont des tests gratuits).
  5. test      - npm test -- --ci --coverage, artefact coverage/ joint.
  6. build     - npm run build, artefact .next/ joint (consommé par slsa).
  7. codeql    - analyse statique, queries security-extended, SARIF.
  8. trivy     - scan CVE filesystem, exit 1 sur HIGH/CRITICAL, SARIF.
  9. slsa      - attestation de provenance du build (supply chain).

SECRETS REQUIS: AUCUN. GITHUB_TOKEN automatique suffit.
PERMISSIONS: contents:read global; security-events:write (codeql/trivy);
             id-token+attestations:write (slsa) — au niveau des jobs
             concernés uniquement, pas global (principe du moindre privilège).

ARTEFACTS: nexus-coverage (7j), nexus-build (7j), attestation SLSA.
DURÉE ESTIMÉE: 6-10 min au premier run (pas de cache), 3-5 min ensuite.

ADAPTATION FRÉQUENTE:
  - le job test lance 'npm test' : si votre script de tests s'appelle
    autrement, adaptez la step dans package.json ou le YAML.

BUG DU SKELETON CORRIGÉ (PROTON ④):
  le skeleton exécutait 'actions/setup-node@v4' comme commande shell
  (run:) — illégal. Le générateur l'écrit correctement (uses:) et le
  selftest vérifie le pattern interdit par grep.
NEXUS_EXPLAIN
}

explain_java() {
    cat <<'NEXUS_EXPLAIN'
TYPE: java — pipeline Maven multi-JDK
FICHIER GÉNÉRÉ: .github/workflows/nexus-java.yml

DÉCLENCHEURS: push + pull_request sur la branche, workflow_dispatch.

JOBS (3):
  1. build  - matrice JDK [17, <votre --java>] avec cache Maven.
              Étapes: vérification pom.xml, compile sans tests (fail
              fast), mvn verify (tests inclus), upload des JAR.
              fail-fast=false : les deux JDK rapportent chacun leur
              verdict (le 17 ne masque pas le 21).
  2. owasp  - org.owasp:dependency-check-maven:check sur la branche
              principale uniquement (job lourd : base NVD à télécharger).
              Rapport HTML joint en artefact même en cas d'échec (always).
  3. codeql - analyse statique java-kotlin.

EXIGE: pom.xml à la racine. Sans lui le job build échoue avec un
       message explicite (step de vérification dédiée).

SECRETS REQUIS: aucun.
ARTEFACTS: nexus-java-jdk17 / nexus-java-jdk<java> (JAR, 7j),
           nexus-owasp-report (14j).
DURÉE ESTIMÉE: build 4-8 min ; owasp 10-20 min au premier run
               (téléchargement NVD), 2-4 min ensuite.

NOTE CVE: dependency-check échoue si une CVE CVSS >= 7 est trouvée
          (seuil par défaut du plugin) ; le seuil se règle dans pom.xml
          via la propriété failBuildOnCVSS.
NEXUS_EXPLAIN
}

explain_python() {
    cat <<'NEXUS_EXPLAIN'
TYPE: python — pipeline qualité & sécurité
FICHIER GÉNÉRÉ: .github/workflows/nexus-python.yml

DÉCLENCHEURS: push + pull_request sur la branche, workflow_dispatch.

JOBS (3):
  1. quality - matrice [votre --python, 3.10, 3.11, 3.13] :
               ruff check (lint bloquant), ruff format --check,
               pytest --cov (rapport XML joint), mypy (tolérant par
               défaut : --ignore-missing-imports).
  2. audit   - pip-audit --strict sur l'environnement résolu :
               chaque dépendance installée, transitives comprises.
  3. codeql  - analyse statique python.

EXIGE: rien à la racine, MAIS le job quality installe
      requirements.txt et requirements-dev.txt s'ils existent, puis
      les outils de qualité. Sans requirements.txt, ruff/pytest/mypy
      sont installés seuls — le pipeline reste vert sur un dépôt
      contenant déjà un setup.py/pyproject autonome.

SECRETS REQUIS: aucun.
ARTEFACTS: nexus-coverage-py<version> (coverage.xml, 7j).
DURÉE ESTIMÉE: quality 3-6 min par interpréteur (matrice parallèle),
               audit 1-3 min.

DURCIR MYPY (recommandé au fil du temps):
  retirer --ignore-missing-imports et ajouter un pyproject.toml avec
  [tool.mypy] strict = true. Le pipeline échouera plus souvent, et
  c'est le but : les types attrapent les bugs avant les utilisateurs.
NEXUS_EXPLAIN
}

explain_node() {
    cat <<'NEXUS_EXPLAIN'
TYPE: node — pipeline npm multi-runtime
FICHIER GÉNÉRÉ: .github/workflows/nexus-node.yml

DÉCLENCHEURS: push + pull_request sur la branche, workflow_dispatch.

JOBS (2):
  1. build - matrice Node [votre --node, 20, 22] avec cache npm :
             npm ci (strict : exige package-lock.json, échec explicite
             sinon), lint/test/build avec --if-present (aucun script
             imposé), artefacts dist/ build/ .next/ joints.
  2. audit - npm audit --audit-level=high, bloquant.

EXIGE: package.json + package-lock.json. npm ci est strict À DESEIN :
       un build sans lockfile n'est pas reproductible, et un build non
       reproductible n'est pas un build, c'est une prière.

SECRETS REQUIS: aucun.
ARTEFACTS: nexus-node-<runtime> (7j).
DURÉE ESTIMÉE: 3-5 min par runtime au premier run, 2-3 ensuite.

POURQUOI --if-present:
  le générateur ne sait pas si votre projet a un script 'lint'. Plutôt
  que d'imposer une convention et de casser les dépôts qui ne la
  suivent pas, les steps optionnelles utilisent --if-present et vous
  gardez le contrôle dans package.json.
NEXUS_EXPLAIN
}

explain_docker() {
    cat <<'NEXUS_EXPLAIN'
TYPE: docker — pipeline image multi-arch
FICHIER GÉNÉRÉ: .github/workflows/nexus-docker.yml

DÉCLENCHEURS:
  - push sur la branche, tags v*, pull_request, workflow_dispatch.
  - Le push vers le registre n'a JAMAIS lieu sur une pull_request
    (code non fusionné = pas d'image publiée).

JOBS (4):
  1. lint  - hadolint sur Dockerfile, échec à partir de warning.
  2. image - QEMU + buildx, plateformes linux/amd64 ET linux/arm64,
             cache type=gha, tags générés par metadata-action :
             branche, sha-, semver sur tag v*, latest sur branche
             par défaut. Login au registre avec GITHUB_TOKEN.
  3. scan  - Trivy sur l'IMAGE (pas juste le filesystem) : le scan
             voit le runtime de l'image. exit 1 sur HIGH/CRITICAL.
  4. sbom  - SBOM SPDX de l'image, joint en artefact.

EXIGE: un Dockerfile à la racine.

SECRETS REQUIS: aucun — le login utilise GITHUB_TOKEN vers ghcr.io.
PERMISSIONS: packages:write sur le job image uniquement.
ARTEFACTS: SARIF Trivy, SBOM nexus-sbom.spdx.json.
DURÉE ESTIMÉE: 8-15 min au premier build multi-arch (QEMU arm64 est
               lent), 4-8 min ensuite grâce au cache gha.

REGISTRE: la valeur de --registry (défaut ghcr.io). Le nom de l'image
          est ${{ github.repository }} : orga/dépôt, en minuscules
          automatiques côté serveur si votre orga a des majuscules,
          préfixez le nom en minuscules dans les settings du paquet.
NEXUS_EXPLAIN
}

explain_go() {
    cat <<'NEXUS_EXPLAIN'
TYPE: go — pipeline qualité & release
FICHIER GÉNÉRÉ: .github/workflows/nexus-go.yml

DÉCLENCHEURS: push branche + tags v*, pull_request, workflow_dispatch.

JOBS (2):
  1. quality - golangci-lint (version latest de l'action), go vet,
               go test -race (détection de race conditions :
               le bug le plus dur à reproduire localement),
               coverage atomique joint, go build.
  2. release - goreleaser release --clean, UNIQUEMENT sur tag v*.

EXIGE: go.mod à la racine (step de vérification dédiée, échec
       avec message explicite s'il manque).

SECRETS REQUIS: aucun — goreleaser publie avec GITHUB_TOKEN
                (contents:write sur le job release uniquement).
ARTEFACTS: nexus-go-coverage (coverage.out, 7j), release goreleaser
           (binaires multi-plateformes + archives + checksums).
DURÉE ESTIMÉE: quality 2-4 min ; release 3-6 min.

NOTE -race: le flag force le runtime Go à détecter les accès
           mémoire concurrents non synchronisés. Un test qui passe
           sans -race peut échouer AVEC : c'est une découverte,
           pas un faux positif. Corrigez le code, pas le test.
NEXUS_EXPLAIN
}

explain_rust() {
    cat <<'NEXUS_EXPLAIN'
TYPE: rust — pipeline qualité & sécurité
FICHIER GÉNÉRÉ: .github/workflows/nexus-rust.yml

DÉCLENCHEURS: push branche + tags v*, pull_request, workflow_dispatch.

JOBS (3):
  1. fmt     - cargo fmt --all --check sur NIGHTLY (le composant
               rustfmt y vit). Format séparé du build : zéro conflit
               de toolchain.
  2. quality - clippy --all-targets -- -D warnings (chaque warning
               EST une erreur), cargo test --all-features,
               cargo-audit (CVE des crates, via rustsec/audit-check).
  3. release - cargo build --release sur tag v* uniquement, binaire
               target/release/ joint (if-no-files-found: error :
               une release sans binaire est un mensonge de release).

EXIGE: Cargo.toml à la racine.

SECRETS REQUIS: aucun.
ARTEFACTS: nexus-rust-release (target/release, 14j).
DURÉE ESTIMÉE: fmt 1-2 min ; quality 5-12 min au premier run (les
               crates compilent depuis zéro), 2-4 min avec le cache
               Swatinem/rust-cache.

POURQUOI -D warnings:
  le compilateur Rust attrape des classes entières de bugs (memory,
  concurrency, null) que d'autres langages laissent passer. Clippy
  va plus loin encore. Ignorer un warning clippy, c'est refuser un
  diagnostic gratuit d'un expert du langage.
NEXUS_EXPLAIN
}

explain_release() {
    cat <<'NEXUS_EXPLAIN'
TYPE: release — release GitHub sur tag v*
FICHIER GÉNÉRÉ: .github/workflows/nexus-release.yml

DÉCLENCHEUR: git tag v1.2.3 && git push --tags (+ manuel).

JOBS (3):
  1. build     - détecte AUTOMATIQUEMENT votre mécanisme de build :
                 build.sh exécutable, Makefile (make build),
                 package.json (npm ci && npm run build), Cargo.toml
                 (cargo build --release), go.mod (go build). Les
                 sorties sont collectées dans dist/.
  2. changelog - release-changelog-builder : catégories par label
                 (feature -> Ajouts, fix -> Corrections, security ->
                 Securite), construit depuis les PR merged entre le
                 tag précédent et le tag courant.
  3. publish   - softprops/action-gh-release : artefacts + changelog
                 + generate_release_notes (les notes natives GitHub
                 en complément).

SECRETS REQUIS: aucun. PERMISSIONS: contents:write (créer la release).
DURÉE ESTIMÉE: 3-8 min selon la durée de votre build.

AVERTISSEMENT HONNÊTE:
  si le job build ne détecte AUCUN mécanisme, il s'affiche vert avec
  un avertissement et zéro artefact. C'est un choix délibéré : le
  générateur n'invente pas un build qui n'existe pas. Adaptez le job
  build à votre projet réel — la release sans artefact publiera les
  notes seules, ce qui est correct mais incomplet.
NEXUS_EXPLAIN
}

explain_nightly() {
    cat <<'NEXUS_EXPLAIN'
TYPE: nightly — scan nocturne complet
FICHIER GÉNÉRÉ: .github/workflows/nexus-nightly.yml

DÉCLENCHEURS: schedule cron (défaut 0 3 * * * = 03:00 UTC) + manuel.

JOBS (4):
  1. secrets - gitleaks sur l'historique COMPLET (fetch-depth 0).
               Le pipeline de push ne scannait que la diff ; ici,
               tout le dépôt, chaque nuit.
  2. codeql  - analyse périodique javascript-typescript + python.
  3. vulns   - Trivy filesystem complet, exit 1 sur HIGH/CRITICAL.
  4. deps    - audit par écosystème DÉTECTÉ : npm audit si
               package-lock.json, pip-audit si requirements.txt,
               cargo audit si Cargo.lock. Chaque audit détecté est
               bloquant ; les écosystèmes absents sont simplement
               sautés (hashFiles() vide = step skip).

SECRETS REQUIS: aucun.
DURÉE ESTIMÉE: 15-30 min (jobs en parallèle, le plus lent est
               codeql + la base NVD de gitleaks).

POURQUOI UN NIGHTLY EXISTE:
  votre code n'a pas changé depuis hier, mais le monde oui : de
  nouvelles CVE sont publiées chaque jour, de nouveaux secrets
  fuient, de nouveaux patterns de vulnérabilité sont découverts.
  Le nightly est le rappel quotidien que "ça marchait hier" n'est
  pas un argument de sécurité.
NEXUS_EXPLAIN
}

explain_php() {
    cat <<'NEXUS_EXPLAIN'
TYPE: php — pipeline composer & qualité
FICHIER GÉNÉRÉ: .github/workflows/nexus-php.yml

DÉCLENCHEURS: push + pull_request sur la branche, workflow_dispatch.

JOBS (2):
  1. quality - matrice PHP [8.2, 8.3, votre --php] avec setup-php
               officiel (intl, mbstring, xml), composer validate
               --strict, composer install (lockfile), php-cs-fixer
               --dry-run --diff (style constaté, jamais réécrit),
               phpunit BLOQUANT : phpunit.xml absent = échec explicite.
  2. audit   - composer audit sur composer.lock (advisory Packagist).
               composer.lock absent = échec explicite.

SECRETS REQUIS: aucun.
ARTEFACTS: aucun (les rapports restent dans les logs du job).
DURÉE ESTIMÉE: quality 2-4 min par version de la matrice, audit 1 min.

POSITION HONNÊTE SUR PHPUNIT:
  là où node utilise --if-present (écosystème hétérogène), php exige
  phpunit.xml : un projet PHP moderne sans config de tests est une
  dette immédiate. Le pipeline le dit au lieu de sourire poliment.
NEXUS_EXPLAIN
}

explain_dotnet() {
    cat <<'NEXUS_EXPLAIN'
TYPE: dotnet — pipeline build/test/pack
FICHIER GÉNÉRÉ: .github/workflows/nexus-dotnet.yml

DÉCLENCHEURS: push + pull_request sur la branche, workflow_dispatch.

JOBS (3):
  1. build  - matrice SDK [8.0.x, votre --dotnet] avec cache NuGet.
              Pattern restore-once : dotnet restore explicite UNE fois,
              puis build --no-restore et test --no-restore. La
              couverture XPlat est collectée par test.
  2. pack   - dotnet pack --output ./artifacts sur la branche
              principale UNIQUEMENT (les PR ne produisent pas de
              paquets). Artefact .nupkg avec if-no-files-found: error :
              un pack qui ne packe rien est un échec, pas un succès.
  3. codeql - analyse statique csharp.

EXIGE: un .sln ou .csproj détectable (step de vérification dédiée).
SECRETS REQUIS: aucun.
ARTEFACTS: nexus-dotnet-nupkg (7j).
DURÉE ESTIMÉE: build 3-6 min par SDK, pack 2-3 min, codeql 4-8 min.

NOTE CACHE:
  le cache NuGet s'appuie sur packages.lock.json si votre projet en
  génère un ; sinon le cache par défaut de setup-dotnet s'applique.
NEXUS_EXPLAIN
}

explain_cpp() {
    cat <<'NEXUS_EXPLAIN'
TYPE: cpp — pipeline cmake & sanitizers
FICHIER GÉNÉRÉ: .github/workflows/nexus-cpp.yml

DÉCLENCHEURS: push + pull_request sur la branche, workflow_dispatch.

JOBS (3):
  1. build    - matrice [gcc, clang] en Release avec -Werror : tout
               avertissement EST une erreur. ctest --output-on-failure.
  2. sanitize - build Debug avec -fsanitize=address,undefined et
               -fno-omit-frame-pointer, puis ctest rejoué SOUS
               sanitizers : use-after-free, overflow, UB reproduits
               en CI au lieu d'attendre le crash en production.
  3. analyse  - cppcheck --enable=warning,style --inconclusive,
               error-exitcode=1. Indépendant du compilateur : il
               attrape les patterns que gcc ET clang acceptent.

EXIGE: CMakeLists.txt à la racine + tests enregistrés dans CTest.
SECRETS REQUIS: aucun.
DURÉE ESTIMÉE: build 4-8 min par compilateur, sanitize 4-8 min,
               analyse 1-2 min.

POURQUOI -Werror EN CI:
  un avertissement laissé vivre devient du bruit, et le bruit devient
  de la cécité. En CI, -Werror force le traitement immédiat : c'est
  le seul endroit où le coût de réparation est minimal.
NEXUS_EXPLAIN
}

explain_android() {
    cat <<'NEXUS_EXPLAIN'
TYPE: android — pipeline gradle & APK
FICHIER GÉNÉRÉ: .github/workflows/nexus-android.yml

DÉCLENCHEURS: push + tags v* + pull_request + workflow_dispatch.

JOBS (2):
  1. quality - vérification du wrapper (gradlew présent ET exécutable
               — erreur explicite sinon), JDK 17 temurin (imposé par
               AGP), setup-gradle avec cache, puis lint,
               testDebugUnitTest, assembleDebug, APK debug joint.
  2. release - assembleRelease sur tag v* uniquement. L'APK produit
               est UNSIGNED et joint en artefact (14j).

EXIGE: gradlew à la racine du dépôt (committez le wrapper : c'est la
       version de build du projet, pas un détail).

SECRETS REQUIS: aucun — ET C'EST UN CHOIX:
  la signature d'un APK avec un keystore stocké en secret CI
  transformerait ce secret en point de défaillance unique. La
  signature reste un acte humain (keystore local ou job dédié
  HSM). Le pipeline livre l'unsigned ; le release manager signe.

ARTEFACTS: nexus-android-debug (7j), nexus-android-release-unsigned (14j).
DURÉE ESTIMÉE: quality 6-15 min (gradle cold), release 4-10 min.
NEXUS_EXPLAIN
}
# ============================================================================
# SECTION 24 — COMMANDE list
# ============================================================================
cmd_list() {
    local t
    log_step "Types de workflows supportés (${#TYPES_ORDER[@]})"
    printf '\n'
    for t in "${TYPES_ORDER[@]}"; do
        printf '  %s%-10s%s  %s\n' "${C_BOLD}${C_CYAN}" "$t" "${C_RESET}" "${WORKFLOW_DESC[$t]}"
        printf '  %s          ->  %s%s%s\n' "${C_DIM}" ".github/workflows/${WORKFLOW_FILE[$t]}" "${C_RESET}" ""
    done
    printf '\n'
    log_info "générer un type: ./nexus-ci-generator.sh <type> [--dir <dépôt>]"
    log_info "documenter un type: ./nexus-ci-generator.sh explain <type>"
}

# ============================================================================
# SECTION 25 — COMMANDE explain
# ============================================================================
cmd_explain() {
    if [ "${#OPT_POSITIONAL[@]}" -lt 1 ]; then
        die "explain requiert un type (ex: explain aegis)" "$EXIT_USAGE"
    fi
    local type="${OPT_POSITIONAL[0]}"
    if ! is_known_type "$type"; then
        die "type inconnu: $type (voir: list)" "$EXIT_USAGE"
    fi
    explain_type "$type"
}

# ============================================================================
# SECTION 26 — COMMANDE validate
# ============================================================================
cmd_validate() {
    if [ "${#OPT_POSITIONAL[@]}" -lt 1 ]; then
        die "validate requiert un chemin de fichier (ex: validate .github/workflows/x.yml)" "$EXIT_USAGE"
    fi
    local file="${OPT_POSITIONAL[0]}"
    if [ ! -f "$file" ]; then
        die "fichier introuvable: $file" "$EXIT_ERR"
    fi
    log_step "Validation du workflow: $file"
    # La commande validate ignore OPT_SKIP_VALIDATION : elle EXISTE pour
    # valider. L'option n'aurait aucun sens ici et est refusée.
    if [ "$OPT_SKIP_VALIDATION" -eq 1 ]; then
        log_warn "--skip-validation ignorée: validate existe pour valider"
    fi
    local saved_flag="$OPT_SKIP_VALIDATION"
    OPT_SKIP_VALIDATION=0
    if validate_yaml_file "$file"; then
        log_ok "structure GitHub Actions valide: $file"
        log_ok "$(grep -c '^' "$file") lignes, $(grep -cE '^  [a-zA-Z0-9_-]+:' "$file") jobs détectés"
        return "$EXIT_OK"
    fi
    OPT_SKIP_VALIDATION="$saved_flag"
    die "validation échouée: $file" "$EXIT_YAML"
}

# ============================================================================
# SECTION 27 — COMMANDE doctor
# ============================================================================
# Diagnostic complet : chaque vérification affiche son verdict UN PAR UN
# (jamais de "tout va bien" global qui cache un détail mort).
cmd_doctor() {
    local ok=0
    local warn=0
    local ko=0
    local line

    log_step "Diagnostic de l'environnement"
    hr

    # 1. bash
    if [ "${BASH_VERSINFO[0]}" -ge 4 ]; then
        printf '  [OK]   bash %s (>= 4 requis: tableaux associatifs)\n' "${BASH_VERSION%%(*}"
        ok=$((ok + 1))
    else
        printf '  [KO]   bash %s (< 4)\n' "${BASH_VERSION%%(*}"
        ko=$((ko + 1))
    fi

    # 2. git
    if command -v git >/dev/null 2>&1; then
        printf '  [OK]   git %s (dépôt cible + détection .git)\n' "$(git --version | awk '{print $3}')"
        ok=$((ok + 1))
    else
        printf '  [KO]   git introuvable\n'
        ko=$((ko + 1))
    fi

    # 3. python3
    if command -v python3 >/dev/null 2>&1; then
        printf '  [OK]   python3 %s\n' "$(python3 --version 2>&1 | awk '{print $2}')"
        ok=$((ok + 1))
    else
        printf '  [KO]   python3 introuvable (validation YAML impossible)\n'
        ko=$((ko + 1))
    fi

    # 4. PyYAML
    if python3 -c "import yaml" >/dev/null 2>&1; then
        printf '  [OK]   PyYAML %s (validation YAML active)\n' "$(python3 -c 'import yaml; print(yaml.__version__)')"
        ok=$((ok + 1))
    else
        printf '  [KO]   module python yaml (PyYAML) introuvable -> pip install pyyaml\n'
        ko=$((ko + 1))
    fi

    # 5. sed (substitution des placeholders)
    if command -v sed >/dev/null 2>&1; then
        printf '  [OK]   sed (substitution placeholders)\n'
        ok=$((ok + 1))
    else
        printf '  [KO]   sed introuvable\n'
        ko=$((ko + 1))
    fi

    # 6. awk (rapports doctor/list)
    if command -v awk >/dev/null 2>&1; then
        printf '  [OK]   awk (rapports)\n'
        ok=$((ok + 1))
    else
        printf '  [ATT]  awk introuvable (rapports dégradés)\n'
        warn=$((warn + 1))
    fi

    # 7. mktemp (fichiers temporaires atomiques)
    if command -v mktemp >/dev/null 2>&1; then
        printf '  [OK]   mktemp (écriture atomique)\n'
        ok=$((ok + 1))
    else
        printf '  [KO]   mktemp introuvable (écriture non atomique)\n'
        ko=$((ko + 1))
    fi

    # 8. répertoire courant = dépôt git ?
    if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        printf '  [OK]   répertoire courant: dépôt git (%s)\n' "$(git rev-parse --show-toplevel 2>/dev/null || printf '.')"
        ok=$((ok + 1))
    else
        printf '  [ATT]  répertoire courant PAS un dépôt git — utilise --dir <chemin>\n'
        warn=$((warn + 1))
    fi

    # 9. espace disque sur le répertoire courant (>50 Mo)
    local free_mb
    free_mb="$(df -Pm . 2>/dev/null | awk 'NR==2 {print $4}' || printf 0)"
    if [ "${free_mb:-0}" -gt 50 ]; then
        printf '  [OK]   espace disque: %s Mo libres\n' "$free_mb"
        ok=$((ok + 1))
    else
        printf '  [ATT]  espace disque faible: %s Mo\n' "${free_mb:-?}"
        warn=$((warn + 1))
    fi

    # 10. shellcheck (qualité du shell — optionnel, recommandé)
    if command -v shellcheck >/dev/null 2>&1; then
        printf '  [OK]   shellcheck %s (audit qualité shell disponible)\n' \
            "$(shellcheck --version 2>/dev/null | awk '/version:/ {print $2}' | head -n1)"
        ok=$((ok + 1))
    else
        printf '  [ATT]  shellcheck absent (audit qualité shell impossible)\n'
        warn=$((warn + 1))
    fi

    # 11. workflows NEXUS déjà installés dans le dépôt courant
    local wf_count
    wf_count=0
    if [ -d .github/workflows ]; then
        for f in .github/workflows/nexus-*.yml; do
            if [ -f "$f" ]; then
                wf_count=$((wf_count + 1))
            fi
        done
    fi
    if [ "$wf_count" -gt 0 ]; then
        printf '  [OK]   %s workflow(s) NEXUS déjà installé(s) (--force pour régénérer)\n' "$wf_count"
        ok=$((ok + 1))
    else
        printf '  [OK]   aucun workflow NEXUS préexistant (première installation)\n'
        ok=$((ok + 1))
    fi

    # 12. réseau vers github.com (validation des actions @v4/@v3)
    if command -v curl >/dev/null 2>&1; then
        if curl -fsS --max-time 5 -o /dev/null https://github.com 2>/dev/null; then
            printf '  [OK]   réseau: github.com joignable\n'
            ok=$((ok + 1))
        else
            printf '  [ATT]  github.com injoignable (offline ? workflows identiques quand même)\n'
            warn=$((warn + 1))
        fi
    else
        printf '  [ATT]  curl absent (sonde réseau ignorée)\n'
        warn=$((warn + 1))
    fi

    hr
    printf '  bilan: %s OK, %s attention, %s bloquant(s)\n\n' "$ok" "$warn" "$ko"
    if [ "$ko" -gt 0 ]; then
        die "environnement INCOMPLET — corrigez les [KO] ci-dessus" "$EXIT_ENV"
    fi
    if [ "$warn" -gt 0 ]; then
        log_warn "avertissements non bloquants: $warn"
    fi
    log_ok "environnement opérationnel"
}

# ============================================================================
# SECTION 28 — COMMANDE uninstall
# ============================================================================
# Sécurité à deux étages :
#   1. on ne touche QUE les fichiers portant le marqueur NEXUS_MARKER
#      (un workflow écrit à la main est REFUSÉ)
#   2. confirmation interactive obligatoire (sauf --force / stdin actif)
cmd_uninstall() {
    local type="" file="" target
    if [ "${#OPT_POSITIONAL[@]}" -ge 1 ]; then
        if is_known_type "${OPT_POSITIONAL[0]}"; then
            type="${OPT_POSITIONAL[0]}"
            file="${WORKFLOW_FILE[$type]}"
        else
            file="${OPT_POSITIONAL[0]}"
        fi
    else
        die "uninstall requiert un type (ex: uninstall aegis) ou un chemin" "$EXIT_USAGE"
    fi
    target="$OPT_DIR/.github/workflows/$file"

    if [ ! -f "$target" ]; then
        die "rien à supprimer: $target inexistant" "$EXIT_ERR"
    fi

    # Étage 1 : le marqueur. head -3 suffit : le marqueur est ligne 2
    # de tout workflow généré (ligne 1 = titre du bloc).
    if ! head -n 3 "$target" | grep -q "$NEXUS_MARKER"; then
        die "REFUS: $target ne porte pas le marqueur NEXUS (fichier écrit à la main ?)" "$EXIT_ERR"
    fi

    log_step "Suppression du workflow: $target"
    if ! confirm "Supprimer définitivement $target ?"; then
        log_warn "suppression annulée par l'utilisateur"
        return "$EXIT_OK"
    fi
    rm -f "$target"
    log_ok "supprimé: $target"
    log_info "pensez à committer la suppression (git add -A && git commit -m 'ci: remove nexus $type')"
}
# ============================================================================
# SECTION 29 — COMMANDE selftest (BANC D'ESSAI PROTON)
# ============================================================================
# Le selftest n'affirme rien : il EXÉCUTE. Il relance le générateur comme
# un vrai utilisateur (sous-processus bash "$NEXUS_SCRIPT_PATH"), dans un
# dépôt git temporaire, et vérifie les contrats un par un :
#
#   T1   outils requis présents (bash/git/python3/PyYAML/sed/mktemp)
#   T2   dépôt git temporaire opérationnel
#   T3   génération réelle des 9 types : fichier + non vide + marqueur
#   T4   validation structurelle des 9 YAML (python3 yaml.safe_load)
#   T5   anti-bug skeleton : AUCUN 'run: actions/' dans aegis (PROTON ④)
#   T6   --dry-run n'écrit JAMAIS rien
#   T7   type inconnu -> exit 2
#   T8   hors dépôt git -> exit 3
#   T9   collision sans --force -> exit 4
#   T10  cron invalide -> exit 2
#   T11  validate sur YAML cassé -> exit 5
#   T12  uninstall du marqueur + refuse un fichier non-NEXUS
#   T13  version --node invalide -> exit 2 (injection sed impossible)
#   T14  validate sur fichier non-YAML -> exit 5
#   T15  list : exit 0 et les 13 types présents
#   T16  --skip-validation : génération quand même + avertissement
#   T17  explain : les 13 documentations opérationnelles répondent
#   T18  doctor : exit 0 (environnement complet)
#
# Tout test échoué est rapporté avec sa preuve (sortie du sous-processus).
ST_PASS=0
ST_FAIL=0

st_pass() {
    ST_PASS=$((ST_PASS + 1))
    printf '  %sPASS%s  %s\n' "${C_GREEN}" "${C_RESET}" "$1"
}

st_fail() {
    ST_FAIL=$((ST_FAIL + 1))
    printf '  %sFAIL%s  %s\n' "${C_RED}" "${C_RESET}" "$1"
    if [ -n "${2:-}" ]; then
        printf '        preuve: %s\n' "$2"
    fi
}

# run_case : exécute le générateur en sous-processus, capture le code de
# retour dans RUN_RC et la sortie dans RUN_OUT. set -e est suspendu le
# temps de l'appel : un échec ATTENDU n'est pas un échec du selftest.
run_case() {
    RUN_RC=0
    RUN_OUT=""
    set +e
    RUN_OUT="$(bash "$NEXUS_SCRIPT_PATH" "$@" 2>&1)"
    RUN_RC=$?
    set -e
}

cmd_selftest() {
    local repo nonrepo t f count_before count_after fixture

    log_step "NEXUS CI GENERATOR v$NEXUS_VERSION — SELFTEST PROTON"
    printf '\n'

    # ------------------------------------------------------------- T1
    printf '  [T1] outils requis\n'
    if command -v git >/dev/null 2>&1 \
        && command -v python3 >/dev/null 2>&1 \
        && python3 -c "import yaml" >/dev/null 2>&1 \
        && command -v sed >/dev/null 2>&1 \
        && command -v mktemp >/dev/null 2>&1; then
        st_pass "outils requis présents (bash/git/python3/PyYAML/sed/mktemp)"
    else
        st_fail "outils manquants"
    fi

    # ------------------------------------------------------------- T2
    printf '  [T2] dépôt git temporaire\n'
    repo="$(nexus_tmpdir_new)"
    if git init -q "$repo" 2>/dev/null && [ -d "$repo/.git" ]; then
        st_pass "dépôt créé: $repo"
    else
        st_fail "impossible de créer le dépôt temporaire"
        die "selftest interrompu: environnement git cassé" "$EXIT_ENV"
    fi

    # ------------------------------------------------------------- T3
    printf "  [T3] génération réelle des ${#TYPES_ORDER[@]} types\n"
    local gen_ok=0
    local gen_fail=""
    local expected=${#TYPES_ORDER[@]}
    for t in "${TYPES_ORDER[@]}"; do
        f="$repo/.github/workflows/${WORKFLOW_FILE[$t]}"
        run_case "$t" --dir "$repo" --force
        if [ "$RUN_RC" -eq 0 ] && [ -s "$f" ]; then
            if head -n 3 "$f" | grep -q "$NEXUS_MARKER"; then
                gen_ok=$((gen_ok + 1))
            else
                gen_fail="$gen_fail $t(marqueur)"
            fi
        else
            gen_fail="$gen_fail $t(rc=$RUN_RC)"
        fi
    done
    if [ -z "$gen_fail" ] && [ "$gen_ok" -eq "$expected" ]; then
        st_pass "$expected/$expected workflows générés, non vides, marqueur présent"
    else
        st_fail "génération incomplète (ok=$gen_ok)$gen_fail" "$RUN_OUT"
    fi

    # ------------------------------------------------------------- T4
    printf "  [T4] validation structurelle des ${#TYPES_ORDER[@]} YAML\n"
    local val_ok=0
    local val_fail=""
    for t in "${TYPES_ORDER[@]}"; do
        f="$repo/.github/workflows/${WORKFLOW_FILE[$t]}"
        if python3 - "$f" <<'NEXUS_PY' >>/dev/null 2>&1
import sys, yaml
with open(sys.argv[1], "r", encoding="utf-8") as fh:
    data = yaml.safe_load(fh)
assert isinstance(data, dict)
assert ("on" in data) or (True in data)
assert isinstance(data.get("jobs"), dict) and data["jobs"]
for name, job in data["jobs"].items():
    assert isinstance(job, dict) and "runs-on" in job
NEXUS_PY
        then
            val_ok=$((val_ok + 1))
        else
            val_fail="$val_fail $t"
        fi
    done
    if [ -z "$val_fail" ] && [ "$val_ok" -eq "$expected" ]; then
        st_pass "$expected/$expected YAML syntaxiquement ET structurellement valides"
    else
        st_fail "validation en échec pour:$val_fail"
    fi

    # ------------------------------------------------------------- T5
    printf '  [T5] anti-bug skeleton (PROTON 4)\n'
    f="$repo/.github/workflows/nexus-aegis.yml"
    if grep -qE '^[[:space:]]*run:.*actions/' "$f"; then
        st_fail "pattern ILLÉGAL 'run: actions/' encore présent dans aegis" \
            "$(grep -nE '^[[:space:]]*run:.*actions/' "$f" | head -n 1)"
    else
        st_pass "aucun 'run: actions/' dans aegis — setup-node est bien un uses:"
        if grep -q 'uses: actions/setup-node@v4' "$f"; then
            st_pass "preuve du correctif: 'uses: actions/setup-node@v4' présent"
        else
            st_fail "setup-node@v4 introuvable dans aegis"
        fi
    fi

    # ------------------------------------------------------------- T6
    printf '  [T6] --dry-run n écrit rien\n'
    count_before="$(ls -A "$repo/.github/workflows" | wc -l)"
    run_case node --dir "$repo" --dry-run
    count_after="$(ls -A "$repo/.github/workflows" | wc -l)"
    if [ "$RUN_RC" -eq 0 ] && [ "$count_before" = "$count_after" ]; then
        st_pass "dry-run: 0 fichier écrit (avant=$count_before après=$count_after)"
    else
        st_fail "dry-run a écrit quelque chose (avant=$count_before après=$count_after)"
    fi

    # ------------------------------------------------------------- T7
    printf '  [T7] type inconnu -> exit 2\n'
    run_case kubernetes --dir "$repo"
    if [ "$RUN_RC" -eq 2 ]; then
        st_pass "type inconnu refusé, exit=$RUN_RC"
    else
        st_fail "type inconnu: exit=$RUN_RC attendu=2" "$RUN_OUT"
    fi

    # ------------------------------------------------------------- T8
    printf '  [T8] hors dépôt git -> exit 3\n'
    nonrepo="$(nexus_tmpdir_new)"
    run_case aegis --dir "$nonrepo"
    if [ "$RUN_RC" -eq 3 ]; then
        st_pass "répertoire non-git refusé, exit=$RUN_RC"
    else
        st_fail "non-git: exit=$RUN_RC attendu=3" "$RUN_OUT"
    fi

    # ------------------------------------------------------------- T9
    printf '  [T9] collision sans --force -> exit 4\n'
    run_case aegis --dir "$repo"
    if [ "$RUN_RC" -eq 4 ]; then
        st_pass "collision détectée, exit=$RUN_RC (et --force la contourne)"
    else
        st_fail "collision: exit=$RUN_RC attendu=4" "$RUN_OUT"
    fi

    # ------------------------------------------------------------ T10
    printf '  [T10] cron invalide -> exit 2\n'
    run_case nightly --dir "$repo" --cron 'pas un cron'
    if [ "$RUN_RC" -eq 2 ]; then
        st_pass "cron invalide refusé, exit=$RUN_RC"
    else
        st_fail "cron invalide: exit=$RUN_RC attendu=2" "$RUN_OUT"
    fi

    # ------------------------------------------------------------ T11
    printf '  [T11] validate sur YAML cassé -> exit 5\n'
    fixture="$repo/.github/workflows/casse.yml"
    printf 'name: YAML casse\non: [push\njobs:\n  bad job sans runs-on\n' >"$fixture"
    run_case validate "$fixture"
    if [ "$RUN_RC" -eq 5 ]; then
        st_pass "YAML cassé refusé par validate, exit=$RUN_RC"
    else
        st_fail "validate: exit=$RUN_RC attendu=5" "$RUN_OUT"
    fi
    rm -f "$fixture"

    # ------------------------------------------------------------ T12
    printf '  [T12] uninstall: marqueur requis + suppression réelle\n'
    run_case uninstall aegis --dir "$repo" --force
    f="$repo/.github/workflows/nexus-aegis.yml"
    if [ "$RUN_RC" -eq 0 ] && [ ! -f "$f" ]; then
        st_pass "uninstall aegis OK (fichier supprimé)"
    else
        st_fail "uninstall aegis: exit=$RUN_RC fichier=$([ -f "$f" ] && echo present || echo absent)"
    fi
    printf '# workflow écrit a la main\nname: main\n' >"$f"
    run_case uninstall aegis --dir "$repo" --force
    if [ "$RUN_RC" -ne 0 ] && [ -f "$f" ]; then
        st_pass "uninstall REFUSE un fichier sans marqueur NEXUS (protégé)"
    else
        st_fail "uninstall a supprimé un fichier non-NEXUS !"
    fi
    rm -f "$f"

    # ------------------------------------------------------------ T13
    printf '  [T13] version --node invalide -> exit 2\n'
    run_case aegis --dir "$repo" --force --node '22; rm -rf /'
    if [ "$RUN_RC" -eq 2 ]; then
        st_pass "tentative d'injection refusée, exit=$RUN_RC (regex valid_version)"
    else
        st_fail "valeur hostile acceptée: exit=$RUN_RC attendu=2" "$RUN_OUT"
    fi

    # ------------------------------------------------------------ T14
    printf '  [T14] validate sur fichier non-YAML -> exit 5\n'
    printf 'ceci nest pas du yaml: [unclosed\n' >"$repo/.github/workflows/pas-yaml.yml"
    run_case validate "$repo/.github/workflows/pas-yaml.yml"
    if [ "$RUN_RC" -eq 5 ]; then
        st_pass "non-YAML refusé, exit=$RUN_RC"
    else
        st_fail "non-YAML: exit=$RUN_RC attendu=5" "$RUN_OUT"
    fi
    rm -f "$repo/.github/workflows/pas-yaml.yml"

    # ------------------------------------------------------------ T15
    printf '  [T15] list : exit 0 et types complets\n'
    local miss_types=""
    run_case list
    if [ "$RUN_RC" -eq 0 ]; then
        for t in "${TYPES_ORDER[@]}"; do
            if ! printf '%s' "$RUN_OUT" | grep -q "^[[:space:]]*$t[[:space:]]"; then
                miss_types="$miss_types $t"
            fi
        done
        if [ -z "$miss_types" ]; then
            st_pass "list: exit 0, ${#TYPES_ORDER[@]}/${#TYPES_ORDER[@]} types affichés"
        else
            st_fail "types manquants dans list:$miss_types"
        fi
    else
        st_fail "list: exit=$RUN_RC attendu=0" "$RUN_OUT"
    fi

    # ------------------------------------------------------------ T16
    printf '  [T16] --skip-validation : avertissement + génération\n'
    run_case aegis --dir "$repo" --force --skip-validation --quiet
    f="$repo/.github/workflows/nexus-aegis.yml"
    if [ "$RUN_RC" -eq 0 ] && [ -s "$f" ]; then
        st_pass "skip-validation: généré avec exit=$RUN_RC (l'utilisateur a signé le risque)"
    else
        st_fail "skip-validation: exit=$RUN_RC fichier=$([ -s "$f" ] && echo present || echo absent)" "$RUN_OUT"
    fi

    # ------------------------------------------------------------ T17
    printf "  [T17] explain : les ${#TYPES_ORDER[@]} documentations\n"
    local exp_ok=0
    local exp_fail=""
    for t in "${TYPES_ORDER[@]}"; do
        run_case explain "$t"
        if [ "$RUN_RC" -eq 0 ] && [ -n "$RUN_OUT" ]; then
            exp_ok=$((exp_ok + 1))
        else
            exp_fail="$exp_fail $t(rc=$RUN_RC)"
        fi
    done
    if [ -z "$exp_fail" ] && [ "$exp_ok" -eq "$expected" ]; then
        st_pass "$expected/$expected explains répondent avec contenu"
    else
        st_fail "explain en échec pour:$exp_fail"
    fi

    # ------------------------------------------------------------ T18
    printf '  [T18] doctor : exit 0 attendu (environnement complet)\n'
    run_case doctor
    if [ "$RUN_RC" -eq 0 ]; then
        st_pass "doctor: exit 0, bilan complet rendu"
    else
        st_fail "doctor: exit=$RUN_RC attendu=0" "$RUN_OUT"
    fi

    # -------------------------------------------------------- BILAN
    printf '\n'
    hr
    printf '  BILAN SELFTEST: %sPASS=%s  FAIL=%s%s\n' "" "$ST_PASS" "$ST_FAIL" ""
    hr
    if [ "$ST_FAIL" -gt 0 ]; then
        die "selftest en échec: $ST_FAIL test(s) rouges — LIVRAISON REFUSÉE (PROTON 2)" "$EXIT_ERR"
    fi
    log_ok "SELFTEST TOUT VERT — livraison autorisée"
}

# ============================================================================
# SECTION 30 — COMMANDE manual (manuel intégré)
# ============================================================================
cmd_manual() {
    cat <<'NEXUS_MANUAL'
NEXUS CI GENERATOR — MANUEL INTÉGRÉ (v2.0.0)
==============================================================================

NOM
    nexus-ci-generator — générateur de pipelines GitHub Actions prêts
    pour la production.

SYNOPSIS
    nexus-ci-generator.sh <commande> [options]
    nexus-ci-generator.sh <type>     [options]

DESCRIPTION
    Génère des workflows GitHub Actions dans .github/workflows/. Le
    générateur applique quatre contrats non négociables :

    1. VALIDATION AVANT INSTALLATION
       Chaque YAML produit est parsé (PyYAML) et vérifié
       structurellement (déclencheur 'on', jobs non vides, runs-on
       par job) AVANT d'être écrit dans le dépôt. Un YAML cassé
       n'est jamais installé.

    2. ÉCRITURE ATOMIQUE
       Le contenu part dans un fichier temporaire du MÊME répertoire,
       puis mv. Une interruption (Ctrl-C, kill) ne laisse jamais de
       fichier à moitié écrit : le trap EXIT supprime les tmp.

    3. PROTECTION DU TRAVAIL AUTRUI
       uninstall refuse de supprimer tout fichier qui ne porte pas
       le marqueur "Genere par NEXUS CI GENERATOR". Vos workflows
       écrits à la main sont intouchables.

    4. ANTI-REGRESSION
       Le validateur rejette le pattern 'run: actions/...' — le bug
       du skeleton v1 (action invoquée comme commande shell) ne peut
       plus JAMAIS revenir : le selftest le vérifie par grep.

ARCHITECTURE INTERNE
    Le script est organisé en sections numérotées :
      1-5    garde-fous, couleurs, journalisation, temporaires
      6-8    registre des types, usage, utilitaires
      9-13   options, validateurs d'entrées, check_env, validateur
             YAML, substitution placeholders, écriture atomique
      14-22e les 13 templates inject_<type> (heredocs quotés)
      23     explain : documentation par type
      24-28  commandes list/explain/validate/doctor/uninstall
      29     selftest (banc d'essai PROTON, 18 tests)
      30     ce manuel
      31     changelog
      32     main (dispatch)

COMMANDES
    <type>     raccourci: génère ce type (voir TYPES ci-dessous)
    list       liste les types avec description et fichier cible
    explain    documentation opérationnelle d'un type: jobs, secrets,
               permissions, artefacts, durée estimée, adaptation
    validate   valide un fichier YAML (syntaxe + structure Actions)
    doctor     diagnostic de l'environnement (verdict par vérification)
    uninstall  supprime un workflow généré (marqueur requis)
    selftest   banc d'essai complet: 18 tests, positives et négatives
    manual     ce manuel
    changelog  historique des versions

TYPES
    aegis    Next.js: paths-filter, gitleaks, eslint --max-warnings=0,
             tsc --noEmit, tests+coverage, next build, CodeQL, Trivy,
             SLSA attest-build-provenance. (skeleton corrigé)
    java     Maven: matrice JDK [17,<--java>], cache maven, verify,
             OWASP dependency-check, CodeQL java-kotlin.
    python   ruff check + format --check, pytest --cov, mypy,
             pip-audit --strict, matrice 3.10-3.13, CodeQL python.
    node     npm ci strict (lockfile exigé), lint/test/build --if-present,
             matrice Node [20,22,<--node>], npm audit bloquant HIGH.
    docker   hadolint, buildx multi-arch amd64+arm64, metadata-action,
             Trivy sur l'image, SBOM SPDX, push ghcr hors PR.
    go       golangci-lint, go vet, tests -race + coverage, goreleaser
             sur tag v*.
    rust     fmt nightly, clippy -D warnings, test --all-features,
             cargo-audit, build --release sur tag.
    release  tag v*: build auto-détecté (build.sh/Makefile/npm/cargo/go),
             changelog par PR merged, gh-release + notes natives.
    nightly  cron: gitleaks full-history, CodeQL périodique, Trivy
             complet, audits npm/pip/cargo par écosystème détecté.
    php      composer validate --strict, install lockfile, php-cs-fixer
             --dry-run --diff, phpunit BLOQUANT, composer audit,
             matrice PHP [8.2, 8.3, <--php>].
    dotnet   matrice SDK [8.0.x, <--dotnet>], restore-once puis build et
             test --no-restore, pack NuGet sur main, CodeQL csharp.
    cpp      cmake Release -Werror sur [gcc, clang], ctest, job
             sanitize séparé (ASan+UBSan), cppcheck warning+style.
    android  gradlew vérifié (présent ET exécutable), JDK 17 temurin,
             lint, testDebugUnitTest, assembleDebug + APK joint,
             assembleRelease UNSIGNED sur tag (signature = acte humain).

OPTIONS
    --dir <chemin>       répertoire du dépôt cible (défaut: .)
    --branch <branche>   branche déclencheuse (défaut: main)
    --node <version>     Node.js (aegis, node) — défaut 22
    --java <version>     JDK (java) — défaut 21
    --python <version>   Python (python) — défaut 3.12
    --go <version>       Go (go) — défaut 1.23
    --php <version>      PHP (php) — défaut 8.3
    --dotnet <version>   .NET SDK (dotnet) — défaut 9.0
    --registry <hote>    registre (docker) — défaut ghcr.io
    --cron <expr>        cron 5 champs (nightly) — défaut 0 3 * * *
    --force              écraser un workflow existant / passer confirm
    --dry-run            afficher le YAML sans l'écrire
    --skip-validation    sauter la validation YAML (déconseillé, la
                         validation est le cœur du générateur)
    --no-color           désactiver les couleurs ANSI
    --quiet, -q          supprimer les messages d'information
    -h, --help           aide courte

CODES DE RETOUR
    0  succès
    1  erreur générique (selftest rouge, IO)
    2  usage incorrect (type inconnu, option inconnue, valeur invalide)
    3  environnement invalide (pas un dépôt git, PyYAML absent)
    4  collision de fichier (workflow existant sans --force)
    5  validation YAML échouée

ENVIRONNEMENT
    bash >= 4 (testé: 5.2), git, python3 + PyYAML, sed, mktemp.
    NO_COLOR=1 est respecté (convention no-color.org).
    TERM=dumb et stdout non-terminal désactivent aussi les couleurs.

FICHIERS
    <dépôt>/.github/workflows/nexus-aegis.yml    (type aegis)
    <dépôt>/.github/workflows/nexus-java.yml     (type java)
    <dépôt>/.github/workflows/nexus-python.yml   (type python)
    <dépôt>/.github/workflows/nexus-node.yml     (type node)
    <dépôt>/.github/workflows/nexus-docker.yml   (type docker)
    <dépôt>/.github/workflows/nexus-go.yml       (type go)
    <dépôt>/.github/workflows/nexus-rust.yml     (type rust)
    <dépôt>/.github/workflows/nexus-release.yml  (type release)
    <dépôt>/.github/workflows/nexus-nightly.yml (type nightly)
    <dépôt>/.github/workflows/nexus-php.yml      (type php)
    <dépôt>/.github/workflows/nexus-dotnet.yml   (type dotnet)
    <dépôt>/.github/workflows/nexus-cpp.yml      (type cpp)
    <dépôt>/.github/workflows/nexus-android.yml  (type android)

SÉCURITÉ
    - Les valeurs d'options sont validées par regex AVANT toute
      substitution (injection sed/YAML impossible).
    - Les heredocs de templates sont quotés (<<'NEXUS_YAML') : les
      expressions GitHub ${{ }} ne sont jamais développées par bash.
    - Les permissions Actions sont au niveau des jobs (moindre
      privilège), jamais contents:write global par défaut.
    - Aucun secret requis : tous les workflows fonctionnent avec le
      GITHUB_TOKEN automatique.

DÉPANNAGE
    "module python 'yaml' introuvable" (exit 3)
        pip install pyyaml  —  la validation YAML est le cœur du
        générateur ; --skip-validation n'est jamais la bonne réponse,
        c'est la déclaration d'un risque.

    "bash >= 4.0 requis" (exit 3)
        macOS livre bash 3.2 par défaut : brew install bash, puis
        re-exécutez avec /opt/homebrew/bin/bash.

    "collision: ... existe déjà" (exit 4)
        Comportement voulu : régénérez avec --force, ou supprimez
        d'abord avec la commande uninstall (confirmation demandée).

    "validation YAML échouée" (exit 5)
        Ne devrait JAMAIS arriver sur un fichier produit par ce
        générateur : c'est un bug à rapporter. Sur un fichier de
        votre cru passé à validate : le message contient la ligne
        et la raison exactes du rejet.

    "uninstall: REFUS: ne porte pas le marqueur"
        Le fichier a probablement été édité à la main après
        génération. Supprimez-le avec git rm vous-même : le
        générateur ne touche jamais au travail humain.

EXEMPLES AVANCÉS
    # régénérer aegis pour Node 20, en écrasant l'existant
    ./nexus-ci-generator.sh aegis --node 20 --force

    # prévisualiser le pipeline docker sans rien écrire
    ./nexus-ci-generator.sh docker --dry-run | less

    # générer nightly sur un dépôt distant, cron lundi 02:30 UTC
    ./nexus-ci-generator.sh nightly --dir ~/work/api --cron '30 2 * * 1'

    # valider un workflow écrit à la main avant de le committer
    ./nexus-ci-generator.sh validate .github/workflows/main.yml

    # diagnostic complet avant d'automatiser un nouveau poste
    ./nexus-ci-generator.sh doctor

NEXUS_MANUAL
}

# ============================================================================
# SECTION 31 — COMMANDE changelog
# ============================================================================
cmd_changelog() {
    cat <<'NEXUS_CHANGELOG'
HISTORIQUE DES VERSIONS — NEXUS CI GENERATOR
==============================================

v2.0.0 (actuelle)
    - 13 types de workflows (aegis, java, python, node, docker, go,
      rust, release, nightly, php, dotnet, cpp, android) au lieu de
      4 dans le skeleton v1.
    - CORRECTION PROTON 4 : le job setup de aegis exécutait
      'actions/setup-node@v4' comme commande shell (run:) — illégal.
      Corrigé en 'uses:' avec with: node-version + cache npm.
      Le validateur rejette désormais le pattern 'run: actions/'
      et le selftest le vérifie par grep (T5).
    - Validation YAML intégrée : syntaxe (PyYAML) + structure
      (on/jobs/runs-on) AVANT toute installation. exit 5 sinon.
    - Écriture atomique (tmp + mv) et trap EXIT de nettoyage.
    - Validation des entrées par regex : branch, versions, cron,
      registry. L'injection via sed est impossible.
    - Sous-commandes : list, explain, validate, doctor, uninstall,
      selftest, manual, changelog.
    - uninstall protégé par marqueur : refuse les fichiers non
      générés par NEXUS (travail manuel intouchable).
    - explain : documentation opérationnelle par type (jobs, secrets,
      permissions, artefacts, durées, adaptation).
    - selftest : 18 tests dont 8 négatifs (exit codes prouvés),
      y compris tentative d'injection via --node (T13), rejet des
      clés YAML dupliquées, et protection anti-suppression de
      fichiers non-NEXUS (T12).
    - Noms des fonctions du skeleton v1 conservés verbatim :
      usage, check_env, inject_aegis, inject_java, inject_python,
      inject_node, main (PROTON 5 : spec préservée).

v1.0.0 (skeleton original — DGK)
    - 4 types : aegis, java, python, node.
    - Génération en heredoc vers .github/workflows/.
    - check_env exigeant un dépôt git.
    - Défaut connu (corrigé en v2) : job setup de aegis avec
      'run: actions/setup-node@v4' — exécuté comme shell par
      GitHub Actions, workflow rouge à chaque run.
NEXUS_CHANGELOG
}

# ============================================================================
# SECTION 32 — main (dispatch général)
# ============================================================================
main() {
    if [ $# -eq 0 ]; then
        usage >&2
        exit "$EXIT_USAGE"
    fi

    local cmd="$1"
    shift

    case "$cmd" in
        -h|--help)
            usage
            exit "$EXIT_OK"
            ;;
        aegis|java|python|node|docker|go|rust|release|nightly|php|dotnet|cpp|android)
            parse_args "$@"
            handle_help_flag
            validate_generation_options "$cmd"
            banner
            generate_workflow "$cmd"
            ;;
        list)
            parse_args "$@"
            handle_help_flag
            banner
            cmd_list
            ;;
        explain)
            parse_args "$@"
            handle_help_flag
            cmd_explain
            ;;
        validate)
            parse_args "$@"
            handle_help_flag
            cmd_validate
            ;;
        doctor)
            parse_args "$@"
            handle_help_flag
            banner
            cmd_doctor
            ;;
        uninstall)
            parse_args "$@"
            handle_help_flag
            cmd_uninstall
            ;;
        selftest)
            parse_args "$@"
            handle_help_flag
            cmd_selftest
            ;;
        manual)
            parse_args "$@"
            handle_help_flag
            cmd_manual
            ;;
        changelog)
            parse_args "$@"
            handle_help_flag
            cmd_changelog
            ;;
        *)
            die "commande inconnue: $cmd (types: ${TYPES_ORDER[*]} — voir --help)" "$EXIT_USAGE"
            ;;
    esac
}

# Point d'entrée — le dispatch n'accepte JAMAIS un appel sans arguments.
main "$@"
