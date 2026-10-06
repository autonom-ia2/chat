# Plano ampliado de snapshot frio — fontes operacionais públicas

Revisão 2, 05/10/2026. Amplia o conjunto inicial HTTPS/B0/discovery com os
conjuntos finais confirmados pelos donos. O mapa completo está em
`recovery-source-allowlist-v2.json`; os documentos da revisão 1 foram preservados.

**O trabalho executado aqui foi inventário, leitura de planos/contratos e cálculo
de hashes. Não houve cópia de fontes para um snapshot, integração ao Git,
refatoração, novo teste ou chamada operacional.**

O fechamento mínimo é um snapshot frio dos bytes públicos e sua restauração no
layout original. Não depende de redesign de imports, separação nova de estado
ou uma bateria adicional. A execução real dos programas continua subordinada
aos gates já existentes e à reconciliação de qualquer estado persistente.

## Allowlist final desta revisão

| Conjunto | Entradas obrigatórias | Opcionais | Delimitação |
| --- | ---: | ---: | --- |
| HTTPS, B0 V2, discovery e reader fe0 | 21 | 2 | Conjunto inicial preservado; os opcionais são recibos públicos dos 24/28 testes offline, não harnesses. |
| Upgrade | 7 | 0 | Dois executores, dois testes, PLAN, REPIN-NOTES e manifesto público anterior 499809. |
| Overlay | 7 | 0 | Candidato, três testes, OVERLAY-HANDOFF, helper vps-env e env-plan público. |
| Cutover Mac corrigido | 6 | 1 | Executor, dois helpers, contrato público, fixture e PLAN; patch público opcional. |
| Produtores | 6 | 0 | Wrapper/remoto, dois testes, PLAN e reader DG histórico 4a1f. |
| Supervisão | 4 | 0 | Wrapper/remoto, fixture e PLAN. |
| **Total** | **51** | **3** | **54 arquivos nomeados, sem glob ou cópia recursiva.** |

Os paths exatos, SHA-256 completos, tamanhos, modos e mapeamentos estão no JSON.
A lista inicial foi observada às 22:17:24 UTC; a extensão às 22:25:06 UTC.
Processos locais 44576 e 49022 terminaram com exit 0. A inspeção seletiva do
schema público do env-plan terminou com PID 48555, exit 0.

## Conjuntos adicionais e referências fixas

### Upgrade

Diretório `runtime/upgrade/`:

- `runtime-upgrade.py` — 8d619986…
- `remote-runtime-upgrade.py` — 29dd56d0…
- `test_upgrade_package.py`, `test_upgrade_rollback.py`
- `PLAN.md`, `REPIN-NOTES.md`

Dependência obrigatória fora desse diretório:

`runtime/manifest-4998091221c2a60ab8e7e6ee3316a6ceb0c0a0bc.json`.

Seu hash dos bytes é
`6693e7a137371b54776be9f4c7c3e2fa265b79cd74c69fb06ca749b4798c3ab8`;
o hash JSON canônico conferido e exigido pelo wrapper é
`42b5f482bf1d15bb1ee6a300921f01ff7be39399be6a6827eb441df0fe7e2d38`.
São representações diferentes do mesmo manifesto, não uma divergência.

Manter o manifesto no pai de upgrade e a profundidade de
`REPO = BASE.parents[3]`. O código e templates runtime já versionados são
recuperados pelos commits Git aprovados; nenhum tar/node_modules foi incluído.
Não inventar manifesto ou SHA de release futura.

### Overlay

Diretório `runtime/env-provision/overlay-candidate/`:

- `overlay-env-deploy.py` — 32ecd57e…
- `test_overlay_regression.py`, `test_overlay_target.py`,
  `test_overlay_transport.py`
- `OVERLAY-HANDOFF.md`

Dependências no pai:

- `runtime/env-provision/vps-env.py` — 8ebfc080…
- `runtime/env-provision/env-plan.json` — 7b91a91f…

O root confirmou o candidato 32ecd57e como escritor final do overlay. O helper
permanece em `../vps-env.py`. O plano público é a entrada `--plan`: contém
somente source_sha, stacks, origens, URL privada, host/porta e modo de proxy,
além de referências de evidência. O schema foi confrontado com
`validate_plan` sem executar o executor ou emitir valores privados. Signing
keys são obtidas pela operação autorizada na VPS e não fazem parte desse plano.

O plano público é uma entrada de configuração histórica, não uma confirmação
fresca da origem, versão SSM ou prontidão. A restauração deve manter essa
distinção; os gates do executor fazem a revalidação operacional.

`env-deploy.py` f960e630 e o README anterior pertencem ao alvo principal antigo
e não foram incluídos como executor/plano final do overlay. Os backups privados,
os planos reais de 19:06 e todos os intents/resultados operacionais ficam fora
da allowlist de fontes. Nenhum desses arquivos foi aberto por esta ampliação.

### Leitor Mac corrigido e contrato

Manter `release/cutover-mac-argv/` como irmão de `release/cutover/`:

- `publisher_cutover.py` — 8e9d82a3…
- `remote_current.py` — 5b44223a…
- `vps_read_proof.py` — 9ba3f3df…
- `mac-cutover-contract.json` — 865170ae…
- `test_mac_argv_contract.py` e `PLAN.md`
- `mac-argv.patch` — opcional, para preservar o delta público revisado.

O teste usa o original fe0 por `../cutover/publisher_cutover.py`; esse original
já está no conjunto B0/discovery e será preservado uma vez só. O candidato
corrigido usa seu contrato e helpers irmãos e mantém a profundidade
`BASE.parents[3]`. Não movemos journals entre os dois diretórios.

PREPARED, SYNC e MAC-FIXTURES são recibos de preparação/sincronização/testes,
não dependências das fontes; ficaram excluídos desta extensão mínima.

### Produtores e supervisão

Em `runtime/producers/`: `producers.py` 9337014d…,
`producers-remote.py` 3d5dbc3d…, `test_producers.py`,
`test_producers_b0.py` e `PLAN.md`.

Em `runtime/supervision/`: `observe.py` bdd3df21…,
`observe-remote.py` 13aed038…, `test_observe.py` e `PLAN.md`.

Preservar suas dependências já incluídas: cutover-mac-argv com helpers/contrato,
checker B0 V2 e o arquivo histórico
`runtime/display-gateway/display-gateway-remote.py` 4a1f436b….
Este último é carregado como **reader auxiliar**, com SHA/STACK ajustados em
memória pelo consumidor; não representa o novo executor de ativação DG.
Não executar `main/start/stop` desse histórico para substituir o gate novo.

Supervisão importa o producer pelo pin final e mantém o vínculo dos recibos de
start/corte/B0. O snapshot não inventa esses recibos nem atesta publicação,
continuidade do browser ou Meta.

## Pendências explícitas, fora do congelamento

- **AWS A5:** aguarda lista e fontes finais da frente AWS/root. Não foi feito
  inventário dos privados, estado da CA, credenciais ou arquivos dessa frente.
- **DG para a próxima release:** aguarda SHA realmente mergeado e candidato de
  repin. Não há path/SHA futuro fabricado. O reader 4a1f incluído como
  dependência de producers não altera essa pendência.

Essas pendências não exigem transformar o snapshot frio dos conjuntos finais
em uma refatoração. O root pode preservar o subconjunto fechado e acrescentar
outros conjuntos depois, sempre com mapa de hashes distinto e explícito.

## Restauração no layout original

A raiz original é
`/Users/rodrigosilva/dev/worktrees/chat2you/995-instagram-vps-runtime`.

O JSON mapeia um futuro `sources/<path>` para
`tmp/approved-1023-20261005/<path>` sob essa raiz. O prefixo de snapshot é uma
proposta de layout interno, ainda não criado. Preservar bytes, caminhos,
parentesco entre diretórios e modos registrados; o Git sozinho não conserva
todos os bits de modo.

Antes de montar o futuro snapshot, comparar os arquivos nomeados com seus
hashes. Se uma fonte mudar, explicar e atualizar somente sua entrada revisada.
Não usar cópia ampla de diretórios. Na restauração, reconciliar arquivos já
existentes e o estado da operação; não sobrescrever intents, journals ou backups
para permitir repetição. Restaurar fonte não dispara sua execução.

Nenhum estado privado entra no pacote. Os backups Serve/overlay, as versões
anteriores necessárias a rollback e as pendências administrativas continuam
exigindo preservação operacional própria. Não alterar aqui a restrição de
Serve a `/tmp/instagram-serve_*.json`, a ACL de Keychain, os imports ou os
diretórios de escrita dos executores.

## Limites preservados

Os limites da revisão inicial continuam: resultados JSON não viram harnesses
executáveis, preparation não vira B0, saúde de processo não vira publicação,
e fonte restaurada não autoriza start/Serve/auth/cutover.

A cláusula histórica de grupo nominal em AUTH_PLAN não cria requisito novo:
a decisão vigente autoriza HTTPS privado na Tailnet existente com JWT
SuperAdmin. O original permanece preservado até a consolidação documental
coordenada. Nenhuma suíte foi repetida para produzir este inventário.
