# Recuperação assistida Instagram — continuação Codex em 07/10/2026

Retomada no M4, worktree `995-meta-page-bootstrap`, branch
`fix/995-meta-page-bootstrap`, head inicial
`8ae330bf1b61db5ec8fc8ecd8b5c80350efce037`, issue #995 e PR draft #1112.
Leitura feita na ordem AGENTS → handoff → manifesto. A continuidade não
reinstala #1089 nem incorpora os seis deltas experimentais antigos.

## Responsabilidades e limites

- Coordenador: único executor de VPS/AWS e responsável por Git/Project.
- Iris (`/root/iris_captura`): diagnóstico inicial e contrato de captura.
- Atlas (`/root/atlas_transporte`): medição de fases do transporte.
- Nexo (`/root/nexo_revisao`): revisão independente, sem mutações.

Os subagentes são processos desta execução, distintos dos revisores históricos.
Nenhum deles recebeu execução de produção. O diagnóstico usa os usuários,
grupos, ENV e Node privado existentes, sem imprimir ENV/payload/credenciais.
Não há publicação, heartbeat, replay, login novo ou alteração do assistido.

## Estado vivo confirmado

`/opt/instagram-meta/current` continua em `9a48a2d…`. Os sete serviços
informados no handoff mantêm os PIDs anteriores, ativos e NRestarts=0.
Manager Autonomia permanece inativo, sem marker humano, lock de gestor,
SingletonLock ou Chrome concorrente. Todas as units continuam desabilitadas
para boot. Publisher CPUQuota=200%, manager=150%; não foram alteradas.
O cgroup publisher Autonomia tinha apenas 12.407 microssegundos cumulativos
de throttling; isso não demonstra que quota de CPU cause a latência.

Os seis arquivos antigos foram relidos por SHA-256: 6/6 iguais ao manifesto.
Nenhum arquivo daquela worktree foi editado, copiado para a release ou apagado.
O Project #3 recebeu os sete campos em #995/#1112, com readback exato salvo
no manifesto desta rodada. Uma listagem ampla retornou limite GraphQL;
a consulta mínima paginada e a leitura dos dois itens funcionaram. Isso não
é queda da VPS nem motivo para mudar autenticação.

## Medição real do transporte

Uma chamada `session/bootstrap`, sem gravação, executada como
`igpub-autonomia` em unit transitória com as restrições do publisher existente.
Fonte instalada importada pelo diagnóstico; orçamento de 25 s preservado.
Unit `instagram-autonomia-transport-20261007-105230`: encerrada,
MainPID=0, Result=success e ExecMainStatus=0.

| Fase | Duração |
| --- | ---: |
| STS | 2.365 s |
| CURRENT, em paralelo com STS | 2.386 s |
| Túnel disponível | 3.915 s |
| Obtenção da chave, paralela ao túnel | 5.247 s |
| SSH + wrapper remoto + boot Rails + bootstrap | 15.587 s |
| Operação total | 23.276 s |

O maior custo está no bloco remoto. Não é ainda medição isolada do boot
Rails ou da execução. Não foi introduzido cache, retry, conexão permanente,
ampliação de deadline ou aumento de CPU. O diagnóstico anterior ao parecer
Nexo foi executado com revisão direta do coordenador e a fonte exata
`d6e3ce827e598c26f34e10e31801d778528cdb8518a248660cfa19239256aff5`.
Ele terminou normalmente antes do limite; os ajustes posteriores do wrapper
não reescrevem esse recibo.

## Diagnóstico inicial: revisão e execução

O candidato foi corrigido para deadline total de 90 s, resposta classificada
antes da leitura, teto de 2 MiB verificado antes/depois da leitura quando
o servidor informa tamanho, espera limitada de resposta, drenagem e fechamento.
Sem Content-Length, Playwright ainda faz buffering antes da verificação:
o limite de memória da unit limita a execução, não é streaming do corpo.
IDs/cookies/body não são registrados; somente nomes públicos seguros,
campos estruturais, status, tempos e comparações booleanas.

Nexo exigiu SHA/caminho revisados no executor, stage exclusivo, parada de
35 s, proteção contra falha de cleanup tardio e resposta não JSON considerada
incompleta. Esses pontos foram corrigidos. Node syntax check passou.
O wrapper usa RuntimeMaxSec=125, KillMode=control-group, sandbox/proxy
e identidade originais. Não muda units permanentes.

Execução única iniciada em `instagram-autonomia-browser-20261007-105544`,
com SHA `0d2ee4bc0cea5280aa51121aad9e35201aa430196cf72d2af0ef83679ccfcfda`.
Resultado recebido em 10:56:31 UTC: consulta inicial HTTP 200, sem erros,
`fetch__Application.id` correspondente, sem papéis. Cinco novas consultas
foram bloqueadas: MetaDeveloperAssistantPageOverlayQuery,
DeveloperHeaderComponentContainerQuery, DeveloperAppVisibilityToggleLazyLoadedQuery,
DeveloperAppBannerQuery e DeveloperAppDashboardSidebarNavigationV2Query.
RolesTable não apareceu na janela registrada. O diagnóstico retornou exit 1
na fase observation antes do DOM; a espera Playwright de 15 s estava envolvida
por timeout também de 15 s, portanto o limite não comprova fechamento da
página. A resposta e o encerramento foram observados: browser_closed=true,
lock_released=true; postcheck confirmou PID0, locks/marker ausentes.
Nenhuma sessão foi publicada. Próximo passo: documentos compilados e
argumentos dessas cinco consultas em lote, sem liberar GraphQL pelo nome.

## Avanço comprovado nesta continuação

A observação batch das cinco queries terminou em 11:02:50 UTC: cinco
observações únicas, zero truncamento, documentos compilados query e hashes
correspondentes, identidades naturais válidas. Requests permaneceram bloqueados.
O coletor apresentou nomes de argumentos compilados como booleanos por um
defeito de saída; os nomes/shape naturais foram registrados corretamente.
Não reescrever esse recibo como prova de nomes compilados.

A execução seguinte, `instagram-autonomia-browser-20261007-110725`, permitiu
a inicial e quatro documentos fixados. A Overlay ficou bloqueada.
Em 11:08:09 UTC o recibo confirmou RolesTable natural, HTTP200,
`get_app_roles` e `roles_valid=true`; DOM com título de papéis e sem ação de
login/campo de senha. Browser fechado e lock liberado. O diagnóstico
retornou exit1 por resposta de cabeçalho não JSON; não esconder o erro
como sucesso integral. Isso não invalida a resposta de papéis registrada.
A implementação não deve capturar nem interpretar respostas de carregamento.

Destino Rails revalidado por STS/CURRENT/tags e SHA do container:
`7aaa19ce04dec6aef3310ec4b4e77b76d7c00d01`. Três medições bootstrap
somente leitura, por SSM com watchdog interno45s e execução60s, sem mudar app:

| Processo Ruby | Boot Rails | Bootstrap no executor |
| --- | ---: | ---: |
| Atual | 9.958 s | 7.468 ms |
| Candidato, eager load desligado somente nesse processo | 5.210 s | 23.271 ms |
| Controle atual depois do candidato | 10.172 s | 7.340 ms |

O controle posterior limita a hipótese de que só aquecer o processo/cache
tenha produzido a melhoria. Ainda é bootstrap de diagnóstico, não transporte
completo da correção instalada ou teste de publicação. Não altera ENV,
configuração web, quota, TTL ou protocolo. Patches de carregamento/boot foram implementados na mesma PR, com
publicação ainda pendente. A revisão independente identificou que os testes
novos só rejeitavam documentos inválidos; faltava positivo real. Para fechar
a lacuna, um coletor revisado observou somente os cinco identificadores
públicos que já passavam pelos hashes/identidades/variáveis aprovados. Não
leu respostas/cookies/config pessoal. Recibo de 11:16:18 UTC com cinco
hashes validados, browser fechado, lock liberado e nenhuma publicação.
O agregado diagnostic_ok=false é esperado porque o listener de respostas
foi deliberadamente removido; não equivale a falha da coleta do fixture.
Os IDs públicos dos documentos servem somente ao fixture de contrato;
identidades e autenticação dos testes continuam sintéticas.

## Validação final antes da liberação

Nexo aprovou a implementação, os positivos dos cinco pins, as rejeições
isoladas, o route handler real, publicação única por Roles e o plano de rollback.
Prettier 3.3.3 formatou os dois testes; código funcional não mudou nessa etapa.
O título do teste foi corrigido para representar a permissão de carregamento.

O planner excluiu o checkout M4 por disco e M2 por cwd inexistente. Foi criado
snapshot isolado com duas réplicas verificadas por checksum; nenhum checkout
ativo foi copiado/sobrescrito. A execução foi agendada no M2 pelo MacCluster.
Primeira rodada: 234/240 aprovados, seis casos de gateway/entrypoint falharam
por `ERR_MODULE_NOT_FOUND: ws`. A preparação geral do workspace recusou um
symlink rastreado preexistente em mockups; não foi forçada nem alterada essa
fonte. O executor preparou apenas as seis dependências locked do VPS nesse
snapshot (`npm ci --ignore-scripts --no-fund --no-audit`), sem downloads de
Chrome ou alterações de runtime/banco. Reexecução: 240/240 aprovados, zero
falhas/skips/cancelamentos, oito arquivos de contrato/lifecycle/transporte/stdio.

Source funcional e fixture têm os mesmos hashes no snapshot e worktree.
Depois da captura do snapshot houve somente formatação e título dos testes;
o CI do novo head deve validar seus bytes finais antes da liberação. Syntax
Node/Ruby e diff check passaram. ESLint completo fica no CI que instala as
dependências locked. O manifesto registra comando, snapshot, SHA e limites.

Plano concreto revisado: `995-release-plan-20261007.md`. Inclui os dois deploys
AWS automáticos disparados pelo merge, janela apenas dos serviços Instagram
VPS, quotas do template medidas antes da consolidação, duas renovações naturais,
reinício controlado das units e reversões AWS/VPS separadas.

## Aceite permanece pendente

Sem recibo de sessão registrada, duas renovações naturais, persistência
após reinício ou conexão/teste de canal no painel. Autonomia primeiro;
Hub2You requer homologação separada. Nenhum merge/deploy ocorreu nesta rodada.
Rollback da release continua o do handoff: preservar perfis/chaves/metadata,
drenar somente units Instagram e restaurar a release anterior comprovada.

Evidência sanitizada: `995-codex-recovery-evidence-20261007.json`.
