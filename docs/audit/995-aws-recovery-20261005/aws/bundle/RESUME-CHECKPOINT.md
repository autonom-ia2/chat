# Estado de retomada A6 — 5 de outubro de 2026

## Decisão vigente

Root autorizou a promoção exata A6 e, depois de seus gates, um C0 Hub novo e
uma coleta A Hub. Os pareceres finais estão fechados. Nenhuma dessas três
operações foi invocada: o conector Mac falhou nas leituras anteriores à
promoção. Root suspendeu novas sondagens após observar `Session terminated`,
`INVALID_ARGUMENT`, JSON-RPC 32600 às 23:01:40 UTC.

A autorização persiste. A próxima condição é a retomada coordenada do mesmo
controle normal e a reconciliação somente leitura. Não há pedido de nova
permissão ao usuário nem autorização para trocar rota ou controles.

## O que foi comprovado

- A5 foi promovida por PID 54154, exit 0; recibo preservado no pacote.
- C0 A5 Hub: PID 54810, exit 0; progresso parcial do protocolo próprio;
  cleanup conclusivo às 22:33:08.147557 UTC.
- A5 Hub: PID 55573, exit 0; fechamento inválido de 175 bytes lido integralmente,
  código 1003 e UTF-8 válido; motivo permaneceu desconhecido na projeção.
  Controle próprio original completou túnel/banner; plugin parou. As duas
  sessões conhecidas foram explicitamente terminadas, com cleanup conclusivo
  às 22:34:33.466124 UTC. `foreign_access_classified` e `cutover_eligible`
  continuam falsos.
- A6 local: oito fixtures finais passaram no cloud e no Mac; PID Mac 63047,
  exit 0. Parecer da projeção: SHA-256
  `9ae3ae73d29de8e71523319ca02c8ce533c7f57bda67da96893fe5ee5965252d`.
  Parecer do promotor: SHA-256
  `a6f80fb6f88210b4344a3abc6970ac5c82208df057f9005f92ab919a6ae133a8`.
- Após a A5, esta frente não invocou nova promoção, AWS, SSH ou sessão.
  As três chamadas registradas no incidente eram somente leitura; nenhuma
  devolveu PID ou conteúdo. A última quietude é histórica, não uma inspeção
  atual da VPS durante a falha do conector.

## Bytes autorizados

| Arquivo | SHA-256 da candidata A6 |
| --- | --- |
| `ssm_close_diagnostic.py` | `f8e3da749b14e3427a61f84af927bbb736a372e6b5a1549dc7c2c6806e31d5f0` |
| `preflight-live-proofs.py` | `d78ce8102641d8327fe27e532954c65bc415ed9c729f3c43c73e766ebb75aea8` |
| `promote-auth-a6.py` | `3e56e68df186e26fd03c0ed80251ea217251608e0c309208f2fcfdccb1872643` |

O helper ativo esperado antes da promoção é b6eb8f23 e o preflight é 0ef4d06e.
Collector 161ba3c6, wrapper e299c0e5, serviço d878ffe4, parser 49866b1c e
provisionador 5280a18b permanecem inalterados. Os hashes completos e o mapa
dos nomes candidatos constam em `PREPARED.json` e no índice de fontes.

## Sequência pendente

1. Respeitar a suspensão de sondagens; quando a coordenação retomar o acesso,
   ler fontes, recibo de promoção, stages e backups pelo controle normal.
   Nenhum timeout anterior comprova ausência de arquivos. Se houver estado
   parcial ou divergente, reconciliar antes de qualquer nova execução.
2. Com os hashes anteriores e candidatos exatos, janela sem writers e ausência
   reconciliada de promoção anterior, executar o promotor uma vez. Ler seu
   recibo e todos os targets. A troca de dois arquivos não é uma transação
   única; o journal pode estar atrasado em relação a um replace interrompido.
3. Executar preflight Hub e um C0 novo. Somente com fontes/CURRENT iguais,
   frescor, progresso parcial observado e cleanup conclusivo, executar
   preflight fresca e uma A Hub vinculada àquele recibo C0 real.
4. Registrar resultado e terminar todas as sessões conhecidas; reconciliar
   qualquer ambiguidade antes de interpretar. Parar para interpretação após
   essa única A6. Não há Aut, novo retry, IAM, compositor ou cutover implícitos.

## Dependências que permanecem no Mac

O pacote é uma recuperação dos fontes e evidências públicas do diagnóstico
A5/A6; não é um backup operacional completo de IAM/PKI. O fonte do provisionador
`provision-identity.py` SHA-256
`5280a18bc67ee5c2be881591415e1971fd0cc458d057ab06f01dfa49bedf7273`
não está disponível nesta cópia cloud. A preflight e o wrapper dependem dele.

Fontes e estado de emissão da CA estão no caminho persistente
`/Users/rodrigosilva/dev/chat2you/.codex/instagram-vps-pki/`; a privada está
somente no Keychain. Não reconstruir CA, índices, seriais, perfis ou estado a
partir deste relato. Não substituir o helper/ACL. Privadas de clientes, SSH e
configurações sensíveis continuam na VPS, fora deste pacote.

O HANDOFF incluído é uma cópia histórica exata, anterior à autorização A6.
Se ele disser que a autorização ainda falta, prevalece este checkpoint e a
mensagem posterior do root; o documento antigo não foi reescrito.
