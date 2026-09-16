#!/usr/bin/env bash
set -euo pipefail


#diretorios e arquivos usados pelo script
dir_base="/root/hash"
arquivo_baseline="${dir_base}/baseline.txt"
arquivo_log="/var/log/fim-check.log"

# diretorios que terao seus arquivos verificados
dir_alvos=(/etc /bin /sbin /boot)

# locais de chaves SSH que nao estao dentro de /etc
dir_chaves_ssh=(/root/.ssh /home/*/.ssh)

# comandos necessarios para o script funcionar
cmds_necessarios=(sha256sum stat find mktemp awk)

# caminho do arquivo temporario atual (usado pela trap de limpeza)
arquivo_tmp=""

#log
log(){
    local nivel="$1"
    shift
    local carimbo
    carimbo="$(date '+%Y-%m-%d %H:%M:%S')"
    echo "[${carimbo}] [${nivel}] $*" | tee -a "$arquivo_log" >&2
}

#tratamento de erro
on_error(){
    local exit_code=$?
    local linha=$1
    log "ERROR" "falha na linha ${linha} (codigo de saida ${exit_code})"
    exit "$exit_code"
}

#limpar temporarios
limpar_temp(){
    if [[ -n "$arquivo_tmp" && -f "$arquivo_tmp" ]]; then
        rm -f "$arquivo_tmp"
    fi
}

trap 'on_error $LINENO' ERR
trap limpar_temp EXIT

#ajuda
mostrar_ajuda(){
    cat <<EOF
Uso: $(basename "$0") [opcao]

Verificador de integridade de arquivos (FIM) para /etc, /bin, /sbin,
/boot e chaves SSH, baseado em hash SHA-256, dono, grupo, permissoes
e contexto SELinux.

Opcoes:
  --baseline    cria (ou recria) a baseline de referencia
  --verificar   compara o estado atual com a baseline existente
  -h, --help    mostra esta mensagem e sai

Exemplos:
  sudo $(basename "$0") --baseline
  sudo $(basename "$0") --verificar
EOF
}

#verificacao de dependencias
dependencias(){
    local cmds_faltando=()
    local cmd
    for cmd in "${cmds_necessarios[@]}"; do
        if ! command -v "$cmd" > /dev/null 2>&1; then
            cmds_faltando+=("$cmd")
        fi
    done

    if (( ${#cmds_faltando[@]} > 0 )); then
        log "ERROR" "comandos essenciais faltando: ${cmds_faltando[*]}"
        exit 3
    fi
}

#verificacao de privilegio
checar_privilegio(){
    if [[ $EUID -ne 0 ]]; then
        log "ERROR" "execute como root (sudo) para ler todos os arquivos alvo"
        exit 2
    fi
}

#lista os arquivos que compoem o escopo do FIM
# imprime um caminho por linha
listar_arquivos_alvo(){
    local dir
    for dir in "${dir_alvos[@]}"; do
        [[ -d "$dir" ]] || continue
        find "$dir" -xdev -type f 2>/dev/null
    done

    for dir in "${dir_chaves_ssh[@]}"; do
        [[ -d "$dir" ]] || continue
        find "$dir" -xdev -type f 2>/dev/null
    done
}

gerar_linha(){
    local caminho="$1"
    local hash dono grupo perms contexto

    hash="$(sha256sum "$caminho" 2>/dev/null | awk '{print $1}')"
    [[ -z "$hash" ]] && return 1

    dono="$(stat -c '%U' "$caminho" 2>/dev/null)"
    grupo="$(stat -c '%G' "$caminho" 2>/dev/null)"
    perms="$(stat -c '%a' "$caminho" 2>/dev/null)"
    contexto="$(stat -c '%C' "$caminho" 2>/dev/null)"
    contexto="${contexto:-sem_selinux}"

    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$hash" "$caminho" "$dono" "$grupo" "$perms" "$contexto"
}

#cria a baseline
criar_baseline(){
    mkdir -p "$dir_base"
    arquivo_tmp="$(mktemp)"

    log "INFO" "gerando baseline em ${arquivo_baseline}"

    local caminho
    while IFS= read -r caminho; do
        gerar_linha "$caminho" >> "$arquivo_tmp" || true
    done < <(listar_arquivos_alvo)

    mv "$arquivo_tmp" "$arquivo_baseline"
    arquivo_tmp=""
    chmod 600 "$arquivo_baseline"

    log "INFO" "baseline criada com $(wc -l < "$arquivo_baseline") arquivos"
}

#compara o estado atual com a baseline
verificar_integridade(){
    if [[ ! -f "$arquivo_baseline" ]]; then
        log "ERROR" "baseline nao encontrada em ${arquivo_baseline}. rode --baseline primeiro"
        exit 2
    fi

    declare -A hash_baseline
    local hash caminho
    while IFS=$'\t' read -r hash caminho _; do
        hash_baseline["$caminho"]="$hash"
    done < "$arquivo_baseline"

    arquivo_tmp="$(mktemp)"
    local achados=0
    local linha_atual hash_atual

    while IFS= read -r caminho; do
        linha_atual="$(gerar_linha "$caminho")" || continue
        hash_atual="$(awk -F'\t' '{print $1}' <<< "$linha_atual")"

        if [[ -n "${hash_baseline[$caminho]+x}" ]]; then
            if [[ "${hash_baseline[$caminho]}" != "$hash_atual" ]]; then
                echo "MODIFICADO  ${caminho}" | tee -a "$arquivo_tmp"
                achados=1
            fi
            unset "hash_baseline[$caminho]"
        else
            echo "NOVO        ${caminho}" | tee -a "$arquivo_tmp"
            achados=1
        fi
    done < <(listar_arquivos_alvo)

    for caminho in "${!hash_baseline[@]}"; do
        echo "REMOVIDO    ${caminho}" | tee -a "$arquivo_tmp"
        achados=1
    done

    if (( achados == 0 )); then
        log "INFO" "verificacao concluida sem divergencias"
    else
        log "WARN" "verificacao concluida com divergencias (detalhes acima e em ${arquivo_log})"
        cat "$arquivo_tmp" >> "$arquivo_log"
    fi

    rm -f "$arquivo_tmp"
    arquivo_tmp=""

    return "$achados"
}

#ponto de entrada
main(){
    if [[ $# -eq 0 ]]; then
        mostrar_ajuda
        exit 2
    fi

    case "$1" in
        -h|--help)
            mostrar_ajuda
            exit 0
            ;;
        --baseline)
            checar_privilegio
            dependencias
            criar_baseline
            exit 0
            ;;
        --verificar)
            checar_privilegio
            dependencias
            local codigo=0
            verificar_integridade || codigo=$?
            exit "$codigo"
            ;;
        *)
            log "ERROR" "opcao invalida: $1"
            mostrar_ajuda
            exit 2
            ;;
    esac
}

main "$@"
