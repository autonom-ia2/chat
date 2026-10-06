# #995 — publicação da correção de latência, 06/10/2026

## Problema e correção

O transporte do publicador tem orçamento global de 25 segundos. O fluxo sequencial de STS, CURRENT, abertura do túnel e obtenção da host key consumia esse orçamento antes de completar o bootstrap no ambiente observado.
A correção sobrepõe somente duas duplas independentes: STS/CURRENT e readiness do listener/host key. Ambas as validações de cada dupla precisam concluir antes da etapa seguinte. O prazo não é reiniciado e nenhuma validação de identidade é removida.

CURRENT pode ser lido pelo mesmo perfil explicitamente autorizado antes de STS terminar. Nenhum túnel, comando de host key ou SSH é liberado antes da validação conjunta. Falha/cancelamento interrompe os ramos e preserva o erro público existente.

## Evidência anterior preservada

O recibo operacional `finalize-20261006/hub-overlap2-candidate.result.json`, concluído em 06/10 às 16:54:10 UTC, registra version 18.333 ms, operator_read 19.832 ms e bootstrap 21.719 ms, todos sob 25.000 ms. O candidato foi usado em diagnóstico sem alterar fontes instaladas; não se trata de aceite Meta ou renovações.
SHA256 do publisher revisado: `36285be4f9df954046a1e7813bd74f4ec65e5316a7fb3a1111beb141bba293b7`.

## Integração

A PR #1065 passa a incluir código do publicador, ajustes de expectativa de cancelamento e `tests/instagram_testers/publisher-concurrency.test.mjs`. O workflow Instagram inclui explicitamente esse teste na execução e no ESLint. Não altera o workflow de deploy, IAM, payloads, Redis ou configuração global.
A bateria local integrada passou 150/150, sem falhas, cancelamentos ou skips. Após ajustes de estilo exclusivamente no teste, a bateria passou novamente 150/150; ESLint, sintaxe dos quatro arquivos e diff check também passaram. Revisão independente da integração aprovou o código, ressalvando a inclusão efetiva do novo arquivo no commit.

## Implantação e aceite

O runtime VPS precisa de nova release imutável contendo a correção. Não sobrescrever a 3783 instalada nem usar o instalador original com unidades ativas. Usar upgrade focal revisado, com parada/retomada apenas das unidades Instagram, preservando Node privado, perfis, chaves e demais serviços.
Após a atualização, revalidar CURRENT/SHA efetivos, concluir prova tipada, coletar B0 real e iniciar produtores por stack. Login/2FA e renovações reais continuam necessários antes de habilitar o assistido. Nenhum teste ou diagnóstico desta PR substitui esses eventos.
Rollback: parar os produtores da própria stack, preservar dados e restaurar o link da release anterior com unidades inativas e hashes conferidos; retomar apenas display/gateway previamente ativos. Não reativar gestores dos Macs nem restaurar sessão/Redis para esconder falha.
