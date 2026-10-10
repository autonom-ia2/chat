# 08/10/2026 — Funções personalizadas: diagnóstico e expansão (#1135)

## Escopo
Análise e proposta; nenhuma mudança de código funcional, autenticação, autorização, banco ou produção.
Documento: `docs/custom-roles/diagnostico-expansao-2026-10-08.md`.

## Localidade e isolamento
- Nó identificado por `maccluster node`: m4.
- Base: `81fd4d88d4c1c1a5b6a121d2c2b84c7d874f18fc`.
- Branch: `codex/1135-custom-roles-expansion`.
- Worktree: `/Users/rodrigosilva/dev/worktrees/chat2you-custom-roles-1135`.
- Arquivos não rastreados de outras tarefas no checkout principal preservados.
- `create_worktree` do app falhou com Git unavailable; fallback `git worktree add` no nó local.
- Nenhum workload pesado, runtime instalado, serviço iniciado ou repository snapshot distribuído.

## Orquestração
Três agentes de leitura: servidor/permissões, interface e escopos de dados.
Escopos e interface entregaram evidências do código; agente principal conferiu o modelo/API, regras Enterprise, diferenças de conversa, resumo CRM, filtros e Guia.
Revisão documental independente solicitada aos agentes antes do fechamento.
Falhas de permissão de rede do app interromperam turnos de agentes; retomados após instrução de continuar.

## Evidências consolidadas
- 34 chaves de permissão e 16 áreas, contadas no código.
- Função tem lista plana de chaves, sem contrato de condições.
- Conversas não têm chave de somente leitura.
- Lista de conversas usa precedência exclusiva; policy individual combina concessões.
- Base de abertura aceita caixa/time; lista usa caixas.
- CRM possui visibilidade de cards por caixa/membership/assigned_only; resumo de relatórios consulta funil da conta sem escopo do usuário.
- Contatos não recebem automaticamente o recorte de cards.
- Filtros pessoais AND/OR não são limite de autorização da função.
- Excluir função anula associação dos membros, que retornam ao baseline nativo.
- Guia consulta APIs como usuário; escrita pelo Guia tem gate adicional de administrador.

## Decisões propostas
Separar área, dados visíveis e ações. Primeiro coerência, depois consulta/alcance em conversas+CRM, ações separadas, condições agrupadas e visões compartilhadas.
Preservar legado, não fazer backfill amplo, não incluir delegação administrativa sensível neste pacote.
Implementação, merge/deploy e mutações posteriores dependem de aprovação explícita do Rodrigo.

## Validação desta documentação
- Leitura de `AGENTS.md`, código OSS/Enterprise, auditorias históricas e Issues #452/#888/#879/#894/#726.
- Script local temporário de conferência: 38 referências de caminho/intervalo válidas; 34 chaves; 16 áreas.
- Script não executa aplicação ou testes.
- `git diff --check` executado; checagem final no índice antes do commit.
- Nenhum teste foi executado. Specs existentes foram somente lidos.
- Sem validação independente de produção; histórico de Issue não tratado como prova atual.

## Rastreabilidade
Issue: https://github.com/autonom-ia2/chat/issues/1135.
Issue adicionada ao Project Autonom.ia Dev (usuário autonom-ia, Project 3) com Hub2You, Investigando, Docs, P2, risco Baixo, Local e próxima ação preenchida.
Conector de Project falhou com MCP SSE/ngrok 404; atualização realizada pelo `gh project`, após consultar schema e IDs reais.
PR somente de documentação; revisão e estado final registrados no fechamento.

## Revisão documental e preparação da PR
- Revisor de escopos: diagnóstico consistente; incorporadas qualificações de administrador, base caixa/time no acesso direto, exclusão admin-only de contato, catálogo por recurso e conclusão restrita ao resumo Summary verificado.
- Commit inicial impedido por hook sem `.husky/_/husky.sh` no worktree sem dependências instaladas. Para os dois Markdown, usar `git -c core.hooksPath=/dev/null commit`, após checagem do índice; não instalar runtimes/dependências só para documentação.

- Revisor de interface: contagens e tabela aprovadas; incorporados nomes pt-BR exatos, rótulo de conversas, gate da tela, redução dos cartões, slots fixos, alcance da prévia estática e resumo legado de crm_admin.
- Revisor de servidor: incorporados PATCH que limpa função ausente, atribuição sem validação explícita de conta/elegibilidade, entradas SAML/SSO e ausência de gate de leitura contact_view. Policies da Central conferidas pelo principal: escrita negada por decisão de produto, não expandida na proposta.
- Também faltava loader Husky no pre-push. Para push desta branch só de documentação, usar override transitório `git -c core.hooksPath=/dev/null push`; configuração permanente do repo não alterada.

## Fechamento
- PR draft de documentação: https://github.com/autonom-ia2/chat/pull/1136, anexada à conversa.
- Issue e PR no Project Autonom.ia Dev: Em review, Hub2You, Docs, P2, Baixo, Local; próxima ação para Rodrigo avaliar a proposta.
- Conferência de PR: OPEN/draft; somente dois arquivos Markdown. Worktree limpa antes do registro final.
- Revisão factual dos três agentes incorporada; não é aprovação do Rodrigo para implementar/merge/deploy.
- Nenhum merge, deploy ou alteração funcional realizada. Rollback desta documentação: reversão do commit de docs se ela vier a ser mergeada; plano para comportamento futuro consta no relatório.


## Complemento — cobertura operacional antes da expansão
- Pedido passou a priorizar Campanhas liberado sem acesso a Anúncios Meta; dois agentes retomados para interface e servidor.
- Fetch somente de origin/main e worktree destacada de leitura em /Users/rodrigosilva/dev/worktrees/chat2you-1135-coverage-current; revisão 372ca4eb5da63a6d87d01d3c40f78344b4c2d7cf. Worktree documental original preservada.
- Revisão instalada conferida via SSM no container chatwoot-web, arquivo /app/.git_sha; corresponde ao snapshot atual.
- Consulta estritamente de leitura via rails runner, dentro de transação com SET TRANSACTION READ ONLY: configuração indicada tem campaign_view, membro base agent e feature meta_ads_hub habilitada. Nenhuma alteração, segredo ou dado pessoal consultado; identificadores/configuração específica do cliente omitidos da documentação.
- Bloqueio confirmado em menu, rota e policy: administrador exigido; não existe permissão customizada Meta no catálogo.
- Lacuna adicional confirmada: rota Modelos WhatsApp permanece exclusiva de administrador, com pendência explícita no comentário do código. Brand Kits e Links/QR já reutilizam as permissões de Campanhas.
- Nova proposta: meta_ads_view explícita, separar leitura de credenciais/configuração/IA e recortar detalhamento por visibilidade. Não ampliar automaticamente campaign_view porque há dados financeiros e comerciais da conta.
- Risco concreto identificado: panel_list/Cohort consultam dados da conta inteira, sem recorte da visibilidade do usuário.
- Sem navegação na sessão pessoal do Chrome: browser isolado iab indisponível. Evidência de configuração obtida por consulta read-only; não confundir com aceitação funcional do agente.
- Nenhum teste executado, spec escrito, código funcional alterado, permissão concedida, merge ou deploy. Somente complemento documental da PR #1136.

- Revisão independente do complemento: incorporadas distinção de gates de rotas administrativas, leituras Graph de contas/Pixels reservadas ao administrador, refresh disparado por consulta do painel e ocultação dos controles de IA no papel de leitura. Seção renumerada para 11; fontes conferidas no snapshot atual.
