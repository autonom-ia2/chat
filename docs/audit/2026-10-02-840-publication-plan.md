# Publicação urgente do zoom do Kanban — #839 / #840

**Publicação concluída nas duas stacks.** Release `ab84a219bdd30f287ed0011ed61d62ec43f1fab4`: deploys oficiais completed/success, revisão de web/worker, saúde e assets confirmados. Sem rollback. Conferência autenticada da interface em produção não executada; cobertura de navegador real local e limites detalhados abaixo.

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

## Resultado local de fechamento

Lote #847, HEAD `341e267a2b85a4126198877f3e27092cb7241e15`; os três relatórios acrescentados depois do squash são documentação. Diff de app, enterprise, config, db, dependências, tests, workflows, scripts e lib contra `9b60773a7c` permanece vazio.

- `bash .codex/840-release/run-rspec.sh`: 509 arquivos, 5.497 exemplos, zero falhas, zero erros fora de exemplo, 15 pending existentes; 12 quarentenas e três avaliações pagas desativadas. Banco local novo, seleção completa e ordem canônica, sem excluir exemplos. Saída JSON e linha final lidas; exit 0.
- `pnpm test` com a união de caminhos fixos, CRM, store crmKanban e Popover: 165 arquivos, 1.889 testes passando, zero falhas; exit 0, TZ=UTC.
- `.github/scripts/email-protection-eslint.mjs` nos nove arquivos JS/Vue tocados: zero achados bloqueantes, dois avisos permitidos de chaves dinâmicas; exit 0.
- `pnpm i18n:fork:check`: nove catálogos, 16.744 mensagens compiladas, chaves e parâmetros en/pt_BR cobertos.
- Após a conclusão de Ruby e frontend: `pnpm guia:build`, `pnpm guia:check`, `pnpm central:check`, todos concluídos; 174 fluxos, 171 telas, zero sem explicação; 175 artigos na Central. Avisos de referências legadas registrados na saída; nenhuma alteração nos gerados ou no produto.
- Project Autonom.ia Dev (usuário autonom-ia, número 3): Issue #839, PR #840 e lote #847 incluídos/atualizados com Projeto Hub2You, Status Em review, Tipo Feature, Prioridade P2, Risco Médio, Ambiente Produção e próxima ação de fechamento/publicação já autorizada. O retorno GraphQL da organização não era esse Project; nenhuma alteração foi feita nos projetos jarvis/untitled.

CI final remoto `37034044222` concluído com success no SHA exato acima, saída lida antes de merge: 652 arquivos/7.423 testes frontend aprovados; 1.063 exemplos Ruby/zero falhas/dois pending legados; contratos puros sem falhas ou erros; lint sem bloqueios; build e 215 verificações de navegador/zero falhas aprovados. Traduções e Guia/Central verdes, incluindo a última execução Guia `37034893150` no mesmo HEAD. Oito check runs SUCCESS e PR MERGEABLE/CLEAN antes de publicar.

## Merge autorizado

PR #847 mergeada com merge commit `ab84a219bdd30f287ed0011ed61d62ec43f1fab4` às 16:41:32 UTC de 02/10/2026. `git diff --exit-code 341e267a2b origin/main` vazio: árvore publicada idêntica à aprovada. Main anterior ainda era 43901a40c2; nenhum deploy anterior em andamento; imagem ativa eda6f1f22f reconfirmada em ambas as stacks imediatamente antes do merge. Nenhum dispatch manual duplicado.

Deploys automáticos: Hub2You `37035643106` e Autonom.ia `37035642988`, ambos para o merge acima. Nenhum deploy manual duplicado.

## Verificação produtiva depois da troca de tráfego

Conferência somente leitura por SSM, EC2, ELB, manifest e downloads HTTPS dos assets, sem consulta ao banco ou dados de clientes:

| Stack | Instância atual | Retorno imediatamente anterior | Comando SSM | Resultado |
| --- | --- | --- | --- | --- |
| Hub2You | i-07e5bc744c4ccda52 | i-04c8e3b417cbe2533 | d963cea6-9b57-417c-a375-4ad823fc4dab | Success / código 0 |
| Autonom.ia | i-018b5c54bf4f35421 | i-031d9fbcd7b197437 | 0d05ca13-c420-4183-b8c9-328f4f24fb9b | Success / código 0 |

Nas duas stacks: web e worker ativos e usando a imagem `ab84a219bdd30f287ed0011ed61d62ec43f1fab4`; `.git_sha` da aplicação igual ao merge; target group atual healthy; target group anterior existente. `/api` e `/app/login` responderam HTTPS 200. As instâncias anteriores ainda estavam running dentro dos cinco minutos de retenção do workflow no instante dessa primeira conferência; o encerramento delas será reconfirmado quando os workflows terminarem.

O hash de cada asset recebido por HTTPS em `chat.hub2you.ai` e `agents.autonomia.site` corresponde ao arquivo dentro da imagem publicada. O chunk `assets/CrmKanbanPage-Ck-8cD1H.js` tem SHA-256 `2ffeaa4879b12af7947c4daaf0345243e7ce7d0361491c09bd4f7e0ae476f410` e contém o contrato de preferência `chat2you.crm.kanban.zoom.v1`. CSS publicado `assets/dashboard-H6R9ZFbW.css`: hash `b3920ee42b5f2d3c8411b18d7fa8d2056294b5bef09f9330bffae07d6411a4b0`, com 61/61 seletores de zoom do quadro e 61/61 do preview. O alias `chat.autonomia.site` também serviu o mesmo chunk/hash novo.

Limite da conferência: Safari real, Firefox e WebKit foram exercitados na aplicação/API locais com dados sintéticos e os mesmos assets compilados; a conferência produtiva confirma versão, serviços, saúde e bytes publicados. A aba isolada do Codex exigiu login e não houve sessão autenticada produtiva disponível. Não foi executado arraste em oportunidades de clientes. A ressalva do import de áudio no login Firefox permanece no relatório de QA; não foi corrigida nesta publicação.

Processos de teste próprios encerrados: Redis isolado 6840 desligado após a bateria Ruby. Banco local de teste e relatórios privados preservados para rastreabilidade; não há upload de fixture, auth, env, perfis ou credenciais.

## Encerramento da publicação

- [Hub2You — workflow 37035643106](https://github.com/autonom-ia2/chat/actions/runs/37035643106): completed/success.
- [Autonom.ia — workflow 37035642988](https://github.com/autonom-ia2/chat/actions/runs/37035642988): completed/success.
- Ambos no SHA `ab84a219bdd30f287ed0011ed61d62ec43f1fab4`. Não houve necessidade de rollback nem alteração de credenciais.
- Conferência EC2 posterior ao término: atuais Hub2You i-07e5bc744c4ccda52 e Autonom.ia i-018b5c54bf4f35421 running; anteriores Hub2You i-04c8e3b417cbe2533 e Autonom.ia i-031d9fbcd7b197437 stopped. Essas anteriores são o retorno imediato para eda6f1f22f pelo workflow oficial, sujeito à janela de um degrau já descrita.
- Esta atualização de auditoria é somente documentação em docs/ e não dispara outro deploy.
