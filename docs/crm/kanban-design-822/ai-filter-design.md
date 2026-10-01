# Encontrar com IA — avaliação e proposta

## Decisão recomendada

Usar GPT-6 Luna como ajuda opcional para traduzir um pedido em filtros revisáveis.
É útil quando a pessoa sabe o resultado que procura, mas não conhece os campos
ou precisa combinar condições. Os controles manuais continuam visíveis.
A primeira versão deve atuar sobre informações estruturadas já suportadas pelo
CRM, sem inferir intenção dos clientes a partir de conversas.

Exemplo: “Mostre os retornos atrasados da Alvorada Tecnologia.” → empresa canônica
+ data de retorno vencida. A interface explica o entendimento, mostra os filtros
e obtém a contagem pela consulta real autorizada, antes da confirmação.

## Tela proposta

1. Ao lado da busca e de Mais filtros, abrir **Encontrar com IA**.
2. Campo vazio **O que você quer encontrar?** e exemplos opcionais.
3. **Entender pedido** gera uma proposta, ainda sem modificar o quadro.
4. **A IA entendeu** apresenta explicação curta, etiquetas e quantidade real.
5. **Usar estes filtros** aplica a seleção, deixando etiquetas removíveis no quadro.

A contagem vem do backend; o modelo não a calcula ou inventa. “Ao confirmar,
estes filtros substituirão os atuais” explicita o efeito. No celular, filtros
ficam em gaveta, e o quadro seleciona uma etapa com resultados para evitar que
a pessoa veja uma coluna vazia enquanto há oportunidades em outra.

## Base que já existe

Código verificado da PR #793 em `56b56f3a79`:

- `Crm::Ai::StageCriteriaImprover::MODEL` usa `gpt-6-luna`.
- `Crm::Ai::ResponsesClient#structured_text_format` usa JSON Schema estrito.
- `Crm::Ai::InteractiveOperation` autoriza solicitante/operação e lê resultado
  por operações explícitas. Ainda não existe operação de filtro IA.
- Resolução de credencial, registro de uso e configuração são serviços existentes
  do CRM. A nova operação precisa reutilizar essa base e sua política de acesso.

Isso torna a implementação plausível; não prova a acurácia do modelo neste fluxo.
Não adicionar dependência de provider ou usar um modelo alternativo silenciosamente.

## Contrato mínimo sugerido

Resposta tipada com estado `ready`, `clarification` ou `unsupported`, explicação
curta e seleção dos filtros suportados: responsável, empresa canônica e retorno
atrasado nesta prévia. Status/caixa/intervalos entram apenas quando seus contratos
reais de busca, permissão e combinação estiverem fechados.

O servidor valida tipos, IDs no escopo do solicitante e valores permitidos,
reutilizando os filtros determinísticos já existentes. Nenhum SQL, permissão ou
expressão livre retornada pelo modelo é executado.

A IA recebe pedido, funil atual, filtros atuais, vocabulário permitido, usuário
solicitante e referências mínimas autorizadas. Não enviar corpos de conversas,
contatos completos ou o board inteiro para montar filtros. Empresas com nomes
parecidos exigem escolha de candidato; nomes inexistentes e condições não
suportadas exigem esclarecimento, sem ignorar parte do pedido silenciosamente.

Para muitas empresas, usar busca autorizada de candidatos; não mandar o cadastro
inteiro em cada chamada. A descoberta de candidatos não pode ficar limitada aos
30 cards já carregados. O modelo decide o significado do texto: sem regex ou
listas de palavras na frente dele.

## Custo e verificação

Rodrigo autorizou teto total de US$ 1 caso seja necessário testar o provider.
Nesta entrega, gasto de chamadas: **US$ 0**. Cost-Aware LLM Pipeline foi usada
para avaliar chamada apenas no clique, payload limitado e contabilização. Não
adotamos downgrade automático, heurísticas por comprimento do pedido ou novas
políticas de retry fora do caminho já suportado pelo projeto.

Antes da implementação ser liberada, realizar eval curto de pedidos claros,
ambíguos, sem empresa encontrada, sem permissão, condições não suportadas,
instruções maliciosas e empresas homônimas. Medir interpretação, consulta final,
latência, uso e gasto, encerrando antes de ultrapassar o orçamento. Não registrar
prompts completos, tokens, credenciais ou dados de clientes em auditoria.

## O que o protótipo demonstra

A tela está renderizada e navegável, com exemplos fictícios mapeados por IDs de
cenário. Não há classificação de linguagem por palavras/regex nem uma chamada
simulada apresentada como provider real. Texto livre invalida o exemplo e informa
que a interpretação será conectada ao GPT-6 Luna depois da aprovação. As três
sugestões de exemplo aplicam filtros em memória e derivam a contagem dos fixtures.
O estado inicial é vazio; avisos de prévia ficam antes do CTA.

O mockup demonstra UI e interação. Acurácia, custo real, disponibilidade, contrato
e autorização da nova operação ainda precisam de implementação e teste.

## Reaproveitar o Guia — conferência da implementação atual

Após Rodrigo apontar que o Guia lê conversas e funis, conferimos o main remoto
em `902f0059d76da8b1c74c47f57c8e66edc6d55bca`. A primeira leitura do checkout
principal antigo (`12b6433b639`) não representava a implementação atual.
O [parecer com fontes do código](reports/guide-crm-audit.md) registra a correção.

O Guia já possui `ler_da_conta`, `propor_acao`, `mostrar_tela` e `ler_da_central`.
A leitura consulta a API como o usuário do turno; o catálogo deriva das rotas
GET. Conversas, funis e cards são leituras reais; empresas dependem do recurso
Enterprise habilitado. O loop permite consultar mais de um recurso/página.

**Decisão recomendada:** compartilhar a capacidade de consulta e autorização
do Guia, com um contrato CRM tipado. O botão do Kanban invoca essa capacidade
com o contexto do funil e GPT-6 Luna; o Guia poderá usar a mesma capacidade
quando o pedido chegar pelo chat. Não criar outro agente persistente com KB,
permissões ou rotina de leitura próprias, nem obrigar a pessoa a abrir o chat
global para filtrar um quadro. O modelo do Guia não deve ser alterado como
consequência desta feature.

O gap concreto é empresa → contatos → cards visíveis. Atualmente `search`
consulta apenas `crm_cards.title`; encontrar Norte Logística no cadastro de
empresas não aplica esse vínculo à consulta CRM. Completar essa relação no
backend atende a busca manual e a IA pelo mesmo caminho. Não enumerar uma
página de cards no modelo para fingir uma consulta de todas as oportunidades.

O interpretador propõe critérios suportados. O servidor resolve referências
canônicas, valida a conta/permissões e calcula resultados/contagens. Nome
parcial ambíguo pede escolha; condição não suportada pede esclarecimento.
Prévia revisável antes da aplicação, mesmos chips e estado dos filtros manuais.
Para busca estruturada por empresa não é necessário ler corpos de conversas.
Pedidos semânticos sobre o conteúdo das mensagens são outro contrato e não
devem ser prometidos por este filtro inicial.

Leituras genéricas do Guia ainda têm regras de parâmetros simples e resumos.
O contrato de filtros precisa suportar listas/intervalos de forma explícita,
sem flexibilizar o catálogo inteiro. A proposta acima ainda precisa de
implementação e teste; auditoria estática não comprova acurácia do GPT-6 Luna
nem confirma quais commits já foram implantados em produção. US$0 gasto.
