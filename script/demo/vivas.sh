# shellcheck shell=bash
# Kit de demo (#2965): lista as demos vivas desta máquina, uma por linha: "<slug> <o que está ligado>"
# (ex.: "2140-kit rails,vite,redis"). Viva = demo registrada (demo.env) com Rails, Vite ou Redis escutando. Só leitura.
# O bin/demo manda este arquivo pelo stdin de um bash (ssh, ou neste Mac): consulta a máquina sem deixar pasta nela.
# Erro do lsof ou do awk, ou porta estranha num demo.env, para tudo: nunca vira "nenhuma demo viva".
set -euo pipefail

RAIZ=/Users/Shared/chat2you-demos
falha() { echo "demo[vivas]: $*" >&2; exit 1; }

# Portas TCP em escuta nesta máquina, numa leitura só do lsof. Sem -w, como no `escutando` do no_m2.sh: código acima
# de 1 ou qualquer linha no stderr para tudo (o lsof do macOS sai com 1 quando não acha nada).
erro=$(/usr/bin/mktemp "${TMPDIR:-/tmp}/demo-vivas.XXXXXX") || falha "mktemp falhou; não sei quais demos estão vivas"
[ -n "$erro" ] && [ -f "$erro" ] || falha "mktemp não criou o arquivo; não sei quais demos estão vivas"
codigo=0
saida=$(/usr/sbin/lsof -nP -iTCP -sTCP:LISTEN -Fn 2> "$erro") || codigo=$?
if [ "$codigo" -gt 1 ] || [ -s "$erro" ]; then
  /usr/bin/head -3 "$erro" >&2
  /bin/rm -f "$erro"
  falha "lsof falhou ou avisou (saída $codigo); não sei quais demos estão vivas"
fi
/bin/rm -f "$erro"
# Cada linha "n<endereço>:<porta>" entra na lista como " <porta> ". O endereço pode ter ":" (IPv6): a porta é o
# último campo.
PORTAS=$(printf '%s\n' "$saida" | /usr/bin/awk -F: 'substr($0, 1, 1) == "n" { printf " %s", $NF } END { print " " }') ||
  falha "awk falhou lendo as portas em escuta"

for estado in "$RAIZ"/*/demo.env; do
  [ -f "$estado" ] || continue
  pasta=${estado%/demo.env}
  ligado=''
  for par in rails=RAILS_PORT vite=VITE_PORT redis=REDIS_PORT; do
    porta=$(/usr/bin/awk -F= -v k="${par#*=}" '$1 == k { print $2 }' "$estado") || falha "awk falhou lendo $estado"
    case "$porta" in '' | *[!0-9]*) falha "porta inválida em $estado (${par#*=}='$porta')" ;; esac
    case "$PORTAS" in *" $porta "*) ligado="$ligado,${par%%=*}" ;; esac
  done
  [ -z "$ligado" ] || echo "${pasta##*/} ${ligado#,}"
done
