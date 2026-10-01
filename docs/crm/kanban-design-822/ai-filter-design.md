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

1. Em Filtros, abrir **Encontrar com IA**.
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
