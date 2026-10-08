# Instagram assistido: rejeição de perfis válidos no backend

Issue: #995. Branch: `codex/995-browser-result-publication`. Base: `61f20cfd107361a431fda51f02cace751cc4978d`.

## Evidência e causa

No piloto autorizado da Hub2You, o manager registrou duas conclusões correlacionadas sem erro do executor às 08:31:42 e 08:32:44 UTC. O backend gravou ambas como `failed/meta_unavailable`, sem resultado armazenado. A fila ficou vazia e nenhuma caixa de entrada foi criada. Um único clique do operador foi enviado; a origem da segunda operação não foi comprovada. O frontend revisado não contém retry automático de busca. Nenhum convite, OAuth ou DM foi iniciado pelo operador.

Há um defeito determinístico em `BrowserOperations#materialize_candidate`: `candidate.keys.sort` era comparado com `%w[id username name avatar_url]`, uma constante não ordenada. Portanto, qualquer candidato com os quatro campos oficiais era rejeitado. O parser real produz exatamente esses campos e o SessionPublisher já usa a ordem canônica.

A mudança única ordena a constante para `%w[avatar_url id name username]`. Permanecem as validações do conjunto exato, ID, username, nome, avatar seguro e duplicidade. Nenhuma permissão, gate, retry, prazo ou fluxo de convite foi ampliado. Não há implementação Instagram correspondente no overlay Enterprise.

## Verificação local

- Reprodução Ruby antes da mudança: candidato válido rejeitado; constante não ordenada.
- `ruby .codex/validate-search-candidate-contract.rb`: PASS. Carrega parser, Validation e BrowserOperations reais, sem Rails, banco ou rede. Perfil sintético aceito; campos ausentes/extras, ID inválido, nome inválido e avatar HTTP rejeitados. Não cria specs no repositório.
- `ruby -c app/services/instagram/testers/browser_operations.rb`: Syntax OK.
- `git diff --check`: PASS.
- `maccluster work plan -- ruby .codex/validate-search-candidate-contract.rb`: nenhum nó elegível (M2 sem cwd; M4 abaixo do piso genérico de disco). A verificação mínima, sem dependências e sem Rails, foi executada explicitamente no M4; não houve alteração de recursos, serviços ou banco.
- Revisão independente Nexo: aprovado, sem bloqueio concreto. Iris confirmou o defeito por reprodução independente.

Essas verificações comprovam o contrato local, não a conexão em produção. O próximo piloto precisa confirmar busca aceita pelo Rails e continuidade até a caixa de entrada.

## Publicação e reversão

Rodrigo autorizou a continuidade da recuperação, incluindo merge/deploy e piloto delimitado; a última instrução foi resolver o problema. Root permanece o único executor de produção. O piloto anterior foi desativado no manager; SSM Hub restaurado de 14 para 15 (flag ausente), e o deploy normal de desativação 37750841459 está em andamento. Autonom.ia permanece fora das operações de navegador.

Seguir fila normal, CI obrigatório e merge real. Os deploys AWS automáticos devem terminar e ter saúde conferida antes de ativar novamente apenas a Hub2You. Os scripts VPS não mudam neste PR; manter a instalação verificada em 61f20cfd e registrar sua equivalência de conteúdo com o novo merge. Reversão: desativar manager, restaurar apenas a linha SSM e usar deploy blue-green normal. Não utilizar a ação legada de rollback nem reiniciar diretamente web/worker.

## Simulação na imagem ativa de produção

Em 08/10/2026, o runner isolado na VPS n8n terminou com exit 0. A imagem OCI ativa de produção foi fixada pelo digest do container, com somente a correção de uma linha montada em modo leitura. Rails production, Postgres/Redis descartáveis e Redis de coordenação com TLS verificado exercitaram os serviços e a API autenticada reais.

A constante antiga reproduziu `failed/meta_unavailable`; a corrigida produziu `ready`, seleção assinada válida, busca/status/autorização/reautorização pela API e resultado recuperado após recriar o cliente Redis. Dados malformados, campos extras, claim incorreto, deadline vencido e outro ator foram rejeitados. A limpeza e os oito serviços permanentes foram conferidos.

O provedor foi sintético, sem egress; reconexão real com Meta ainda não foi validada. Postgres sandbox 18.6 difere da minor RDS 18.3. O recibo sanitizado, hashes e limites estão em [995-pr1139-production-image-simulation-20261008.json](995-pr1139-production-image-simulation-20261008.json).
