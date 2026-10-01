# UX/UI — parecer do agente

## Revisão da versão final renderizada

**Versão revisada:** `docs/crm/kanban-design-822/prototype/`
**Evidência visual disponível:** `/Users/rodrigosilva/.codex/visualizations/2026/10/01/01a0f6fe-8fce-7991-812a-8857cd9a674d/822/01-kanban-desktop.png`
**Comparação:** esta é a versão final do ROOT; o rascunho anterior em `.codex/kanban-design/prototype/` fica como histórico de QA rejeitado.

A versão 822 consolidou a direção premium e simples: topo enxuto, cards de aproximadamente 165px, título do negócio separado de pessoa/empresa, um único sinal de atenção, responsável explícito e `Mover` visível. Os dois funis têm fixtures distintos, as contagens são calculadas a partir dos onze cards sintéticos e o layout usa utilities Tailwind compiladas. A captura disponível confirma a hierarquia visual principal; as correções finais abaixo foram conferidas no HTML/JavaScript mais recente e ainda precisam de captura renovada nos três tamanhos antes do gate visual.

### Correções confirmadas em relação ao rascunho rejeitado

| Ponto | Estado atual | Leitura de UX |
| --- | --- | --- |
| Descoberta dos cinco status | Resolvido no protótipo: `Mais status` e `Ver status anteriores` têm nome acessível, alvo de 44px e limites desabilitados quando não há mais conteúdo | O primeiro quadro pode mostrar os status operacionais sem obrigar cinco colunas estreitas. É disclosure progressivo explícito, não overflow silencioso. A captura final deve confirmar a visibilidade desses controles em 1280px, 1440px e 390px. |
| Linha vazia no card | Resolvido: `renderCard` só cria a linha de valor/sinal quando existe valor, score ou próximo contato | Cards sem sinal continuam compactos. Não adicionar um placeholder decorativo; se faltar próximo passo acionável, essa informação deve aparecer no detalhe com contexto. |
| Origem do score | Resolvido no fixture e no copy: `Atenção IA`, `Atenção manual` ou `Atenção` neutro quando a origem é desconhecida | O número organiza atenção, não representa temperatura ou chance de venda. A origem não é inferida só porque existe um número. |
| Identidade B2B/B2C | Resolvido na demonstração: empresa canônica fica em `contact.company`; B2C não reserva linha de empresa; sem contato usa `Sem contato vinculado` | O título da oportunidade permanece preservado, mesmo quando a pessoa ou empresa é mostrada abaixo. O contrato real ainda é um gate separado. |
| Foco depois de drawers | Resolvido no protótipo: ação de origem é guardada e o foco retorna ao controle/card visível após fechar | A captura de QA deve exercitar `Tab`, `Escape`, abertura de `Mover` e retorno para confirmar a implementação renderizada, sem declarar acessibilidade apenas por atributo. |
| Configuração e caixas | Resolvido como arquitetura de informação: `Configurar` separa gestão de caixas da conta de `Caixas conectadas ao funil`; o drawer explica que mais de uma caixa pode ser vinculada | A distinção preserva a simplicidade sem esconder a configuração necessária para o funil. Permissões e credenciais continuam fora do protótipo. |

### Limites que permanecem antes de levar para o produto

| Prioridade | Limite real | Decisão necessária |
| --- | --- | --- |
| P1 | O placeholder promete buscar oportunidade, contato e empresa; o backend atual comprova busca por título, enquanto `matches()` cobre esses campos apenas nos fixtures | Implementar consulta autorizada por título, pessoa e empresa canônica com contrato/indexação adequados, ou reduzir o placeholder até o backend suportar a promessa. O protótipo demonstra a intenção e não prova integração. |
| P1 | A empresa canônica está representada no fixture, mas o payload compacto atual do board não a entrega de forma garantida | Fechar `contact.company: { id, name } \| null` no escopo/autorização correto e sem N+1 para board, Lista e detalhe. Não usar nome solto de atributo como substituto do vínculo canônico. |
| P1 | A ordenação por score do fixture é local; no produto real a paginação e a ordenação podem ocorrer em chaves diferentes | Alinhar a prioridade no servidor antes de comunicar ranking global. Enquanto isso, usar `Atenção entre oportunidades carregadas` ou preservar a ordem recebida. Nunca apresentar o score como probabilidade de venda. |
| P2, decisão de produto | A caixa de entrada aparece no detalhe, não em todos os cards | Manter assim se a origem não for necessária na triagem diária, preservando densidade. Se múltiplas caixas mudarem a decisão operacional, incluir filtro ou chip condicional apenas quando houver mais de uma origem; não repetir canal e telefone em cada card por padrão. |
| P2, evidência visual | A captura disponível é de uma etapa anterior aos últimos ajustes de navegação/status e não substitui a revisão final renderizada | Capturar novamente 1280px, 1440px e 390px; verificar primeira linha do board, controles `Mais status`/anterior, cards sem sinal, foco, tabs e alternativa `Mover`. |

### Aprovado para a próxima revisão visual

- Cabeçalho curto, uma única CTA `Nova oportunidade`, views persistentes e administração dentro de `Configurar`.
- Barra de trabalho com funil, busca, filtros e atualizar sem `<select>` nativo.
- Card com título da oportunidade, identidade de contato/empresa, no máximo um sinal, responsável e `Mover`.
- Cinco status preservados no fluxo, com navegação explícita quando não couberem na viewport.
- Cenários B2B, B2C, sem contato, sem responsável, loading, vazio, erro e dois funis demonstráveis com dados sintéticos.
- Copy de atenção neutro quando não houver origem; score sem linguagem de venda.
- Drawer que mantém detalhes da caixa de entrada e diferencia gestão de caixas da conta do vínculo ao funil.
- Foco visível e retorno ao elemento de origem; drag acompanhado de alternativa por clique/teclado.
- `Protótipo · estados` e a documentação de implementação deixam claro que esta é uma demonstração, não uma tela de produção nem prova de contrato.

A versão final está pronta para aprovação visual condicionada à nova captura nos três tamanhos e aos gates de backend acima. Isso não autoriza copiar o harness para produção, merge, deploy ou alteração de contrato; esses passos continuam separados da aprovação do design.

## Revisão UX — Filtros do quadro

**Escopo:** avaliar a organização proposta para `Responsável`, `Empresa`, `Somente atrasados`, contador de filtros ativos, chips removíveis, busca no picker e aplicação instantânea. Esta revisão não altera o protótipo nem cria IA ou algoritmo novo.

### Recomendação principal

Manter um único painel `Filtros` abaixo da barra de busca, aberto sob demanda, com aplicação instantânea e sem botão `Aplicar`. A pessoa deve conseguir responder três perguntas em ordem curta:

1. **Quem cuida?** `Todos`, `Minha carteira` e `Sem responsável`.
2. **Qual empresa?** `Todas as empresas`, empresas canônicas, `Sem empresa vinculada`.
3. **O que está atrasado?** `Somente retornos atrasados`.

Essa ordem preserva a proposta atual e dá sentido ao filtro: pessoa responsável, contexto da conta e urgência. A inteligência vem de opções que representam decisões reais e de feedback imediato; não é necessário adicionar IA.

Ajustes de copy que melhoram a compreensão sem mudar o contrato:

- usar `Empresa` como título do grupo; `Empresa vinculada ao contato` é correto tecnicamente, mas pesado para uma ação diária;
- usar `Somente retornos atrasados` como rótulo completo do toggle; `Retorno` + `Somente atrasados` exige que a pessoa una duas partes;
- manter `Minha carteira` apenas se esse termo já for conhecido no produto. Se não for, `Minhas oportunidades` é mais direto para uma pessoa nova;
- usar `Todas as empresas` como estado inicial, paralelo a `Todos`, e manter `Sem empresa vinculada` no picker para não esconder o significado de `null`.

### Estado aplicado e interação

- Mostrar um pequeno contador no botão como `Filtros 3` (ocultar o contador quando for zero). Não chamar esse número apenas de `Ativos`, porque isso pode ser confundido com oportunidades ativas.
- Mostrar, abaixo da barra e antes da linha de resultados, chips somente quando houver filtros aplicados: `Responsável: Minha carteira`, `Empresa: Norte Logística` e `Retornos atrasados`.
- Cada chip deve remover apenas a própria condição, ter um botão de remoção com nome acessível e permanecer visível enquanto o painel estiver aberto. A pessoa enxerga o efeito sem reabrir o filtro.
- `Limpar filtros` deve limpar os três grupos e preservar a busca textual. Se o produto quiser apagar também a busca, o rótulo precisa dizer `Limpar busca e filtros`; não usar um comando ambíguo.
- A seleção atualiza a contagem e o board imediatamente. O painel principal permanece aberto para combinar condições; o picker de empresa fecha depois de uma escolha e devolve o foco ao seu botão.
- A linha de resultados deve separar estado de filtro de quantidade de dados: `4 de 11 oportunidades` é mais útil que apenas `4 ativos`. Em produção, essa contagem deve vir do resultado autorizado do servidor, não de uma estimativa dos cards carregados.

### Picker de empresa

O picker deve usar empresas canônicas, nunca texto livre disfarçado de filtro. Com a escala prevista, incluir `Buscar empresa` no topo do picker e filtrar a lista conforme a digitação. O estado vazio deve dizer `Nenhuma empresa encontrada` e oferecer a limpeza da busca do picker. Com poucas empresas, a busca pode aparecer somente quando a lista crescer, desde que a mudança seja consistente e não esconda uma lista pequena.

Se há busca, o controle deve se comportar como `combobox` com lista de opções, e não como `menu` de comandos. A lista precisa aceitar foco, setas, `Enter` e `Escape`; `Sem empresa vinculada` é uma opção real. Não usar `<select>` nativo. No mobile, o picker ocupa a largura disponível e os chips quebram linha sem scroll horizontal.

### Semântica e acessibilidade

- `Responsável` é uma escolha única; tratar como grupo de opções, com uma seleção claramente marcada.
- `Somente retornos atrasados` é um toggle binário com estado visual e `aria-pressed`/semântica equivalente, não um texto que muda sem indicação.
- `Filtros` usa `aria-expanded` para informar se o painel está aberto. O contador de filtros aplicados não deve ser comunicado como `aria-pressed` do botão que abre o painel.
- Chips e seus botões de remoção precisam de nomes completos, por exemplo, `Remover filtro Empresa: Norte Logística`, foco visível e alvo de pelo menos 44px.
- A atualização da quantidade deve ocorrer em uma região `aria-live` discreta, sem roubar foco nem fechar o painel.

### Limites de produto que precisam permanecer explícitos

1. `Minha carteira` precisa usar o usuário e as permissões da conta no servidor; não pode depender do `ownerId` do fixture.
2. `Sem responsável` precisa ter definição única para pessoa, equipe e IA; o filtro não deve esconder oportunidades atribuídas a um bot por acidente.
3. Empresas devem vir do vínculo canônico `contact.company` e aceitar `null` para `Sem empresa vinculada`. A busca local da demonstração não prova que o backend atual consegue pesquisar empresa.
4. `Somente retornos atrasados` precisa usar o fuso e a regra de vencimento do account, não o relógio arbitrário do navegador.
5. Para volumes grandes, filtros, busca por empresa e total filtrado precisam ser suportados pelo contrato/paginação do servidor. Não prometer que os dez fixtures representam o universo da conta.

A organização proposta é simples o suficiente para implementação incremental sobre a base atual: três facetas, escolhas canônicas, aplicação instantânea, chips reversíveis e sem camada de IA. O gate antes da produção é fechar os contratos de responsável, empresa e retorno; a decisão visual pode avançar sem esperar um algoritmo novo.


## Evidência posterior do integrador

Capturas atualizadas em `../screenshots/`; testes e resultados em `../validation.md`.
A prévia IA é explicitamente simulada. Filtros combinados e empresa específica
foram exercitados em desktop/celular; o contrato autorizado ainda é um gate real.

## Revisão da identidade — decisão posterior às capturas iniciais

Rodrigo pediu empresa em destaque, pessoa abaixo e negócio secundário. Essa ordem
está aplicada nas capturas 19/20/21, incluindo Lista e Calendário. Os pareceres
acima sobre título primário e `contact.company` são históricos e foram substituídos
pelo contrato `card.company` descrito na auditoria Prospecção. Sem empresa, pessoa
principal; repetições exatas omitidas na exibição, sem editar nomes persistidos.
