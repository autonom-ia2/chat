# #792 — Parte 10: oportunidades na ficha da empresa

## Autorização e referência

Rodrigo aprovou a parte 9 e autorizou somente a lista equivalente na ficha da empresa. Base `e630c0a00d9688297dd1c0362cd7fbfcf4152426`, branch/worktree exclusiva `feat/792-crm-relacionamentos`, Issue #792, PR #793 em rascunho. Apresentar as telas reais e parar para novo aceite. Sem merge/deploy, alterações na AWS, credenciais, dependências ou esquema do banco.

Referência M07 do HTML aprovado: oportunidades dos contatos atualmente vinculados à empresa. A adaptação segue a ficha real e a parte 9 aprovada: nova aba Oportunidades no painel Acompanhamento, preservando Contatos como entrada e as abas Histórico, Notas, Atributos e Mídia. Não substitui a ficha nem altera sua largura. O card aberto no CRM mantém os 640px de Editar funil.

## Implementação

A empresa lista título, **contato da negociação**, funil, etapa, situação, valor/moeda, responsável comercial e previsão. O nome da pessoa diferencia oportunidades da mesma empresa; é texto dentro do link do card, não uma âncora aninhada. Buscar pelo título e trocar Situação consulta o servidor. Páginas de cinco registros. Por padrão, exclui arquivadas, mas mantém ganhas e perdidas; permite todas/abertas/ganhas/perdidas/arquivadas. Não soma nem converte moedas e conserva valor zero e o dia da previsão.

Abertura do card em outra aba preserva o formulário e seu rascunho empresarial. Atualizar ou voltar ao foco da ficha consulta o estado atual; não promete push em tempo real sem foco/ação. A consulta não herda filtros ou páginas do Kanban. Quando a empresa, conta, permissão ou aba muda, os resultados antigos são invalidados. Um erro tem retentativa própria e não se apresenta como lista vazia bem-sucedida.

O componente de apresentação da parte 9 foi renomeado de `ContactOpportunities` para `RelationshipOpportunities`, com contexto contato/empresa. Seletores e conteúdo do contato permanecem compatíveis. A lógica compartilhada está em `useRelationshipOpportunities`; o wrapper de contato conserva seu contrato e testes. A empresa usa o mesmo controlador por ficha, compartilhado entre desktop e celular, para não duplicar consultas.

## Consulta somente leitura e escopo

`GET /api/v1/accounts/:account_id/crm/companies/:company_id/opportunities`

O controller empresarial fica no overlay Enterprise e a rota só é registrada nessa edição. Requer CRM habilitado, recurso Companies da conta, `Crm::Card#index?` e `Company#show?`. Resolve a empresa na conta atual e restringe as oportunidades por uma subconsulta dos IDs dos contatos **atualmente** vinculados, na mesma conta. Aplica o `policy_scope(Crm::Card)` nativo antes de contar e paginar. Nenhuma lista de IDs fornecida pelo navegador decide a associação.

A projeção/paginação comum de contatos foi extraída para `ProfileOpportunitiesController`, sem alterar o contrato do endpoint anterior. As duas ações autorizam a entidade antes de usá-la. O resultado da empresa acrescenta somente `contact: {id,name}` à projeção comercial. Não carrega/retorna e-mail, telefone, mensagens, IDs de conversas, notas, anexos, descrição do card ou metadados de IA. Preload de pipeline/stage/owner/contact evita consulta individual para cada linha.

A contagem usa a mesma visibilidade e filtros das linhas. Parâmetros: `page` decimal positivo, `result` em active/all/open/won/lost/archived e `search` textual com até 200 caracteres. Os mesmos limites e erros 422 da consulta de contato são preservados; empresa de outra conta não produz lista nem total. Sem novos regex.

O vínculo empresarial é atual, não histórico: mover ou desvincular uma pessoa altera o conjunto apresentado na próxima leitura, mas não altera/exclui suas oportunidades. Empresa homônima, texto legado `company_name` ou mesmo domínio no texto não substituem o `company_id`. A subconsulta não é limitada à primeira página de Contatos da ficha.

## Validação e ambiente

Ambiente exclusivo: Rails test em 127.0.0.1:3792, PostgreSQL `chat2you_792_ui_test` para UI e `chat2you_792_test` para requests, Redis 6792. Dados/usuários sintéticos, adaptadores de teste para jobs/e-mail e nenhum worker de entrega. Browser plugin não disponível: usados Playwright/Chrome existentes, sem instalação de dependências. O roteiro utiliza o bundle compilado, sem servidor de hot reload, e APIs reais. Só a falha de GET é deliberadamente provocada; nenhum sucesso de negócio é simulado.

A bateria inicial de requests do endpoint e regressão do contato passou. O teste isolado antigo da ficha empresarial precisou expor a nova dependência de permissão do CRM no mock, preservando seus quatro testes existentes; foram acrescentados os gates e o carregamento da aba. Lint de alinhamento, ordem de declaração e formatação foi corrigido, sem suspender testes ou relaxar as verificações.

O primeiro ensaio compilado passou pela consulta, filtros, paginação, abertura, erro/retentativa e responsividade, mas o teste de papel personalizado não conseguiu abrir a ficha empresarial. A inspeção confirmou uma restrição anterior em `companies/routes.js`: a rota aceita administrator/agent, enquanto o papel sintético tem contact_view/crm_view. Não foi ampliado esse acesso para satisfazer o teste. A verificação desse papel foi separada: a navegação personalizada permanece bloqueada e não é contada como teste visual aprovado; a API real deve retornar apenas os cards e a contagem autorizados. Esta entrega não afirma que a ficha empresarial é acessível a toda função personalizada com crm_view; o alinhamento transversal de papéis permanece pendente de decisão/revisão.

A inspeção visual mostrou a aba Mídias isolada na segunda linha do cabeçalho empresarial. Somente nessa ficha, quando a nova aba está disponível, as abas agora formam duas linhas equilibradas de três colunas com utilitários existentes. A ficha do contato mantém o desenho aprovado e o componente compartilhado de navegação não foi modificado.

### Retomada em 01/10/2026 e resultado deste checkpoint

O acesso ao Mac foi recuperado. Git, fontes, logs e processos exclusivos foram inspecionados antes de continuar: a parte 10 ainda estava sem commit e seus arquivos estavam preservados. O último ensaio interrompido tinha dez checks concluídos, mas falhara ao esperar redirecionamento da rota empresarial do papel personalizado. A URL permanecia na empresa e a ficha não carregava; portanto, não era correto afirmar que essa navegação havia sido validada. Uma sondagem separada também não alcançou o estado carregado. Os logs originais foram mantidos e o fluxo ficou explicitamente em `knownLimitations`, como **blocked_not_passed**, não removido da lista de pendências.

O ensaio final cobre a ficha empresarial com administrador e também com um **agente padrão**, papel já aceito pela rota nativa. A fixture desse agente tem acesso somente a uma caixa de teste contendo duas das oportunidades; não há alteração de permissões de usuários reais ou de configuração da aplicação. Visualmente, o agente viu apenas seus dois cards e total 2; o filtro de ganhas mostrou zero, mesmo existindo uma ganha visível ao administrador. A API recusou a abertura de um card restrito. O papel personalizado também teve sua API verificada separadamente, sem receber acesso adicional à ficha.

| Verificação reexecutada | Resultado |
|---|---|
| Frontend selecionado, incluindo ficha da empresa, CRM, Relacionamentos, APIs e stores | 502 testes em 50 arquivos aprovados. Não equivale a reexecutar toda a suíte frontend. |
| Backend equivalente ao workflow de Relacionamentos | 531 exemplos: 527 aprovados, zero falhas e quatro suspensos históricos, não contados como sucesso. |
| Consulta empresarial no navegador | 14 checks concluídos, 12 capturas reais. Navegação de papel personalizado segue bloqueada em separado. |
| Regressão da consulta do contato | 14 checks concluídos no mesmo bundle após o reaproveitamento dos componentes. Total: 28 checks de navegador aprovados, sem contar reexecuções ou o cenário bloqueado. |
| Persistência da consulta empresarial | Mantidos 49 contatos, 23 empresas, 81 oportunidades, 33 mensagens e duas conversas. Empresa, três pessoas e nove cards comparados integralmente, incluindo timestamps: nenhuma alteração. |
| Persistência da regressão do contato | Mesmas contagens; contato e seus oito cards intactos. Baseline separado, sem confundir os dois roteiros. |
| Build e navegador | Bundle compilado validado, sem HMR; manifesto registra entradas e hashes das fontes, PNGs e bundle carregado. |
| Qualidade | ESLint em dez arquivos JS/Vue: zero bloqueadores e quatro avisos de chave dinâmica existentes. RuboCop em cinco arquivos Ruby sem infrações; formatação/whitespace aprovados. |
| Guia, Central e traduções | 172 fluxos/170 telas no Guia; Central com 174 artigos/170 telas; oito catálogos e 16.226 mensagens. AST sem novos regex aprovado. |

Os quatro suspensos anteriores continuam em `spec/models/account_spec.rb:52` e `spec/requests/api/v1/accounts/crm/cards_spec.rb:333,556,583`. Nenhum teste foi suspenso ou removido neste incremento. O conjunto de requests próprios da nova consulta empresarial e regressão da consulta de contato passou em 49 exemplos, também incluídos na bateria backend maior.

O console dos caminhos concluídos não apresentou exceções JavaScript nem erros de renderização. Os manifestos conservam os 404 da consulta de limites Enterprise no ambiente local e a interrupção proposital de GET para testar erro/retentativa. Não foi simulada resposta positiva de cadastro ou consulta. Viewports: 1620×1000, 1366×768 e 390×844, com painel dentro da viewport e card CRM de 640px. As imagens deste checkpoint são de APIs/PostgreSQL reais e dados fictícios, não do mockup HTML.

### Reprodução e evidências

Frontend: `pnpm test --maxWorkers=2 --minWorkers=1` com CRM, `components-next/Relationships/specs`, `CompanyDetailView.spec.js`, telefone, BackButton, cache, APIs de contatos/CRM, stores de CRM/empresas e useAbortableRequest. Backend: seleção de `.github/workflows/relationships.yml`, incluindo o diretório `spec/enterprise/requests/relationships`. Logs da retomada: `part10-resume-frontend.log`, `part10-resume-backend.log` e `part10-resume-rspec.json`.

UI: `part10-seed.rb` → `part10-browser.mjs` → `part10-persistence.rb`, depois `part9-seed.rb` → `part9-browser.mjs` → `part9-persistence.rb`, sempre no banco UI local com Rails test/CI=true e sem worker. Os dados de comparação foram lidos diretamente no banco, com timestamps UTC de seis casas; credenciais e snapshots detalhados não são publicados. Os arquivos da galeria antiga da parte 9 não foram sobrescritos.

Qualidade: `.codex/792/part10-quality.py`, `pnpm guia:check`, `pnpm central:check`, `pnpm i18n:fork:check` e `pnpm relationships:check`. Build aprovado em `part10-build-acceptance.log`; os hashes do ensaio final comprovam correspondência das fontes sem alteração desde a compilação. Evidências compartilháveis em `docs/relationships/screenshots/792-part10/`. Scripts e logs temporários permanecem em `.codex/792/`.

**Situação:** trecho funcional encerrado para aprovação visual dos caminhos de administrador/agente. O cenário de navegação empresarial do papel personalizado não está certificado; integra a revisão transversal obrigatória antes da liberação, junto de CI remoto e revisão independente. Esta documentação não é uma aprovação global para produção.

## Governança e próxima parada

A explicação foi escrita em `lib/operator_guide/porques.md`; o mapa do Guia é regenerado, nunca editado manualmente. Os requests Enterprise já são abrangidos pela seleção do workflow de Relacionamentos. O conector específico de Project retornou 404 nesta sessão; as atualizações usam o GitHub autenticado local, preservando os sete campos e os itens existentes do board Autonom.ia Dev.

Aguardar aprovação visual de Rodrigo antes da revisão integrada final M01–M08. Permanecem os gates de revisão independente, concorrência entre escritores, permissões/transversalidade, automações/integrações externas e CI do commit final. Nenhum resultado local comprova deploy na AWS. Merge só após nova autorização explícita no final; workflows de main podem publicar mais de uma stack. Rollback de código não apaga cadastros confirmados.
