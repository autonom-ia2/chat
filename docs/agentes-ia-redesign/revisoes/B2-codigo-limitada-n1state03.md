# Checagem limitada N1/STATE03 — B2

**Alvo:** snapshot24 `/Users/Shared/maccluster-workspaces/chat2you/20261007-185427-532a5b7b-b1aa0b036a-315b68de/src`  
**SHA:** `b1aa0b036a4d47b5c82d889cb07de3cd05a395db71554c5464fb71d7760b9d8f`  
**Referência de causa:** `docs/audit/2026-10-07-agentes-b2-n1state03-causa-raiz.md`  
**Tipo:** checagem limitada única, somente leitura e estática.

## Resultado

**STOP — o contrato de orçamento da projeção falhou no runtime24.**

A leitura estática dos quatro contratos continua coerente, e o ensaio específico de disponibilidade nativa de 1 para 20 agentes passou com custo constante. Porém, a execução coordenada encontrou uma falha concreta no orçamento geral da projeção: `index_spec[1:5]` esperava no máximo 12 SELECTs e observou 14.

Evidência registrada pelo coordenador: 222 exemplos, 1 falha, 0 pendências/externos; JSON `/tmp/chat2you-agentes-b2-b3-check24.json`, SHA `9ef84ec2669c887ad6f1ca4a1db3dcc4898344504365f9a7ae69c418c3bbca04`, job `m2-6c966836c151480392595bde27e5df9c`.

O residual impede declarar N1 aprovado. A causa aparente é a soma de duas leituras introduzidas incondicionalmente no caminho de `ListProjection`: o `includes(:account, ...)` em `app/services/autonomia/agents/list_projection.rb:11` e o `Connection.preload_for_accounts(...)` em `:29`, mesmo quando a projeção mista não precisa consultar disponibilidade nativa. O código confirma os dois caminhos; a atribuição exata de cada SELECT ainda deve ser comprovada pelo coordenador antes da correção final.

O ensaio separado de disponibilidade nativa de 1 para 20 agentes passou com custo constante, portanto o residual está no orçamento da projeção mista, não autoriza ampliar o escopo nem declarar toda a integração GREEN. Esta checagem para aqui até a causa ser confirmada e corrigida na única etapa final autorizada.

## Contratos conferidos

### Isolamento da disponibilidade

Em `app/models/autonomia/insurance/connection.rb:53-100`, a leitura em lote recebe IDs deduplicados e seleciona apenas `id`, `account_id` e `status`. O contexto temporário usa `ActiveSupport::IsolatedExecutionState` e restaura o valor anterior em `ensure`. A chamada fora da projeção mantém o caminho anterior `for_account(account).any?(&:ready?)`.

Isso cobre o limite de disponibilidade por conta sem expor credenciais, sessão cifrada, capabilities ou payload serializado. O contexto não fica disponível para outra conta, request ou execução depois do bloco.

### Política própria de cada agente

Em `app/services/autonomia/agents/tools/registry.rb:68-84`, `for_agents` apenas avalia `for_agent(agent)` individualmente dentro do contexto de leitura. O método preserva:

- slugs habilitados pelo agente;
- catálogo fechado e deduplicação;
- `available_for?` de cada ferramenta;
- a política especial da Lia, que usa as ferramentas mantidas pelo deploy.

Não há união de slugs entre agentes nem substituição da política de runtime.

### Projeção e digest

Em `app/services/autonomia/agents/list_projection.rb:20-43`, a projeção pré-carrega a associação `account`, carrega a disponibilidade uma vez para as contas dos rascunhos e gera o mapa nativo por agente. Em `:80-95`, o vetor já calculado é passado ao `TestDigest`; o digest não precisa navegar novamente pelo Registry ou pelas conexões.

O restante da projeção usa agregações em lote para threads, fontes, entries, tools e eventos. O contrato de teste existente mede 1 contra 20 agentes, exige o teto de 12 SELECTs da projeção e igualdade do custo; o GET mede o teto de 20. Essa evidência ainda depende da execução coordenada, que não foi assumida nesta checagem.

### Segurança

O caminho de disponibilidade não seleciona nem serializa credenciais, sessão, capabilities ou URL. O vetor nativo fica interno à projeção e não entra no payload da lista.

## Limite

O resultado final desta checagem limitada é STOP por falha observada no runtime24. Não houve nova revisão geral nem edição de produto nesta sessão. Nenhum teste, build, banco, rede ou produção foi executado por esta sessão; o resultado runtime24 foi apenas incorporado como evidência fornecida pelo coordenador.
