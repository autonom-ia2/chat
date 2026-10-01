# #792 — Parte 13: visibilidade de conversas, origens e contagens

## Escopo e ponto de partida

Rodrigo aprovou as partes 1–12 e autorizou continuar a revisão integrada. Base `281d6b08f57e21425c2dfbfead5cbd95fc13a24c`, worktree `chat2you-792-crm-relacionamentos`, branch `feat/792-crm-relacionamentos`, Issue #792 e PR #793 em rascunho. Este incremento trata projeções e filtros derivados de conversas; não é aprovação global do plano. Sem merge, deploy, consulta à AWS, mudança de usuários reais, migração ou dependências novas.

## Três testes de visibilidade reativados

Foram removidas somente as marcações `skip` dos três exemplos de visibilidade em `spec/requests/api/v1/accounts/crm/cards_spec.rb` (linhas 333, 556 e 583 na base). Antes de alterar código de produto, os três exemplos passaram com suas asserções originais. Portanto, este trabalho **reativa cobertura que já passa no código/harness atual**, não atribui a correções novas uma falha que não foi reproduzida. Nenhuma expectativa desses exemplos foi removida ou enfraquecida.

A associação de conta suspensa em `account_spec.rb:52` não foi inventada para satisfazer o teste. Na bateria ampliada também foram encontrados seis exemplos já suspensos fora do recorte anterior: dois de follow-up, um de configuração de caixa, um de vínculo de funil/caixa, um de funis/etapas e um de automações. Nenhum deles foi suspenso neste incremento. Permanecem sete pendências históricas na seleção ampliada, apesar da reativação dos três exemplos de conversas.

## Defeitos reproduzidos e corrigidos

### Origem de campanha de uma conversa restrita aparecia em um card permitido

O card podia ter uma conversa primária permitida e uma secundária restrita da mesma pessoa. A agregação anterior juntava as campanhas de todas as conversas e consultava apenas a visibilidade da primária. O usuário recebia o identificador, o título e a URL da campanha da conversa secundária que não podia abrir. O problema foi reproduzido em detalhe, lista, Kanban e payload por destinatário do websocket.

A agregação compartilhada agora exige o contexto de visibilidade e verifica **cada conversa de origem**. O mesmo contrato é usado pelo detalhe/lista, Kanban, exportação e payload de atualização por usuário. As fontes autorizadas conservam sua ordem temporal e a deduplicação da primária que também possui linha de vínculo. Corpos e identificadores brutos de clique continuam fora da projeção. Não há alteração nos registros, na atribuição do contato ou nas conversas armazenadas.

A conferência é por origem, e não uma proibição global baseada na primária. Quando a primária está restrita, uma secundária autorizada continua contribuindo com sua própria campanha; nada da primária é revelado. Um teste adicional reproduziu a divergência em que o filtro encontrava a campanha autorizada, mas o payload a apagava. Lista e Kanban agora apresentam somente a origem permitida que fundamenta o resultado do filtro.

### Filtros e totais podiam revelar informação de conversas não autorizadas

Ocultar a campanha no JSON não bastava: consultar um identificador conhecido ainda encontrava o card através da conversa restrita. Os filtros compartilhados de campanha e da etiqueta da conversa agora aplicam a visibilidade **antes** de paginação, contagem e agrupamento. A etiqueta própria do contato permanece independente e não perde seu resultado legítimo quando a conversa primária é restrita.

`Crm::Conversations::Visibility#scope` expressa em SQL as regras de `visible?` já utilizadas pelo CRM: conta selecionada, participação na caixa e, para caixas com restrição por atribuição, responsável/participante permitido. Os novos testes comparam explicitamente as duas formas, a restrição de um escopo menor, outra conta, ausência de usuário e revogação de participação na caixa no contexto seguinte. Não foi reescrita a autorização geral de todos os módulos.

`FilterQuery` e `GroupSummary` exigem o contexto de visibilidade de seus chamadores; não recebem um default permissivo. CardsController, resumo agrupado e Kanban fornecem esse contexto. A exportação reutiliza o escopo e o payload autorizados. A consulta usa SQL construído pelo ActiveRecord para os IDs permitidos e continua parametrizando os valores fornecidos pelo usuário.

O campo de total da etapa antes consultava `stage.cards.count`, incluindo cards que o usuário não podia ver. Agora consulta o escopo autorizado da etapa e do funil. O total da etapa conserva sua finalidade distinta da contagem dos filtros, mas não inclui registros restritos. O teste com um card permitido e um restrito retornava dois antes; depois retorna um.

## Evidência antes e depois

O primeiro conjunto novo de privacidade executou 13 exemplos e reproduziu nove falhas antes da correção. O teste adicional do total de etapa reproduziu uma falha separada. A revisão de consistência da campanha secundária permitida reproduziu outra divergência, corrigida sem ocultar a origem autorizada. O conjunto final inclui testes de autorização por conversa, participação, revogação, filtros, contagens, agrupamentos, exportação, ordem/deduplicação e payload por destinatário.

Um caso de preparação de fixture tentou cadastrar participante sem acesso prévio à caixa e foi recusado pela validação nativa. O teste foi ajustado para conceder a participação normalmente e depois revogar o acesso à caixa, reproduzindo o estado legítimo que deseja verificar. Não se desativou a validação de produto para montar o teste.

## Validação local e limitações das medições

A primeira execução ampliada teve 740 exemplos, uma falha de tempo e sete pendências antigas. O teste existente de busca de mídias (1.000 ocorrências) mediu p95 máximo de 620,6 ms, acima do limite inalterado de 500 ms. A execução completa do frontend feita no mesmo período teve 7.097 aprovações e um timeout de 5.000 ms na compilação do catálogo de e-mail. Não houve modificação nesses dois testes ou nos respectivos módulos neste incremento.

Essas falhas são preservadas nos logs originais. Foi feita uma única reexecução sequencial das baterias, sem backend/frontend simultâneos e sem mudar os limites. Concorrência/carga local é uma hipótese para o tempo observado, não uma causa comprovada nem autorização para ignorar a falha. Os resultados finais são registrados separadamente dos ensaios iniciais.

O backend final executou 741 exemplos: **734 aprovações, zero falhas e sete suspensos históricos**. A busca de mídias preservou seu limite de 500 ms e registrou p95 de 105,06 ms para 25 itens e 104,71 ms para 50 itens; ambas com máximo de 14 consultas, 20 amostras e total de 1.000 ocorrências. São medidas locais desse ensaio, não uma garantia de desempenho em produção. A nova cobertura inclui 18 exemplos de projeções/filtros e seis de paridade da visibilidade, dentro da contagem maior.

### Resultado final das baterias

| Verificação | Resultado |
|---|---|
| Frontend completo, reexecução sequencial | **7.098 testes, 636 arquivos, todos aprovados**. O caso de catálogo que excedeu 5.000 ms na primeira rodada passou com o mesmo limite. |
| Backend ampliado | **741 exemplos: 734 aprovados, zero falhas, sete suspensos históricos**. |
| Três antigos testes de visibilidade | Reativados sem alteração das asserções e incluídos no backend aprovado. |
| Novos contratos de privacidade | 18 exemplos de projeção/filtros e seis de paridade do escopo, incluídos na contagem maior. |
| Build | Vite compilado em modo test aprovado. Os avisos existentes de chunks/Browserslist foram mantidos. |
| Qualidade | 13 arquivos Ruby conferidos pelo RuboCop; nenhuma infração restante. Traduções, Guia, Central, whitespace e AST sem regex novos aprovados. |

Não há mudança em JavaScript/Vue neste incremento; a bateria frontend completa e a compilação foram reexecutadas para validar o conjunto. Não foram alterados limites de tempo, expectativas ou arquivos dos dois testes de tempo que falharam inicialmente. O fato de a rodada sequencial passar não certifica o runtime Linux ainda pendente.

## Navegador e persistência

Ambiente exclusivo: Rails test/CI=true em `127.0.0.1:3792`, Redis 6792 e banco de UI `chat2you_792_ui_test`, separado do banco RSpec `chat2you_792_test`. Jobs e e-mail usam adaptadores de teste; nenhum worker de entrega foi iniciado. Browser plugin não disponível: utilizado Playwright/Chrome já instalado, sem dependências novas. Nenhuma resposta de negócio foi simulada. Somente dados fictícios.

O roteiro abriu a aplicação compilada com o mesmo card para um papel de consulta e um administrador. Verificou as respostas reais de detalhe/lista/Kanban/resumo, filtros de origem permitida/restrita, contagens de etapa, recarregamento, aba Relacionamento e aba Conversas. O leitor recebe somente a conversa/campanha permitida; o administrador conserva ambas as conversas. Desktop 1620×1000 e celular 390×844, lateral 640px no desktop e ajuste à largura disponível. Não foi redesenhada a interface nem imposta cota de oportunidades.

A comparação direta no banco confere o contato, dois cards e duas conversas integralmente, com datas UTC de seis casas. O objetivo é somente consultar; zero escritas de negócio é um critério do roteiro. Contagens e resultado da comparação são publicados sem os snapshots completos ou dados de autenticação.

## Continuidade e gates de liberação

A seleção do workflow de Relacionamentos foi ampliada no YAML para os contratos de projeção/filtro/exportação/visibilidade. Isso não reabilita o workflow desabilitado no GitHub nem substitui sua prova de runtime Linux. Revisão independente, demais caminhos de escrita e concorrência, controles legados de atendimento e efeitos externos permanecem pendentes. A ausência de novas mensagens no banco sintético não prova ausência de efeitos de webhooks de produção.

O frontend não foi redesenhado e não ganhou ações por este patch. Controles legados que ainda aparecem para determinados perfis precisam da revisão já prevista; não apresentar screenshots desta correção de dados como certificação de todos os controles de autorização.

Logs e roteiros temporários: `.codex/792/part13-*`. Evidências compartilháveis: `docs/relationships/screenshots/792-part13/`. Fontes, PNGs e resultados devem ter hashes conferidos após commit. **Parar para aceite de Rodrigo; não fazer merge ou deploy.**
