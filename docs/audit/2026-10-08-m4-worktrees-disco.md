# M4 — auditoria de disco e worktrees (08/10/2026)

Solicitação: verificar worktrees e branches que podem ser apagadas. Execução somente de leitura do conteúdo: nenhuma exclusão, commit, push, merge ou operação de produção. Referências Git atualizadas com `git fetch origin --prune`.

## Estado confirmado

- Nó local: M4. `df -h`: Data 460 GiB, 405 GiB usados, 2,4 GiB disponíveis, capacidade 100%.
- Chat2You: 30 worktrees registradas; 357 branches locais.
- 147 branches locais sem worktree associada são ancestrais de `origin/main`; 81 têm PR mergeado corroborado nos 600 PRs recentes consultados. Ausência nessa janela não significa ausência de PR. Excluir refs locais quase não libera espaço; nenhuma exclusão remota é recomendada neste bloco.
- 14 worktrees apresentam alterações rastreadas ou arquivos não rastreados; nove checkouts limpos não têm HEAD contido nas referências remotas consultadas. Não são candidatos à remoção integral neste levantamento.
- Soma `du -sk` das worktrees do Chat2You, excluindo sobreposição das worktrees filhas de `.claude` já incluídas no principal: aproximadamente 22,05 GiB. APFS, clones e hardlinks impedem prometer que esta soma será recuperada como espaço livre.

## Candidatos verificados

| Caminho | Espaço medido | Evidência e limite |
|---|---:|---|
| `/Users/rodrigosilva/dev/worktrees/chat2you-1135-coverage-current` | 338 MiB | Detached `372ca4eb`; ancestral de `origin/main`; zero alterações, ignorados, operações, locks, sparse checkout ou submodules. `lsof +D` sem referências observadas. Remoção futura por `git worktree remove`; revalidar imediatamente antes. |
| `/Users/rodrigosilva/dev/worktrees/chat2you-757-relacionamentos/.codex/relationships/tools/cache` | 1,09 GiB alocados | Cache de downloads Homebrew e Bootsnap, 142 arquivos tar.gz e 142 manifests reais, além do cache compilado; symlinks não somados outra vez. Nenhum uso aberto observado. Reinstalação/rebuild pode ser necessário. Não inclui ferramentas instaladas, evidências ou PostgreSQL do diretório irmão. |

Revisão independente por `r9_tecnica` confirmou a natureza dos candidatos. A soma aparente feita seguindo aliases do cache duplicou entradas; o valor adotado é `du -sk` sem seguir symlinks. Liberação real deve ser medida com `df` depois de qualquer limpeza futura.

## Preservar

- `agentes-ia-prd`, `funcoes-auditoria`, main e sessões ativas.
- Prévia54 e banco50/claro30, incluindo réplicas e runtimes no M2.
- `1143-tela-assuntos`: apesar do PR mergeado e checkout limpo, possui segredo local ignorado e artefato de CI em `tmp`, além de dependências/cache. A worktree inteira não passa na condição de preservar arquivos ignorados únicos.
- `chat2you-757-relacionamentos`: 3,76 GiB no total; contém evidências locais e PostgreSQL isolado. Apenas o cache acima foi classificado como reconstruível.
- Worktrees com PR aberto, commits apenas locais, alterações pendentes ou arquivos ignorados não classificados. Não inferir descarte a partir do nome, idade ou PR mergeado.

## Comandos e evidências

Comandos usados: `maccluster node`, `df -h`, `git worktree list --porcelain`, `git fetch origin --prune`, `git status --porcelain --untracked-files=all`, `git ls-files --others --ignored --exclude-standard`, `git for-each-ref --contains HEAD`, `git merge-base --is-ancestor HEAD origin/main`, `git rev-parse --git-path`, `du -sk`, `lsof -a -d cwd`, `lsof +D`, `gh pr list` somente leitura.

Inventários sanitizados no scratch local `.codex/preview/check55/disk-*.json` e `.txt`: metadados, tamanhos, nomes e contagens; nenhum conteúdo de segredo foi lido ou incluído.

## Outros projetos — descoberta limitada

O agente `registrar_decisoes` encontrou 137 marcadores Git fora do Chat2You: 64 raízes e 73 marcadores de worktree. A descoberta foi limitada aos layouts conhecidos, sem seguir symlinks nem percorrer dependências; não é contagem exaustiva do volume.

As cinco maiores raízes medidas incluem `estudio-hyperframes` (6,84 GiB) e `vector-api` (5,19 GiB). São projetos, não caches descartáveis. O primeiro contém 14.443 arquivos não rastreados e branch sem commit inicial; nenhum descarte recomendado. A maior worktree medida, `vector-api-predeploy-fixes` (370 MiB), tem ponteiro Git órfão para Downloads; pode guardar conteúdo sem histórico acessível. Deve ser preservada.

Nenhuma referência remota desses outros projetos foi atualizada: resultados de tracking podem estar desatualizados, e nenhum candidato deles foi liberado para exclusão. Inventário completo deste escopo em `.codex/preview/check55/disk-other-repos.json`.

## Snapshots e caches externos

O agente `r9_produto` mediu diretórios com 285 manifestos sob `/Users/Shared/maccluster-workspaces`: 43,33 GiB alocados estimados e 38,78 GiB aparentes. A contagem inclui fixtures de testes do laboratório MacCluster, não somente snapshots de projeto. Chat2You tem 75 diretórios de snapshot nesse levantamento, somando 29,82 GiB alocados estimados. Desses, 54 apontam para o HEAD da branch de Agentes, mas hashes de conteúdo variam; mesmo HEAD não significa cópia descartável.

A medição soma `lstat().st_blocks*512`, sem seguir symlinks. Clones/hardlinks/APFS podem compartilhar blocos; nenhuma dessas somas é promessa de espaço livre recuperável. A maior oportunidade de uma limpeza posterior está nesses snapshots; não há lote de exclusão aprovado nesta auditoria, pois runtimes, bancos locais e evidências precisam ser separados do código reconstruível. Prévia54 e banco50 permanecem expressamente protegidos.

Caches externos somam 2,97 GiB alocados estimados, principalmente binários do Playwright (2,21 GiB) e Playwright MCP (0,48 GiB). São reconstruíveis, mas podem sustentar sessões e prévias abertas; não foram classificados como imediatamente removíveis. Processos Node foram observados usando 15 diretórios de snapshots e cache Firebase. Nenhum processo foi interrompido.

Medição final `df -h` no Data: aproximadamente 3,0 GiB livres. A variação em relação aos 2,4 GiB iniciais ocorreu sem exclusão desta sessão e não pode ser atribuída à auditoria.

Inventário sanitizado: `.codex/preview/check55/disk-snapshots.json`. O relatório cobre os caminhos descritos; não é auditoria exaustiva do volume Data.

## Resultado

Candidatos concretos para primeira limpeza: worktree de cobertura (338 MiB) e cache isolado de ferramentas (1,09 GiB), aproximadamente 1,42 GiB medidos antes de efeitos de blocos compartilhados. 147 refs locais integradas podem ser removidas numa higiene Git separada, sem ganho significativo de disco. Nenhuma worktree, branch, cache ou snapshot foi excluído nesta tarefa. Revalidar os candidatos e sessões ativas imediatamente antes de uma futura execução.


## Redirecionamento do Rodrigo — limpeza em outra sessão

Rodrigo autorizou inicialmente remover snapshots antigos. A preparação confirmou63 manifestos iguais no M2/M4 e filtrou47 réplicas antigas de Agentes, preservando snapshots46/49/50/52/53/54 e qualquer runtime. Apenas o snapshot54 teve verificação efetiva dos hashes nas duas réplicas, com consistência confirmada. O lote não chegou a executar a verificação nem a exclusão: antes disso, Rodrigo determinou que a limpeza seria tratada em outro chat e pediu retomada imediata do redesign. Nenhum snapshot foi apagado, movido ou replicado nesta sessão. Os inventários preliminares não são um lote liberado para remoção.
