# Prospecção: paridade com o Orth, as 486 funções

Prestação de contas do épico #676 (E6, #682). Cada função do inventário do plano rev.7 (google-saas `1f8ad9a` x chat2you `1bf71b3fa1`) tem aqui o destino: o PR que entregou, a decisão que tirou do escopo, ou pendente com o motivo. Código conferido na `main` em `732c23da08` (25/09/2026); as 18 funções da própria E6 foram conferidas na branch `feat/682-fechamento`, que junta as frentes A (exportar), B (Listas e tour), C (pt_BR, menu e permissão), D (este documento) e as correções de LOCAL-42, ENRIQ-57 e ENRIQ-69. Como a E6 mexe em vários desses arquivos, o número de linha da coluna Conferido já é o da branch: cada referência conferida na `main` foi levada para a linha equivalente na branch, casando o arquivo das duas versões trecho a trecho (37 referências mudaram de linha, nenhuma teve o trecho alterado). As correções de LOCAL-42, ENRIQ-57 e ENRIQ-69 e a atualização da branch com a main deslocaram mais 35 referências de outras funções; cada uma foi levada para a linha nova e conferida trecho a trecho contra `b5be0da576`.

## Resumo

| Destino | Funções |
|---|---:|
| **Entregue por PR** | **279** |
| &nbsp;&nbsp;#706 (E2) | 84 |
| &nbsp;&nbsp;#699 (E1) | 66 |
| &nbsp;&nbsp;#709 (E3) | 43 |
| &nbsp;&nbsp;#714 (E4) | 33 |
| &nbsp;&nbsp;#691 (E0) | 20 |
| &nbsp;&nbsp;#719 (E5) | 12 |
| &nbsp;&nbsp;#670 (lote #652) | 1 |
| &nbsp;&nbsp;#671 (lote #652) | 1 |
| &nbsp;&nbsp;#688 (fecha #675) | 1 |
| &nbsp;&nbsp;#682 (E6): frente B, Listas e tour | 8 |
| &nbsp;&nbsp;#682 (E6): frente A, exportar | 5 |
| &nbsp;&nbsp;#682 (E6): frente C, pt_BR | 2 |
| &nbsp;&nbsp;#682 (E6): defeitos do cliente (LOCAL-42, ENRIQ-57, ENRIQ-69) | 3 |
| **Preservado (já existia no chat2you)** | **90** |
| **Movido para outra issue (#732 E8, #705 Central e Guia, #713 recusa)** | **28** |
| &nbsp;&nbsp;#732 (E8), decisão 25/09 | 25 |
| &nbsp;&nbsp;#705 | 3 |
| **Fora do escopo por decisão** | **38** |
| &nbsp;&nbsp;fora (decisão 25/09) | 9 |
| &nbsp;&nbsp;fora (decisão), plano rev.7 e decisões anteriores | 29 |
| **Pendente, esperando etapa** | **51** |
| **Pendente, esperando decisão** | **0** |
| **Total** | **486** |

- **158 funções** têm arquivo e linha conferidos na `main` (`732c23da08`): 164 referências, cada uma aberta e com o trecho esperado na linha, e com o número de linha já levado para a branch da E6. As demais entregues se apoiam no corpo do PR ou na nota da etapa na #705, e isso está dito na linha.
- **#700** (Guia fora de cima do Aplicar) e **#712** (telefone do cadastro confirma a empresa) corrigem entregas da E1 e da E3 e não têm linha própria no inventário.
- **#682 (E6)** entregou 18 funções, todas com arquivo e linha conferidos na branch `feat/682-fechamento` (32 referências abertas uma a uma): exportar CSV e Excel pelo servidor, da busca e da lista (frente A); Listas com o mesmo card e painel da busca e o tour guiado (frente B); tela e recusas da prospecção em pt_BR (frente C); e os três defeitos que o cliente sentia, achados na conferência dos pendentes: centro do raio fora do círculo (LOCAL-42), verificação de WhatsApp presa ao número antigo (ENRIQ-69) e busca refeita apagando verificação gravada em paralelo (ENRIQ-57). O número do PR da E6 entra aqui quando ele for aberto.
- **A E6 também entregou o que o inventário não lista como função própria:** o atalho Configurações no menu Prospecção da barra lateral, visível para administrador ou `prospecting_manage` (`F/utils/prospectingSidebar.js:45`), e os botões Enviar ao CRM e Adicionar à campanha escondidos de quem não tem `Crm::CardPolicy#create?` ou `campaign_manage`, pela mesma regra do servidor (`C/settings_controller.rb:68`; nota em PLAT-48).
- **Desvios da E6 registrados:** o export deixa de fora a coluna Dist km do Orth e o link de WhatsApp tirado do site sem verificação; o tour marca a visita ao abrir, e não ao concluir como no Orth, e só pede sugestões do Google no clique; a tela de Listas ainda não tem botão de exportar (o cliente da API já tem `exportList`).

### Por parte da tela

| Parte | PR de E0 a E5 e lotes | preservado | #682 (E6) | outra issue | fora | pendente | Total |
|---|---:|---:|---:|---:|---:|---:|---:|
| Modo e jogadas | 31 | 10 | 1 | 3 | 4 | 2 | 51 |
| Onde buscar | 24 | 10 | 3 | 1 | 5 | 7 | 50 |
| Filtros | 24 | 3 | 0 | 3 | 5 | 5 | 40 |
| Motor da busca | 31 | 12 | 1 | 4 | 4 | 7 | 59 |
| Enriquecimento e WhatsApp | 37 | 13 | 2 | 1 | 6 | 13 | 72 |
| Card do lead e resultados | 33 | 15 | 2 | 3 | 1 | 5 | 59 |
| Painel do lead e pesquisa | 32 | 6 | 2 | 2 | 2 | 3 | 47 |
| Ações pós-busca, CRM, campanha e tour | 24 | 11 | 5 | 7 | 4 | 6 | 57 |
| Plataforma, chaves e permissões | 25 | 10 | 2 | 4 | 7 | 3 | 51 |

### Por situação original no inventário

| Situação original | PR de E0 a E5 e lotes | preservado | #682 (E6) | outra issue | fora | pendente | Total |
|---|---:|---:|---:|---:|---:|---:|---:|
| ausente no c2 | 111 | 0 | 8 | 14 | 28 | 26 | 187 |
| divergente | 95 | 10 | 6 | 9 | 8 | 15 | 143 |
| defasado | 29 | 0 | 4 | 0 | 1 | 3 | 37 |
| igual | 8 | 40 | 0 | 0 | 1 | 1 | 50 |
| só no c2 | 18 | 40 | 0 | 5 | 0 | 6 | 69 |

## O que está pendente e por quê

**O termo de Evidência da #682 está parcial.** Das 486 funções, 51 continuam sem PR e sem etapa dona. Nenhuma espera mais decisão: as 34 que esperavam foram decididas pelo Rodrigo em 25/09 (issue #732 e comentário no #676), que aprovou todas as recomendações. Por isso o PR da E6 cita a issue com `Refs #682`, e não com `Closes #682`: a #682 só fecha quando cada pendente abaixo tiver uma etapa dona. Até lá, estas são as funções do Orth que o cliente do chat2you ainda não tem.

**Decididas em 25/09 (#732, comentário no #676).** 25 viram código na #732 (E8), com destino `#732 (E8), decisão 25/09`:

- **Lead "já no CRM" no lugar do bloqueio por vendedor:** MOTOR-17, MOTOR-18, FILTRO-37, CARD-24, PAINEL-29, ACAO-21, ACAO-22, PLAT-21.
- **Jogadas salvas visíveis na grade:** MODO-25, MODO-26, FILTRO-27, PLAT-17.
- **Raio como o Orth:** LOCAL-18, FILTRO-17, MOTOR-03.
- **Agente vê só as próprias buscas:** MOTOR-37, ACAO-33, CARD-59.
- **Bloco técnico da nota só para administrador:** MODO-51, PLAT-05.
- **Descartar o lead e criar contatos:** CARD-58, ACAO-X04, ACAO-X05.
- **Campanha pela API oficial do WhatsApp:** ACAO-X09.
- **Log estruturado:** ENRIQ-60.

E 9 ficam fora, com destino `fora (decisão 25/09)`:

- **Ofertas viram perfis do catálogo:** MODO-39, PLAT-18.
- **Janela de posição rígida:** FILTRO-07, MOTOR-11.
- **Navegador real no scraper, só depois de medir:** ENRIQ-09, PLAT-28.
- **Verificação na sessão WAHA da conta:** ENRIQ-38.
- **Filtros de jogada sem tela (bairro e cidade, avaliações recentes):** FILTRO-13, FILTRO-14.

Continuam pendentes **51 que não dependem de decisão** e ficaram sem etapa dona ou fora do que cada PR fez:

- **Modo e jogadas:** MODO-46, MODO-49.
- **Onde buscar:** LOCAL-02, LOCAL-06, LOCAL-08, LOCAL-11, LOCAL-45, LOCAL-46, LOCAL-48.
- **Filtros:** FILTRO-11, FILTRO-12, FILTRO-15, FILTRO-16, FILTRO-22.
- **Motor da busca:** MOTOR-04, MOTOR-12, MOTOR-14, MOTOR-26, MOTOR-42, MOTOR-49, MOTOR-51.
- **Card do lead e resultados:** CARD-37, CARD-42, CARD-43, CARD-48, CARD-51.
- **Painel do lead e pesquisa:** PAINEL-04, PAINEL-07, PAINEL-30.
- **Enriquecimento e WhatsApp:** ENRIQ-21, ENRIQ-22, ENRIQ-23, ENRIQ-24, ENRIQ-25, ENRIQ-26, ENRIQ-27, ENRIQ-31, ENRIQ-32, ENRIQ-37, ENRIQ-47, ENRIQ-59, ENRIQ-61.
- **Ações pós-busca, CRM, campanha e tour:** ACAO-15, ACAO-20, ACAO-35, ACAO-36, ACAO-X06, ACAO-X10.
- **Plataforma, chaves e permissões:** PLAT-29, PLAT-34, PLAT-51.

Somando: nenhuma espera decisão e 51 esperam uma etapa.

Não sobrou nenhum **a confirmar**. Os 8 que a primeira versão deixou sem prova foram abertos no código da branch, cada um com arquivo e linha na própria nota: 3 estavam entregues (ENRIQ-56 pelo #706; PAINEL-43 e PLAT-15 pelo #709) e 5 não estavam feitos e passaram a pendente (LOCAL-42, ENRIQ-32, ENRIQ-37, ENRIQ-57, ENRIQ-69). LOCAL-42 e ENRIQ-69 eram defeitos que o cliente sentia: no modo raio, arrastar a prévia mudava o centro da busca sem mudar o círculo; e, depois de uma busca que troca o telefone do lead, o botão de WhatsApp seguia com o número verificado antigo. Os dois e o ENRIQ-57 foram corrigidos na própria E6; ENRIQ-32 e ENRIQ-37 seguem pendentes.

## Como ler a tabela

- **Destino.** `#NNN (Ex)`: PR que entregou, com a etapa. `preservado`: o inventário mandou manter o que o chat2you já tinha e nenhum PR tirou. `#682 (E6)`: entregue nesta etapa, pela issue enquanto o PR não tem número. `#705`: Central de Ajuda e Guia no lote único do fim. `#732 (E8), decisão 25/09`: vira código na E8, pela decisão do Rodrigo de 25/09. `fora (decisão)`: fora do escopo, com a decisão na nota. `fora (decisão 25/09)`: fora do escopo pela decisão do Rodrigo de 25/09. `pendente`: não feito, com o motivo.
- **Conferido.** Arquivo e linha quando a função foi aberta no código: conferido na `main` (ou na branch `feat/682-fechamento`, para as funções da E6), com o número de linha da branch `feat/682-fechamento`. Abreviações: `S/` = `app/services/autonomia/prospecting/`, `C/` = `app/controllers/api/v1/accounts/autonomia/prospecting/`, `M/` = `app/models/autonomia/prospecting/`, `J/` = `app/jobs/autonomia/prospecting/`, `F/` = `app/javascript/dashboard/routes/dashboard/autonomia/prospecting/`.
- **Decisões usadas:** as de 24/09 no épico #676 (sem cobrança, créditos, trava nem gate de plano; chaves Google e BigDataCorp nossas; IA só na credencial do Kanban; nota do Orth inteira), as de 25/09 nas issues #679 (não apagar dado, sai a retenção), #680 (recusa no contato vai para a #713), #681 (perfil restrito a contas, pesos próprios mapeados, relevância e posição saem da nota) e #705 (Central e Guia num lote só), as 34 de 25/09 na #732 e no comentário do #676 (todas as recomendações aprovadas: 25 viram código na E8, 9 ficam fora), e o "não portar" do próprio inventário rev.7 para código morto do Orth.

## Modo e jogadas (51)

| ID | Capacidade | Situação original | Destino | Nota | Conferido |
|---|---|---|---|---|---|
| MODO-01 | Modo de score da empresa guardado no banco (gbp ou general, padrão gbp) | igual | preservado | Modo por conta no metadata do Setting. | `M/setting.rb:113` |
| MODO-02 | Quem pode trocar o modo | divergente | preservado | Regra do c2 mantida (manage na tela e na API). Permissão própria para configurar segue sem decisão (nota da revisão). |  |
| MODO-03 | Controle de troca do modo na tela de configuração | divergente | #671 (lote #652) | Modo na configuração com ChoiceSelect. O texto explicativo do Orth não foi conferido. | `F/pages/ProspectingSettingsPage.vue:7` |
| MODO-04 | PUT sem o campo modo preserva o valor salvo | divergente | preservado | PUT sem modo preserva o salvo. |  |
| MODO-05 | Trocar o modo só para uma busca | só no c2 | #699 (E1) | Modo por busca no formulário, com a grade de jogadas seguindo o modo da busca. | `F/components/search/SearchModeFields.vue:38` |
| MODO-06 | Selo 'Modo: GMN (atacar lacunas)' / 'Modo: Geral (qualificar leads)' no topo da busca | ausente no c2 | #699 (E1) | Selo de modo no topo: âmbar GMN, verde-azulado Geral. | `F/components/search/SearchModeBadge.vue:37` |
| MODO-07 | Tela de busca lê o modo ao carregar | igual | preservado |  |  |
| MODO-08 | Seção '1. Sua jogada' na tela de busca | ausente no c2 | #699 (E1) | Seção de jogada no formulário. | `F/components/search/SearchModeFields.vue:8` |
| MODO-09 | Catálogo de jogadas filtrado pelo modo (3 por modo, 6 no total) | ausente no c2 | #699 (E1) | Catálogo de 6 jogadas, 3 por modo. | `S/search_presets.rb:15` |
| MODO-10 | Jogada 'Vender site' (modo GMN) | ausente no c2 | #699 (E1) |  | `F/utils/searchPresets.js:11` |
| MODO-11 | Jogada 'Gestão de reviews' (modo GMN) | ausente no c2 | #699 (E1) |  | `F/utils/searchPresets.js:20` |
| MODO-12 | Jogada 'Otimização GBP' (modo GMN) | ausente no c2 | #699 (E1) |  | `F/utils/searchPresets.js:29` |
| MODO-13 | Jogada 'Prova social' (modo Geral) | ausente no c2 | #699 (E1) |  | `F/utils/searchPresets.js:38` |
| MODO-14 | Jogada 'Mercado maduro' (modo Geral) | ausente no c2 | #699 (E1) |  | `F/utils/searchPresets.js:47` |
| MODO-15 | Jogada 'Presença digital' (modo Geral) | ausente no c2 | #699 (E1) |  | `F/utils/searchPresets.js:56` |
| MODO-16 | Card 'Sem jogada' (busca livre) | ausente no c2 | #699 (E1) | Card Sem jogada. | `F/components/search/SearchPresetGrid.vue:42` |
| MODO-17 | Visual do card de jogada | ausente no c2 | #699 (E1) | Card de jogada com tokens n-* (SearchPresetCard.vue). |  |
| MODO-18 | Ícones SVG das jogadas | ausente no c2 | #699 (E1) | Ícones lucide no card de jogada (SearchPresetCard.vue). |  |
| MODO-19 | Escolher jogada aplica filtros base; clicar de novo desmarca | ausente no c2 | #699 (E1) | Jogada aplica os filtros dela. | `F/composables/useSearchPresets.js:74` |
| MODO-20 | Jogada se desmarca quando os filtros divergem dela | ausente no c2 | #699 (E1) | Jogada desmarcada quando um filtro diverge. | `F/composables/useSearchPresets.js:21` |
| MODO-21 | Jogada enviada ao motor e gravada na busca | ausente no c2 | #699 (E1) | preset_id aceito, validado e gravado no metadata da busca. | `C/searches_controller.rb:127`, `S/search_runner.rb:727` |
| MODO-22 | Jogada muda a leitura da nota: filtros ativos zeram ou reduzem pesos | ausente no c2 | #719 (E5) | Filtros ativos zeram ou reduzem pesos (EffectiveWeights). Visível só em conta virada para o motor orth. | `S/scoring/component_score.rb:2` |
| MODO-23 | Jogadas não mudam a ordenação | igual | preservado |  |  |
| MODO-24 | Selo 'Jogada base: X · Modo: GMN/Geral' no painel de filtros | ausente no c2 | #699 (E1) | Linha Jogada base e Modo no topo da gaveta. | `F/components/search/filters/FiltersBaseLine.vue:15` |
| MODO-25 | 'Salvar como jogada': filtros atuais viram jogada da empresa | ausente no c2 | #732 (E8), decisão 25/09 | Entregue na E8, frente B (branch `feat/732-b-jogadas`): "Salvar como jogada" na gaveta de filtros do formulário, só com prospecting_manage, grava nome, modo da busca e filtros da conta na tabela autonomia_prospecting_saved_presets; a jogada nova fica marcada. | `C/saved_presets_controller.rb:7`, `F/composables/useSearchPresets.js:110` |
| MODO-26 | Listar, editar e excluir jogadas salvas | ausente no c2 | #732 (E8), decisão 25/09 | Entregue na E8, frente B: a jogada salva aparece na grade do modo dela, depois das prontas, vai na busca como `saved-<id>` (conferida por conta e modo no servidor) e tem selo no histórico. Editar (nome e filtros) e excluir ficam na aba Jogadas das Configurações da Prospecção. | `F/utils/searchPresets.js:84`, `S/search_presets.rb:20`, `F/components/ProspectingSavedPresets.vue:1` |
| MODO-27 | Selo da jogada no histórico de buscas | ausente no c2 | #699 (E1) | Selo da jogada no histórico. | `F/components/search/SearchHistory.vue:29` |
| MODO-28 | Reabrir ou refazer busca do histórico reaplica jogada e filtros | defasado | #699 (E1) | Reabrir marca a jogada; Repetir e Editar do histórico vieram no #706. |  |
| MODO-29 | Nota invertida por modo (GMN: nota alta = lacuna; Geral: nota alta = bem estruturado) | defasado | #719 (E5) | Fórmula do Orth com leitura invertida por modo. | `S/scoring/orth_scorer.rb:67` |
| MODO-30 | Multiplicador de tração pela posição no Google (só GMN) | divergente | #719 (E5) | Tração pela posição só no GMN; google_rank saiu da nota (decisão de 25/09 na #681). | `S/scoring/component_score.rb:2` |
| MODO-31 | Pesos exibidos por modo na configuração | divergente | #719 (E5) | Aba Score mostra os 6 componentes na conta virada (ProspectingOrthScoreWeights.vue). |  |
| MODO-32 | Frase de leitura da nota por modo | defasado | #719 (E5) | Frase de leitura por modo. | `S/scoring/human_insight.rb:1` |
| MODO-33 | Texto do modo no detalhe do lead | ausente no c2 | #719 (E5) | Frase do Orth no detalhe depois da virada (corpo do #719 e nota da E5 na #705). |  |
| MODO-34 | Tom do selo de estrela no card muda com o modo | ausente no c2 | #706 (E2) | Selo de nota do card lê o modo da busca. | `F/components/search/LeadCard.vue:48` |
| MODO-35 | Fator negativo 'inactive_gbp' só no modo GMN | só no c2 | preservado |  | `S/lead_scorer.rb:163` |
| MODO-36 | Tour guiado com texto por modo | ausente no c2 | #682 (E6) | Tour guiado (frente B): os textos de modo, jogada e decisor mudam entre GMN e Geral. | `F/utils/searchTour.js:13`, `F/utils/searchTour.js:60` |
| MODO-37 | Modo gravado em cada lead e em cada busca | igual | preservado |  |  |
| MODO-38 | Modo entra na chave do cache de busca | só no c2 | preservado | Modo e filtros na chave do cache. | `S/search_runner.rb:70` |
| MODO-39 | Ofertas de serviço que definem os pesos (7 globais, só no GMN) | divergente | fora (decisão 25/09) | Decisão de 25/09 (#732, comentário no #676): fica fora; as ofertas viram perfis do catálogo. |  |
| MODO-40 | Pesos customizados valem mesmo sem oferta | divergente | preservado |  |  |
| MODO-41 | Perfis de score globais geridos pelo superadmin | só no c2 | #719 (E5) | Catálogo global preservado e perfil restrito a contas (decisão de 25/09). | `M/scoring_profile_account.rb:22` |
| MODO-42 | Pesos customizados por conta com 8 sinais | só no c2 | #719 (E5) | Pesos próprios mapeados para 6 componentes; query_relevance e google_rank saem (decisão de 25/09 na #681). | `S/scoring/weight_mapping.rb:2` |
| MODO-43 | Perfis de busca (field mask econômico/completo) | igual | fora (decisão) | Plano rev.7: não portar, é código morto ou legado que a tela atual do Orth não usa. |  |
| MODO-44 | IA que sugere nichos, pesos e gera jogadas a partir das ofertas | ausente no c2 | fora (decisão) | Plano rev.7: não portar agora, no Orth não há tela que use. |  |
| MODO-45 | Diagnóstico de chaves do Google configuradas | igual | #691 (E0) | Chave passou a ser da plataforma; a tela mostra só o estado. | `C/settings_controller.rb:50` |
| MODO-46 | Assistente lê o modo da empresa | ausente no c2 | pendente | Assistente (Guia) lendo o modo da empresa: sem etapa dona no épico. |  |
| MODO-47 | Módulo de prospecção liberado por conta pelo superadmin | só no c2 | preservado |  | `config/routes.rb:1079` |
| MODO-48 | Pesos de score por jogada salva | ausente no c2 | fora (decisão) | Plano rev.7: não portar pesos por jogada salva. |  |
| MODO-49 | Perfil de score gravado em cada busca | só no c2 | pendente | O runner ainda aceita scoring_profile_id do cliente; pendência registrada pela E5 na #705. | `S/search_runner.rb:725` |
| MODO-50 | Um só estado de filtro para formulário de nova busca e para refino dos resultados | divergente | #699 (E1) | Filtros da nova busca e refino da busca aberta deixaram de dividir o estado (corpo do #699). |  |
| MODO-51 | Detalhes técnicos da nota para o superadmin: modo, pesos contextuais e multiplicador de tração | ausente no c2 | #732 (E8), decisão 25/09 | Decisão de 25/09 (#732, comentário no #676): vira código na E8: o bloco técnico da nota fica só para administrador. |  |

## Onde buscar (50)

| ID | Capacidade | Situação original | Destino | Nota | Conferido |
|---|---|---|---|---|---|
| LOCAL-01 | Campo de nicho em texto livre, obrigatorio para buscar | igual | preservado |  |  |
| LOCAL-02 | Montagem do textQuery enviado ao Google Places | divergente | pendente | O textQuery ainda leva o texto do local (registrado em "Fora deste PR" do #706). | `S/providers/google_places_provider.rb:119` |
| LOCAL-03 | Autocomplete de local (sugestoes enquanto digita) | divergente | #699 (E1) | Autocomplete com país e idioma da conta. | `S/providers/google_places_location.rb:57` |
| LOCAL-04 | Restringir o autocomplete ao pais da conta | ausente no c2 | #699 (E1) |  | `S/providers/google_places_location.rb:52` |
| LOCAL-05 | Obter as coordenadas do local escolhido | igual | preservado | Com idioma e região do país desde o #699. | `S/providers/google_places_location.rb:34` |
| LOCAL-06 | Geocodificacao de reserva quando a pessoa digita o local e nao escolhe sugestao | ausente no c2 | pendente | Não existe geocodificação de reserva (nenhuma ocorrência de geocod no código da prospecção). |  |
| LOCAL-07 | Comportamento quando o autocomplete falha ou nao ha chave | divergente | #699 (E1) | Erro visível nas sugestões de local (corpo do #699). A saída pela geocodificação depende de LOCAL-06. |  |
| LOCAL-08 | Raio em km (entrada e limites) | divergente | pendente | O servidor não corta o raio pedido; só o viés enviado ao Google tem teto. | `S/search_runner.rb:465`, `S/search_area.rb:11` |
| LOCAL-09 | Enviar o raio ao Places como locationBias em circulo | igual | preservado |  |  |
| LOCAL-10 | Pre-visualizar o raio no mapa antes de buscar | igual | preservado |  |  |
| LOCAL-11 | Botao mostrar/ocultar mapa da area | ausente no c2 | pendente | Não há botão de mostrar e ocultar o mapa no formulário. |  |
| LOCAL-12 | Desenhar um circulo no mapa para definir a area | ausente no c2 | #706 (E2) | Formas editáveis do núcleo do Maps; a Drawing Library saiu do ar. | `F/utils/googleMapsLoader.js:4` |
| LOCAL-13 | Desenhar um retangulo no mapa | ausente no c2 | #706 (E2) | Retângulo desenhado (SearchAreaDrawMap.vue). |  |
| LOCAL-14 | Buscar na area visivel do mapa | só no c2 | preservado |  |  |
| LOCAL-15 | Desenho livre (poligono) com filtro ponto dentro do poligono | ausente no c2 | #706 (E2) | Polígono com ponto no polígono. | `S/search_area.rb:42` |
| LOCAL-16 | Texto de ajuda do modo desenhar | ausente no c2 | #706 (E2) | Ajuda do desenho (Desfazer último ponto, Limpar desenho), segundo a nota da E2 na #705. |  |
| LOCAL-17 | Seletor do tipo de area | divergente | #706 (E2) | Tipos de área sem select nativo. |  |
| LOCAL-18 | Expansao automatica de raio quando faltam resultados | igual | #732 (E8, frente C) | Como no Orth: ligada por padrão, uma tentativa com o dobro do raio, teto de 10 km, só na busca por raio com centro, e a busca fica com a expansão só se ela trouxer mais lugares que passam nos filtros. A caixa desliga, e a busca grava `radius_expanded` e mostra "X km, ampliado de Y km" no histórico e nos resultados. Prova: `spec/services/autonomia/prospecting/search_runner_radius_expansion_spec.rb` com as páginas reais do Google. | `S/search_runner.rb:218` |
| LOCAL-19 | Registro de que o raio foi expandido | só no c2 | preservado |  | `S/search_runner.rb:96` |
| LOCAL-20 | Cobrir a area com varias paginas do Places (ate 60 lugares) | ausente no c2 | #706 (E2) | Até 3 páginas de 20. | `S/providers/google_places_provider.rb:29` |
| LOCAL-21 | Cobertura por tiles (varios centros para passar do limite de 60) | ausente no c2 | fora (decisão) | Plano rev.7: não portar ladrilhos, não rodam no Orth. |  |
| LOCAL-22 | Configurar o pais da busca por conta (tela) | ausente no c2 | #699 (E1) | País por conta (metadata search_country, sem coluna nova). | `S/search_country.rb:1` |
| LOCAL-23 | Idioma e regiao do Places derivados do pais da conta | divergente | #699 (E1) |  | `S/providers/google_places_provider.rb:121` |
| LOCAL-24 | Pais gravado no lead | divergente | #699 (E1) | Lead deixa de nascer marcado como Brasil (corpo do #699: país por conta). |  |
| LOCAL-25 | Cidade e UF do lead | só no c2 | #699 (E1) | Cidade e UF do addressComponents, sem regex. | `S/providers/google_places_provider.rb:10` |
| LOCAL-26 | Log de auditoria de pais invalido ou diferente de BR | ausente no c2 | #699 (E1) | Log de país inválido guardado. | `M/setting.rb:153` |
| LOCAL-27 | Carregar o script do Google Maps no navegador | divergente | #691 (E0) | Chave de navegador da plataforma; formas do núcleo no #706. | `M/setting.rb:88` |
| LOCAL-28 | Chave do Google Places no servidor | divergente | #691 (E0) | Chave do Places só da plataforma. | `M/setting.rb:75` |
| LOCAL-29 | Aviso quando falta chave ou o mapa nao carrega | igual | preservado |  |  |
| LOCAL-30 | Gravar a area e o rotulo do local na busca | igual | preservado | Formato do c2 estendido para polígono no #706. |  |
| LOCAL-31 | Recarregar ou reexecutar a area de uma busca do historico | ausente no c2 | #706 (E2) | Repetir e Editar restauram a área, inclusive o desenho (useSearchRepeat.js). |  |
| LOCAL-32 | Rotulo da area no card do historico | igual | #706 (E2) | Histórico mostra Área desenhada com o tipo (nota da E2 na #705). |  |
| LOCAL-33 | Cache de busca repetida por impressao digital da area | só no c2 | preservado | Área desenhada entrou na chave do cache no #706. |  |
| LOCAL-34 | Provedor simulado (mock) para buscar sem Google | só no c2 | preservado | Mock só para desenvolvimento e teste. | `S/providers/mock_provider.rb:86` |
| LOCAL-35 | Ordenar resultados por distancia do centro | ausente no c2 | #706 (E2) | Ordenar por distância. | `F/utils/sortLeads.js:6` |
| LOCAL-36 | Mapa de resultados com marcadores clicaveis | divergente | #706 (E2) | Pinos agrupados. | `F/components/ProspectingGoogleMap.vue:4` |
| LOCAL-37 | Tour guiado que preenche nicho, local e raio | ausente no c2 | #682 (E6) | Tour pré-preenche nicho, local e raio (exemplo restaurante, Moema, 3 km); sugestão do Google só no clique em "Ver sugestões do local", sem chamada paga automática. | `F/composables/useSearchTour.js:35`, `F/utils/searchTour.js:10` |
| LOCAL-38 | Vies da busca pelo endereco da empresa (geocodeCompanyAddress) | ausente no c2 | fora (decisão) | Plano rev.7: não portar, é código morto ou legado que a tela atual do Orth não usa. |  |
| LOCAL-39 | Autocomplete em dois campos, cidade e bairro | ausente no c2 | fora (decisão) | Plano rev.7: não portar, é código morto ou legado que a tela atual do Orth não usa. |  |
| LOCAL-40 | Proxy de foto do Google Places | ausente no c2 | fora (decisão) | Plano rev.7: a busca do Orth não usa o proxy de foto. |  |
| LOCAL-41 | Geocodificacao reversa (coordenada vira nome e endereco) | ausente no c2 | fora (decisão) | Plano rev.7: fora da busca. |  |
| LOCAL-42 | O centro da busca por raio e o do local escolhido, nao o do mapa arrastado | divergente | #682 (E6) | No modo raio o centro do pedido e o do círculo da prévia saem da mesma função: o do local escolhido ou, numa busca salva reaberta para repetir ou editar, o centro que ela usou, como o `mapCenter` do Orth (`BuscaClient.tsx`). Arrastar a prévia não muda mais a busca; na área visível segue valendo o que a prévia mostra. Testes em `ProspectingSearchPage.form.spec.js` e `.repeat.spec.js`. | `F/composables/searchSlices/locationSlice.js:21`, `F/composables/searchSlices/locationSlice.js:49`, `F/composables/useSearchLocation.js:151` |
| LOCAL-43 | Buscar no Google desde o primeiro uso, sem provedor simulado por padrao | divergente | #691 (E0) | google_places passou a ser o padrão (migration 20260925100000); conta 17 migrada em produção. |  |
| LOCAL-44 | Bairro do lead e filtro por bairro e por cidade | ausente no c2 | #699 (E1) | Bairro gravado no lead. O filtro por bairro e cidade não foi portado (ver FILTRO-14). | `S/providers/google_places_provider.rb:186` |
| LOCAL-45 | Sessao de autocomplete (session token) entre sugestoes e detalhes | divergente | pendente | Não há session token no autocomplete. |  |
| LOCAL-46 | Escolher sugestao de local pelo teclado | divergente | pendente | Campo de local sem navegação por teclado WAI-ARIA (SearchWhereFields.vue sem keydown nem combobox). |  |
| LOCAL-47 | Telefone do lead normalizado conforme o pais | divergente | #699 (E1) | Telefone pelo país da conta. | `S/phone_contract.rb:23` |
| LOCAL-48 | Aviso de que nomes e enderecos vem no idioma do provedor | ausente no c2 | pendente | Não há aviso de idioma do provedor na tela. |  |
| LOCAL-49 | Mensagem amigavel para erro do Google Places | ausente no c2 | #691 (E0) | Erro do Google em português pelo status. | `S/providers/google_places_location.rb:79` |
| LOCAL-50 | Textos da tela de busca em mais de um idioma | divergente | #682 (E6) | Textos da prospecção em pt_BR (frente C): erros da tela, carregando, prévia do mapa, fonte, validade do cache; recusas do servidor com frase em pt_BR e código em campo separado. | `app/javascript/dashboard/i18n/locale/en/prospecting.json:4`, `config/locales/pt_BR.yml:874` |

## Filtros (40)

| ID | Capacidade | Situação original | Destino | Nota | Conferido |
|---|---|---|---|---|---|
| FILTRO-01 | Filtro Site: tem ou não tem site (gs hasWebsite, c2 has_website) | igual | #699 (E1) | Site no grupo da gaveta; repeso do peso site veio no #719. | `F/components/search/filters/LeadFiltersPanel.vue:95` |
| FILTRO-02 | Filtro Telefone: tem ou não tem (gs hasPhone, c2 has_phone) | igual | #699 (E1) | Telefone no grupo Operacional; repeso no #719. |  |
| FILTRO-03 | Mínimo de reviews (gs userRatingCountMin, c2 reviews_min) | igual | #699 (E1) | Mínimo de avaliações no grupo Qualificação; repeso no #719. |  |
| FILTRO-04 | Avaliação: 'Acima de' ou 'Abaixo de' N estrelas (gs ratingMin/ratingMax, c2 rating_min/rating_max) | divergente | #699 (E1) | Operador de avaliação; lead sem nota passa no rating_max. | `F/components/search/filters/LeadFiltersPanel.vue:142`, `S/search_runner.rb:530` |
| FILTRO-05 | Posição máxima no Google (gs searchRankMax, c2 search_rank_max) | defasado | #699 (E1) | Faixa de posição com duas alças. | `F/components/search/filters/RankRangeSlider.vue:2` |
| FILTRO-06 | Fora do top N no Google (gs outsideTop), alça esquerda do slider, com compensação de coleta | ausente no c2 | #699 (E1) | outside_top no motor. | `S/search_runner.rb:132` |
| FILTRO-07 | Janela de rank como preferência + aviso 'ampliamos a janela de rank de X para Y' | ausente no c2 | fora (decisão 25/09) | Decisão de 25/09 (#732, comentário no #676): fica fora; a janela de rank continua rígida. |  |
| FILTRO-08 | Filtro 'Tem horário' (gs hasOpeningHours) | ausente no c2 | #699 (E1) | Tem horário. | `S/search_runner.rb:520` |
| FILTRO-09 | Filtro 'Aberto agora' (gs openNow, c2 open_now) | divergente | #699 (E1) | Aberto agora lido do lugar. | `S/search_runner.rb:519` |
| FILTRO-10 | Filtro Fotos (gs hasPhotos, c2 has_photos) | divergente | #699 (E1) | Com foto sim e não. | `S/search_runner.rb:548` |
| FILTRO-11 | Mínimo de fotos (gs photosMin) | ausente no c2 | pendente | photos_min não existe no motor. |  |
| FILTRO-12 | Tem reviews (gs hasReviews) | ausente no c2 | pendente | has_reviews não existe no motor. |  |
| FILTRO-13 | Reviews recentes (gs hasRecentReviews) | ausente no c2 | fora (decisão 25/09) | Decisão de 25/09 (#732, comentário no #676): ficam fora, por serem filtros de jogada sem tela. |  |
| FILTRO-14 | Bairro em / Cidade em (gs neighborhoodIn, cityIn) | ausente no c2 | fora (decisão 25/09) | Decisão de 25/09 (#732, comentário no #676): ficam fora, por serem filtros de jogada sem tela. |  |
| FILTRO-15 | Esconder sinal fraco (gs hideWeakSignal) | ausente no c2 | pendente | hide_weak_signal não existe no motor. |  |
| FILTRO-16 | Score mínimo (gs scoreMin) | ausente no c2 | pendente | score_min não existe no motor. |  |
| FILTRO-17 | Expansão automática de raio (gs allowRadiusExpansion, c2 auto_expand_radius) | igual | #732 (E8, frente C) | Como no Orth: ligada por padrão, uma tentativa com o dobro do raio, teto de 10 km, só na busca por raio com centro, e a busca fica com a expansão só se ela trouxer mais lugares que passam nos filtros. A caixa desliga, e a busca grava `radius_expanded` e mostra "X km, ampliado de Y km" no histórico e nos resultados. Prova: `spec/services/autonomia/prospecting/search_runner_radius_expansion_spec.rb` com as páginas reais do Google. |  |
| FILTRO-18 | Total desejado (quantidade de leads por busca) | defasado | #706 (E2) | Total pedido até 60, com o teto de 20 removido no #691. | `S/providers/google_places_provider.rb:26` |
| FILTRO-19 | Seletor 'Tipo de decisor' no card 'Decisor e quantidade' | ausente no c2 | #699 (E1) | Tipo de decisor enviado e gravado na busca. | `S/search_runner.rb:728` |
| FILTRO-20 | Disponibilidade de cada perfil de decisor vinda do backend, com rótulo 'em breve' | ausente no c2 | #699 (E1) | Perfis com rótulo em breve. A lista é fixa no front (valores do backend), não vem da API. | `F/utils/decisionMakerTypes.js:29` |
| FILTRO-21 | Tipo de decisor chega ao motor de pesquisa e ao painel do lead | ausente no c2 | #709 (E3) | Tipo de decisor chega à pesquisa. | `S/research/runner.rb:112` |
| FILTRO-22 | Seletor de decisor desativado quando a pesquisa de decisores não está liberada | ausente no c2 | pendente | O seletor desliga só os perfis sem executor; não olha se a pesquisa está liberada na conta. | `F/utils/decisionMakerTypes.js:30` |
| FILTRO-23 | Gaveta de filtros avançados em 4 grupos por intenção comercial | defasado | #699 (E1) | Gaveta em 4 grupos. | `F/components/search/filters/LeadFiltersPanel.vue:10` |
| FILTRO-24 | Rascunho com Aplicar, Limpar tudo e Salvar como jogada na gaveta | defasado | #699 (E1) | Rascunho com Aplicar e Limpar tudo. | `F/components/search/filters/LeadFiltersPanel.vue:3` |
| FILTRO-25 | Contador de filtros ativos | divergente | #699 (E1) | Contador de filtros ativos. | `F/components/search/SearchAdvancedFilters.vue:25` |
| FILTRO-26 | Combinação filtro + preset (jogada) | ausente no c2 | #699 (E1) | Merge com jogada e regra de desmarcar. Jogada salva segue pendente (MODO-25). |  |
| FILTRO-27 | Salvar filtros atuais como jogada, com resumo em etiquetas | ausente no c2 | #732 (E8), decisão 25/09 | Entregue na E8, frente B: a janela de salvar e a grade mostram o resumo dos filtros em etiquetas. O servidor aceita só as chaves da gaveta, com os valores dela (schema em SavedPresetFilters), exige ao menos um filtro e recusa o resto. | `F/utils/searchPresets.js:112`, `S/saved_preset_filters.rb:24` |
| FILTRO-28 | Filtros gravados na busca e restaurados ao reabrir ou reexecutar | igual | #706 (E2) | Repetir e Editar restauram filtros, decisor, jogada, quantidade e ordem (nota da E2 na #705). |  |
| FILTRO-29 | País e idioma da busca no provider | defasado | #699 (E1) | País por conta no provider. |  |
| FILTRO-30 | Catálogo completo do FilterBuilder (acordeões, filtros rápidos, aviso min>max) | ausente no c2 | fora (decisão) | Plano rev.7: não portar a tela FilterBuilder. |  |
| FILTRO-31 | Refiltrar na tela os leads já carregados, pelo painel de filtros do resultado | só no c2 | preservado | Refino dos resultados preservado; estado separado desde o #699. |  |
| FILTRO-32 | Filtros avançados na tela de Listas (listar e adicionar lead) | só no c2 | preservado | Filtros avançados na tela de Listas (advancedLeadFilters.js). |  |
| FILTRO-33 | Cache de busca que considera os filtros | só no c2 | preservado |  |  |
| FILTRO-34 | Limites diário e mensal de consultas por conta | só no c2 | #691 (E0) | Limites diário e mensal deixaram de barrar (corpo do #691). As colunas ficaram no banco. |  |
| FILTRO-35 | Os filtros ativos repesam o score: o critério que o filtro já garante deixa de pesar, e os pesos são renormalizados para 100 | ausente no c2 | #719 (E5) | Repeso pelos filtros ativos. | `S/scoring/component_score.rb:4` |
| FILTRO-36 | O bônus de 'aberto agora' na prioridade é desligado quando o filtro openNow está ativo | divergente | #719 (E5) | Bônus de aberto agora desligado com o filtro. | `S/scoring/priority.rb:20` |
| FILTRO-37 | Leads 'queimados' (já cliente de outro vendedor da casa) não viram cartão na busca | ausente no c2 | #732 (E8), decisão 25/09 | Decisão de 25/09 (#732, comentário no #676): vira código na E8, com o lead "já no CRM" no lugar do bloqueio por vendedor. |  |
| FILTRO-38 | A posição no Google é guardada por busca, e não sobrescrita por buscas seguintes | divergente | #699 (E1) | Nota, posição e prioridade guardadas por busca (corpo do #699; metadata lead_scoring). | `S/search_runner.rb:92` |
| FILTRO-39 | Teste do motor de filtros | defasado | #699 (E1) | Filtros provados com resposta real gravada do Google (corpo do #699). |  |
| FILTRO-40 | Modo 'guaranteed' com ladrilhos (tile-generator) e continuação por nextPageToken | ausente no c2 | fora (decisão) | Plano rev.7: não portar, é código morto ou legado que a tela atual do Orth não usa. |  |

## Motor da busca (59)

| ID | Capacidade | Situação original | Destino | Nota | Conferido |
|---|---|---|---|---|---|
| MOTOR-01 | Paginação no Google Places com pageToken até atingir o total pedido | ausente no c2 | #706 (E2) | Paginação por nextPageToken. | `S/providers/google_places_provider.rb:24` |
| MOTOR-02 | Teto de leads por busca (60) e tamanho de página (20) | divergente | #706 (E2) | Teto de 60 e página de 20; max_results_per_search deixou de ser lido pelo motor (só o schema o cita). | `S/providers/google_places_provider.rb:120` |
| MOTOR-03 | Expansão automática de raio quando faltam resultados | igual | #732 (E8, frente C) | Como no Orth: ligada por padrão, uma tentativa com o dobro do raio, teto de 10 km, só na busca por raio com centro, e a busca fica com a expansão só se ela trouxer mais lugares que passam nos filtros. A caixa desliga, e a busca grava `radius_expanded` e mostra "X km, ampliado de Y km" no histórico e nos resultados. Prova: `spec/services/autonomia/prospecting/search_runner_radius_expansion_spec.rb` com as páginas reais do Google. |  |
| MOTOR-04 | Texto da consulta enviado ao Google e viés de localização | divergente | pendente | textQuery ainda leva o local (Fora deste PR do #706). |  |
| MOTOR-05 | País e idioma da busca vindos da configuração da empresa | ausente no c2 | #699 (E1) | País por conta no provider. | `S/providers/google_places_provider.rb:122` |
| MOTOR-06 | Campos pedidos ao Google (field mask) | defasado | #699 (E1) | Field mask com addressComponents e googleMapsUri; nextPageToken no #706. |  |
| MOTOR-07 | Bairro e cidade do lead | divergente | #699 (E1) | Bairro e cidade do addressComponents. | `S/providers/google_places_provider.rb:32` |
| MOTOR-08 | Posição no Google (search_rank) atribuída antes dos filtros | defasado | #706 (E2) | Posição real de 1 a 60 entre páginas. |  |
| MOTOR-09 | Filtro 'só até a posição N no Google' (searchRankMax) | igual | preservado | Vale para posições acima de 20 desde o #706. |  |
| MOTOR-10 | Filtro 'fora do top N' (outsideTop) com coleta ampliada | ausente no c2 | #699 (E1) | outside_top com meta de coleta. | `S/search_runner.rb:133` |
| MOTOR-11 | Soft cap da janela de rank com banner 'ampliamos a janela' | ausente no c2 | fora (decisão 25/09) | Decisão de 25/09 (#732, comentário no #676): fica fora; a janela de rank continua rígida. |  |
| MOTOR-12 | Filtro de score mínimo depois da pontuação (scoreMin) | ausente no c2 | pendente | score_min não existe no motor. |  |
| MOTOR-13 | Filtros com foto e aberto agora executados no servidor | divergente | #699 (E1) | Foto e aberto agora no servidor, com fixture real. |  |
| MOTOR-14 | Demais filtros aplicados na coleta (horário, fotos mínimas, com avaliações, avaliações recentes, bairro, cidade, sinal fraco) | ausente no c2 | pendente | Tem horário entrou no #699; fotos mínimas, com avaliações, avaliações recentes, bairro e cidade não existem no motor. |  |
| MOTOR-15 | Filtros do preset (jogada) mesclados aos da tela | ausente no c2 | #699 (E1) | Jogada aceita, validada e mesclada. |  |
| MOTOR-16 | Deduplicação e persistência do lead preservando o enriquecimento | divergente | preservado | Dedupe por place_id e reserva do c2. |  |
| MOTOR-17 | Cartão privado por vendedor, herança de dados objetivos entre colegas e contagem de coexistência | divergente | #732 (E8), decisão 25/09 | Decisão de 25/09 (#732, comentário no #676): vira código na E8, com o lead "já no CRM" no lugar do bloqueio por vendedor. |  |
| MOTOR-18 | Bloqueio de lead 'queimado' (já cliente de outro vendedor) | ausente no c2 | #732 (E8), decisão 25/09 | Decisão de 25/09 (#732, comentário no #676): vira código na E8, com o lead "já no CRM" no lugar do bloqueio por vendedor. |  |
| MOTOR-19 | Cálculo da Prioridade (posição 'ligar primeiro') | defasado | #719 (E5) | Prioridade do Orth (contato, decisor, aberto agora, penalidades, percentil). | `S/scoring/priority.rb:17` |
| MOTOR-20 | Ordenação na tela: opções | defasado | #706 (E2) | Ordenações novas. | `F/utils/sortLeads.js:50` |
| MOTOR-21 | Ordenar por distância do centro (distance_km) | ausente no c2 | #706 (E2) | Distância. |  |
| MOTOR-22 | Ordenar por posição no Google | ausente no c2 | #706 (E2) | Posição no Google, começando da 1ª. |  |
| MOTOR-23 | Inverter a direção da ordenação (crescente/decrescente) | ausente no c2 | #706 (E2) | Botão que inverte a direção (ResultsFiltersPopover.vue). |  |
| MOTOR-24 | Chave do Google Places usada na busca | divergente | #691 (E0) | Chave da plataforma. | `S/search_runner.rb:265` |
| MOTOR-25 | Contagem de chamadas ao Google por busca | igual | preservado | Soma por página desde o #706. | `S/search_runner.rb:69` |
| MOTOR-26 | Mostrar 'N chamadas à API' no título dos resultados | ausente no c2 | pendente | A tela não mostra N chamadas nem os selos do cache e do raio ampliado; só o aviso de busca parcial. |  |
| MOTOR-27 | Agendamento automático da pesquisa de decisor/empresa para todos os leads da busca | ausente no c2 | #709 (E3) | Pesquisa enfileirada ao fim da busca. | `S/research/queue.rb:17` |
| MOTOR-28 | Tipo de decisor pedido na busca (quem o Radar procura) | ausente no c2 | #699 (E1) | Tipo de decisor na busca, levado à pesquisa no #709. |  |
| MOTOR-29 | Barra de progresso da pesquisa ('X de Y itens concluídos', 'Solicitados · Google retornou · Persistidos · Agendados') | ausente no c2 | #709 (E3) | Barra X de Y sem texto de créditos. | `F/components/search/SearchResults.vue:203` |
| MOTOR-30 | Verificação automática de WhatsApp dos telefones após a busca | defasado | #706 (E2) | Verificação de WhatsApp em job por lote. | `S/lead_work_queue.rb:46` |
| MOTOR-31 | O que é gravado em cada lead da busca | defasado | #699 (E1) | Colunas novas no lead (migration 20260925110000). | `S/providers/google_places_provider.rb:207` |
| MOTOR-32 | O que é gravado na busca | igual | preservado | Com preset_id desde o #699. |  |
| MOTOR-33 | Continuar a busca (próxima página) na mesma busca | ausente no c2 | fora (decisão) | Plano rev.7: não portar agora; o total vem numa chamada. |  |
| MOTOR-34 | Cancelar a busca anterior ao disparar outra | divergente | preservado |  |  |
| MOTOR-35 | Mensagens de erro do Google em português | ausente no c2 | #691 (E0) | Erro do Google em português. |  |
| MOTOR-36 | Histórico de buscas: listar com paginação | igual | preservado | Jogada no card do histórico desde o #699. |  |
| MOTOR-37 | Visibilidade do histórico por hierarquia | ausente no c2 | #732 (E8), decisão 25/09 | Decisão de 25/09 (#732, comentário no #676): vira código na E8: o agente vê só as próprias buscas. Hoje tudo é por conta. |  |
| MOTOR-38 | Abrir o resultado de uma busca antiga | igual | preservado | Valores por busca ao reabrir desde o #699/#706. |  |
| MOTOR-39 | Reexecutar busca do histórico | ausente no c2 | #706 (E2) | Repetir do histórico com os parâmetros originais, sem cache (decisão do Rodrigo no #706). |  |
| MOTOR-40 | Cache de busca idêntica por fingerprint e TTL | só no c2 | preservado |  |  |
| MOTOR-41 | Provider mock para desenvolvimento e teste | só no c2 | preservado | Mock devolve fotos e horário. | `S/providers/mock_provider.rb:102` |
| MOTOR-42 | Status da busca e registro do erro | só no c2 | pendente | Status e erro preservados; o card do histórico ainda não mostra falhou (SearchHistory.vue sem status). |  |
| MOTOR-43 | Retrato fixo dos leads de cada busca (lead_ids) | só no c2 | preservado |  |  |
| MOTOR-44 | Destino de CRM (funil e estágio) por busca | só no c2 | preservado | Vira sugestão da janela de envio no #714. |  |
| MOTOR-45 | Ordenação persistida na busca e opções Nome e Data | só no c2 | preservado |  |  |
| MOTOR-46 | Limites diários e mensais de chamadas por conta | só no c2 | #691 (E0) | Limites deixaram de barrar. |  |
| MOTOR-47 | Medição, cota e reconciliação de uso da busca (cobrança) | ausente no c2 | fora (decisão) | Decisão do Rodrigo (24/09): sem cobrança, sem créditos, sem trava de consumo e sem gate de plano. |  |
| MOTOR-48 | Busca por polígono desenhado (filtro ponto-no-polígono) | ausente no c2 | #706 (E2) | Polígono recortado depois da posição. |  |
| MOTOR-49 | Rota de diagnóstico da chave do Google (só hiper_admin) | ausente no c2 | pendente | Não há botão testar chave no superadmin (opcional no plano). |  |
| MOTOR-50 | Busca garantida por ladrilhos (oversampling) | ausente no c2 | fora (decisão) | Plano rev.7: não portar, é código morto ou legado que a tela atual do Orth não usa. |  |
| MOTOR-51 | Limite de raio (0 a 50 km) | defasado | pendente | Raio sem corte no servidor (ver LOCAL-08). |  |
| MOTOR-52 | Cache devolve busca que falhou (ou ainda pendente) como resultado vazio | só no c2 | #691 (E0) | Cache só de busca concluída; parcial não vira cache. | `S/search_runner.rb:72` |
| MOTOR-53 | Filtrar antes de cortar no total pedido | divergente | #706 (E2) | Filtro antes do corte. | `S/search_runner.rb:85` |
| MOTOR-54 | Pedir o nextPageToken no FieldMask | ausente no c2 | #706 (E2) |  | `S/providers/google_places_provider.rb:24` |
| MOTOR-55 | Rank, score e Prioridade guardados por busca (não só no lead) | divergente | #706 (E2) | Nota, prioridade e posição por busca no metadata (sem tabela de junção). | `S/search_runner.rb:92` |
| MOTOR-56 | Chamadas ao Google fora da transação do banco | divergente | #706 (E2) | A transação só envolve o upsert e o save da busca. | `S/search_runner.rb:62` |
| MOTOR-57 | Provider padrão de conta nova | divergente | #691 (E0) | Padrão google_places; mock só em teste e desenvolvimento. |  |
| MOTOR-58 | Atualização ao vivo de cada lead da lista (site, decisor, WhatsApp) | ausente no c2 | #706 (E2) | Evento prospecting.lead.updated. | `S/lead_payload.rb:2` |
| MOTOR-59 | Exportar uma busca do histórico gerada no servidor | defasado | #682 (E6) | Export da busca gerado no servidor (frente A): GET .../searches/:id/export?format=csv ou xlsx. | `config/routes.rb:388`, `C/searches_controller.rb:84` |

## Enriquecimento e WhatsApp (72)

| ID | Capacidade | Situação original | Destino | Nota | Conferido |
|---|---|---|---|---|---|
| ENRIQ-01 | Enriquecimento dispara sozinho ao abrir o detalhe do lead (auto_open), sem clique | divergente | #706 (E2) | Enriquecimento entra na fila ao fim da busca, quando a pesquisa está ligada. | `S/lead_work_queue.rb:36` |
| ENRIQ-02 | Botão manual Enriquecer no card, com estados Enriquecendo e Enriquecido e motivo de desabilitado (sem site, desligado) | só no c2 | preservado |  |  |
| ENRIQ-03 | Enriquecimento assíncrono: responde 202 na hora e processa em segundo plano | divergente | #706 (E2) | EnrichLeadJob; endpoint responde 202. | `S/lead_work_queue.rb:26` |
| ENRIQ-04 | Supressão de gatilho automático duplicado para o mesmo lead em 120 s | ausente no c2 | #706 (E2) | Pedido duplicado recusado (corpo do #706). |  |
| ENRIQ-05 | Regra de quando refazer o scrape (leadNeedsSiteScrape) | divergente | #706 (E2) | Falha retomável com contador de tentativas. |  |
| ENRIQ-06 | Site fora do ar ou HTTP de erro conta como falha, não como sucesso | divergente | #706 (E2) | Site fora do ar vira falha. | `S/lead_enricher.rb:178` |
| ENRIQ-07 | Novo scrape vazio ou com erro não apaga dados capturados antes | ausente no c2 | #706 (E2) | Merge que não apaga o que o enriquecimento anterior achou. | `S/enrichment_merge.rb:8` |
| ENRIQ-08 | Contador de tentativas de scrape que falharam | ausente no c2 | #706 (E2) | Coluna enrichment_failed_attempts (migration 20260925120000). | `S/enrichment_merge.rb:41` |
| ENRIQ-09 | Motor de leitura do site com navegador headless (renderiza JavaScript) | divergente | fora (decisão 25/09) | Decisão de 25/09 (#732, comentário no #676): fica fora; navegador real só depois de medir. O scraper continua HTTP. |  |
| ENRIQ-10 | Tempo limite de abertura do site | divergente | #706 (E2) | Prazo por etapa e total. | `S/safe_page_fetcher.rb:18` |
| ENRIQ-11 | User agent de navegador real | divergente | #706 (E2) | User agent de navegador. | `S/safe_page_fetcher.rb:19` |
| ENRIQ-12 | Proxy Webshare com teste de conexão e queda para sem proxy | ausente no c2 | fora (decisão) | Plano rev.7: não portar agora, o proxy está inativo no Orth. |  |
| ENRIQ-13 | Guarda de URL: só http/https e sem usuário/senha na URL | divergente | #706 (E2) | URL com usuário embutido recusada (#476). | `app/services/autonomia/agents/knowledge/url_guard.rb:70` |
| ENRIQ-14 | Guarda de URL: nomes internos bloqueados | divergente | #706 (E2) | Nomes internos bloqueados. | `app/services/autonomia/agents/knowledge/url_guard.rb:83` |
| ENRIQ-15 | Guarda de URL: faixas de IP privadas e reservadas | divergente | #706 (E2) | IPv4 mapeado em IPv6 bloqueado. | `app/services/autonomia/agents/knowledge/url_guard.rb:48` |
| ENRIQ-16 | Guarda de URL: falha de DNS bloqueia | divergente | #706 (E2) | Resolução vazia bloqueia. | `app/services/autonomia/agents/knowledge/url_guard.rb:93` |
| ENRIQ-17 | Fixação do IP validado (anti DNS rebinding) e guarda em cada navegação | divergente | #706 (E2) | IP fixado na conexão. | `S/safe_page_fetcher.rb:8` |
| ENRIQ-18 | Política de redirecionamento | divergente | #706 (E2) | Revalidação por salto mantida no fetcher novo. |  |
| ENRIQ-19 | Só o HTML principal é baixado, sem subrecursos | igual | preservado |  |  |
| ENRIQ-20 | Limite de tamanho do HTML lido | só no c2 | #706 (E2) | Corpo limitado durante o download. | `S/safe_page_fetcher.rb:14` |
| ENRIQ-21 | Site do lead é um perfil do Instagram | ausente no c2 | pendente | Atalho de site Instagram não portado; o scraper continua com o site_link simples. | `S/website_scraper.rb:59` |
| ENRIQ-22 | Instagram escolhido pela zona da página, com nível de confiança | divergente | pendente | Classificação por zona e confiança não portadas. | `S/website_scraper.rb:126` |
| ENRIQ-23 | Facebook escolhido por zona, aceitando fb.com e m.facebook.com | divergente | pendente | fb.com e m.facebook.com não aceitos (compara host exato). | `S/website_scraper.rb:60` |
| ENRIQ-24 | LinkedIn pessoal (/in/) priorizado sobre a página da empresa | divergente | pendente | LinkedIn aceita /in/ e /company/ sem prioridade. | `S/website_scraper.rb:139` |
| ENRIQ-25 | WhatsApp extraído do site | divergente | pendente | WhatsApp do site ainda pega o primeiro link, sem zona. | `S/website_scraper.rb:119` |
| ENRIQ-26 | Ignora links de compartilhamento (sharer, intent) | igual | pendente | O filtro de compartilhamento não inclui send?text= no WhatsApp. |  |
| ENRIQ-27 | Limpeza da URL de rede social (utm, ref, âncora, www, m.) | ausente no c2 | pendente | Limpeza de URL de rede social não portada no scraper (CompanyUpserter só limpa utm no domínio). |  |
| ENRIQ-28 | CNPJ formatado encontrado no site | igual | preservado |  |  |
| ENRIQ-29 | E-mail do site | só no c2 | preservado |  |  |
| ENRIQ-30 | Título, descrição, telefone do site, trecho de texto e links de origem | só no c2 | preservado |  |  |
| ENRIQ-31 | Diagnóstico do scrape e trace opcional | ausente no c2 | pendente | Contadores de diagnóstico do scrape não existem. |  |
| ENRIQ-32 | Mensagem de erro de site legível | divergente | pendente | Conferido: não feito. O erro do enriquecimento é gravado (`S/lead_enricher.rb:174`) e vai no payload do lead, mas nenhuma tela o lê nem o traduz. Sem etapa dona. | |
| ENRIQ-33 | WhatsApp achado no site é verificado no WAHA durante o enriquecimento | ausente no c2 | #706 (E2) | WhatsApp do site verificado. | `S/whatsapp_verifier.rb:10` |
| ENRIQ-34 | WhatsApp do site confirmado entra na lista de telefones do lead e vira o botão WhatsApp | ausente no c2 | #706 (E2) | Botão WhatsApp e Ligar usam o número do site confirmado (nota da E2 na #705). |  |
| ENRIQ-35 | Verificação automática do telefone do Google logo após a busca | divergente | #706 (E2) | Verificação no servidor ao fim da busca. |  |
| ENRIQ-36 | Verificação ao abrir o detalhe, com vários candidatos (Google, internacional, site) | ausente no c2 | #706 (E2) | Candidatos do Google e do site verificados no job, não ao abrir o painel. |  |
| ENRIQ-37 | Rota de verificação que só grava se o número existe, com códigos de erro distintos | divergente | pendente | Conferido: não feito. Todo erro da verificação volta 422 com a chave do erro (`C/leads_controller.rb:105`); número inválido e WAHA fora não se separam. Sem etapa dona. | |
| ENRIQ-38 | Qual sessão WAHA faz a checagem | divergente | fora (decisão 25/09) | Decisão de 25/09 (#732, comentário no #676): fica fora; a verificação segue na sessão WAHA da conta. |  |
| ENRIQ-39 | Resultado negativo e falha da verificação ficam gravados | só no c2 | preservado |  |  |
| ENRIQ-40 | Selo WhatsApp verificado ao lado do telefone | divergente | #706 (E2) | Selo verificado ao lado do telefone (LeadPhoneActions.vue). | `F/components/search/LeadCardActions.vue:107` |
| ENRIQ-41 | Botão WhatsApp em três estados e estado Verificando | igual | preservado |  |  |
| ENRIQ-42 | Botões de Instagram, Facebook e LinkedIn no card da lista | ausente no c2 | #706 (E2) | Instagram, Facebook e LinkedIn no card. | `F/components/search/LeadCardActions.vue:108` |
| ENRIQ-43 | Bloco Dados do site com links clicáveis e selo de confiança do WhatsApp | divergente | #706 (E2) | Links clicáveis no painel. O selo de confiança do WhatsApp não existe (ver ENRIQ-22). |  |
| ENRIQ-44 | Aviso de dados do site pendentes ou em processamento | divergente | #706 (E2) | Card mostra na fila e Enriquecendo. |  |
| ENRIQ-45 | Atualização ao vivo do lead quando enriquecimento ou verificação termina | ausente no c2 | #706 (E2) | Atualização ao vivo. |  |
| ENRIQ-46 | Enriquecimento em lote por API | ausente no c2 | #706 (E2) | Lote pela fila ao fim da busca; sem rota avulsa de lote. |  |
| ENRIQ-47 | Rotina agendada de reenriquecimento | ausente no c2 | pendente | Não há rotina agendada de reenriquecimento; os falhos antigos não são refeitos sozinhos. |  |
| ENRIQ-48 | Segunda fase do lote: decisor via Perplexity com cobrança | divergente | fora (decisão) | Decisão do Rodrigo (24/09): sem cobrança, sem créditos, sem trava de consumo e sem gate de plano. |  |
| ENRIQ-49 | Uso de IA no enriquecimento | divergente | preservado | IA só na credencial crm_kanban_ai desde o #691. | `S/ai_credential.rb:7` |
| ENRIQ-50 | Resumo comercial do lead | só no c2 | preservado |  |  |
| ENRIQ-51 | Chave liga/desliga do enriquecimento por conta | só no c2 | #691 (E0) | Interruptor passou ao superadmin. | `C/settings_controller.rb:2` |
| ENRIQ-52 | Status do enriquecimento com datas e erro | só no c2 | preservado |  |  |
| ENRIQ-53 | Normalização de telefone por biblioteca, com país | divergente | #699 (E1) | telephone_number com país. | `S/phone_contract.rb:2` |
| ENRIQ-54 | Telefone nacional e internacional guardados e exibidos formatados | divergente | #699 (E1) | Contrato de telefone nos cinco pontos. |  |
| ENRIQ-55 | Telefone do contato criado no Chatwoot a partir do lead | divergente | #699 (E1) | Mesma normalização no contato; o #714 prefere o WhatsApp verificado. |  |
| ENRIQ-56 | Lista estruturada de telefones do lead com principal de WhatsApp e gravação atômica | divergente | #706 (E2) | Telefone do Google e WhatsApp do site com verificação própria cada um, o do site vira o principal quando o do Google não é WhatsApp, e a gravação é atômica no jsonb. Diferente do Orth: não é uma lista com rótulo por número. | `S/whatsapp_verifier.rb:8`, `S/lead_payload.rb:83`, `S/whatsapp_verifier.rb:94` |
| ENRIQ-57 | Gravação final do enriquecimento não apaga telefones gravados em paralelo | divergente | #682 (E6) | A verificação grava só a sua chave no jsonb desde o #706, a gravação final do enriquecimento não toca o metadata (`S/lead_enricher.rb:72`) e agora a busca refeita também soma no banco só as chaves que traz, em vez de regravar o metadata lido antes; o verificador grava sob a trava da linha. A pesquisa de empresa e decisor (#679) também regrava o metadata do lead, mas depois de `lock!`, que recarrega a linha travada (`S/research/lead_writer.rb:23`): uma verificação que termina no meio espera a trava e soma a sua chave depois, sem se perder. | `S/search_runner.rb:344`, `S/whatsapp_verifier.rb:94` |
| ENRIQ-58 | Pular número já verificado e tentar de novo após falha | divergente | #706 (E2) | Nova tentativa quando a verificação falhou. | `S/lead_work_queue.rb:58` |
| ENRIQ-59 | Observabilidade estruturada do enriquecimento | ausente no c2 | pendente | Sem log estruturado de início, fim e duração do enriquecimento. |  |
| ENRIQ-60 | Registro de eventos em log de aplicação | igual | #732 (E8, frente C) | Log estruturado do Rails, sem tabela: `[Autonomia::Prospecting::Event]` + JSON com evento, lead_id, account_id, motivo, origem e desfecho, no enriquecimento (LeadEnricher, EnrichLeadJob) e na verificação de WhatsApp (WhatsappVerifier, VerifyWhatsappJob). Motivo de exceção é a classe, nunca a mensagem; telefone, e-mail, chat e chave não entram. `S/event_log.rb` |  |
| ENRIQ-61 | Log de depuração da verificação de WhatsApp ligado por variável | ausente no c2 | pendente | O job loga só o erro da verificação, sem chave de depuração. | `J/verify_whatsapp_job.rb:29` |
| ENRIQ-62 | Consulta avulsa de WhatsApp de qualquer número | ausente no c2 | fora (decisão) | Plano rev.7: uso é do CRM, não da prospecção. |  |
| ENRIQ-63 | Seletor de país e metadados de telefone da sessão de conexão WhatsApp | divergente | fora (decisão) | Plano rev.7: fora da prospecção. |  |
| ENRIQ-64 | Checagem de hierarquia de dono antes de enriquecer ou verificar | divergente | preservado | Escopo por conta. |  |
| ENRIQ-65 | Verificação de WhatsApp na página de Listas | só no c2 | #706 (E2) | Listas também usam a fila e o evento ao vivo. |  |
| ENRIQ-66 | WhatsApp verificado aumenta a contactabilidade no score | igual | preservado | Contactabilidade entra na prioridade do Orth no #719. |  |
| ENRIQ-67 | Testes automatizados de scraper, guarda de URL, telefone e verificação | ausente no c2 | #691 (E0) | Testes de caracterização antes de mexer (#691) e specs do scraper seguro (#706). |  |
| ENRIQ-68 | Dados do enriquecimento chegam ao CRM e à campanha (e-mail, WhatsApp do site, redes, CNPJ, decisor, resumo) | ausente no c2 | #714 (E4) | E-mail, WhatsApp, redes, CNPJ, decisor e resumo levados ao contato e ao card. | `S/crm_card_converter.rb:65` |
| ENRIQ-69 | Verificação de WhatsApp amarrada ao número verificado, não ao lead | divergente | #682 (E6) | Busca refeita que traz outro telefone tira a verificação que não é do número novo (E.164), decidido no próprio UPDATE sobre o metadata da hora, e o lead volta à fila de verificação da E2 no fim da busca; a do WhatsApp do site e a de um telefone que não mudou ficam. O verificador só grava se o lead ainda tem o número consultado (E.164, com a linha travada); se o número mudou no meio, solta a marca "queued" antiga e põe o número novo na fila, em vez de deixar o lead em "Verificando" até o reaper, e a verificação manual responde pendente. | `S/search_runner.rb:13`, `S/search_runner.rb:344`, `S/whatsapp_verifier.rb:94`, `S/whatsapp_verifier.rb:109`, `C/leads_controller.rb:102` |
| ENRIQ-70 | Reaproveitamento do enriquecimento em buscas repetidas | igual | preservado |  |  |
| ENRIQ-71 | Status running sem dono após queda da requisição | divergente | #706 (E2) | ReaperJob devolve running antigo a falha. | `S/lead_work_queue.rb:6` |
| ENRIQ-72 | Quem pode disparar enriquecimento e verificação | divergente | #706 (E2) | Disparo automático roda no servidor, sem depender de quem abriu a tela. |  |

## Card do lead e resultados (59)

| ID | Capacidade | Situação original | Destino | Nota | Conferido |
|---|---|---|---|---|---|
| CARD-01 | Anel de prioridade 0-100 no card; sem prioridade mostra traço | divergente | #706 (E2) | O anel mostra só a prioridade (nota da E2 na #705). |  |
| CARD-02 | Faixa textual da prioridade (Lead muito quente, Oportunidade alta, Lead morno, Prioridade baixa) | igual | preservado |  |  |
| CARD-03 | Selo G #N (posição no Google) | igual | preservado |  |  |
| CARD-04 | Texto Posição N (fila de ação) | igual | preservado |  |  |
| CARD-05 | Selo Ligar 1º | igual | preservado |  |  |
| CARD-06 | Nome da empresa no card | igual | preservado |  |  |
| CARD-07 | Bairro ao lado da faixa de prioridade | divergente | #706 (E2) | Bairro no card. |  |
| CARD-08 | Chip de site (Tem site/Sem site) | divergente | #706 (E2) | Chip Tem site. |  |
| CARD-09 | Chip de telefone (Tem fone/Sem fone) | igual | preservado |  |  |
| CARD-10 | Chip de fotos (Sem foto, Pouca foto, N fotos) | ausente no c2 | #706 (E2) | Fotos em quatro faixas. |  |
| CARD-11 | Chip #N Google | igual | preservado |  |  |
| CARD-12 | Chip de rating | divergente | #706 (E2) | Nota em 4 faixas por modo. | `F/components/search/LeadCard.vue:48` |
| CARD-13 | Ordem e teto de 4 sinais | divergente | #706 (E2) | Ordem e teto de 4 sinais. |  |
| CARD-14 | Chip de avaliações (N avaliações) | só no c2 | preservado | Entra só se couber no teto (#706). |  |
| CARD-15 | Número de telefone exibido no card, formatado | ausente no c2 | #706 (E2) | Telefone formatado no card. |  |
| CARD-16 | Marca verificado ao lado do telefone (WhatsApp confirmado) | divergente | #706 (E2) | Selo verificado. |  |
| CARD-17 | Botão WhatsApp (sólido se verificado, contorno se não) | divergente | #706 (E2) | Botão WhatsApp com número verificado. |  |
| CARD-18 | Normalização do telefone para links wa.me e tel: | divergente | #699 (E1) | PhoneContract no lugar da regex. |  |
| CARD-19 | Botão Ligar | igual | preservado |  |  |
| CARD-20 | Verificação automática de WhatsApp ao abrir a busca | só no c2 | #706 (E2) | Verificação passou para o servidor. |  |
| CARD-21 | Botões Instagram, Facebook, LinkedIn no card | ausente no c2 | #706 (E2) | Redes no rodapé do card. | `F/components/search/LeadCardActions.vue:108` |
| CARD-22 | Abrir detalhe: card inteiro clicável e botão Abrir | divergente | #706 (E2) | Card inteiro abre e fecha o painel. | `F/components/search/LeadCard.vue:72` |
| CARD-23 | Realce visual do card aberto | ausente no c2 | #706 (E2) | Card aberto realçado. | `F/components/search/LeadCard.vue:81` |
| CARD-24 | Faixa Já é cliente de <vendedor> até <data> e checkbox bloqueado (lead queimado) | ausente no c2 | #732 (E8), decisão 25/09 | Decisão de 25/09 (#732, comentário no #676): vira código na E8, com o lead "já no CRM" no lugar do bloqueio por vendedor. |  |
| CARD-25 | Selos Empresa: <estado> e Decisor: <estado> | ausente no c2 | #709 (E3) | Selos Empresa e Decisor. | `F/components/search/LeadResearchSummary.vue:62` |
| CARD-26 | Linha Decisor: com estados (Aguardando capacidade, Pesquisa em andamento, não concluída, nome · cargo, Possível decisor, Não confirmado, Pesquisa desativada, Não pesquisado) | divergente | #709 (E3) | Linha do decisor muda com o estado. |  |
| CARD-27 | NN% de confiança do decisor | ausente no c2 | #709 (E3) | Confiança em %. |  |
| CARD-28 | verificado em <data> do decisor | ausente no c2 | #709 (E3) | Verificado em DD/MM/AAAA. | `S/research/payload.rb:21` |
| CARD-29 | resultado reutilizado | ausente no c2 | #709 (E3) | Resultado reutilizado. | `S/research/payload.rb:43` |
| CARD-30 | Bloco Enriquecimento concluído com resumo no card | só no c2 | preservado | Bloco mantido; o decisor da IA sai quando há pesquisa nova (#709). |  |
| CARD-31 | Botão Enriquecer no card | só no c2 | preservado |  |  |
| CARD-32 | Botão Mapa (abre Google Maps) | só no c2 | #706 (E2) | Mapa abre o googleMapsUri. | `S/lead_payload.rb:97` |
| CARD-33 | Abrir contato, Abrir card e Criar card no próprio card | só no c2 | #714 (E4) | Criar card virou Enviar ao CRM; Abrir contato e Abrir card ficam. |  |
| CARD-34 | Checkbox de seleção por card | divergente | #706 (E2) | Checkbox com aria-label. Esconder para queimado depende de CARD-24. | `F/components/search/LeadCard.vue:146` |
| CARD-35 | Selecionar todos | divergente | #714 (E4) | Selecionar visíveis coerente com o filtro. |  |
| CARD-36 | Contador de selecionados | igual | #714 (E4) | Contador igual ao que é enviado. |  |
| CARD-37 | Limpar seleção | ausente no c2 | pendente | Não existe botão Limpar seleção (BulkActionsBar.vue só tem selecionar visíveis). |  |
| CARD-38 | Enviar selecionados ao CRM | divergente | #714 (E4) |  |  |
| CARD-39 | Adicionar selecionados à campanha | ausente no c2 | #714 (E4) | Adicionar à campanha a partir da seleção. | `F/pages/ProspectingSearchPage.vue:14` |
| CARD-40 | Exportar CSV | defasado | #682 (E6) | CSV do servidor (frente A): BOM UTF-8, ponto e vírgula, 35 colunas; célula que começa com =, +, -, @, %, barra vertical, tab ou CR ganha apóstrofo. Fica de fora a coluna Dist km do Orth. | `S/export/csv_file.rb:9`, `S/export/cell.rb:14` |
| CARD-41 | Exportar Excel (.xlsx) | ausente no c2 | #682 (E6) | Excel .xlsx mínimo montado com rubyzip (frente A): texto em inlineStr, sem fórmula; o que começa como fórmula leva o estilo quotePrefix em vez do apóstrofo do CSV, e o telefone +55 sai limpo. | `S/export/xlsx_file.rb:55` |
| CARD-42 | Aviso de idioma misto do provedor | ausente no c2 | pendente | Não há aviso de idioma misto. |  |
| CARD-43 | Título com total de resultados e chamadas de API | divergente | pendente | Título não mostra as chamadas à API. |  |
| CARD-44 | Mapa de resultados com clique no pino abrindo o lead | igual | preservado |  |  |
| CARD-45 | Agrupamento de pinos (cluster) | ausente no c2 | #706 (E2) | markerclusterer 2.6.2. |  |
| CARD-46 | Pinos numerados | só no c2 | #706 (E2) | Número do pino é a Posição N. |  |
| CARD-47 | Área da busca desenhada no mapa de resultados | só no c2 | preservado |  |  |
| CARD-48 | Mostrar/ocultar mapa de resultados | ausente no c2 | pendente | Não há mostrar e ocultar o mapa de resultados. |  |
| CARD-49 | Mensagem de chave do mapa ausente | igual | preservado |  |  |
| CARD-50 | Mapa estático de um ponto (MapPin) | ausente no c2 | fora (decisão) | Plano rev.7: não portar, é código morto ou legado que a tela atual do Orth não usa. |  |
| CARD-51 | Grade de 2 colunas com drawer fechado | ausente no c2 | pendente | Lista em uma coluna (SearchResults.vue:162); grade de 2 colunas não feita. |  |
| CARD-52 | Ordenação dos resultados | divergente | #706 (E2) | Ordenações novas e direção. |  |
| CARD-53 | Estados de carregando, vazio e sem resultado no filtro | igual | preservado |  |  |
| CARD-54 | Atualização ao vivo do card (pesquisa, site, WhatsApp) | ausente no c2 | #706 (E2) | Card ao vivo. |  |
| CARD-55 | Barra de progresso da pesquisa em lote acima da lista (N de M itens concluídos, em andamento/concluído) | ausente no c2 | #709 (E3) | Barra de progresso. |  |
| CARD-56 | Contador de selecionados e Selecionar visíveis coerentes com o filtro aplicado | divergente | #714 (E4) | Contador coerente com o filtro. |  |
| CARD-57 | Resultado honesto do envio em lote ao CRM | divergente | #714 (E4) | Resumo criados, existentes e falhas. | `F/components/crm/CrmSendModal.vue:14` |
| CARD-58 | Mudar status do lead (qualificado, descartado com motivo) e criar contato a partir do resultado | só no c2 | #732 (E8), decisão 25/09 | Decisão de 25/09 (#732, comentário no #676): vira código na E8, com descartar o lead e criar contatos a partir do resultado. |  |
| CARD-59 | Escopo de visibilidade dos resultados e da exportação por hierarquia | divergente | #732 (E8), decisão 25/09 | Decisão de 25/09 (#732, comentário no #676): vira código na E8: o agente vê só as próprias buscas. Hoje tudo é por conta. |  |

## Painel do lead e pesquisa (47)

| ID | Capacidade | Situação original | Destino | Nota | Conferido |
|---|---|---|---|---|---|
| PAINEL-01 | Componente de pesquisa (DecisionResearchPanel) embutido no drawer do lead, com os blocos Quem atende, Empresa, Pesquisa de decisores e os cards Dados da empresa e Decisores | divergente | #709 (E3) | Bloco de pesquisa no painel. | `F/components/search/LeadDetailDrawer.vue:183` |
| PAINEL-02 | Resumo da nota: card de prioridade com anel e texto human_insight (ou 'Score base N') | igual | preservado | Texto human_insight do Orth na conta virada (#719). |  |
| PAINEL-03 | Cabeçalho do drawer: selo G #rank, 'Posição N da sua lista', selo 'Ligar primeiro', nome e endereço | igual | preservado |  |  |
| PAINEL-04 | Acessibilidade do drawer: role=dialog, aria-modal, foco no botão fechar, trap de Tab, Escape fecha, trava de scroll do body e retorno do foco | defasado | pendente | Painel sem role=dialog, aria-modal, foco e Escape (LeadDetailDrawer.vue). |  |
| PAINEL-05 | Bloco 'Quem atende': lista de candidatos a decisor (nome · cargo) | divergente | #709 (E3) | Quem atende com o vínculo de cada sócio. |  |
| PAINEL-06 | Botão 'Usar como contato' por candidato (adota o decisor como contato do lead) | ausente no c2 | #714 (E4) | Usar como contato. | `C/leads_controller.rb:139` |
| PAINEL-07 | Candidato vindo de cadastro anterior: aviso 'Dado anterior · verifique novamente para selecionar' | ausente no c2 | pendente | Candidato "dado anterior" não foi criado; o #709 só solta o decisor antigo em dois casos. |  |
| PAINEL-08 | Bloco Empresa: Razão social | ausente no c2 | #709 (E3) | Razão social. |  |
| PAINEL-09 | Bloco Empresa: Nome fantasia, mostrado só quando difere da razão social | ausente no c2 | #709 (E3) | Nome fantasia quando difere. |  |
| PAINEL-10 | Bloco Empresa: CNPJ formatado com botão copiar | defasado | #709 (E3) | CNPJ com copiar. | `F/components/search/LeadResearchCompany.vue:41` |
| PAINEL-11 | Bloco Empresa: Situação cadastral e UF de registro | ausente no c2 | #709 (E3) | Situação e UF. | `S/research/registry/brasil_api_parser.rb:15` |
| PAINEL-12 | Alerta 'Empresa com situação X na Receita' (role=alert) | ausente no c2 | #709 (E3) | Alerta de situação. |  |
| PAINEL-13 | Cabeçalho 'Pesquisa de decisores' com botão Pesquisar decisores / Verificar decisores novamente / Pesquisando… | divergente | #709 (E3) | Pesquisar e Verificar novamente. |  |
| PAINEL-14 | Confirmação 'Refazer pesquisa?' preservando resultado anterior e edições manuais | ausente no c2 | #709 (E3) | Confirmação Refazer pesquisa sem frase de cobrança. |  |
| PAINEL-15 | Motor: descoberta de CNPJ candidato por nome e telefone na BigDataCorp (conta nossa) | ausente no c2 | #709 (E3) | BigDataCorp com credencial da plataforma. | `S/research/big_data_corp_client.rb:18` |
| PAINEL-16 | Motor: completar dados do CNPJ em cadastros públicos gratuitos (OpenCNPJ, BrasilAPI, CNPJ.ws, CNPJá) e extrair o QSA | ausente no c2 | #709 (E3) | Quatro cadastros públicos, 1 MB, hosts fixos. | `S/research/registry/http_transport.rb:12` |
| PAINEL-17 | Motor: regra de quem é dono (QSA pessoa física adulta; sócio-administrador, sócio, titular etc. antes de administrador ou diretor; empresário individual pela razão social) | divergente | #709 (E3) | Regra do dono sem IA. | `S/research/owner_policy.rb:32` |
| PAINEL-18 | Motor: sinal do site para corroborar o CNPJ (site-scraper do pipeline) | defasado | #709 (E3) | CNPJ do site como sinal (Research::SiteCnpj). |  |
| PAINEL-19 | Papel procurado: seletor de cargo (Proprietário mais 10 papéis 'em breve') e recusa de papel sem executor | ausente no c2 | #699 (E1) | Seletor no formulário, Proprietário ativo e os demais em breve; guarda no servidor no #709. | `S/research/owner_policy.rb:43` |
| PAINEL-20 | Fila durável: POST responde 202, job em radar_research_jobs, cron /api/cron/research-queue pega os itens por RPC com lease de 300 s | divergente | #709 (E3) | ResearchJob na fila prospecting; 202. |  |
| PAINEL-21 | Estados da pesquisa por capacidade: Não pesquisado, Na fila, Em pesquisa, Aguardando capacidade, Confirmado, Possível, Ambíguo, Nenhum resultado, Falha técnica, Bloqueado | defasado | #709 (E3) | Estados por capacidade (research/states.rb). |  |
| PAINEL-22 | Atualização ao vivo do painel: Realtime nas projeções, com polling de reserva (5, 10, 20, 30 s) e anúncio aria-live | ausente no c2 | #709 (E3) | Evento lead.updated leva o bloco research. |  |
| PAINEL-23 | Mensagens de bloqueio: desativada na empresa, provedor não configurado, falha ('A última pesquisa não pôde ser concluída'), lead sem nome (MISSING_COMPANY_NAME) | defasado | #709 (E3) | Mensagens de bloqueio sem código interno. |  |
| PAINEL-24 | Liga e desliga as capacidades empresa e decisor por conta (radar_ai_feature_settings); as duas precisam estar ligadas para rodar | divergente | #691 (E0) | Interruptor da pesquisa no superadmin. | `config/routes.rb:1080` |
| PAINEL-25 | Reaproveitamento de resultado por 90 dias ('Resultado reutilizado' / 'Pesquisa atualizada em DD/MM/AAAA') | ausente no c2 | #709 (E3) | Reaproveitamento por 90 dias. | `S/research/reuse.rb:7` |
| PAINEL-26 | Texto de cobrança nos cards (billingCopy), créditos cobrados, 'Cobrança em apuração', 'Saldo insuficiente', 'Orçamento bloqueado', aguardando capacidade por AI_SPEND_* | ausente no c2 | fora (decisão) | Decisão do Rodrigo (24/09): sem cobrança, sem créditos, sem trava de consumo e sem gate de plano. |  |
| PAINEL-27 | Dados do site: WhatsApp, Instagram, Facebook e LinkedIn como ícones clicáveis, CNPJ do site e estados 'coletando' / erro de acesso | defasado | #706 (E2) | Redes e WhatsApp como links. A coleta ao abrir o painel não existe; ela roda ao fim da busca. |  |
| PAINEL-28 | Verificação de WhatsApp ao abrir o drawer, testando todos os telefones candidatos (incluindo o WhatsApp do site) | defasado | #706 (E2) | Verificação inclui o WhatsApp do site, no job. |  |
| PAINEL-29 | Banner de lead queimado (cliente de outro vendedor) e aviso de coexistência (colegas trabalhando o mesmo lead) | ausente no c2 | #732 (E8), decisão 25/09 | Decisão de 25/09 (#732, comentário no #676): vira código na E8, com o lead "já no CRM" no lugar do bloqueio por vendedor. |  |
| PAINEL-30 | Sinais do GBP em grade 4 colunas com rating e total de reviews no cabeçalho | divergente | pendente | Grade de 4 colunas do Orth não conferida no painel; nenhum PR cita. |  |
| PAINEL-31 | Últimas 5 avaliações | igual | preservado |  |  |
| PAINEL-32 | Detalhes técnicos do score (modo, score base, priority, traction, componentes, pesos, penalizações, flags) só para hiper_admin | só no c2 | preservado | Card técnico mantido aberto por enquanto; pela decisão de 25/09 (MODO-51, PLAT-05), o bloco técnico passa a ser só do administrador na #732 (E8). |  |
| PAINEL-33 | Resumo de IA do lead (enrichment_summary) e e-mail do site (enriched_email) | só no c2 | preservado |  |  |
| PAINEL-34 | Categoria, etapa do CRM, coordenadas, motivo de descarte e links Abrir contato / Abrir card no drawer | só no c2 | preservado | A etapa do CRM no painel ainda é a da busca, não a do card (ver ACAO-15). |  |
| PAINEL-35 | Adicionar ao CRM no drawer com escolha de funil e etapa | divergente | #714 (E4) | Enviar ao CRM no painel abre funil e estágio. |  |
| PAINEL-36 | Caminho antigo de decisor via Perplexity (extractDecision), pipeline Apify, webhook de pesquisa e cron de reconciliação | ausente no c2 | fora (decisão) | Plano rev.7: não portar, é código morto ou legado que a tela atual do Orth não usa. |  |
| PAINEL-37 | Pesquisa de decisor em lote disparada pela própria busca, com barra 'X de Y itens concluídos' | ausente no c2 | #709 (E3) | Pesquisa em lote disparada pela busca. |  |
| PAINEL-38 | Selos 'Empresa' e 'Decisor' com estado da pesquisa, confiança, data de verificação e 'resultado reutilizado' no card da lista | defasado | #709 (E3) | Selos na linha da lista, na busca e nas Listas. |  |
| PAINEL-39 | Projeção do resultado da pesquisa no próprio lead (dados da empresa e estado do decisor) para lista, CSV e CRM | ausente no c2 | #709 (E3) | Colunas da pesquisa no lead (migration 20260925140100). |  |
| PAINEL-40 | Exportação CSV com CNPJ do cadastro (prioridade sobre o do site), razão social, fantasia, situação, decisor, LinkedIn e Instagram do decisor, confiança, papel e data | defasado | #682 (E6) | Export com CNPJ do cadastro acima do do site, razão social, fantasia, situação, UF, decisor (nome, cargo, confiança, LinkedIn, Instagram), sócios e data da pesquisa (frente A). Empresa e decisor só com a empresa confirmada, pelo mesmo Research::Payload da tela. | `S/export/table.rb:76` |
| PAINEL-41 | Painel de empresa e decisor também dentro do lead no CRM, e dados do decisor e da empresa levados ao contato e ao card | ausente no c2 | #714 (E4) | Decisor, CNPJ e razão social no contato e no card. |  |
| PAINEL-42 | Segunda superfície no C2: a tela de Listas também tem botão Enriquecer e card de enriquecimento | divergente | #682 (E6) | Listas usam o mesmo LeadCard e LeadDetailDrawer da busca (frente B): enriquecer, pesquisa, adotar sócio, WhatsApp e estágio padrão do CRM; o #709 já tinha posto o resumo da pesquisa nas Listas. | `F/pages/ProspectingListsPage.vue:802`, `F/pages/ProspectingListsPage.vue:1321` |
| PAINEL-43 | Estados vazios e de carregamento do painel | ausente no c2 | #709 (E3) | Estados do painel de pesquisa: pesquisando, falha, bloqueada, nunca pesquisado e motivo de não haver decisor, cada um com frase própria e testado. Sem o esqueleto de carregamento do Orth. | `F/components/search/LeadDetailResearch.vue:66`, `F/specs/components/LeadDetailResearch.spec.js:414` |
| PAINEL-44 | Rede social do decisor presa à pessoa certa | divergente | #709 (E3) | Rede do decisor nunca cai para a da empresa. |  |
| PAINEL-45 | Confiança e fonte do decisor gravadas mas invisíveis no C2 | defasado | #709 (E3) | Confiança e data visíveis. |  |
| PAINEL-46 | Documentação do produto no C2 descreve o Enriquecer antigo | só no c2 | #705 | Central de Ajuda e Guia no lote único da #705 (decisão de 25/09). |  |
| PAINEL-47 | Cobertura de testes do painel e do motor | defasado | #709 (E3) | Specs do job, parsers, regra do dono e endpoint (1915 exemplos no #709). |  |

## Ações pós-busca, CRM, campanha e tour (57)

| ID | Capacidade | Situação original | Destino | Nota | Conferido |
|---|---|---|---|---|---|
| ACAO-01 | Botão "Enviar ao CRM" na barra de ações em lote, visível quando há leads selecionados | divergente | #714 (E4) | Enviar ao CRM abre a janela. |  |
| ACAO-02 | Modal de envio com escolha de funil e estágio no momento do envio | ausente no c2 | #714 (E4) | Janela de funil e estágio com ChoiceSelect. | `F/pages/ProspectingSearchPage.vue:13` |
| ACAO-03 | Frase de confirmação "Enviando N lead(s) para o funil X, estágio Y" | ausente no c2 | #714 (E4) | Frase Enviando N lead(s). |  |
| ACAO-04 | Estado vazio quando a empresa não tem funil: texto explicativo + link "Criar funil no CRM" | ausente no c2 | #714 (E4) | Estado vazio com Criar funil no CRM. |  |
| ACAO-05 | Motor do envio em lote ao CRM | divergente | #714 (E4) | Lote de até 30, transação por lead. |  |
| ACAO-06 | Feedback do envio em lote | divergente | #714 (E4) | Resumo honesto. | `F/components/crm/CrmSendSummary.vue:67` |
| ACAO-07 | Envio individual ao CRM pelo drawer do lead | divergente | #714 (E4) | Mesma janela no painel. |  |
| ACAO-08 | O que é o "card" do CRM e quais dados ele carrega | divergente | #714 (E4) | Card leva nota, prioridade, posição, decisor e empresa. |  |
| ACAO-09 | Decisor levado ao CRM (nome, cargo, LinkedIn, Instagram, confiança) | ausente no c2 | #714 (E4) | Decisor no contato e no card. |  |
| ACAO-10 | Enriquecimento e empresa levados ao CRM (e-mail, CNPJ, redes, WhatsApp verificado, resumo) | defasado | #714 (E4) | Enriquecimento e empresa no CRM. |  |
| ACAO-11 | Nota no card ao enviar | igual | preservado |  |  |
| ACAO-12 | Dedupe no envio ao CRM e reenvio | divergente | #714 (E4) | Um card por lead; reenvio não cria nada novo (aceite da #680). |  |
| ACAO-13 | Criação/dedupe de contato ao enviar ao CRM | só no c2 | preservado |  |  |
| ACAO-14 | Normalização do telefone do contato criado | só no c2 | #699 (E1) | Normalização única de telefone. |  |
| ACAO-15 | Estágio do CRM exibido no drawer do lead | só no c2 | pendente | O painel ainda mostra o estágio da busca, não o do card. | `F/components/search/LeadDetailDrawer.vue:49` |
| ACAO-16 | Destino de CRM padrão por conta e por busca ("Configurações" da busca) | só no c2 | preservado | Destino da busca vira sugestão da janela (#714). |  |
| ACAO-17 | Evento/webhook ao criar card pela prospecção | só no c2 | preservado |  |  |
| ACAO-18 | Automação de estágio ao entrar no CRM | igual | #714 (E4) | Automação de entrada roda uma vez para card novo. | `S/crm_card_converter.rb:79` |
| ACAO-19 | Permissão e escopo no envio | divergente | #714 (E4) | Servidor exige Crm::CardPolicy#create?; esconder o botão é a frente C desta E6. | `C/base_controller.rb:16` |
| ACAO-20 | Seleção: selecionar todos e limpar seleção | defasado | pendente | Não existe Limpar seleção (ver CARD-37). |  |
| ACAO-21 | Lead queimado (já é cliente de outro vendedor): selo, bloqueio de seleção e ações | ausente no c2 | #732 (E8), decisão 25/09 | Decisão de 25/09 (#732, comentário no #676): vira código na E8, com o lead "já no CRM" no lugar do bloqueio por vendedor. |  |
| ACAO-22 | Liberação manual de lead queimado por admin/gestor | ausente no c2 | #732 (E8), decisão 25/09 | Decisão de 25/09 (#732, comentário no #676): vira código na E8, com o lead "já no CRM" no lugar do bloqueio por vendedor. |  |
| ACAO-23 | Coexistência: "Mais N colegas também trabalham esse lead" | ausente no c2 | fora (decisão) | Plano rev.7: não portar como está. |  |
| ACAO-24 | Painel de duplicatas | ausente no c2 | fora (decisão) | Plano rev.7: não portar; gate de plano fora e o c2 não gera duplicata. |  |
| ACAO-25 | "Adicionar à campanha" direto dos resultados selecionados | ausente no c2 | #714 (E4) | Adicionar à campanha a partir da seleção. |  |
| ACAO-26 | Validação de audiência da campanha com motivo por lead | defasado | #714 (E4) | Motivo por lead bloqueado. |  |
| ACAO-27 | Opt-out respeitado na campanha | divergente | #714 (E4) | Recusa e bloqueio respeitados na guarda da campanha; gravar no contato ficou na #713. | `S/campaign_segment_builder.rb:101` |
| ACAO-28 | Buscas recentes: card com nicho, local, área e tempo relativo | igual | preservado |  |  |
| ACAO-29 | Selo da jogada (preset) com cor e ícone no card do histórico | ausente no c2 | #699 (E1) | Selo da jogada no histórico. |  |
| ACAO-30 | Métricas do histórico: leads e "N enviados ao CRM" | igual | preservado |  |  |
| ACAO-31 | "Ver leads" (reabrir resultado salvo sem custo) e "Repetir busca" | ausente no c2 | #706 (E2) | Repetir e Editar. |  |
| ACAO-32 | Excluir busca do histórico e "Ver mais" | igual | preservado |  |  |
| ACAO-33 | Escopo do histórico por usuário/hierarquia | divergente | #732 (E8), decisão 25/09 | Decisão de 25/09 (#732, comentário no #676): vira código na E8: o agente vê só as próprias buscas. Hoje tudo é por conta. |  |
| ACAO-34 | Listas de prospecção: criar, abrir, remover lead | só no c2 | preservado | Listas preservadas; a #682 (E6) troca card e painel pelos da busca e mantém remover da lista e campanha. |  |
| ACAO-35 | Adicionar lead à lista muda status para ready_for_campaign | só no c2 | pendente | Adicionar à lista ainda muda qualquer status para ready_for_campaign. | `C/lists_controller.rb:36` |
| ACAO-36 | Modal "adicionar leads" limitado aos 100 leads mais recentes | só no c2 | pendente | Modal de adicionar leads segue limitado; adicionar à lista direto da busca só existe pelo caminho da campanha (#714). |  |
| ACAO-37 | Segmento de campanha a partir da lista (etiqueta + campanha one_off) | só no c2 | preservado | Destino de Adicionar à campanha (#714). |  |
| ACAO-38 | Verificação automática de WhatsApp ao abrir listas | só no c2 | #706 (E2) | Verificação no servidor, inclusive para Listas. |  |
| ACAO-39 | Exportar resultados | defasado | #682 (E6) | Botão de download da busca oferece CSV e Excel pelo servidor, com os selecionados ou os visíveis depois do filtro, na ordem da tela (frente A). A lista também exporta (GET .../lists/:id/export); o botão nas Listas não existe ainda, só exportList no cliente da API. | `F/components/search/SearchResults.vue:31`, `app/javascript/dashboard/api/autonomiaProspecting.js:43`, `config/routes.rb:404` |
| ACAO-40 | Tour guiado: disparo automático e persistência | ausente no c2 | #682 (E6) | Tour abre sozinho na primeira visita de quem tem prospecting_manage e grava a marca ao abrir (o Orth marca ao concluir ou pular e só abre para empresa sem busca). | `F/composables/useSearchTour.js:130`, `F/utils/searchTour.js:8` |
| ACAO-41 | Tour: passos de boas-vindas, modo, jogada, decisor com texto por score_mode | ausente no c2 | #682 (E6) | Oito passos: boas-vindas, modo, jogada, local, decisor, filtros, Buscar e resultados; texto por score_mode. | `F/utils/searchTour.js:13`, `F/utils/searchTour.js:30` |
| ACAO-42 | Tour: pré-preenche busca, espera local confirmado, abre/fecha filtros, espera resultados, fecha sozinho | ausente no c2 | #682 (E6) | Pré-preenche o exemplo, espera o local confirmado, abre e fecha a gaveta de filtros, espera busca com leads e fecha sozinho em 3,5 s; a busca só roda no clique em Buscar. | `F/composables/useSearchTour.js:35`, `F/utils/searchTour.js:9` |
| ACAO-43 | Botão "Refazer tour" no rodapé | ausente no c2 | #682 (E6) | Refazer tour no rodapé da tela de busca. | `F/pages/ProspectingSearchPage.vue:112` |
| ACAO-44 | Assistente de IA executar a busca, enviar ao CRM ou montar campanha | só no c2 | preservado | Endpoints novos entram no catálogo do Guia; a bateria é da #705. |  |
| ACAO-45 | Assistente de IA ler configuração de score e progresso do onboarding da busca | divergente | fora (decisão) | Plano rev.7: nada a portar para score; marco de tour depende de ACAO-40. |  |
| ACAO-46 | Assistente de IA levar à tela de busca | igual | preservado |  |  |
| ACAO-47 | Gates de plano nas ações pós-busca (campanha em massa, duplicatas, limite de funis) | divergente | fora (decisão) | Decisão do Rodrigo (24/09): sem cobrança, sem créditos, sem trava de consumo e sem gate de plano. |  |
| ACAO-X01 | Criar card do CRM também na tela de Listas, por lead | só no c2 | #714 (E4) | Enviar lista ao CRM nas Listas. |  |
| ACAO-X02 | O contador de seleção e o que é enviado ou exportado divergem quando há filtro | divergente | #714 (E4) | Seleção coerente com o filtro. |  |
| ACAO-X03 | Escolha de funil, estágio e campanha feita com <select> nativo | divergente | #714 (E4) | Janela com ChoiceSelect; os selects das telas saíram nos #670 e #671. |  |
| ACAO-X04 | Criar só o contato (sem card) a partir do lead | só no c2 | #732 (E8), decisão 25/09 | Decisão de 25/09 (#732, comentário no #676): vira código na E8, com descartar o lead e criar contatos a partir do resultado. |  |
| ACAO-X05 | Descartar lead ou mudar status do lead | só no c2 | #732 (E8), decisão 25/09 | Decisão de 25/09 (#732, comentário no #676): vira código na E8, com descartar o lead e criar contatos a partir do resultado. |  |
| ACAO-X06 | Gestão da lista: excluir, renomear e adicionar leads em lote de verdade | só no c2 | pendente | Excluir e renomear lista e adicionar em lote não estão em nenhuma etapa. |  |
| ACAO-X07 | Score, prioridade e dono do card criado pela prospecção | divergente | #714 (E4) | Card com nota e prioridade. |  |
| ACAO-X08 | IA do gs coloca lead em funil e dispara campanha | divergente | #705 | Casos na bateria do Guia (lote da #705). |  |
| ACAO-X09 | Campanha pela API do WhatsApp alimentada pela prospecção | divergente | #732 (E8), decisão 25/09 | Decisão de 25/09 (#732, comentário no #676): vira código na E8, com a campanha pela API oficial do WhatsApp. O #714 usa campanhas one_off. |  |
| ACAO-X10 | Métricas do histórico calculadas sem carregar todos os leads | divergente | pendente | Métricas do histórico ainda carregam os leads de cada busca. |  |

## Plataforma, chaves e permissões (51)

| ID | Capacidade | Situação original | Destino | Nota | Conferido |
|---|---|---|---|---|---|
| PLAT-01 | Liberar o módulo de prospecção por conta (menu e endpoints) | só no c2 | preservado | Toda rota nova herda o BaseController. | `C/base_controller.rb:2` |
| PLAT-02 | Quem pode usar a busca: papel fixo no gs, papel customizado Ver/Editar no c2 | divergente | preservado | Papel customizado (decisão de 24/09); interruptor de papéis no console no #691. |  |
| PLAT-03 | Semântica de 'Ver' na prospecção: ler sim, buscar não | divergente | preservado | Leitura por GET e escrita por não-GET. |  |
| PLAT-04 | Quem altera a configuração da busca (score, modo GMN, país, chaves) | divergente | preservado | Corte por manage mantido no #719. |  |
| PLAT-05 | Detalhes técnicos do score no drawer do lead (modo, score bruto, fatores negativos) | ausente no c2 | #732 (E8), decisão 25/09 | Decisão de 25/09 (#732, comentário no #676): vira código na E8: o bloco técnico da nota fica só para administrador. |  |
| PLAT-06 | Tour guiado da busca na primeira vez | ausente no c2 | #682 (E6) | Marca prospecting_search_tour_seen_at no ui_settings do usuário. | `F/utils/searchTour.js:8` |
| PLAT-07 | Gate de plano no botão 'Adicionar à campanha' | divergente | #714 (E4) | Sem gate de plano; pôr numa campanha exige campaign_manage, criar só o segmento pede a prospecção (a janela da busca esconde a escolha da campanha sem campaign_manage). | `C/base_controller.rb:32` |
| PLAT-08 | Cota e medição de chamadas ao Google Places | divergente | #691 (E0) | Limites fora; consumed_api_units segue como medição. |  |
| PLAT-09 | Créditos de inteligência (reserva, débito, pacotes, compra, câmbio) | ausente no c2 | fora (decisão) | Decisão do Rodrigo (24/09): sem cobrança, sem créditos, sem trava de consumo e sem gate de plano. |  |
| PLAT-10 | Modo do score (GMN x geral) gravado por lead | igual | preservado |  |  |
| PLAT-11 | Dados cadastrais do CNPJ no lead (razão social, fantasia, situação, abertura, sócios, endereço) | ausente no c2 | #709 (E3) | Dados cadastrais no perfil da empresa (migration 20260925140000). |  |
| PLAT-12 | Estado da pesquisa de decisor no lead | defasado | #709 (E3) | Estado da pesquisa no lead (migration 20260925140100). |  |
| PLAT-13 | Perfil canônico da empresa e candidatos a decisor com fontes e escolha manual | ausente no c2 | #709 (E3) | autonomia_prospecting_company_profiles. | `M/company_profile.rb:3` |
| PLAT-14 | Fila de pesquisa e projeção de capacidade por lead | ausente no c2 | #709 (E3) | Fila por Sidekiq e estado por lead. |  |
| PLAT-15 | Guarda cifrada da resposta bruta dos provedores de pesquisa | ausente no c2 | #709 (E3) | Não se aplica mais: a pesquisa não guarda resposta bruta de provedor, só a lista fechada de campos do cadastro e dos sócios, que o inventário pedia para proteger. Se um dia guardar, vale a nota da revisão (encrypts do Rails com a configuração exigida). | `S/research/profile_attributes.rb:18` |
| PLAT-16 | Registro da busca (histórico) | defasado | #699 (E1) | preset_id no metadata; custo estimado fora por decisão. |  |
| PLAT-17 | Presets de filtros salvos por empresa | ausente no c2 | #732 (E8), decisão 25/09 | Entregue na E8, frente B: tabela própria por conta (nome único na conta sem diferenciar maiúsculas, até 30 por conta, criada sob lock da configuração da conta). Não usa o metadata das configurações porque ele é regravado inteiro pela tela e pelo superadmin. | `M/saved_preset.rb:26` |
| PLAT-18 | Configuração de score por empresa (ofertas ativas, pesos, nichos sugeridos, modo) | defasado | fora (decisão 25/09) | Decisão de 25/09 (#732, comentário no #676): fica fora; as ofertas viram perfis do catálogo. |  |
| PLAT-19 | Catálogo global de critérios de score | divergente | #719 (E5) | Mapeamento dos pesos para os 6 componentes (volume a partir de reviews_count). Ofertas seguem pendentes. |  |
| PLAT-20 | País principal da busca por empresa | ausente no c2 | #699 (E1) | País por conta. |  |
| PLAT-21 | Lead queimado (cliente fechado por outro vendedor bloqueia o place) | ausente no c2 | #732 (E8), decisão 25/09 | Decisão de 25/09 (#732, comentário no #676): vira código na E8, com o lead "já no CRM" no lugar do bloqueio por vendedor. |  |
| PLAT-22 | Chave do Google Places (busca, autocomplete, detalhes) | divergente | #691 (E0) | GOOGLE_PLACES_API_KEY só de plataforma. |  |
| PLAT-23 | Chave do mapa no navegador | divergente | #691 (E0) | GOOGLE_MAPS_BROWSER_API_KEY da plataforma. |  |
| PLAT-24 | IA do score, sugestões e enriquecimento: de quem é a credencial | divergente | #691 (E0) | Só crm_kanban_ai, sem CAPTAIN_OPEN_AI_API_KEY. | `S/ai_credential.rb:4` |
| PLAT-25 | Provedor de pesquisa web de decisor (Perplexity) | ausente no c2 | fora (decisão) | Perplexity está desligado no Orth (nota da revisão) e a #679 definiu as fontes: BigDataCorp, cadastros públicos e regra fixa. |  |
| PLAT-26 | Consulta cadastral (BigDataCorp) com conta nossa | ausente no c2 | #709 (E3) | BigDataCorp com conta nossa. | `S/research/big_data_corp_client.rb:5` |
| PLAT-27 | Provedor de pesquisa de perfis (Apify) | ausente no c2 | fora (decisão) | A #679 definiu as fontes da pesquisa (BigDataCorp, cadastros públicos e regra fixa); Apify não entrou. |  |
| PLAT-28 | Raspagem de site: navegador real e proxy | divergente | fora (decisão 25/09) | Decisão de 25/09 (#732, comentário no #676): fica fora; navegador real só depois de medir. O scraper continua HTTP. |  |
| PLAT-29 | Foto do estabelecimento (proxy do Places Photo) | ausente no c2 | pendente | Não há proxy de foto; o card mostra só a contagem de fotos. |  |
| PLAT-30 | Job de enriquecimento em lote | ausente no c2 | #706 (E2) | Jobs de enriquecimento e reaper no schedule. | `config/schedule.yml:222` |
| PLAT-31 | Job da fila de pesquisa e retomada de pesquisas travadas | ausente no c2 | #709 (E3) | ResearchJob com trava e varredor. |  |
| PLAT-32 | Crons financeiros da busca e da IA | ausente no c2 | fora (decisão) | Decisão do Rodrigo (24/09): sem cobrança, sem créditos, sem trava de consumo e sem gate de plano. |  |
| PLAT-33 | Idiomas da tela de busca | divergente | #682 (E6) | Tela da prospecção em pt_BR (frente C); termos mantidos de propósito: Status, Score, Lead, GMN, Google Places. | `app/javascript/dashboard/i18n/locale/en/prospecting.json:4` |
| PLAT-34 | Idioma da resposta da IA | divergente | pendente | A instrução da IA do enriquecimento não recebe o idioma do usuário ou da conta. |  |
| PLAT-35 | Status do lead no funil de prospecção e motivo do descarte | só no c2 | preservado |  |  |
| PLAT-36 | Envio ao CRM com funil e etapa padrão da conta, e vínculo com contato e card | só no c2 | preservado | Base do envio com funil e estágio do #714. |  |
| PLAT-37 | Dedupe e cache de busca | só no c2 | preservado |  |  |
| PLAT-38 | Provedor mock | só no c2 | preservado | Mock só fora de produção (#691). |  |
| PLAT-39 | Segmento de campanha a partir da lista, e listas com status | só no c2 | preservado |  |  |
| PLAT-40 | Central de Ajuda da prospecção | só no c2 | #705 | Reescrita da Central no lote da #705. |  |
| PLAT-41 | Liga e desliga cada capacidade de IA por empresa, com escolha de modelo e esforço (sugestão de score, enriquecimento de empresa, pesquisa de decisor) | divergente | #691 (E0) | Interruptor da pesquisa no superadmin, que também controla o enriquecimento. Escolha de modelo não entrou. |  |
| PLAT-42 | Endpoint de disponibilidade da pesquisa (a tela sabe se a pesquisa de empresa e a de decisor podem rodar) | ausente no c2 | #691 (E0) | Settings mostra o estado da plataforma, da pesquisa e da IA. | `C/settings_controller.rb:52` |
| PLAT-43 | Hidratação cadastral por fontes públicas gratuitas (OpenCNPJ, BrasilAPI, CNPJ.ws, CNPJá) com fallback em cadeia | ausente no c2 | #709 (E3) | Cadastros públicos em cascata. | `S/research/registry/open_cnpj_parser.rb:20` |
| PLAT-44 | Retenção e limpeza dos dados de pesquisa (payload bruto, candidatos não adotados, perfis órfãos, nonces) | ausente no c2 | fora (decisão) | Decisão do Rodrigo de 25/09 na #679: não apagar nada; a regra de retenção saiu do aceite. |  |
| PLAT-45 | Trava por empresa pesquisada, registro de execuções e reuso do perfil com validade | ausente no c2 | #709 (E3) | Trava por empresa e reuso. | `S/research/company_lock.rb:25` |
| PLAT-46 | Atualização em tempo real da tela (leads da busca, presets, novas buscas, progresso da pesquisa) | ausente no c2 | #706 (E2) | Evento ao vivo (lead); progresso da pesquisa no #709. |  |
| PLAT-48 | Permissões cruzadas: a prospecção cria contato, cartão no CRM, etiqueta e mexe no público de campanha | só no c2 | #714 (E4) | Servidor exige a permissão do módulo de destino (#714). A #682 (E6) esconde Enviar ao CRM sem Crm::CardPolicy#create? e Adicionar à campanha sem campaign_manage (can_send_to_crm e can_manage_campaigns em C/settings_controller.rb:68). |  |
| PLAT-49 | Abrir a prospecção por link direto ou F5 | divergente | #688 (fecha #675) | Link direto e F5 abrem a tela certa (fecha #675). |  |
| PLAT-50 | Escolhas da tela sem <select> nativo | defasado | #670 (lote #652) | Selects nativos trocados na busca (#670), nas Listas (#671) e na configuração (#672). Nenhum <select> no código da prospecção. |  |
| PLAT-51 | Diagnóstico da chave do Google Places da plataforma | ausente no c2 | pendente | Não há diagnóstico da chave do Google no superadmin (opcional no plano). |  |
| PLAT-52 | Falha silenciosa nas sugestões de local | divergente | #699 (E1) | Sugestões de local deixam de falhar caladas. |  |
