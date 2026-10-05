# Retomada A6 após indisponibilidade do controle Mac

Root já autorizou a sequência A6 exata depois de revisar fontes, fixtures e
pareceres. A autorização persiste. O impedimento observado é de acesso: uma
sondagem normal de prontidão somente leitura e uma leitura de reconciliação no
Filesystem retornaram timeout/UNAVAILABLE. Uma última sondagem somente leitura,
enviada antes da pausa global, retornou `Session terminated`, `INVALID_ARGUMENT`
e JSON-RPC 32600, sem PID. Root observou o mesmo erro em uma leitura do HANDOFF
às 23:01:40 UTC e suspendeu novas sondagens. Nenhuma promoção, AWS, SSH ou sessão
A6 foi invocada por essas chamadas. O erro identifica o estado do conector; não
permite afirmar que a VPS está indisponível ou que seus arquivos mudaram.

`ACCESS-INCIDENT.json` preserva o comando público da sondagem e os limites do
que foi observado. `RECOVERY-SOURCE-INDEX.json` fixa os fontes e evidências
disponíveis no cloud. Esses arquivos não restauram nem executam nada.

## Quando a coordenação liberar a retomada do mesmo controle normal

A autorização operacional já foi dada e persiste. A pausa atual é de sondagens
ao conector; não contorná-la trocando a rota ou reproduzindo comandos por outra
ferramenta. O registro `RESUME-CHECKPOINT.md` contém o estado mais recente; o
HANDOFF preservado é uma cópia histórica que antecede essa autorização.

1. Ler o estado local e os hashes, sem presumir ausência de recibo por causa de
   timeout. A versão esperada antes da promoção é A5: helper b6eb8f23 e preflight
   0ef4d06e. O promotor deve ser 3e56e68d e a candidata f8e3da74/d78ce810. A última
   prova A5 comprovada terminou com cleanup e plugin parado em
   2026-10-05T22:34:33.466124 UTC; isso é histórico, não uma nova inspeção do host.
2. Se existir `auth-a6-promotion-20261005.json`, reconciliar estado, targets,
   stages e backups. Não rodar o promotor outra vez por ausência de PID na
   resposta do controle. O journal pode estar atrasado em relação a um replace.
3. Com fontes e estado reconciliados, executar o promotor uma vez pelo caminho
   normal. Ler sua conclusão e readback exato. Depois executar preflight e um
   C0 Hub novo. Apenas se contexto/fontes/CURRENT, progresso e cleanup forem
   válidos, executar preflight fresco e uma A Hub usando esse C0. Encerrar e
   reconciliar todas as sessões conhecidas antes de interpretar o resultado.

Diretório de execução no Mac:

`/Users/rodrigosilva/dev/worktrees/chat2you/995-instagram-vps-runtime/tmp/approved-1023-20261005/aws`

Comandos já preparados, respeitando os gates acima:

```sh
/usr/bin/python3 promote-auth-a6.py
/usr/bin/python3 preflight-live-proofs.py --stack hub2you
/usr/bin/python3 probe-client-from-mac.py --stack hub2you --mode protocol-control
```

Após ler o C0 real e passar a preflight fresca, o último comando usará
`--mode auth-binding --c0-receipt` com o caminho exato retornado pelo C0 novo.
Nenhum caminho ou recibo A5 antigo deve ser substituído por um nome presumido.

O promotor altera só helper e preflight, com backups A5 e recibo exclusivo. Os
demais módulos devem manter hashes atuais. O provisionador `provision-identity.py`
528 continua sendo uma dependência da preflight; sua fonte não foi incluída
neste bundle cloud. As fontes/estado PKI estáveis precisam ser lidos do Mac
quando disponível; não reconstruir a CA, seriais, perfis ou estado de emissão
por memória, e não copiar privadas para este pacote.

A sequência não libera Aut, mudança IAM, requisição nova, compositor ou corte.
Todos os resultados A6 continuam observacionais até revisão contextualizada.
Nenhuma rota, guard, launcher ou mecanismo de enrollment deve ser alterado para
contornar a indisponibilidade. Leituras só permitem afirmar o que retornarem;
timeout não prova que um comando mutante deixou de executar.
