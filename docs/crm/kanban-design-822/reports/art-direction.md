# Direção de arte — CRM Kanban principal

**Data:** 2026-10-01
**Escopo:** direção visual e crítica de UX para o Kanban principal. Este documento orienta o protótipo navegável e a próxima revisão visual; não altera a UI nem o produto.

## Decisão de direção

O Kanban deve parecer uma mesa de trabalho ampla, silenciosa e previsível. O usuário precisa responder em poucos segundos: **qual é o negócio, quem é a pessoa/empresa, qual é o próximo sinal e quem cuida dele**.

A recomendação é uma única linguagem:

- canvas claro e plano para o quadro;
- sidebar azul-marinho como âncora de marca, sem espalhar azul por todas as colunas;
- azul-marinho forte reservado ao cabeçalho das gavetas e ao contexto de edição, como no Editar funil integrado;
- cores das etapas apenas no ponto de identificação: ponto no cabeçalho e trilho fino no card;
- um botão primário evidente por contexto: **Nova oportunidade** no quadro e **Salvar** dentro da gaveta;
- administração e configurações em **Mais**, preservando acesso sem transformar o Kanban em uma faixa de botões.

O resultado deve ser premium pela proporção, tipografia e foco, não por mais caixas, gradientes ou efeitos.

## Diagnóstico do estado atual

### 1. O topo compete consigo mesmo — P1 visual

O código atual separa ações em duas faixas: a primeira reúne visualização, atualizar, configurar inboxes, agenda e novo funil; a segunda reúne funil, editar funil, atribuição/handoff, busca, filtros e nova oportunidade. Em uma janela menor isso vira duas linhas de botões e faz ações administrativas parecerem tão importantes quanto trabalhar nos cards.

Na captura descrita por Rodrigo, o efeito aparece como “muitos botões em duas linhas”. A solução recomendada é hierárquica:

1. **Linha de trabalho:** seletor do funil, busca, Filtros e Nova oportunidade.
2. **Linha de navegação:** Kanban, Lista e Calendário.
3. **Mais:** atualizar, configurar inboxes, atribuição/handoff, agenda e novo funil; Editar funil pode permanecer próximo do seletor quando há permissão.

Em desktop largo, as duas linhas podem ficar visualmente próximas, mas não devem misturar ações de administração com ações de operação. Em larguras menores, o menu Mais absorve antes de quebrar o cabeçalho.

### 2. O card mistura identidade e responsabilidade — P1 semântico

`CrmKanbanCard.vue` usa hoje o avatar para representar o responsável e mostra o nome do mesmo responsável novamente no rodapé. Quando o responsável é um bot, o avatar grande parece ser o cliente. O usuário não sabe se o círculo é a pessoa, a empresa ou quem atende.

Regra recomendada:

- **Avatar principal:** contato ou empresa, nunca o responsável.
- **Rodapé:** `Responsável · Mariana` ou `Responsável · IA`, com ícone pequeno.
- **Sem responsável:** texto explícito `Sem responsável`, sem avatar que pareça uma pessoa.
- **Card avulso:** `Card avulso` em tom secundário.
- **Bot:** usar `IA` ou `Assistente de IA` no rodapé; o bot pode ter ícone pequeno, não ocupar a identidade visual do cliente.

Isso resolve a crítica “bot owner avatar” sem retirar a informação de atribuição.

### 3. Score só com número não ensina o usuário — P1 de compreensão

O score aparece como número e ícone, mas `82` sozinho não explica se é valor, prioridade ou probabilidade. Tooltip e `aria-label` ajudam acessibilidade, mas não resolvem a primeira leitura de uma pessoa que acabou de abrir o CRM.

No card, usar uma etiqueta curta e explícita:

- `IA 82` para score calculado pela IA;
- `Manual 82` para score informado por uma pessoa;
- ícone de faixa junto do texto, mantendo cor + ícone + palavra;
- score zero ou ausente fica fora do card, como já ocorre.

O detalhe do motivo continua na gaveta/tooltip. Não colocar explicação longa em todos os cards.

### 4. Telefone, inbox e origem precisam de papéis separados — P1 de leitura

Telefone identifica o contato; inbox identifica o canal/caixa; origem identifica campanha. Esses três dados não podem disputar a mesma linha nem repetir o mesmo texto.

Regra de identidade:

- **B2B:** `Mariana Costa · Horizonte Seguros`.
- **B2C:** `Mariana Costa · +55 31 90000-0001` quando o telefone for útil.
- **Sem nome:** telefone assume a linha de identidade uma única vez.
- **Inbox:** chip separado, com ícone do canal + `Comercial`, sem telefone.
- **Origem:** chip separado somente quando houver campanha; se não houver, não reservar espaço vazio.

O card deve ter uma única fonte visual para o telefone. O título da oportunidade não deve repetir telefone, nome e inbox ao mesmo tempo.

### 5. Muitos sinais transformam o card em legenda — P1 de densidade

Hoje o card pode acumular etiqueta, origem, SLA, handoff, inbox, valor, follow-up, IA e última mensagem. Cada item é válido isoladamente, mas a soma faz todos parecerem igualmente importantes. Isso é especialmente crítico quando uma etapa tem 115 cards, contra 23, 47 e 6 nas outras etapas.

Padrão recomendado para a primeira visão:

1. Título do negócio, uma linha, com truncamento limpo.
2. Identidade de contato/empresa, uma linha.
3. **Um sinal principal:** próximo follow-up vencido, handoff pendente, score de IA ou valor — escolhido pela urgência.
4. Rodapé com responsável e última atividade.
5. Demais sinais em `+N sinais` ou na gaveta, com tooltip/resumo.

O valor pode continuar visível quando for o dado central da operação; não deve ocupar o lugar do follow-up vencido. O card não precisa contar toda a história da conversa.

## Tokens visuais recomendados

| Elemento | Direção |
|---|---|
| Canvas do Kanban | `n-background`/superfície neutra, sem faixa azul grande |
| Sidebar | Azul-marinho de marca, item ativo com contraste claro e foco visível |
| Cabeçalho de gaveta | Azul-marinho aprovado do Editar funil, com título e subtítulo |
| Coluna | Superfície neutra discreta, borda fraca, sem fundo específico por etapa |
| Etapa | Ponto + trilho de 4px usando a cor da etapa; não pintar a coluna inteira |
| Card | Superfície elevada apenas o suficiente para separar do canvas; uma borda e sombra leve |
| Título | 14px, peso 600, uma linha |
| Identidade | 12–13px, tom secundário, uma linha |
| Sinais | 11–12px, chips curtos, no máximo uma linha primária |
| Rodapé | 11–12px, responsável + última atividade |
| Espaçamento | Ritmo 8/12/16; coluna com 16px de distância e card com 12px entre itens |
| Toque/foco | Alvos de pelo menos 44px para ações; foco visível sem depender de cor |

As cores da etapa devem orientar, não decorar. Verde, âmbar e vermelho ficam para estados e urgência; não usar cor da etapa para comunicar score ou permissão.

## Densidade

### Padrão recomendado: confortável

Usar como padrão da primeira visita. Card com altura visual estável, título, identidade, um sinal e rodapé. Descrição fica limitada a uma linha ou é aberta na gaveta. O objetivo é permitir escanear uma coluna sem transformar cada card em uma mini ficha.

### Alternativa útil: compacta, explícita

Manter a densidade compacta como preferência do usuário para etapas grandes, sem alternar automaticamente. Nela, ocultar descrição e sinais secundários, manter título, identidade, score/urgência e responsável. O controle deve dizer `Densidade: confortável/compacta`, sem ícone ambíguo.

Não recomendo criar uma terceira variação visual. O usuário precisa aprender um só card; a compacta é apenas uma redução previsível.

## Colunas e escala

- Cabeçalho da coluna: ponto da etapa, nome, `23 cards`/`47 cards`/`115 cards`/`6 cards` e, se existir regra real, WIP em texto secundário.
- Não adicionar KPIs, percentuais ou mini gráficos dentro de cada coluna; isso compete com os cards.
- A coluna mantém largura estável. O board pode rolar horizontalmente, com a barra de rolagem percebida e sem comprimir cards até ficarem ilegíveis.
- Para 115 cards, manter `Carregar mais` no fim e oferecer a Lista como alternativa operacional. Não tentar mostrar tudo de uma vez nem criar paginação visual dentro de cada cartão.
- A descrição do status continua no editor do funil; no Kanban, pode aparecer apenas como tooltip ao focar o nome da etapa, caso seja necessário contexto. Não transformar o cabeçalho da coluna em outro painel de texto.

## Revisão do protótipo provisório: altura antes do board

O `index.html` provisório melhora a hierarquia das ações, mas ainda soma quatro camadas acima das colunas: `breadcrumb + h1 + subtítulo`, toolbar de funil/visualização/configuração, linha de busca/filtros e `board-status`. Com os valores atuais do CSS, o cabeçalho tende a consumir aproximadamente 330–340px antes do primeiro card em desktop; no mobile, o empilhamento pode passar de 400px. Isso deixa o Kanban parecendo um painel de controles com um board sobrando embaixo.

Correção recomendada para o próximo mockup, sem remover **Nova oportunidade**:

1. **Título enxuto:** manter `CRM / Kanban` como contexto pequeno e `Kanban` como título. Remover `Veja o que precisa avançar agora.`; é uma frase genérica que não ajuda a operar o quadro. No mobile, manter título e ação primária na mesma linha sempre que houver espaço.
2. **Toolbar de uma leitura:** colocar seletor do funil, abas de visualização e `Mais` na mesma faixa de 44–48px. O resumo `5 etapas · 191 oportunidades` fica dentro do seletor ou em texto secundário, sem um rótulo `Funil` ocupando outra linha.
3. **Busca/filtros como segunda faixa curta:** manter busca e Filtros juntos, sem título auxiliar. A busca deve crescer; Filtros e contador permanecem compactos. `Nova oportunidade` continua visível no cabeçalho, como ação primária única.
4. **Status sem painel:** reduzir `board-status` a uma linha de 32–36px, sem fundo ou card. Mostrar apenas dado verificável, por exemplo `191 oportunidades` ou `12 resultados após os filtros`. A frase `3 precisam de um próximo passo hoje.` só deve aparecer se vier de uma contagem real e acionável; em dados de protótipo, é KPI inventado e deve sair.

Meta visual: manter aproximadamente 160–190px acima das colunas em desktop, alinhado à medição real de 1440×900. A estimativa de 210–230px feita para o protótipo provisório não é um alvo: o render final precisa ser medido novamente. O quadro precisa dominar a primeira tela. Não adicionar mais indicadores, textos de orientação ou resumos para preencher o espaço; a sensação premium vem de retirar camadas e preservar ritmo.

## Revisão do `renderCard` atual

O novo render melhora a explicação de score e torna `Mover` acessível, mas recoloca densidade que a direção anterior havia retirado. A ordem atual é: tipo de entidade, score, arrastar, título, identidade, inbox + valor, responsável + atividade, próximo passo em duas linhas e duas ações. Em uma coluna de 19rem isso transforma cada card em uma ficha alta e reduz a comparação entre oportunidades.

Correções de direção para a próxima captura:

- **Remover o tipo de entidade do topo.** `Pessoa · Empresa` repete `Mariana Costa · Norte Logística`; `Pessoa` também repete o caso B2C. O ícone e a própria identidade já explicam o tipo. Manter no card apenas `Pessoa · Empresa` não acrescenta informação operacional.
- **Identidade em uma linha:** contato + empresa quando ambos existem; apenas contato quando B2C; empresa quando não houver contato. Evitar o sufixo literal `· Pessoa` e evitar `Sem contato · Empresa` quando o nome da empresa já estiver disponível.
- **Score curto e consistente:** usar `IA 82`, `Manual 54` e `IA pendente`/`Sem score`. `Atenção IA · 82` e `Atenção ainda não calculada` ocupam largura demais e variam entre card, lista e drawer. O significado completo pode ficar na gaveta. Estado pendente deve ter aparência neutra; aplicar a mesma classe visual de score baixo faz `não calculado` parecer uma pontuação ruim.
- **Próximo passo não é requisito desta entrega.** `card.next` é texto novo e a API atual só garante a data de follow-up. Não transformar uma sugestão sintética em contrato. No card, mostrar apenas o follow-up real (`Hoje`, `Amanhã`, `Sem data`) ou deixar o detalhe na gaveta; a proposta específica pode entrar em uma etapa posterior com fonte de dados definida.
- **Inbox e valor devem ser secundários.** Se o inbox for sempre o mesmo, mostrar o nome curto ou só o ícone com texto acessível; não repetir `WhatsApp Comercial` em todos os cards. O valor pode permanecer como dado curto, sem ganhar uma segunda linha.
- **Uma ação visível por card.** O título já abre detalhes; `Detalhes` no rodapé repete a mesma ação. Manter `Mover` como ação explícita para teclado/toque e deixar a alça de arrastar aparecer no hover/foco. Isso preserva a alternativa acessível sem criar duas ações para o mesmo destino.

Critério de aceite: primeira visão do card com **título + identidade + um sinal (score ou follow-up) + rodapé de responsável/atividade**. Inbox, valor e próximo passo entram somente quando forem a informação operacional prioritária, e não como linhas obrigatórias em todos os cards.

## Interação e estados

- O card inteiro pode abrir detalhes, mas a ação de abrir conversa deve continuar com alvo separado e foco próprio.
- Para arrastar, mostrar `cursor-grab`/alça discreta no foco e reservar a área de ação para não conflitar com abrir card ou abrir conversa. No mobile, oferecer `Mover para` em ação explícita em vez de depender de arrasto preciso.
- Estado hover deve elevar contraste da borda, não aplicar uma cor forte no card inteiro.
- Estado selecionado deve usar contorno de marca e texto; não depender só de um fundo azul.
- Estado vazio de coluna pode manter o contorno tracejado e a frase curta de soltar/criar; não precisa de ilustração grande.
- Estado loading preserva o tamanho da coluna para evitar salto de layout.
- Erro de carregamento fica em uma faixa curta com `Tentar novamente`; não esconder o board inteiro quando apenas uma coluna falha.

## Handoff para o mockup navegável

O protótipo deve demonstrar esta mesma direção em uma sequência curta:

1. **Board inicial:** quatro colunas com 23/47/115/6 cards; apenas as ações operacionais ficam expostas.
2. **Hover/foco de card:** avatar de contato/empresa, `IA 82`, inbox sem telefone repetido e responsável no rodapé.
3. **B2B e B2C:** um card com empresa e outro sem empresa, mantendo a mesma estrutura.
4. **Filtros abertos:** busca + painel de filtros, com contador de filtros ativos e botão Limpar.
5. **Menu Mais:** ações administrativas agrupadas, sem mudar a posição do board.
6. **Estado denso:** opção compacta aplicada à coluna grande, sem criar uma terceira linguagem.
7. **Drag/mover:** área de arrasto clara no desktop e ação `Mover para` no mobile.

O mockup deve manter o canvas amplo e plano. O drawer de Editar funil continua sendo a referência de cabeçalho azul-marinho; ele não deve virar o tratamento visual de todo o Kanban.

## Critérios de QA visual

- Em 1280px e 1440px, nenhuma ação primária fica escondida ou vira uma terceira linha sem intenção.
- O usuário identifica contato/empresa, responsável, score e inbox sem tooltip.
- Nenhum telefone aparece duas vezes no mesmo card.
- `IA 82`, `Manual 82` e ausência de score são distinguíveis por texto e ícone, além de cor.
- O bot nunca parece ser o cliente.
- B2B e B2C não deixam espaços vazios ou labels de empresa inexistente.
- O card selecionado, foco de teclado, drag e abrir conversa têm estados visíveis.
- A coluna de 115 cards continua navegável, com largura e rolagem estáveis.
- Nenhuma mudança amplia o cabeçalho do board até parecer uma gaveta ou um banner de campanha.

## Parecer final — protótipo 822

Esta seção substitui a leitura do protótipo provisório anterior para fins de aprovação visual. O protótipo antigo, em `.codex/kanban-design/prototype/`, fica **rejeitado** como direção de densidade: empilhava título, subtítulo, duas faixas de toolbar e status antes do quadro; repetia tipo de entidade; propunha próximo passo sintético; e deixava os cards altos demais para a comparação rápida.

O novo protótipo, em `docs/crm/kanban-design-822/prototype/`, corrige o problema central. Na captura real `822/01-kanban-desktop.png`, as colunas começam em aproximadamente **y=177px** e os cards medem aproximadamente **165px**. A marca usa o asset correto `assets/hub2you-icon.png`; o cabeçalho é enxuto; `Nova oportunidade` permanece soberana; funil, busca e filtros ficam em uma faixa compacta; e a sidebar azul-marinho não contamina o canvas do Kanban.

A anatomia do novo card está aprovada para o padrão confortável: título, identidade contato/empresa em uma linha, valor ou um sinal prioritário, e rodapé com responsável/atividade. `Mover` é explícito e o bot aparece como `IA · Gabriela`, sem parecer ser o contato. O uso do ícone de ajuda no cabeçalho de cada status preserva a descrição do status sem transformar cada coluna em um painel de texto.

As capturas finais resolvem o corte observado na primeira versão: em 1920px, os cinco status aparecem inteiros; no celular, o seletor mostra um status por vez e desabilita visualmente os limites. O cabeçalho mobile não duplica o desktop e não há overflow da página. A rolagem horizontal continua sendo um comportamento de board e deve permanecer perceptível quando a largura não comportar todos os status.

`Protótipo · dados fictícios`, `Ver cenários` e `Demonstração` continuam visíveis por decisão de transparência desta entrega. São chrome de QA e devem ser removidos quando a UI for integrada ao produto; não são defeitos da direção visual.

Há apenas uma melhoria opcional, sem bloquear aprovação: cards sem valor, score ou retorno ficam cerca de 40px mais baixos que os demais. Isso é legível e economiza espaço; se o padrão confortável exigir ritmo perfeitamente uniforme, reservar a altura da linha de sinal deixará a coluna mais regular.

Minha recomendação final é **aprovar visualmente o novo protótipo 822**. Não há motivo para outro redesenho. Esta aprovação cobre as capturas desktop e celular analisadas; não cobre contrato de API, persistência, integração ou deploy.

## Parecer final — Encontrar com IA

As capturas `11-encontrar-com-ia.png` e `12-ia-celular.png` corrigem os três problemas apontados na primeira versão: a simulação fica explícita no topo antes da ação, o resultado usa chips + contagem para permitir conferência, e a mensagem de substituição agora é condicional (`Ao confirmar...`). A composição desktop e o modal mobile estão legíveis, sem corte no rodapé; a sequência pedido → entender → conferir → usar ficou compreensível.

Não identifiquei falha visual material restante neste estado pós-entendimento. A aprovação é limitada à UI e ao fluxo demonstrado: a prévia continua sendo uma simulação, sem chamada ao GPT-6 Luna, e a análise de texto livre, interpretação real, persistência e aplicação dos filtros dependem do contrato de backend antes de qualquer release.

## Fontes e limites

- Código revisado: `app/javascript/dashboard/routes/dashboard/crm/pages/CrmKanbanPage.vue` e `app/javascript/dashboard/routes/dashboard/crm/components/CrmKanbanCard.vue`.
- Referência visual integrada: `/Users/rodrigosilva/.codex/visualizations/2026/10/01/01a0f6fe-8fce-7991-812a-8857cd9a674d/793/02-referencia-funil-integrado.jpg`.
- Capturas integradas relacionadas: `793/05-depois-nova-oportunidade.jpg`, `793/06-depois-relacionamento.jpg`, `793/07-depois-celular.jpg` e `793/08-depois-celular-fim.jpg`.
- Medição real do produto local em 1440×900: `/Users/rodrigosilva/.codex/visualizations/2026/10/01/01a0f6fe-8fce-7991-812a-8857cd9a674d/822/00-produto-atual-local-1440.jpg`; a primeira coluna começa em aproximadamente y=185px.
- Protótipo 822 revisado: `/Users/rodrigosilva/.codex/worktrees/kanban-design-review/chat2you/docs/crm/kanban-design-822/prototype/`; captura final desktop: `/Users/rodrigosilva/.codex/visualizations/2026/10/01/01a0f6fe-8fce-7991-812a-8857cd9a674d/822/01-kanban-desktop.png`.
- Capturas finais revisadas: `/Users/rodrigosilva/.codex/visualizations/2026/10/01/01a0f6fe-8fce-7991-812a-8857cd9a674d/822/06-kanban-1920.png` e `/Users/rodrigosilva/.codex/visualizations/2026/10/01/01a0f6fe-8fce-7991-812a-8857cd9a674d/822/03-kanban-celular.png`.
- Capturas do filtro IA revisadas: `/Users/rodrigosilva/.codex/visualizations/2026/10/01/01a0f6fe-8fce-7991-812a-8857cd9a674d/822/11-encontrar-com-ia.png` e `/Users/rodrigosilva/.codex/visualizations/2026/10/01/01a0f6fe-8fce-7991-812a-8857cd9a674d/822/12-ia-celular.png`.
- Skill aplicada: `/Users/rodrigosilva/.codex/plugins/cache/ui-ux-pro-max-skill/ui-ux-pro-max/2.13.0/.claude/skills/ui-ux-pro-max/SKILL.md`.

Não houve acesso a produção, deploy, dados de cliente ou paid AI. A aprovação acima cobre as capturas desktop e celular analisadas; não substitui a verificação de teclado, filtros, rolagem em outras larguras e integração com dados reais.
