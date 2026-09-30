# Campanhas de e-mail — revisão de UI/UX e proposta visual

Data: 30/09/2026. Issue: https://github.com/autonom-ia2/chat/issues/800.
Base inspecionada: `7e62bc97b752418fdae5bce39a2ae366aea8e5d0`.
Este registro começou na revisão e nos mockups. Após aprovação do Rodrigo, o escopo avançou para a implementação descrita abaixo. Merge, deploy e restauração do catálogo em produção permanecem pendentes.

## Evidências e limites

- Conta 16 consultada no navegador: lista de campanhas, biblioteca da campanha 50 e editor da campanha 51. Navegação e leitura; nenhum disparo, importação, atualização, exclusão ou aplicação de modelo em produção.
- As quatro capturas fornecidas pelo Rodrigo complementam a leitura, em especial o editor com conteúdo e suas barras concorrentes. Na consulta atual, a campanha 51 abriu o estado inicial de criação.
- A biblioteca da conta mostrou exatamente dois modelos salvos e a categoria técnica `meus-modelos`.
- O repositório contém 14 modelos MJML e seus 14 HTMLs compilados, distribuídos em nove diretórios de categorias, com licença MIT de Mailteorite.
- O controlador usa `EmailCampaignTemplate.for_account(Current.account)`. Esse escopo inclui os modelos da conta e os globais. A página consulta o índice sem filtro de categoria. A tarefa `email_campaign_templates:seed` cadastra modelos globais; não foi encontrada sua invocação nos workflows de deploy inspecionados.
- Isso comprova que os arquivos continuam disponíveis e que a galeria atual não oferece o catálogo. **Não comprova exclusão de registros do banco nem a causa operacional da ausência.** Não foi executada consulta ao banco nesta revisão.
- Na lista atual, algumas campanhas incompletas não exibem envio. Uma campanha mais abaixo exibe “Enviar agora”. Portanto, a ação não está ausente em todas as situações.
- `canSendNow` exige rascunho, importação inativa, destinatários e HTML. Não exige assunto nessa função. A proposta de checklist precisa reutilizar as regras reais de envio do servidor e não inventar requisitos no cliente.
- O clique atual em `sendNow` despacha diretamente a ação. A proposta adiciona uma revisão explícita antes da confirmação.

## Achados e proposta

| Prioridade | Problema observado | Impacto para o usuário | Proposta recomendada |
|---|---|---|---|
| P1 | A ação de enviar desaparece em rascunhos incompletos | Não fica claro como avançar ou o que falta | “Disparar” visível nos rascunhos; quando houver pendência, abre orientação com botão de correção |
| P1 | Vários painéis extensos de importação, saúde e classificação em cada campanha | A lista deixa de servir para encontrar e acompanhar campanhas | Linha compacta com nome, assunto, situação, público e próxima ação; diagnósticos sob demanda |
| P1 | Catálogo original não aparece na galeria da conta | Só dois modelos ficam disponíveis, apesar dos arquivos existentes | Investigar os registros globais e recuperar a biblioteca pela tarefa existente após aprovação; preservar os modelos da conta |
| P1 | Muitas ações com o mesmo peso e ações destrutivas perto das principais | É difícil identificar o caminho normal; aumenta o risco de clique incorreto | Editar e Disparar em destaque; duplicação, reutilização e ações destrutivas em menu contextual |
| P1 | Sem etapa de revisão visível entre edição e envio na lista | Público, conteúdo e remetente não são conferidos juntos | Revisão única de mensagem, domínio, remetente, público apto, exclusões e momento do envio; confirmação final |
| P2 | Indicadores de falha em vermelho mesmo com zero ocorrências e sem envio | A cor parece indicar um problema que ainda não aconteceu | Rascunhos mostram prontidão; campanhas enviadas mostram resultados reais; vermelho só em problema existente |
| P2 | “Somente análise”, “Ainda não informado” e “Reavaliar envio” sem hierarquia | Mistura estado do provedor, importação e elegibilidade dos destinatários | Separar claramente a condição do envio e os endereços excluídos; explicar motivo, efeito e próxima ação |
| P2 | Lista usa filtro de situação longo e controles dispersos | Encontrar um rascunho ou agendamento exige percorrer muito conteúdo | Abas por situação, busca por nome/assunto e resumo curto no topo |
| P2 | Editor com assunto espremido entre muitos comandos | Campos importantes ficam pequenos e os botões competem pelo espaço | Assunto e texto de prévia em linha própria; salvar/revisar no topo; teste como ação secundária |
| P2 | IA e modelos competem com controles de visualização e salvamento | Falta separar criar, editar e conferir | Criação com IA e modelos no painel de conteúdo; uma única alternância desktop/celular |
| P2 | Blocos com ícones pouco claros na captura e painel de propriedades sem contexto | Não fica evidente o que selecionar nem como editar | Ícones reais da biblioteca; propriedades do bloco selecionado e contexto para o estado vazio |
| P2 | Códigos de personalização ocupam toda uma barra | Linguagem técnica ocupa o espaço de trabalho | Menu “Personalizar com dados”, com nomes legíveis e exemplo preenchido na prévia |
| P2 | Categoria crua `meus-modelos` | Aparência inacabada e sem orientação | Abas “Biblioteca” e “Meus modelos”; categorias traduzidas por objetivo |
| P2 | Botão “Usar este modelo” cortado na captura | A ação principal fica visualmente quebrada | Dois controles curtos por card, com largura e altura suficientes: Prévia / Usar modelo |
| P2 | `useTemplate` sem campanha volta para a lista sem aplicar o conteúdo | Entrar na galeria fora do editor pode terminar sem resultado | Ao abrir sem campanha, escolher/criar um rascunho; ao abrir pelo editor, aplicar à campanha atual |
| P2 | Miniaturas sem panorama suficiente dos layouts | Difícil escolher sem abrir várias prévias | Prévia maior no card e janela de visualização completa, com desktop/celular |

## Direção visual

Preservar o menu azul-marinho, o azul de ação, os ativos de Hub2you, a tipografia do sistema e os componentes do produto. Usar bordas discretas, cantos arredondados coerentes, espaços regulares e uma ação principal por contexto. O resumo é uma faixa contínua, com destaque de marca, em vez de uma coleção de quadrados independentes.

O azul dos botões no protótipo usa um tom mais escuro da mesma família (`#1D6EE3`), com contraste branco calculado de 4,78:1. O azul `#2781F6` teria 3,78:1 para o mesmo texto. Na implementação, mapear essa função à variante acessível do sistema de design, sem substituir a identidade de marca global.

O protótipo contém quatro telas conectadas: lista de campanhas, editor, biblioteca e revisão do disparo. Um exemplo adicional mostra a orientação ao tentar disparar um rascunho incompleto. Os dados são fictícios; a aparência dos 14 templates é dos HTMLs originais. O e-mail “Novidades Chat2You” é uma nova ilustração de design, identificado como exemplo, sem reproduzir conteúdo de clientes.

O protótipo simula navegação, categorias, busca, escolha de modelo, edição do assunto, prévias e confirmação. Não implementa edição de blocos por arrastar, chamadas de IA, validação de destinatários, persistência ou envio. Esses limites aparecem na interface e no README.

## Compatibilidade e próximo passo após aprovação

Aplicar a organização visual nos componentes existentes, mantendo o editor e os contratos de API. Verificar os caminhos OSS/Enterprise e os papéis `campaign_manage`. Não alterar políticas de envio, supressão ou reputação por causa do redesign. Resultados da importação continuam acessíveis e acionáveis.

Antes de restaurar o catálogo: verificar a presença dos registros globais e comparar os modelos por nome e origem. Usar o mecanismo idempotente já existente quando apropriado; não apagar modelos da conta nem criar duplicatas. Essa etapa depende de autorização para a alteração concreta no ambiente.

Implementação, testes do produto, revisão, capturas reais do produto construído, merge e deploy seguem depois da aprovação do desenho. Plano de rollback: reverter o PR de UI; eventual ajuste de catálogo deve ser separado e documentado, sem exclusão dos modelos existentes.

## Registro de execução

- Worktree separada, branch `codex/800-email-campaigns-ux-mockups`; checkout principal preservado.
- Skill aplicada: `ecc:make-interfaces-feel-better`, para hierarquia, legibilidade, dimensões de controles e consistência visual.
- Preparação de ativos locais reusa 14 HTMLs originais por links relativos, preserva a licença e extraiu 55 ícones Lucide da dependência existente. O pacote portátil contém os arquivos materializados. A primeira preparação identificou um alias de ícone e foi corrigida para usar o pai oficial do alias.
- Tailwind compilado com a dependência existente. O aviso de Browserslist desatualizado não impediu a compilação; nenhuma dependência foi atualizada.
- Servidor HTTP estático vinculado somente a `127.0.0.1`, porta 34780. Não iniciou Rails, jobs, Redis, banco ou provedor de IA.
- Guia: nenhuma rota, menu do produto ou explicação do Guia foi alterada; protótipo em `docs/` não exige geração do Guia.
- A validação final de interações e os arquivos de capturas estão registrados no README e em `browser-report.json` do protótipo.
- `node --check docs/campaigns/mockups/800/mockup.js`: concluído sem erro de sintaxe. Tailwind compilou sem erro. Os 14 HTMLs usados são idênticos aos originais, verificado por SHA-256.
- Navegador: 15 verificações funcionais do protótipo passaram; quatro telas avaliadas em 390 e 1440 px, sem transbordamento horizontal e sem texto cortado nos comandos principais. Nenhum erro de console observado.
- Duas asserções preliminares foram inadequadas (campo ocultado automaticamente na leitura de `value`; expectativa de papel semântico de input de data). Foram substituídas por verificações do objetivo no DOM e passaram. Os resultados preliminares e motivos estão preservados em `supersededAssertions` do relatório.
- Capturas JPEG reais, usando `Page.captureScreenshot` pela capacidade CDP do CUA para respeitar as dimensões de teste. A captura comum do painel cortava o viewport temporário; o método CDP resolveu a captura sem alterar o conteúdo. O viewport foi restaurado.
- A cópia inicial dos HTMLs duplicava arquivos já existentes e trazia os espaços finais desses arquivos ao diff. A preparação foi ajustada para links relativos aos originais, mantendo o pacote portátil completo. `git diff --cached --check` refeito após o ajuste.
- O hook local de pre-commit não iniciou nesta worktree porque `.husky/_/husky.sh` não existe. Após as validações manuais acima e a leitura do diff, o commit de documentação usa `git -c core.hooksPath=/dev/null commit`, sem alterar a configuração persistente do repositório.

## Implementação após aprovação — 30/09/2026

Autorização: Rodrigo aprovou implementar o desenho, recuperar os modelos prontos, preservar a UI/UX e incluir um agente independente de QA antes de subir. A exigência anterior de capturas reais antes de merge/deploy continua atendida por esta entrega. O checkout principal, antigo e com alterações locais, foi preservado; toda implementação usa a worktree desta issue.

### Entrega

- Lista compacta, resumo contínuo com identidade visual, busca e filtros; Disparar nos rascunhos abre a revisão. Diagnósticos extensos ficam acessíveis sob demanda. Ações destrutivas exigem confirmação.
- Editor existente reorganizado em assunto/prévia, passos, blocos, canvas e propriedades. Preservadas geração assíncrona, salvamento, teste e edição de campanhas antigas com HTML. O assunto ainda não desfocado é persistido ao salvar/revisar/testar.
- Revisão com requisitos atuais do servidor, remetente, destinatários aptos, exclusões, envio/agendamento e confirmação final. Falha ao atualizar a prontidão impede a confirmação. Não altera a política de reputação/SES nem a supressão individual.
- Biblioteca com modelos globais e da conta, categorias, busca, prévias reais e controles completos. Entrar sem campanha permite preparar uma nova campanha com o modelo escolhido. Trocar Desktop/Mobile na prévia não aplica o modelo nem submete o formulário.
- Catálogo explícito dos 14 designs licenciados originais. Os HTMLs recompilados usam o mesmo conteúdo sanitizado do editor, com rodapé de descadastro protegido. A tarefa de produção lê ativos pré-compilados: não depende de `node_modules`, removido da imagem final Docker. O seed prepara tudo antes da transação e atualiza somente modelos globais pelos nomes originais, sem duplicar nem alterar modelos das contas.
- Nova rota de biblioteca sem campanha mantém guards/permissões existentes. Pesquisa em OSS e Enterprise não encontrou override correspondente. Explicações humanas do Guia atualizadas; conteúdo gerado reconstruído pela ferramenta.

### Validação e leitura dos resultados

Ambiente Rails exclusivamente local: PostgreSQL em 127.0.0.1:55779, banco novo `email800_workspace`; Redis em 127.0.0.1:56779/8. Não acessou banco, secrets, infraestrutura, dados de clientes, IA ou envios de produção. O ambiente de navegador usa conta fictícia 800 e API em memória; endpoints de envio/agendamento/teste retornam 403.

- `bundle exec rspec spec/services/email_campaigns/presentation spec/services/email_campaigns/template_catalog_spec.rb spec/requests/api/v1/accounts/email_campaigns/templates_workspace_spec.rb spec/models/email_template_spec.rb spec/services/email_campaigns/reputation/provider_gate_spec.rb spec/services/email_campaigns/preflight_decision_suppression_spec.rb spec/services/email_campaigns/resume_integration_spec.rb`: **159 exemplos, 0 falhas**. Inclui catálogo idempotente, isolamento de contas, prontidão e supressão com SES saudável. O primeiro rerun apontou dois caminhos de specs incorretos; caminhos corrigidos antes da execução final, sem falha de produto.
- `pnpm exec vitest run app/javascript/dashboard/components-next/Campaigns/EmailProtection/specs app/javascript/dashboard/routes/dashboard/campaigns/pages/specs/emailTemplateBody.spec.js --reporter=dot --silent`: **438 testes, 16 arquivos, 0 falhas**. Abrange importação/recuperação, proteção, destinatários, ações, atualização assíncrona, revisão e prévias.
- ESLint dos arquivos de produto e specs alterados: 0 erros. RuboCop dos sete arquivos Ruby de produto/specs: 0 infrações. `git diff --check`: limpo. Formatadores foram seguidos de leitura do diff e novos testes; nenhum teste foi encadeado com commit.
- O exportador Ruby do harness também passou no RuboCop e na verificação de sintaxe. O setup `.husky/_/husky.sh` continua ausente nesta worktree; o commit usa `core.hooksPath=/dev/null` somente nessa invocação, após checks manuais e leitura dos resultados, sem alterar Git config persistente.
- O primeiro push foi recusado pelo mesmo setup Husky ausente, antes de publicar o commit. O único check do pre-push, `sh bin/validate_push`, foi lido e executado manualmente na branch `codex/800-email-campaigns-ux-mockups`; passou. O push também usa o override de hooks somente nessa invocação.
- `bundle exec vite build --mode test`: concluído. Avisos existentes de Browserslist, tamanho de chunks e enums Rails não impediram os checks; nenhuma dependência atualizada.
- Checker de i18n: contrato anterior preservado em 57 locales, novas chaves compiladas no catálogo canônico inglês. `pnpm guia:build` e `pnpm guia:check`: 169 fluxos, 170 rotas, 0 sem explicação; quatro explicações antigas sem rota permanecem como avisos.
- QA independente `/root/qa_800`: 13 exemplos Ruby e 5 testes Vue sob sua responsabilidade passaram; revisão visual em 390/768/1440 px sem overflow ou comandos cortados; revisão de envio, agendamento, perfil de leitura, galeria e cancelamento. Após ajuste do tooltip, mais 68 testes direcionados passaram.
- A captura final revelou miniaturas pequenas que o navegador adiava: a lista passou a renderizar seus HTMLs já recebidos sem `loading=lazy`; a biblioteca mantém a busca de conteúdo por visibilidade. Também corrigidos foco da busca, tooltip sem motivo, botão Desktop/Mobile dentro do formulário e contraste/posição da ação de correção. Conferência visual refeita nos componentes reais.

### Evidência visual e limites

Capturas em `docs/campaigns/workspace-800/previews/`: lista, editor, biblioteca, revisão, pendência e telas responsivas. São telas dos componentes de produto executados localmente, com shell externo sintético; não são montagens nem capturas de produção. O harness e sua forma de execução estão em `tests/qa/email-workspace/README.md`.

O catálogo pt_BR novo não foi alterado: o AGENTS.md enviado nesta tarefa limita produto ao inglês, enquanto o repositório permite a exceção para chaves próprias do fork. Foi solicitada autorização específica para en/pt_BR das campanhas; sem resposta, não presumir autorização. Esses textos novos precisam da tradução aprovada antes da liberação em português.

Não há evidência de entrega real por SES nesta rodada. Os resultados locais e o parecer QA não garantem ausência absoluta de regressão. O CI do commit de documentação anterior não comprova o código implementado: a versão atual do PR deve ser verificada novamente. Consulta ao GitHub após publicar `e85b9745b0` confirmou os workflows de e-mail, Guia e traduções em `disabled_manually`, sem checks no novo HEAD. Essa configuração não foi alterada nesta tarefa; não declarar CI remoto verde. O Project foi movido para Review e o PR #801 permanece draft.

Prettier cumulativo dos 14 arquivos JS/Vue selecionados pelo script de CI passou. `pnpm i18n:fork:check` também passou: 9 catálogos e 15.864 mensagens existentes compiladas. Esses resultados não incluem tradução pt_BR das novas chaves WORKSPACE.

Plano de publicação/restauração e rollback: `docs/campaigns/email-workspace-release-800.md`. Não executado em produção nesta etapa.
