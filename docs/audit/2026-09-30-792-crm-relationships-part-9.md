# #792 — Parte 9: oportunidades vinculadas na ficha do contato

## Autorização e escopo

Rodrigo aprovou a parte 8 e autorizou somente a lista de oportunidades na ficha do contato. Base `599e7df06683563755cf8553635c1a766148e2fe`, branch `feat/792-crm-relacionamentos`, Issue #792, PR #793 em rascunho. Ao concluir, apresentar telas reais e aguardar novo aceite. Sem autorização de merge, deploy, produção, credenciais ou migrações.

Referência M06 do HTML aprovado: uma lista de Oportunidades no CRM para o mesmo contato, com título, etapa, valor e abertura do card. **Adaptação explícita à ficha real:** usa a nova aba Oportunidades no painel Acompanhamento existente. Não substitui a ficha por outro leiaute, não remove Notas/Atributos/Histórico/Mídia/Mesclar e mantém Notas como a aba inicial. A largura do card CRM permanece 40rem/640px, sem alteração neste incremento.

## Interface e contrato de dados

`ContactOpportunities` apresenta título, funil, etapa, situação, valor/moeda, responsável comercial e previsão quando preenchida. Os links abrem o card existente em outra aba para preservar o preenchimento da ficha, com indicação acessível. Não criam oportunidades nem atualizam contato/empresa.

A consulta inicial é Não arquivadas (abertas, ganhas e perdidas). O usuário pode escolher Aberto/Ganho/Perdido/Arquivado/Todas as situações. A busca por título e a paginação são realizadas no servidor; não filtram somente os cards já carregados do Kanban. Cada página contém até cinco itens. O total é o desta consulta, já filtrado por contato, situação, busca e visibilidade.

Os controles e cores usam os componentes/tokens existentes, com ChoiceSelect em vez de select nativo. Títulos longos quebram linha; o valor zero é exibido como zero na moeda do card. As moedas não são somadas nem convertidas. O formatador existente da Lista transforma zero em travessão por decisão daquela tela; esta lista usa a mesma apresentação monetária do CRM, mas conserva zero explicitamente, sem alterar o comportamento das outras telas.

`useContactOpportunities` pertence à ficha e é compartilhado pelas apresentações desktop/mobile. Abrir a ficha não faz essa consulta enquanto a aba Oportunidades estiver inativa. A lista não escreve na store do Kanban nem herda seus filtros. Requisições antigas são canceladas/ignoradas quando muda conta, contato ou autorização/aba. Linhas e contagem anteriores são removidas imediatamente. Ao voltar de outra aba, o foco atualiza a consulta; o botão Atualizar também busca o estado atual. Isso não é uma promessa de sincronização em tempo real sem foco ou sem ação do usuário.

Falha de rede é exibida como erro com Tentar novamente, não como lista vazia. Uma resposta vazia válida tem estado próprio. A pesquisa digitada mas ainda não aplicada não é enviada ao trocar situação ou atualizar; o texto permanece no campo até a confirmação explícita.

## Endpoint somente leitura

`GET /api/v1/accounts/:account_id/crm/contacts/:contact_id/opportunities`

- Gate de CRM e autenticação nativos; `authorize Crm::Card, :index?` e `authorize contact, :show?` antes de listar.
- `policy_scope(Crm::Card)` aplica a visibilidade já existente, inclusive oportunidades sem inbox pertencentes ao usuário, membership de inbox e assigned-only. A conta e o ID canônico do contato restringem a consulta.
- Projeção mínima: `id`, `title`, `status`, `value_cents`, `currency`, `expected_close_at`, `pipeline: {id,name}`, `stage: {id,name}`, `owner: {id,name}` ou nulo. Não usa o serializer amplo do card nem carrega conversas, mensagens, metadados de IA, notas, contatos ou anexos.
- Metadados: `total_count`, `page`, `per_page: 5`, `has_more`. A contagem usa o mesmo escopo autorizado das linhas; não expõe a quantidade de cards ocultos.
- Parâmetros: `page` inteiro decimal positivo, `result` em `active/all/open/won/lost/archived`, `search` texto de até 200 caracteres. ID malformado, array/objeto ou situação desconhecida retornam 422. Contato de outra conta/inexistente não é resolvido por aproximação.
- Busca case-insensitive escapando curingas SQL; ordenação `updated_at DESC, id DESC` para desempate determinístico. Preload somente dos três relacionamentos utilizados. Não há migração, novo vínculo ou regra de gravação.

O controller está no caminho comum OSS, reutilizando os overlays de política Enterprise. Os testes Enterprise verificam crm_view sem crm_manage_cards, ausência de crm_view, leitura negada do contato, assigned-only e revogação de permissão. A revisão global das políticas e dos escritores do plano completo continua pendente; este incremento não altera nem mascara os testes antigos suspensos.

## Correções durante a validação

O primeiro teste de apresentação encontrou a diferença do formatador monetário compartilhado: ele representa zero como travessão. A lista nova passou a conservar zero em sua moeda sem modificar o formatador usado por outras telas. O teste original foi mantido.

O primeiro ensaio compilado carregou a ficha, a nova aba e a contagem correta, mas nenhuma linha era renderizada. O console revelou `RangeError: Invalid language tag: pt_BR` na apresentação da previsão: a chave do catálogo da conta não era um identificador aceito pelo Intl do navegador. A exceção era capturada pelo Vue e aparecia no console, não em `pageerror`. O componente converte somente a grafia do idioma para `pt-BR` antes de formatar datas/números. O teste unitário foi ampliado para usar a chave real `pt_BR`, reproduziu duas falhas (data e moeda legada) antes da correção e conserva as asserções. O roteiro passou a conferir também erros de renderização no console; não filtra essa falha para obter sucesso.

A revisão da previsão conferiu o contrato do input de data do drawer (`expected_close_at.slice(0, 10)`). A lista mantém esse mesmo dia de calendário, inclusive quando o servidor devolve meia-noite UTC e o navegador está em America/Sao_Paulo. O ensaio usa uma previsão às 00:00 UTC e exige 15/11, não 14/11.

A repetição do preparo dos dados sintéticos atualizou legitimamente seus timestamps, alterando a ordem esperada da primeira página. O seed passou a confirmar a ordenação explícita depois de gravar seus campos, antes do baseline. Não foi alterada a ordenação da aplicação nem enfraquecida a asserção de paginação.

O ensaio de abertura em outro funil revelou um problema real no deep link já existente: o card correto abria, mas o quadro ao fundo e seu seletor continuavam no primeiro funil da conta. O caminho `card_id` agora alinha o funil com o card efetivamente carregado e autorizado, desde que esse funil exista na seleção nativa. Não aceita um funil arbitrário pela URL nem injeta funis arquivados/indisponíveis; mudança de conta ou de card durante a leitura impede a atualização atrasada. O mesmo roteiro exige card correto, funil correto e largura de 640px.

## Validação

| Verificação | Resultado |
|---|---|
| Frontend selecionado: CRM, Relacionamentos, APIs/stores e componentes compartilhados afetados | 484 testes em 48 arquivos aprovados. Não é uma alegação de reexecução dos mais de sete mil testes da parte anterior. |
| Backend equivalente ao workflow de Relacionamentos, incluindo o endpoint novo | 511 exemplos: 507 aprovados, zero falhas, quatro suspensos históricos. |
| Navegador da parte 9 | 14 verificações aprovadas, 11 capturas reais, zero gravações de negócio. |
| Regressão de criação contextual da parte 8 no mesmo bundle | 14 verificações aprovadas e uma oportunidade sintética criada, conforme esperado. Total de 28 checks de navegador, sem somar reexecuções. |
| Persistência da consulta | Mantidos 45 contatos, 20 empresas, 71 oportunidades, 33 mensagens e duas conversas. Contato e oito cards comparados integralmente, incluindo timestamps UTC com seis casas, sem alteração. |
| Persistência da regressão posterior | Somente uma oportunidade adicional (71 → 72); pessoa e empresa originais intactas. Baselines separados para não misturar os dois roteiros. |
| Build compilado | `pnpm exec vite build --mode test` aprovado; o painel carregado e seu SHA-256 estão em `compiled-assets.json`. Sem servidor Vite/HMR durante o ensaio final. |
| Qualidade | ESLint em oito arquivos JS/Vue: zero bloqueadores e seis avisos de chaves dinâmicas aceitos pela política existente. RuboCop em quatro arquivos Ruby: nenhuma infração. Prettier e whitespace aprovados. |
| Guia, Central e traduções | 171 fluxos/170 telas no Guia; Central com 174 artigos/170 telas; oito catálogos e 16.220 mensagens verificados. AST sem novos regex aprovado. |

Os quatro suspensos continuam em `spec/models/account_spec.rb:52` e `spec/requests/api/v1/accounts/crm/cards_spec.rb:333,556,583`. Nenhum teste foi suspenso ou removido neste incremento; eles não contam como aprovados. O endpoint novo tem 29 exemplos de request próprios (comum + Enterprise) sem falhas.

O perfil CRM somente leitura recebeu exatamente suas duas oportunidades, sem enxergar os títulos ou a contagem dos demais cards. Ao filtrar ganhas, recebeu zero, embora o administrador veja uma oportunidade ganha. A tentativa de abrir diretamente um card oculto foi recusada pela API nativa. O estado vazio não oferece criação a quem não tem essa ação.

A inspeção visual identificou uma captura do celular durante a animação de abertura, embora não houvesse overflow interno. A coleta passou a esperar também os limites reais do painel dentro da viewport, antes de capturar. As 11 imagens finais foram refeitas e conferidas com esse critério. O roteiro também espera a ficha carregar efetivamente antes de escolher a aba após uma navegação completa; não trata o cabeçalho ainda carregando como uma tela pronta.

O console final não teve exceções JavaScript nem erros de renderização. Permanecem registrados os 404 da consulta de limites Enterprise local e uma interrupção deliberada de GET para testar erro/retentativa. Não houve resposta de negócio positiva simulada; a retentativa consulta Rails/PostgreSQL reais. Avisos existentes de Browserslist, depreciações e tamanho de bundles não foram ocultados.

Ambiente exclusivo: banco UI `chat2you_792_ui_test`, requests em `chat2you_792_test`, Redis 6792, Rails local 3792 com `CI=true` para usar os assets compilados. Dados e usuários sintéticos; jobs/e-mails em adaptadores de teste, sem worker de entrega. Browser plugin não disponível: Chrome/Playwright existentes, sem instalar dependências. Viewports 1620×1000, 1366×768 e 390×844. O card do CRM foi medido em 640px; o painel Acompanhamento conserva o leiaute responsivo nativo.

### Reprodução

Requests próprios: `bundle exec rspec spec/requests/api/v1/accounts/crm/contact_opportunities_spec.rb spec/enterprise/requests/relationships/contact_opportunities_spec.rb`. A seleção backend completa é a de `.github/workflows/relationships.yml`, ampliada com os requests CRM neste histórico. Resultado JSON resumido em `backend-summary.json`.

Frontend: `pnpm test --maxWorkers=2 --minWorkers=1` em `app/javascript/dashboard/routes/dashboard/crm`, `components-next/Relationships/specs`, os specs de telefone, BackButton, cache, APIs de contatos/CRM, stores CRM/empresa e useAbortableRequest. Os novos arquivos `ContactOpportunities.spec.js`, `useContactOpportunities.spec.js` e o caso adicionado a `api/specs/crmKanban.spec.js` são versionados. Para a reprodução manual, abrir a ficha → Oportunidades → testar situação, busca, páginas, abertura do mesmo card e retorno à ficha; repetir com um usuário somente leitura.

Verificações adicionais: `pnpm guia:check`, `pnpm central:check`, `pnpm i18n:fork:check`, `pnpm relationships:check`, `.github/scripts/email-protection-eslint.mjs`, Prettier, RuboCop e `git diff --check`. Scripts/logs do ensaio local estão em `.codex/792/part9-*`; credenciais e snapshots detalhados não são publicados. Evidências versionadas: `docs/relationships/screenshots/792-part9/`.

## Documentação e próxima parada

O Guia recebeu o novo caminho a partir de `porques.md` e foi regenerado, sem editar os arquivos gerados manualmente. O workflow de Relacionamentos inclui os novos requests. A próxima parte proposta, dependente de novo aceite, é a lista equivalente na ficha da empresa usando seus contatos canônicos. Revisão independente, CI final e revisão transversal de permissões/concorrência/integrações permanecem requisitos antes do pedido de merge. Nada publicado na AWS.
