# Publicação urgente do zoom do Kanban — #839 / #840

Preparação em 02/10/2026. Rodrigo autorizou o fechamento, merge e deploy nas duas stacks com “pode fazer”, após a apresentação dos três gates. Esta autorização não inclui movimentar dados reais de clientes.

## Escopo para aprovação

Lote urgente de um único PR, conforme a regra 10 de `docs/processo-de-release.md`: #840, commit `9b60773a7cdba194f4bcd8323bb4fa1117753b25`, sobre main `43901a40c2eb6ef43cf3e5052c297879e0abdbd4`. Não incluir outros PRs. Branch `release/2026-10-02-lote3`; os lotes 1 e 2 do dia já foram publicados. A listagem completa dos PRs abertos confirmou ausência de outro lote aberto; busca head:release/ isolada não foi usada como prova final.

O merge final na main publica nas duas stacks: Autonom.ia e Hub2You. #840 foi retargetada para o lote e integrada por squash em `879d1e818adbb26f8a50726df1b1d203d6269aae`. `git diff --exit-code 9b60773a7c HEAD` confirmou árvore idêntica. Nesta etapa não houve merge na main nem deploy.

## Evidências confirmadas

- PR OPEN, MERGEABLE/CLEAN; SHA e base inalterados; oito check runs SUCCESS. CI do SHA revisado: 7.423 testes de frontend aprovados.
- Zoom validado em Firefox, Safari real e WebKit; relatórios de revisão e navegador estão nesta pasta. Ressalva de importação de áudio no login Firefox, fora do diff, sem atribuição causal comprovada.
- Main posterior ao último deploy bem-sucedido `eda6f1f22fd5e90573f3cd6b10b06b10c9d0fe6b` só altera dois documentos. Nenhuma mudança adicional de produto na base.
- Ambos os últimos workflows de deploy terminaram com success nesse SHA; sem execução em curso nas listagens consultadas. Isso não substitui confirmação de aceite funcional do lote anterior.
- Endpoints públicos das duas stacks responderam HTTPS 302.
- Hub2You: runtime-image SSM aponta para imagem `eda6f1f22fd5e90573f3cd6b10b06b10c9d0fe6b`; instância atual `i-04c8e3b417cbe2533`, anterior `i-006f22e2f0182fc45`; target groups atual/anterior presentes nos parâmetros.
- Consulta AWS da Autonom.ia pelo perfil local default falhou com InvalidClientTokenId/UnrecognizedClientException. Não houve tentativa de alterar autenticação, solicitar credenciais ou substituir configuração. Último workflow Autonom.ia verde não comprova o estado atual da instância/rollback.
- O perfil existente financial foi identificado no registro versionado da publicação #800 e confirmou a conta Autonom.ia 140023375763. SSM confirmou imagem ativa eda6f1f22f; instância atual i-031d9fbcd7b197437 running e target healthy; anterior i-02520b7b7faf6417d stopped, target group anterior existente. Hub2You também confirmou instância atual running/healthy e anterior stopped. Nenhuma credencial foi alterada. O aceite do lote anterior consta da auditoria #835 e das capturas finais na main.
- Bateria de fechamento em execução na árvore integrada, na worktree de QA existente. Banco local novo chat2you_840_release_20261002 e Redis próprio 6840; sem base de produção nem inferência paga. Seleção Ruby canônica: 509 arquivos, caminhos fixos mais requests CRM, sem exclusões. Frontend: caminhos fixos mais CRM, store Kanban e Popover. Os resultados serão lidos antes do merge final e registrados na descrição do PR do lote.

## Gates antes do merge final

1. Aprovação explícita do Rodrigo para integrar/publicar exclusivamente #840 nas duas stacks.
2. Confirmar aceite do lote anterior e consultar estado atual/retorno da Autonom.ia por acesso autorizado; revalidar Hub2You imediatamente antes de publicar.
3. Criar lote de um PR a partir da main atual, integrar #840 e abrir/anexar PR do lote; não publicar diretamente na main. Preservar branches originais.
4. Rodar e ler a bateria de fechamento descrita na regra 2 do processo: RSpec nos caminhos fixos mais CRM; frontend fixo mais CRM, store e Popover; lint dos arquivos tocados; por último guia:build, guia:check e central:check. Checks do PR de feature não substituem essa bateria de lote. Se a árvore de produto mudar, repetir a verificação de navegador correspondente. Atualizar Issue/Project e registrar revisão do candidato final.
5. Revalidar SHA, checks, diff e ausência de outro deploy antes de um único merge commit para main.

## Após o merge autorizado

Acompanhar `deploy-autonomia-blue-green.yml` e `deploy-hub2you-blue-green.yml` até conclusão; confirmar imagem/revisão, web, workers, target healthy e HTTPS. No CRM, smoke com registros de teste autorizados: 70/87/130%, persistência ao recarregar, arraste entre etapas/última coluna, retorno de Lista/Calendário e painéis sem escala. Não movimentar dados reais de clientes. Fechar #839 e atualizar Project somente após entrega confirmada.

## Retorno em falha

O caminho existente é `workflow_dispatch` na main com `action=rollback` e `confirm_production=true`, no workflow da stack afetada; se o problema for comum ao lote, retornar ambas. Conferir imagem, workers, target healthy e HTTPS após o retorno. Existe só um degrau de rollback; não iniciar outra publicação até o aceite desta.

O rollback após o novo deploy deve retornar à versão ativa imediatamente antes dele, esperada `eda6f1f22fd5e90573f3cd6b10b06b10c9d0fe6b` e ainda sujeita à confirmação em ambas as stacks. Não confundir com a instância anterior hoje armazenada: os parâmetros são atualizados durante o novo deploy. A feature não altera banco, API nem configuração do produto; não há rollback de dados específico do zoom.
