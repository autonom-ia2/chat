# Kanban CRM — proposta para aprovação

Issue: [#822](https://github.com/autonom-ia2/chat/issues/822). Data: 2026-10-01.

Esta entrega é uma proposta visual com dados fictícios. O produto não foi alterado.
Ela considera o Editar Funil integrado em main e as oportunidades/relacionamentos
em revisão na [PR #793](https://github.com/autonom-ia2/chat/pull/793).

## Abrir e revisar

- [Protótipo navegável](prototype/index.html): abrir por um servidor local.
- **Atual:** [quadro sem faixa intermediária](screenshots/22-kanban-sem-faixa.png); [hierarquia do cliente](screenshots/19-identidade-cliente.png), [celular](screenshots/20-identidade-cliente-celular.png) e [Prospecção sintética](screenshots/21-identidade-prospeccao.png).
- Histórico: [quadro desktop — cinco status](screenshots/06-kanban-1920.png).
- [Contato e empresa no detalhe](screenshots/02-card-empresa.png).
- [Kanban no celular](screenshots/03-kanban-celular.png).
- [Busca única e ações visíveis](screenshots/15-busca-unificada.png); [Mais filtros completo](screenshots/16-filtros-completos.png); [filtros completos no celular](screenshots/18-filtros-celular.png).
- Histórico: [Revisão dos filtros compactos e Criar funil visível](screenshots/13-filtros-compactos.png); [celular revisado](screenshots/14-filtros-compactos-celular.png).
- [Filtros combinados](screenshots/09-filtros-combinados.png) e [filtros no celular](screenshots/10-filtros-celular.png).
- [Encontrar com IA](screenshots/11-encontrar-com-ia.png) e [IA no celular](screenshots/12-ia-celular.png).
- [Parecer de arte](reports/art-direction.md), [UX/UI](reports/ux-analysis.md),
  [QA com fontes de código](reports/qa-kanban.md) e [validação renderizada](validation.md).
- [Mapa de implementação e gates de backend](implementation-notes.md).

Para abrir sem instalar dependências, na raiz do repositório:

```sh
python3 -m http.server 47835 --bind 127.0.0.1 --directory docs/crm/kanban-design-822/prototype
```

Acessar `http://127.0.0.1:47835/`. O estado fica somente na memória e é restaurado
com recarregar. Não há API, login, envio, storage ou chamada de IA. `styles.css`
está compilado; o fonte usa Tailwind e os assets existentes da marca/Inter.

A marcação **Protótipo · dados fictícios** e o controle **Ver cenários** são
intencionais para revisão. Não são parte da futura interface do produto.
Criar/mover oportunidades e criar funil funcionam em memória; Editar Funil,
caixas, atribuição e agendamento são prévias de contexto somente leitura.
O mockup não replica nem substitui os editores completos já existentes.

## O que estamos resolvendo

A tela atual distribui operação e configuração por duas faixas de botões com
peso semelhante. Nos cards, a identidade da oportunidade, a pessoa, o responsável,
a caixa de entrada e sinais de atenção disputam espaço. A proposta organiza a
primeira leitura em três perguntas: **quem é o cliente, qual negócio estamos
tratando e o que merece atenção agora?**

A captura fornecida por Rodrigo é uma referência visual da conta 18; não é uma
medição de produção feita por esta equipe. A conferência usa código da PR #793
em `56b56f3a79`, main em `902f0059d7` e uma tela local real com dados sintéticos.
Após autorização, lemos as contas 16 (Chat2You) e 20 (Autonom.ia) no Chrome,
sem alteração de dados. Não consultamos a conta 18 nem copiamos dados de clientes.

## Direção recomendada

- Quadro claro e amplo, mantendo a sidebar de marca. O cabeçalho azul-marinho do
  Editar Funil continua próprio das gavetas; não se torna um banner no Kanban.
- Identidade do funil próxima de busca e filtros, com **Nova oportunidade** como
  ação principal. Kanban, Lista e Calendário continuam fáceis de encontrar.
- Configurações administrativas reunidas em uma entrada rotulada, preservando
  todas as funções existentes e suas permissões.
- Empresa em destaque, pessoa abaixo e nome do negócio em hierarquia menor.
  Sem empresa, pessoa em destaque. O título salvo é preservado; repetições exatas
  ficam ocultas na exibição. Um bot responsável não se apresenta como cliente.
- Sinais com significado escrito, sem exigir que o usuário decore ícones ou
  interprete uma nota como probabilidade de venda.
- Movimento por arrastar e por clique/teclado. Escolhas usam componentes do
  design system, nunca o select nativo do navegador.

## Pesquisa aplicada

Esta pesquisa orienta decisões; não substitui teste com usuários do Chat2You.
As frequências de uso do menu ainda são hipóteses a validar.

| Fonte primária | Aplicação na proposta |
|---|---|
| [HubSpot — Board cards](https://knowledge.hubspot.com/object-settings/select-properties-to-show-on-records-in-board-view) | Ordenar propriedades/associações para o trabalho da equipe e ocultar campos vazios. |
| [Pipedrive — Deal cards](https://support.pipedrive.com/en/article/deal-card-customization-sorting) | Manter pessoa, organização e negócio distinguíveis. A ordem adotada aqui atende nossa operação de conversas e prospecção; não é uma regra universal. |
| [NN/g — Progressive Disclosure](https://www.nngroup.com/articles/progressive-disclosure/) | Manter trabalho frequente visível e revelar opções avançadas por uma entrada com rótulo claro. |
| [NN/g — Complex Applications](https://www.nngroup.com/articles/complex-application-design/) | Reduzir ruído preservando funções e acesso ao detalhe sem perder o contexto do quadro. |
| [Atlassian — Typography](https://atlassian.design/foundations/typography) | Hierarquia e espaçamento coerentes; fontes e marca do próprio Chat2You preservadas. |
| [W3C — Dragging Movements](https://www.w3.org/WAI/WCAG22/Understanding/dragging-movements) | Alternativa por clique para movimentação; arrastar não pode ser o único caminho. |
| [W3C — Focus Not Obscured](https://www.w3.org/WAI/WCAG22/Understanding/focus-not-obscured-minimum) | Gavetas e rodapés não devem esconder foco; abertura e fechamento mantêm o contexto de teclado. |
| [W3C — Target Size](https://www.w3.org/WAI/WCAG22/Understanding/target-size-minimum) | O mínimo AA é 24px com exceções/espaçamento. Nesta proposta adotamos 44px nas ações principais para facilitar toque. |

A skill UI-UX Pro Max foi aplicada para contraste, foco, toque, densidade e
responsividade. As duas buscas de design system devolveram padrões de marketing
inadequados ao quadro operacional; esses layouts e novas paletas foram rejeitados.
A busca de UX por `dragging movements` retornou a orientação apropriada. Mantemos
Inter, a marca e os componentes já usados no produto.

## Filtros que geram valor

O botão mostra quantos filtros estão ativos. Responsável, empresa e retorno
atrasado combinam por **AND**, aplicando imediatamente. Empresa é uma escolha
específica, com busca e opções de qualquer empresa ou sem vínculo; não apenas
um botão “tem empresa”. As seleções viram etiquetas removíveis, com contagem
separada do número de filtros. Limpar filtros preserva a busca textual.

No celular, a gaveta mostra a contagem e **Ver oportunidades** volta ao quadro.
Isso fecha a gaveta, sem uma segunda etapa de aplicação. A etapa visível passa
a uma que tem resultados quando um novo filtro esvazia a etapa atual.
“Sem empresa vinculada” inclui contatos sem empresa e cards sem contato; não
classifica essas pessoas como B2C. Na integração, preservar todos os filtros
existentes de status/caixa/campanha etc. Esta prévia demonstra cinco grupos progressivos em Mais filtros.

A ajuda opcional **Encontrar com IA** está descrita em
[avaliação e contrato sugerido](ai-filter-design.md). Ela transforma um pedido
em uma proposta para conferir antes de confirmar. A chamada GPT-6 Luna ainda
não está conectada; a demonstração de UI está explicitamente marcada.

## Identidade do cliente e Prospecção

**Empresa principal; pessoa abaixo; negócio menor.** Sem empresa, pessoa principal.
Sem contato, o título continua válido e a ausência do vínculo fica clara.
Não renomeamos cards e não fundimos oportunidades da mesma empresa.

A Prospecção já destaca empresas na tela e grava o nome do lead como título do
card. A conversão cria/reutiliza empresa e contato; leads diferentes podem
compartilhar um contato, mas pertencer a empresas diferentes. Por isso a proposta
anterior de usar apenas `contact.company` foi substituída.

Contrato recomendado: `card.company: { id, name } | null`, resolvida pelo backend
por card. Para Prospecção, usar a empresa do metadata persistido; para cards comuns,
a empresa do contato. Respeitar conta, permissões, Enterprise/OSS e carregar em lote.
Busca, filtro, quadro, Lista e detalhe devem usar a mesma relação. Nunca inferir
empresa por texto do título, inbox ou responsável.

O payload atual não entrega esse contrato; o protótipo ilustra a proposta.
[Auditoria do fluxo e bloqueador de dados](reports/identity-prospecting-audit.md).

## Funis e status

Manter uma identidade de funil selecionado e um ponto claro de configuração.
A ordem do quadro acompanha a ordem configurada no Editar Funil; não criar duas
ordens independentes. No editor, numeração e controles convencionais continuam
úteis para organizar os status. No quadro, nome e cor já identificam a etapa;
um indicador `2 de 5` no celular deve significar posição de navegação, não uma
promessa de que todo negócio percorre todas as etapas, inclusive Perdido.

Arrastar oportunidades entre status é diferente de reordenar os status. O quadro
oferece **Mover para…** para a primeira ação; a segunda continua contextual ao
Editar Funil, com arrasto e alternativa convencional. Excluir um status precisa
preservar as regras de cards associados e confirmação do fluxo existente.

Vincular caixas ao funil também não é o mesmo que administrar todas as caixas da
conta. A proposta deve manter acesso à última etapa do Editar Funil para os
vínculos e preservar o fluxo/permissão da configuração de caixas por conta.

## Outros pontos verificados pelo QA

| Situação atual em código | Implicação | Proposta |
|---|---|---|
| Avatar principal e rodapé representam o responsável | Bot/humano pode ser confundido com cliente | Identidade no topo; responsável escrito uma vez no rodapé. |
| Busca compara somente o título | Pessoa/empresa podem não ser encontradas | Busca única por título, contato e empresa, implementada no servidor autorizado. |
| API pagina por ID; interface ordena por score/atividade somente carregados | Um negócio antigo prioritário pode ficar fora da primeira página | Ordem e cursor coerentes no servidor; até lá, não prometer prioridade global. |
| Contagem filtrada/aberta difere do total do status | Números podem parecer contraditórios | Contagem com escopo explícito e progresso de carregamento. |
| Score e responsável IA são dados diferentes; o board não entrega proveniência/motivo do score | Uma nota pode ser lida como chance de venda ou indevidamente atribuída à IA | Usar **Atenção**, distinguindo IA/manual somente com proveniência explícita; mostrar motivo no detalhe. |
| Inbox, origem da campanha e telefone são conceitos separados | Repetição de números ocupa espaço sem orientar | Nome da caixa legível; canal/origem em contexto secundário. |
| Há filtros próprios e estados de erro/vazio existentes | Simplificação pode apagar recursos úteis | Preservar filtros, retry e estados; melhorar rótulos e semântica ativa. |
| A Lista possui edição manual de etapa/lote; o próprio Kanban depende de drag | Caminho manual existe, mas fica distante do contexto do quadro | Ação **Mover para…** no card, preservando a edição e o lote na Lista. |

O relatório QA detalha fontes por arquivo e linha, limites e matriz B2B/B2C. Os
itens acima são achados deste escopo, não uma afirmação de que novos defeitos
foram introduzidos pela PR #793.

## Aprovação e próxima etapa

A aprovação pedida nesta entrega é da direção visual e dos comportamentos
demonstrados. Depois, a implementação precisa preservar contratos de dados,
permissões, filtros e escala reais. A liberação da PR #793 é independente desta
proposta; ela não deve esperar nem absorver um redesenho ainda não aprovado.

Merge, deploy e mudanças de produção continuam exigindo autorização explícita.

## Como avaliar a proposta

Antes de aprovar aparência, vale tentar cinco tarefas no protótipo:

1. Encontrar o funil e criar uma oportunidade sem precisar entender configurações.
2. Distinguir título do negócio, pessoa, empresa e responsável em dois cards.
3. Filtrar ou pesquisar, entender o que está sendo contado e voltar ao quadro.
4. Mover uma oportunidade sem arrastar, inclusive usando teclado/celular.
5. Encontrar Editar Funil, caixas de entrada e atribuição sem procurar por vários menus.

Na implementação, a aceitação precisa cobrir também os pontos que um protótipo
não prova: permissão de gestor/agente, contatos de outra conta, OSS/Enterprise,
empresa ausente/alterada, busca autorizada completa, paginação com 31+ cards,
atualização consistente entre quadro/lista, erro de gravação e atualização em
tempo real. A interface pode demonstrar esses fluxos; só a API e testes reais
podem garantir seus resultados.

**Ordem de implementação recomendada após aprovação:** primeiro identidade e
contrato empresa/proveniência; depois busca, ordenação e contagens coerentes;
então hierarquia visual, controles e movimento direto no Kanban. Densidade
compacta e melhorias secundárias ficam condicionadas ao uso observado.

## Revisão de descoberta e filtros — 01/10, após feedback do Rodrigo

Criar funil passou a ser ação visível junto ao seletor; o menu serve só para
trocar de funil. Rodrigo encontrou a criação após procurar: existência não
comprovava descoberta. Filtros deixaram a caixa alta e viraram uma faixa com
IA alinhada ao lado dos controles. Capturas 13/14 substituem a direção da
composição anterior dos filtros; as capturas 01–12 são histórico da primeira
revisão. A ajuda do status agora oferece caminho direto para Editar funil.

Rodrigo também questionou a identidade em negrito do card. Hoje é o título da
oportunidade. A recomendação para próxima decisão visual é empresa em destaque
e pessoa abaixo; sem empresa, pessoa em destaque. Conservar o negócio como
informação secundária evita tornar oportunidades da mesma empresa indistintas.
Essa nova hierarquia ainda não foi aplicada ao protótipo nesta revisão.

## Revisão de filtros após feedback do Rodrigo

Busca por nome, **Mais filtros** e **Encontrar com IA** têm entradas distintas.
A empresa exata fica dentro de Mais filtros; não há outro campo de empresa na
faixa do quadro. O drawer reúne atalhos de carteira/atraso e cinco categorias
recolhidas, com resumo curto do conteúdo. Chips removíveis e badge tornam os
critérios ativos visíveis após fechar. Criar funil continua exposto.

Etiquetas e campanhas aceitam mais de uma opção (qualquer uma das escolhidas);
estágios, atendimento, responsável, equipe, caixa, valor e atividade continuam
representados. Prioridade da equipe e nota de atenção são conceitos distintos.
Empresa e faixa de score ainda exigem contrato novo no backend. O protótipo
não demonstra consulta paginada, fechamento dos dados ou permissão real.

Esta composição usa divulgação progressiva: abrir apenas a categoria necessária,
sem perder acesso aos filtros. A referência [Carbon — Filtering](https://www.carbondesignsystem.com/building-blocks/core/patterns/filtering)
recomenda sinalizar filtros ocultos e permitir limpar sem reabrir. A referência
[NN/g — User Intent Affects Filter Design](https://www.nngroup.com/articles/applying-filters/)
orienta preservar o contexto enquanto a pessoa combina critérios.

Na integração, critérios complexos devem ser preparados antes da aplicação;
a decisão entre atualização instantânea e em lote depende da latência real da
consulta. A prévia calcula apenas onze fixtures em memória, imediatamente.
Para muitas empresas e usuários, os botões de fixtures serão substituídos por
pickers pesquisáveis do design system, com consulta autorizada e sem select nativo.

## Guia da Plataforma e busca CRM

[Auditoria atual do Guia](reports/guide-crm-audit.md): já consulta conversas,
funis e cards como o operador. A proposta é reutilizar essa capacidade com
resultado CRM tipado, mantendo a busca contextual no quadro. Falta fechar a
consulta por empresa canônica; não é preciso outro agente independente.
A avaliação e os limites estão em [Encontrar com IA](ai-filter-design.md).
