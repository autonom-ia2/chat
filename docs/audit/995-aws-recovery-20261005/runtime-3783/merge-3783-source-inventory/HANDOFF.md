# Fonte mergeada 3783: inventário preparado, pacote ainda pendente

A PR #1039 foi mergeada em 2026-10-05 às 23:18:33 UTC no SHA
`3783da330716bf92346e5b017a6a491fdb8f1377`, segundo o recibo da frente release e
a coordenação. O commit aprovado `c46cf166438b64626d45125450ec2ed4826915aa` é
um parent direto do merge. A data interna do commit, 23:09:25 UTC, pertence à
criação do grupo da fila e não substitui a hora de merge.

Este diretório contém somente evidência pública de fonte obtida pela API GitHub
e validação local cloud. Não contém tar, manifesto operacional, intent de
upgrade ou recibo de execução na VPS. Nenhum comando foi enviado ao Mac ou por
SSH nesta preparação. Nenhuma suíte foi repetida.

## Conferência da fonte

O seletor foi lido por AST do wrapper congelado `../upgrade/runtime-upgrade.py`,
SHA256 `8d619986a8f9f297da87b5c5ee3a9b3b945bb1306656901bacfa3a5ddf08a6b8`.
Foram percorridas as árvores Git exatas desde a raiz
`4959339843ca4428f730415debeee9d95769984d` até o subtree VPS
`591b43e432d5473a87cc998b03815a8615641eca`. Nenhuma resposta foi truncada.

O conjunto tem 41 arquivos: 32 mantêm blob Git, modo e tamanho exatos do
manifesto 499809; oito mudaram; `runtime/entrypoint.mjs` foi acrescentado; nenhum
foi removido. Para os 32 inalterados, o SHA256 provém do manifesto anterior
fixado pelo digest canônico
`42b5f482bf1d15bb1ee6a300921f01ff7be39399be6a6827eb441df0fe7e2d38`.
Para os nove novos ou modificados, os bytes vieram do endpoint Git blob e foram
revalidados tanto pelo SHA1 do objeto Git completo quanto por SHA256.

As alterações são somente helper, sete entrypoints e inclusão do helper no
installer. O compare entre c46 e o merge não contém qualquer caminho do pacote.
O installer e o packager declaram exatamente os mesmos oito scripts necessários.
Templates de unidades, env, package-lock, autorização do gateway e sockets
permanecem nos blobs anteriores.

| Referência | SHA256 |
| --- | --- |
| `source-inventory.json` | `25ee03c819e6289b8b197111f04992d337de00afc76dfe3ccd05f6ca02411ac5` |
| JSON canônico somente do membro `files` | `c5df697fbfdb884f6e728118efb75b32ac1cb3ea164d6c8a8941ec2560dafc8d` |

O inventário identifica explicitamente `operational_manifest=false`,
`archive_created=false`, checksum/tamanho do arquivo nulos e reconciliação Mac
pendente. Os arquivos auxiliares preservam a cadeia de árvores, a comparação
com o head aprovado e os bytes dos nove blobs. `build-source-inventory.py`
somente valida esses dados locais; não cria Git repository, tar ou manifesto de
deploy e não invoca o wrapper operacional.

A primeira validação documental usou indevidamente o caminho completo de repo
para localizar o helper no installer; ela abortou antes de gravar o inventário.
A fonte mostra que a tupla do installer usa caminhos relativos a
`scripts/instagram_testers/`. A validação foi corrigida para comparar as duas
tuplas por AST com esse prefixo explícito; a execução seguinte passou. Nenhuma
fonte de runtime foi alterada por esse ajuste no verificador documental.

## Dependência exata para gerar o pacote real

O Mac Terminal e Filesystem retornaram `Session terminated 32600`; a coordenação
suspendeu sondagens a partir de 23:01:40 UTC. O packager aprovado depende do Git
real dessa worktree e dos objetos do merge, do layout fixo e de `/usr/bin/git`.
Não foi adaptado nem executado em outro ambiente.

Quando a coordenação liberar novamente o caminho normal, reconciliar os hashes
dos executores e a existência dos objetos/artefatos antes da chamada. Um fetch
normal de origin, caso o objeto esteja ausente, não exige mudar branch/código.
Comando preparado, ainda não executado:

```sh
/usr/bin/python3 /Users/rodrigosilva/dev/worktrees/chat2you/995-instagram-vps-runtime/tmp/approved-1023-20261005/runtime/upgrade/runtime-upgrade.py package 3783da330716bf92346e5b017a6a491fdb8f1377
```

Os únicos artefatos esperados desse comando ficam no diretório `upgrade/`:
`runtime-3783da330716bf92346e5b017a6a491fdb8f1377.tar.gz` e
`manifest-3783da330716bf92346e5b017a6a491fdb8f1377.json`. Não existem como resultado
desta preparação. Ler o stdout integral e os artefatos reais, conferir o digest
canônico de `files` contra o inventário acima e entregar checksum/tamanho do tar
à coordenação. Stage/preflight/install/verify-inactive continuam fases separadas
e dependem da revisão do manifesto real, além da janela de quietude do n8n.

## Candidato display/gateway já preparado

O diretório cloud irmão
`../display-gateway-3783da330716bf92346e5b017a6a491fdb8f1377/` preserva o wrapper
aprovado e altera somente a constante SHA no remoto. Os originais continuam
intactos.

| Arquivo | SHA256 |
| --- | --- |
| wrapper idêntico | `ea58b75358dfb607fb70458a1de87601c94b7d3ee9f19ad51b50bd69c7251aae` |
| remoto com SHA novo | `22cc71edbeaa5c689177c541f91bd2163fa8799f3a3f8c1fe473140f346a4de1` |
| patch de uma linha | `08308c908fc3cfb197a6261d8e0701e641cbf42b96667e204abf257820a567e0` |

Revisão focal foi solicitada às frentes HTTPS e independente. A reconciliação
persistente no diretório novo do Mac permanece pendente. A aprovação do código
não substitui instalação/verify-inactive/verify-pair e autorização de start.
Publisher e manager não fazem parte dessa primeira ativação. Recibos e intents
da tentativa antiga permanecem preservados.
