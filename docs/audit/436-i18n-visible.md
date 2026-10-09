# #436 — Traduções das telas efetivamente renderizadas

## Evidência e escopo

A leitura de `tmp/email436/visual/results.json` confirmou a lacuna real: 87 verificações aprovadas e cinco falhas, incluindo chaves legadas cruas nas páginas em árabe e alemão. A cobertura anterior de 92 mensagens, descrita em `docs/audit/436-i18n.md`, não abrangia esses textos. Esta tarefa não executa uma nova QA de navegador; o responsável principal reconstruirá o Vite e repetirá árabe, alemão, português e mobile.

Escopo de escrita: apenas as porções de e-mail/gestão/links WhatsApp de `locale/*/{crm.json,campaign.json,index.js}`, o checker, seu spec e este documento. Os 57 arquivos `emailCampaignProtection.json` permanecem idênticos à leitura inicial. Não houve alteração de componentes, backend, modelos, schema, registro central de idiomas ou índice Git; nem instalação, serviços externos de tradução, chamadas pagas de avaliação, Rails, banco ou produção.

## Inventário verificável

A lista explícita `REQUIRED_LEGACY_KEYS` está no próprio `scripts/check-email-protection-i18n.mjs`: **167 chaves**, sendo **48 de CAMPAIGN_MANAGEMENT + 19 de CRM_KANBAN.TRACKED_LINKS + 100 de CAMPAIGN.EMAIL_CAMPAIGN**.

Foram consultadas as páginas de listagem e gestão, os diálogos de criação/edição e detalhes, RecipientImportStatus, PlaceholderChips e os componentes/apresentação de EmailProtection. O inventário também acompanha o helper de erros de importação, o store, o adaptador de API e o layout da campanha. A lista `VISIBLE_SURFACES` registra os caminhos e verifica novas referências literais; o mapa dinâmico de erros de importação também é conferido.

As sete chaves legadas STATUS e os estados/resumo legados IMPORT ficam cobertos conforme o contrato solicitado. Na versão atual dos componentes, os badges e o resumo de RecipientImportStatus usam o namespace novo, cujas 92 mensagens continuam integralmente verificadas. Não existe um ramo legado IMPORT_STATUS no inglês atual. AI.BADGE tem apenas os três rótulos mostrados na listagem; os demais textos de IA, GrapesJS e editor não entram nesta expansão.

## Tradução e semântica

- Textos autorais por idioma, com reutilização de traduções já existentes apenas quando o significado é equivalente. Variantes regionais mantêm os respectivos idiomas e alfabetos.
- Descrição de gestão em linguagem simples: envios, entregas e qualidade das campanhas. Sem promessa de pontuação oficial do domínio.
- BOUNCED/BOUNCE_RATE legados significam não entrega em geral. Não indicam que toda falha seja permanente nem que toda caixa seja inexistente. Em pt-BR: “Não entregues” e “Taxa de não entrega”.
- Reclamações/marcações como spam continuam distintas do cancelamento de inscrição; nenhuma descrição julga a pessoa destinatária.
- Campos/variáveis de personalização e texto de prévia substituem termos técnicos em inglês nas mensagens visíveis, inclusive no canônico pt-BR.
- Placeholders nomeados mantêm exatamente o conjunto canônico; literais `{'@'}` são compilados e renderizados. `Name`/`Email` e `name`/`email` permanecem nas instruções de importação onde representam cabeçalhos aceitos pelo parser. A alternativa portuguesa `Nome` também é aceita pelo código.
- Palavras compartilhadas entre idiomas, como Email, Status, Editor e Link, não são tratadas como parágrafos traduzidos. O checker rejeita frases inglesas idênticas com duas ou mais palavras nas chaves legadas.

As traduções e a revisão são do modelo GPT-6 Astra/high, incluindo a divisão por grupos independentes de idiomas. Não houve revisão por falantes nativos. Compilação e paridade de chaves não certificam naturalidade linguística; esse é um limite da entrega.

## Verificação

O checker carrega os JSONs referenciados pelos imports reais e avalia a expressão exportada pelo índice, respeitando ordem de spreads e mesclas. Compara o resultado efetivo com as mensagens dos arquivos, verifica placeholders/compilação e renderiza cada chave com apenas o locale sob teste instalado e `fallbackLocale: false`.

O spec usa `import.meta.glob` para importar os módulos reais de locale, além de conferir o registro real de 43 idiomas. Testes negativos cobrem raiz ausente/sobrescrita, chave crua, frase inglesa copiada e token alterado. Uma reprodução offline usando o conteúdo inicial de árabe/alemão falhou por chave visível ausente; os módulos corrigidos de alemão e pt-BR passaram na mesma verificação.

Resultado consolidado em 16/09/2026. A rodada final do Vitest começou às 10:11:22 (America/Sao_Paulo), durou 4,02 s e terminou com saída 1 pelas duas falhas de `zh`. A última revisão de húngaro foi revalidada separadamente nas 259 mensagens e incluída nessa rodada.

Identificação do conteúdo validado: SHA-256 `8b52f2df77ec367d52497d8552c06f4a1783875232096bd5988f2921a1c8c3da`, calculado sobre os 169 arquivos de locale alterados e os dois arquivos de verificação, ordenados pelo caminho relativo, concatenando `caminho + NUL + conteúdo + NUL`. Este documento não entra no digest.

| Verificação                                                                                                                                                                    | Resultado                                                                                                                                                                                                                                                  |
| ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Inventário                                                                                                                                                                     | 57 diretórios, 57 índices presentes, 43 idiomas ativos; registro central preservado.                                                                                                                                                                       |
| Corpus selecionado                                                                                                                                                             | 92 mensagens de proteção + 167 legadas = 259 por idioma. Os 14.763 pares idioma/chave dos JSONs foram compilados e renderizados sem fallback. São 5.244 pares do namespace existente e 9.519 legados.                                                      |
| Índices efetivos                                                                                                                                                               | 56 módulos carregáveis, 14.504 pares renderizados; `zh` bloqueado pelos imports inexistentes descritos abaixo. Os 43 módulos ativos passaram.                                                                                                              |
| `node scripts/check-email-protection-i18n.mjs`                                                                                                                                 | Saída 1 exclusivamente no import inexistente de `zh/advancedFilters.json`. O checker não esconde nem transforma esse bloqueio em sucesso.                                                                                                                  |
| `node_modules/.bin/vitest run app/javascript/dashboard/components-next/Campaigns/EmailProtection/specs/locales.spec.js --maxWorkers=2 --minWorkers=1 --no-cache --no-coverage` | 154 testes: 152 aprovados e dois falharam, ambos no carregamento de `zh` (checker consolidado e import real desse módulo). Nenhum teste ignorado.                                                                                                          |
| ESLint dos dois arquivos de verificação                                                                                                                                        | Saída 0, sem erros ou avisos.                                                                                                                                                                                                                              |
| Prettier `--check` dos 172 arquivos desta entrega                                                                                                                              | Saída 0, todos aprovados.                                                                                                                                                                                                                                  |
| Parse de todos os JSONs em `dashboard/i18n/locale`                                                                                                                             | 2.772 arquivos válidos. Nenhuma exigência de tradução foi estendida a chaves não relacionadas.                                                                                                                                                             |
| Comparação com a leitura inicial                                                                                                                                               | 114 JSONs de CRM/campanha conferidos por chave: mudanças restritas à lista autorizada. Os 57 JSONs de proteção permanecem idênticos byte a byte. Os 56 índices preexistentes preservam todo o texto exceto o import/spread de CRM adicionado onde faltava. |

Entrega: **172 arquivos** — 57 `crm.json`, 57 `campaign.json`, 55 `index.js`, checker, spec e este documento. Os CRM novos contêm apenas os dois sub-ramos pertinentes. O português brasileiro recebeu as 14 mensagens legadas de importação que também faltavam.

Os testes não compilam nem exigem tradução de namespaces não relacionados: por exemplo, o valor vazio preexistente em `lv/CAMPAIGN.SMS.CARD.CAMPAIGN_DETAILS.ON` foi preservado. O Vitest emitiu o aviso preexistente de Browserslist desatualizado; nenhuma dependência foi atualizada.

## Limite de integração encontrado

`bn` não possuía índice: recebeu um módulo mínimo dos três arquivos pertinentes, sem ativação no registro central. `zh` já possuía um índice com referências a 21 JSONs inexistentes fora do escopo de e-mail, além do campaign.json agora criado. Foi solicitada orientação antes de remover essas referências não relacionadas; sem resposta, elas permanecem intactas. Por isso, **a validação integral dos 57 módulos ainda não está aprovada**.

Correção concreta pendente: remover somente os 21 imports quebrados e seus 21 spreads em `zh/index.js`, sem remover mensagens existentes ou ativar um idioma. Os arquivos referenciados ausentes são: `advancedFilters`, `agentBots`, `attributesMgmt`, `auditLogs`, `automation`, `bulkActions`, `components`, `contactFilters`, `csatMgmt`, `customRole`, `datePicker`, `emoji`, `general`, `helpCenter`, `inbox`, `integrationApps`, `macros`, `search`, `sla`, `teamsSettings` e `whatsappTemplates` (todos `.json`). Uma proposta revisável está em `/tmp/email436-zh-index-proposed.js`; não foi aplicada. Isso depende de ampliar a restrição do solicitante de editar apenas porções de e-mail do índice. Não é uma exigência de skill nem rejeição automática de aprovação.

A QA original também apontou direção do endereço de e-mail em RTL e alcance de botões por teclado no mobile. Esses comportamentos não são alterados por esta tarefa de tradução e precisam da nova QA do responsável principal. Não há declaração de PR pronto, merge ou deploy.
