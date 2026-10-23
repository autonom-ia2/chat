# shellcheck shell=bash
# Funções do kit de demo (#2140) usadas nos dois lados: o bin/demo (M4) e o no_m2.sh (M2) carregam este arquivo.
# Quem carrega precisa ter definido `falha`.

# em_uso <diretório>
# Imprime os PIDs com arquivo aberto no diretório e devolve 0 quando há algum; devolve 1 só quando o lsof confirmou
# que está livre (saída vazia E stderr vazio). Falha do mktemp ou código do lsof acima de 1 chama `falha`, que
# encerra o script. Qualquer linha no stderr do lsof (aviso de permissão, de sistema de arquivos etc.) conta como
# "em uso": o lsof roda sem -w para que nenhum aviso fique escondido. Medido em 23/10 no lsof 4.91: em operação
# normal (snapshot com node_modules no M2 e no M4, portas livres e ocupadas) o stderr sai vazio, então não há aviso
# benigno a tolerar. O código de saída não separa "nada" de "erro" (sai 1 nos dois casos), por isso o stderr decide.
# Quem chama costuma estar num `if`, onde o set -e não vale, por isso cada passo é conferido à mão.
# Indexador (Spotlight) e buscas de disco abrem arquivo de passagem: só é "em uso" se continuar assim em 5 leituras
# seguidas, com 3 s entre elas. Sem exceção de PID: os servidores da demo já foram parados e conferidos antes.
# Tempo medido do lsof +D: ~3 s num snapshot com node_modules (89 mil arquivos, 602 MB de node_modules) no M2.
em_uso() {
  local dir=$1 tentativa saida erro codigo pid
  erro=$(/usr/bin/mktemp "${TMPDIR:-/tmp}/demo-lsof.XXXXXX") || falha "mktemp falhou; não sei se $dir está em uso, não apago"
  [ -n "$erro" ] && [ -f "$erro" ] || falha "mktemp não criou o arquivo; não sei se $dir está em uso, não apago"
  for tentativa in 1 2 3 4 5; do
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
      /bin/rm -f "$erro"
      return 1
    fi
    [ "$tentativa" -eq 5 ] || sleep 3
  done
  /bin/rm -f "$erro"
  for pid in $saida; do /bin/ps -p "$pid" -o pid=,comm= || echo "$pid (já saiu)"; done
  return 0
}
