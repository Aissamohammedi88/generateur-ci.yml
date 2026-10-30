#!/usr/bin/env bash
# ============================================================================
#  NEXUS TOUT-EN-UN v1.0.1 — l'orchestrateur qui fait TOUT
#  Auteur : DGK — Aissa Mohammedi (protocole PROTON)
# ----------------------------------------------------------------------------
#  CORRECTION : Chemin absolu vers le générateur ajouté à l'étape 1/6.
# ============================================================================

# Garde anti-fermeture n°1 : SOURCÉ → re-exécution en enfant
if [ -n "${BASH_SOURCE[0]}" ] && [ "${BASH_SOURCE[0]}" != "$0" ] && [ -f "${BASH_SOURCE[0]}" ]; then
    bash "${BASH_SOURCE[0]}" "$@"
    return 0 2>/dev/null || exit 0
fi

# ----------------------------------------------------------------------------
# CONSTANTES ET COULEURS
# ----------------------------------------------------------------------------
NEXUS_TOUT_VERSION="1.0.1"
ALL_TYPES="aegis java python node docker go rust release nightly php dotnet cpp android"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)" || SCRIPT_DIR="."

if [ -t 1 ]; then
    C_OK=$'\033[92m'; C_INFO=$'\033[96m'; C_WARN=$'\033[93m'; C_ERR=$'\033[91m'; C_OFF=$'\033[0m'; C_GRAS=$'\033[1m'
else
    C_OK=''; C_INFO=''; C_WARN=''; C_ERR=''; C_OFF=''; C_GRAS=''
fi

log_ok()   { printf '%s[OK]%s %s\n'   "$C_OK"   "$C_OFF" "$*"; }
log_info() { printf '%s[INFO]%s %s\n' "$C_INFO" "$C_OFF" "$*"; }
log_warn() { printf '%s[WARN]%s %s\n' "$C_WARN" "$C_OFF" "$*"; }
log_err()  { printf '%s[ERR]%s %s\n'  "$C_ERR"  "$C_OFF" "$*"; }
etape()    { printf '\n%s%s── %s ──────────────────────────────%s\n' "$C_GRAS" "$C_INFO" "$*" "$C_OFF"; }
titre()    { printf '%s\n' "${C_GRAS}${C_INFO}============================================================${C_OFF}"
             printf '%s\n' "${C_GRAS}  $*${C_OFF}"; }

usage_tout() {
    titre "NEXUS TOUT-EN-UN v${NEXUS_TOUT_VERSION} — l'orchestrateur"
    printf 'Usage: bash nexus-tout-en-un.sh [options]\n\n'
    printf 'Options :\n'
    printf '  --repo <dir>        dépôt cible (défaut: dossier courant)\n'
    printf '  --generator <f>     chemin du nexus-ci-generator.sh\n'
    printf '  --only <types...>   génère seulement ces types (ex: --only aegis node)\n'
    printf '  --node <ver>        version Node projet (défaut 22)\n'
    printf '  --php <ver>         version PHP projet (défaut 8.3)\n'
    printf '  --branch <br>       branche principale (défaut main)\n'
    printf '  --skip-selftest     saute l étape selftest (déconseillé)\n'
    printf '  --skip-npm          saute install+build npm\n'
    printf '  --skip-generate     env check + selftest seulement\n'
    printf '  --help, -h          cette aide\n\n'
    printf 'Les 13 types : %s\n' "$ALL_TYPES"
    printf 'Codes retour : 0 vert | 1 usage | 2 générateur absent | 3 selftest | 4 génération | 5 npm\n'
}

# ----------------------------------------------------------------------------
# LE TRAVAIL ENTIER — appelé dans un SOUS-SHELL
# ----------------------------------------------------------------------------
main_tout() {
    set -euo pipefail

    # ---------------- parsing ----------------
    OPT_REPO="$PWD"
    OPT_GENERATOR=""
    OPT_NODE="22"; OPT_PHP="8.3"; OPT_BRANCH="main"
    OPT_SKIP_SELFTEST=0; OPT_SKIP_NPM=0; OPT_SKIP_GENERATE=0
    OPT_ONLY=""
    RC_USAGE=1; RC_NOGEN=2; RC_SELFTEST=3; RC_GENERATE=4; RC_NPM=5

    while [ $# -gt 0 ]; do
        case "$1" in
            --repo)      if [ $# -ge 2 ]; then OPT_REPO="$2"; shift 2
                         else log_err "--repo exige un dossier"; exit "$RC_USAGE"; fi ;;
            --generator) if [ $# -ge 2 ]; then OPT_GENERATOR="$2"; shift 2
                         else log_err "--generator exige un chemin"; exit "$RC_USAGE"; fi ;;
            --node)      if [ $# -ge 2 ]; then OPT_NODE="$2"; shift 2
                         else log_err "--node exige une version"; exit "$RC_USAGE"; fi ;;
            --php)       if [ $# -ge 2 ]; then OPT_PHP="$2"; shift 2
                         else log_err "--php exige une version"; exit "$RC_USAGE"; fi ;;
            --branch)    if [ $# -ge 2 ]; then OPT_BRANCH="$2"; shift 2
                         else log_err "--branch exige un nom"; exit "$RC_USAGE"; fi ;;
            --only)      shift
                         while [ $# -gt 0 ] && [ "${1#-}" = "$1" ]; do
                             OPT_ONLY="$OPT_ONLY $1"; shift
                         done ;;
            --skip-selftest) OPT_SKIP_SELFTEST=1; shift ;;
            --skip-npm)      OPT_SKIP_NPM=1; shift ;;
            --skip-generate) OPT_SKIP_GENERATE=1; shift ;;
            --help|-h)       usage_tout; exit 0 ;;
            *)               log_err "option inconnue: $1 (voir --help)"; exit "$RC_USAGE" ;;
        esac
    done

    if [ -n "$OPT_ONLY" ]; then
        if ! printf '%s' "$OPT_ONLY" | grep -Eq '^ *[a-z][a-z ]*$'; then
            log_err "--only: noms de types invalides (a-z et espaces seulement)"
            exit "$RC_USAGE"
        fi
    fi

    titre "NEXUS TOUT-EN-UN v${NEXUS_TOUT_VERSION} — tout faire, en une commande"

    # ---------------- étape 1/6 : trouver le générateur ----------------
    etape "1/6 — Localisation du générateur nexus-ci-generator.sh"
    GEN=""
    if [ -n "$OPT_GENERATOR" ]; then
        if [ -f "$OPT_GENERATOR" ]; then
            GEN="$OPT_GENERATOR"
        else
            log_err "générateur introuvable : $OPT_GENERATOR"
            exit "$RC_NOGEN"
        fi
    # ★ CHEMIN ABSOLU AJOUTÉ ICI ★
    elif [ -f "/home/nexus/Bureau/nexus-ci-generator.sh" ]; then
        GEN="/home/nexus/Bureau/nexus-ci-generator.sh"
    elif [ -f "$SCRIPT_DIR/nexus-ci-generator.sh" ]; then
        GEN="$SCRIPT_DIR/nexus-ci-generator.sh"
    elif [ -f "$PWD/nexus-ci-generator.sh" ]; then
        GEN="$PWD/nexus-ci-generator.sh"
    elif command -v nexus-ci-generator.sh >/dev/null 2>&1; then
        GEN="$(command -v nexus-ci-generator.sh)"
    fi
    if [ -z "$GEN" ]; then
        log_err "nexus-ci-generator.sh introuvable."
        log_info "mets-le dans le MÊME dossier que nexus-tout-en-un.sh, ou :"
        log_info "  bash nexus-tout-en-un.sh --generator /chemin/nexus-ci-generator.sh"
        exit "$RC_NOGEN"
    fi
    log_ok "générateur : $GEN"

    if grep -q '__NODE_MATRIX__' "$GEN" 2>/dev/null; then
        log_ok "version corrigée confirmée (matrices dédupliquées)"
    else
        log_warn "ANCIENNE VERSION détectée : doublons de matrices possibles."
        log_warn "re-télécharge nexus-ci-generator.sh (sha256 doit commencer par 78e23787)."
        log_warn "je continue quand même — mais re-génère après mise à jour."
    fi

    # ---------------- étape 2/6 : environnement ----------------
    etape "2/6 — Vérification de l'environnement"
    ENV_FAIL=0

    if [ "${BASH_VERSINFO[0]:-0}" -ge 4 ]; then
        log_ok "bash ${BASH_VERSINFO[0]}.${BASH_VERSINFO[1]} (>= 4 requis)"
    else
        log_err "bash ${BASH_VERSINFO[0]} trouvé, >= 4 requis"; ENV_FAIL=1
    fi

    if command -v git >/dev/null 2>&1; then
        log_ok "git $(git --version 2>/dev/null | awk '{print $3}')"
    else
        log_err "git absent — installe-le (sudo apt install git)"; ENV_FAIL=1
    fi

    if command -v python3 >/dev/null 2>&1; then
        log_ok "python3 $(python3 --version 2>&1 | awk '{print $2}')"
        if python3 -c 'import yaml' >/dev/null 2>&1; then
            log_ok "PyYAML $(python3 -c 'import yaml; print(yaml.__version__)' 2>/dev/null)"
        else
            log_warn "PyYAML absent — tentative d'installation (pip --user)..."
            if python3 -m pip install --user pyyaml >/dev/null 2>&1 && python3 -c 'import yaml' >/dev/null 2>&1; then
                log_ok "PyYAML installé"
            else
                log_warn "PyYAML reste absent : le générateur utilisera son validateur interne"
                log_warn "(installable : sudo apt install python3-yaml)"
            fi
        fi
    else
        log_warn "python3 absent : le validateur PyYAML du générateur sera indisponible"
    fi

    NPM_OK=0
    if command -v node >/dev/null 2>&1 && command -v npm >/dev/null 2>&1; then
        log_ok "node $(node --version 2>/dev/null) + npm $(npm --version 2>/dev/null)"
        NPM_OK=1
    else
        log_warn "node/npm absents — l'étape 6 (npm install + build) sera déclarée manquante"
    fi

    if [ "$ENV_FAIL" -ne 0 ]; then
        log_err "environnement incomplet — corrige les lignes [ERR] puis relance"
        exit "$RC_USAGE"
    fi

    # ---------------- étape 3/6 : selftest ----------------
    etape "3/6 — Selftest du générateur (banc interne)"
    if [ "$OPT_SKIP_SELFTEST" -eq 1 ]; then
        log_warn "selftest sauté par --skip-selftest (PROTON déconseille)"
    else
        if bash "$GEN" selftest 2>&1 | tail -n 5; then
            log_ok "selftest TOUT VERT"
        else
            log_err "selftest ÉCHOUÉ — générateur cassé, je refuse de continuer."
            log_err "re-télécharge nexus-ci-generator.sh puis relance."
            exit "$RC_SELFTEST"
        fi
    fi

    # ---------------- étape 4/6 : dépôt git ----------------
    etape "4/6 — Préparation du dépôt"
    if [ ! -d "$OPT_REPO" ]; then
        log_err "dossier inexistant : $OPT_REPO"
        exit "$RC_USAGE"
    fi
    cd "$OPT_REPO"
    if [ -d .git ]; then
        log_ok "dépôt git existant : $PWD"
    else
        log_info "pas de .git — git init fait pour toi"
        if git init -q . ; then
            log_ok "dépôt git créé : $PWD"
        else
            log_err "git init a échoué"; exit "$RC_GENERATE"
        fi
    fi

    # ---------------- étape 5/6 : génération des workflows ----------------
    etape "5/6 — Génération des workflows GitHub Actions"
    if [ "$OPT_SKIP_GENERATE" -eq 1 ]; then
        log_warn "génération sautée par --skip-generate"
    else
        TYPES="$OPT_ONLY"
        if [ -z "$TYPES" ]; then TYPES="$ALL_TYPES"; fi
        GEN_OK=0; GEN_TOTAL=0
        for t in $TYPES; do
            case " $ALL_TYPES " in
                *" $t "*) ;;
                *)  log_err "type inconnu ignoré : $t"; continue ;;
            esac
            GEN_TOTAL=$((GEN_TOTAL + 1))
            if bash "$GEN" "$t" --dir "$PWD" --node "$OPT_NODE" --php "$OPT_PHP" \
                   --branch "$OPT_BRANCH" --force >/dev/null 2>&1; then
                printf '  %s[+]%s %-9s injecté\n' "$C_OK" "$C_OFF" "$t"
                GEN_OK=$((GEN_OK + 1))
            else
                printf '  %s[x]%s %-9s ÉCHEC\n' "$C_ERR" "$C_OFF" "$t"
            fi
        done
        if [ "$GEN_TOTAL" -eq 0 ] || [ "$GEN_OK" -ne "$GEN_TOTAL" ]; then
            log_err "génération incomplète : $GEN_OK/$GEN_TOTAL"
            log_info "lance le générateur seul pour le détail : bash nexus-ci-generator.sh <type> --dir ."
            exit "$RC_GENERATE"
        fi
        log_ok "$GEN_OK/$GEN_TOTAL workflows installés dans .github/workflows/"
    fi

    # ---------------- étape 6/6 : npm install + build ----------------
    etape "6/6 — npm install + build (si package.json)"
    NPM_DONE=0
    if [ "$OPT_SKIP_NPM" -eq 1 ]; then
        log_warn "étape npm sautée par --skip-npm"
    elif [ ! -f package.json ]; then
        log_info "pas de package.json — étape npm déclarée manquante (PROTON ③)"
    elif [ "$NPM_OK" -ne 1 ]; then
        log_warn "node/npm absents — install + build NON exécutés (déclaré, pas caché)"
    else
        if [ -f package-lock.json ]; then
            log_info "lockfile détecté → npm ci (build reproductible)"
            if npm ci --no-audit --no-fund >/dev/null 2>&1; then
                log_ok "npm ci terminé"
            else
                log_err "npm ci a échoué (détail : npm ci)"; exit "$RC_NPM"
            fi
        else
            log_info "pas de lockfile → npm install (committe le package-lock.json ensuite)"
            if npm install --no-audit --no-fund >/dev/null 2>&1; then
                log_ok "npm install terminé"
            else
                log_err "npm install a échoué (détail : npm install)"; exit "$RC_NPM"
            fi
        fi
        if grep -q '"build"' package.json 2>/dev/null; then
            if npm run build >/dev/null 2>&1; then
                log_ok "npm run build terminé"
            else
                log_err "npm run build a échoué (détail : npm run build)"; exit "$RC_NPM"
            fi
        else
            log_info "pas de script \"build\" dans package.json — build sauté (déclaré)"
        fi
        if grep -q '"test"' package.json 2>/dev/null; then
            if npm test --silent >/dev/null 2>&1; then
                log_ok "npm test terminé"
            else
                log_warn "npm test en échec (détail : npm test)"
            fi
        fi
        NPM_DONE=1
    fi

    # ---------------- résumé final ----------------
    titre "RÉSUMÉ NEXUS TOUT-EN-UN v${NEXUS_TOUT_VERSION}"
    printf 'Dépôt        : %s\n' "$PWD"
    printf 'Générateur   : %s\n' "$GEN"
    if [ -d .github/workflows ]; then
        N="$(find .github/workflows -maxdepth 1 -name '*.yml' 2>/dev/null | wc -l)"
        printf 'Workflows    : %s fichiers\n' "$N"
        for f in .github/workflows/*.yml; do
            if [ -f "$f" ]; then
                printf '  %-38s %4s lignes\n' "$(basename "$f")" "$(wc -l <"$f")"
            fi
        done
    else
        printf 'Workflows    : aucun (génération sautée)\n'
    fi
    if [ "$NPM_DONE" -eq 1 ]; then
        printf 'npm          : install + build FAITS\n'
    elif [ -f package.json ]; then
        printf 'npm          : non exécuté (déclaré ci-dessus)\n'
    fi
    printf '\nProchaines commandes à TON tour :\n'
    printf '  git add -A && git commit -m "ci: workflows NEXUS injectés"\n'
    printf '  git push\n'
    printf '%s\n' "${C_GRAS}  Tout ce qui précède a été exécuté par UNE commande. — DGK / PROTON${C_OFF}"
    exit 0
}

# ----------------------------------------------------------------------------
# Garde anti-fermeture n°2
# ----------------------------------------------------------------------------
rc=0
( main_tout "$@" ) || rc=$?
case "$-" in
    *i*) if [ "$rc" -ne 0 ]; then
             printf '%s[INFO]%s fin (rc=%s) — ton terminal reste ouvert.\n' "$C_INFO" "$C_OFF" "$rc"
         fi ;;
    *)   exit "$rc" ;;
esac
