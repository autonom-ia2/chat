# shellcheck shell=bash
# Funções do kit de demo (#2140) usadas nos dois lados: o bin/demo (M4) e o no_m2.sh (M2) carregam este arquivo.
# Quem carrega precisa ter definido `falha`.

# em_uso <diretório>
# Devolve 1 ("livre") só depois de LEITURAS_LIVRE leituras vazias SEGUIDAS do lsof; qualquer leitura com PID zera a
# contagem. Passando de TETO_LEITURAS leituras sem chegar lá, é "em uso" (devolve 0 e imprime os PIDs da última
# leitura com PID). Indexador (Spotlight) e buscas de disco abrem arquivo de passagem: por isso a tolerância a
# leitura com PID, e por isso "livre" exige uma sequência limpa, não uma leitura vazia isolada.
# O lsof roda sem -w (nenhum aviso escondido): qualquer linha no stderr conta como "em uso" na hora. Código acima de
# 1 ou falha do mktemp chama `falha`, que encerra o script. O lsof 4.91 do macOS sai com 1 tanto sem nada aberto
# quanto achando processos, então quem decide é saída vazia com stderr vazio. Medição dos avisos com os mounts de
# cada Mac e passo manual: docs/runbooks/demo-tela-real.md, "Checagem de uso".
# Quem chama costuma estar num `if`, onde o set -e não vale, por isso cada passo é conferido à mão.
# Sem exceção de PID: os servidores da demo já foram parados e conferidos antes.
# Tempo medido do lsof +D: ~3 s num snapshot com node_modules (89 mil arquivos) no M2, ~2 s no M4.
LEITURAS_LIVRE=5
TETO_LEITURAS=20
em_uso() {
  local dir=$1 leitura=0 seguidas=0 saida ultima='' erro codigo pid
  erro=$(/usr/bin/mktemp "${TMPDIR:-/tmp}/demo-lsof.XXXXXX") || falha "mktemp falhou; não sei se $dir está em uso, não apago"
  [ -n "$erro" ] && [ -f "$erro" ] || falha "mktemp não criou o arquivo; não sei se $dir está em uso, não apago"
  while [ "$leitura" -lt "$TETO_LEITURAS" ]; do
    leitura=$((leitura + 1))
    codigo=0
    saida=$(/usr/sbin/lsof -t +D "$dir" 2> "$erro") || codigo=$?
    if [ "$codigo" -gt 1 ]; then
      /usr/bin/head -5 "$erro" >&2
      /bin/rm -f "$erro"
      falha "lsof falhou em $dir (saída $codigo); não sei se está em uso, não apago"
    fi
    if [ -s "$erro" ]; then
      echo "lsof avisou em $dir; conta como em uso:" >&2
      /usr/bin/head -5 "$erro" >&2
      /bin/rm -f "$erro"
      return 0
    fi
    if [ -z "$saida" ]; then
      seguidas=$((seguidas + 1))
      if [ "$seguidas" -ge "$LEITURAS_LIVRE" ]; then
        /bin/rm -f "$erro"
        return 1
      fi
    else
      seguidas=0
      ultima=$saida
    fi
    sleep 1
  done
  /bin/rm -f "$erro"
  echo "$dir em uso: $TETO_LEITURAS leituras sem $LEITURAS_LIVRE vazias seguidas; última leitura com PID:" >&2
  for pid in $ultima; do /bin/ps -p "$pid" -o pid=,comm= >&2 || echo "$pid (já saiu)" >&2; done
  return 0
}
