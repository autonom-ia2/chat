# B2 inicial — causas antes da correção

**Data:** 07/10/2026  
**Branch/worktree:** `docs/agentes-ia-prd` / `/Users/rodrigosilva/dev/worktrees/chat2you/agentes-ia-prd`  
**Snapshot RED:** `/tmp/chat2you-agentes-b2-initial.json`  
**Resultado:** 117 exemplos, 30 falhas, 0 pendentes, 0 erros fora dos exemplos.  

Este registro antecede qualquer correção deste bloco. O resultado completo do RED continua no arquivo
local indicado acima; não houve nova execução, banco, produção, commit ou push nesta análise.

## Causa B2-B-01 — falso negativo do teste do digest

O único exemplo que falha diretamente em `MaterialProjection` é
`spec/services/autonomia/agents/material_projection_spec.rb:236`, com as asserções em 243 e 247.
O exemplo chama `projection` para criar `baseline`, altera o fingerprint da fonte e chama `projection`
novamente; depois altera `updated_at` da entry e chama o mesmo método pela terceira vez.

O helper do próprio spec, na linha 29, é:

```ruby
def projection
  @projection ||= service_class.new(agent: agent).call
end
```

Portanto, todas as chamadas devolvem o mesmo `Result` memoizado. O fingerprint e o timestamp nunca
voltam a ser lidos. A mensagem do RED (“digest igual”) é consequência de fixture/cache do teste, não
prova de erro em `snapshot_digest`, na precisão de seis casas ou na consulta de `KnowledgeEntry`.
A correção deve remover somente esse cache do helper ou construir uma nova projeção em cada comparação;
não deve alterar o algoritmo para acomodar o teste stale. O teste novo de precisão e os demais casos
devem permanecer.

## Causa B2-B-02 — invalidação material pode limpar teste iniciado depois da escrita

O caminho atual calcula um digest anterior, efetiva a escrita do material e só depois chama
`MaterialProjection.invalidate_if_digest_changed!`, que termina em `AgentStateStore.invalidate!`.
Entre esses dois momentos, outro request pode chamar `AgentStateStore.start_pending!` e substituir o
namespace pelo `session_id` do novo Testar. Como `start_pending!` ainda não carrega no namespace o digest
capturado pelo novo teste, a invalidação posterior só enxerga “há um teste” e limpa indiscriminadamente
o teste novo.

Sequência concreta:

1. teste A está em andamento ou concluído com o material antigo;
2. writer grava uma entry/fingerprint nova;
3. antes de `invalidate!`, teste B começa e grava `completion=pending`;
4. writer compara digest antigo/novo e executa `AgentStateStore.invalidate!`;
5. o teste B é apagado, embora tenha começado depois da mudança e deva usar o snapshot novo.

Isso é uma condição de corrida entre o escritor de material e o domínio de lock do Agent. Não deve ser
resolvida com um `sleep`, retry ou guarda baseada em estado informativo. A correção precisa preservar o
lock/versão de sessão do AgentStateStore e invalidar somente a conclusão ou sessão que existia antes da
mudança; a implementação do domínio de lock fica com o owner de Agent/estado. Este documento não altera
`Agent` nem `AgentStateStore`.

### Contrato mínimo para a correção

- o escritor fotografa, antes da mutação, o `session_id` observado no namespace do teste;
- `MaterialProjection.invalidate_if_digest_changed!` recebe esse identificador explicitamente e chama
  `AgentStateStore.invalidate_if_current!(agent:, reason: 'material', session_id:)`;
- o novo método executa a comparação e a invalidação dentro do mesmo `with_lock` do Agent, devolvendo
  `false` quando a sessão atual é outra (inclusive quando ela está `pending` ou `completed`) e `true`
  somente quando ainda é a sessão fotografada;
- ausência observada antes da escrita (`nil`) não é um pedido para limpar uma sessão posterior: o escritor
  não invalida nesse caso. Chamadas sem a fotografia devem permanecer impossíveis no caminho de material,
  ou usar um sentinel explícito no domínio, para não transformar ausência em wildcard.

Essa interface mantém a ordem Agent → Source: a fotografia ocorre antes da escrita, a projeção após a
escrita acontece sem segurar lock de Source, e somente o método do Store adquire o lock de Agent para
validar a sessão. O owner do Agent/estado deve implementar o método; este bloco não altera o Store.

O spec de MaterialProjection registra os dois interleavings necessários (nova sessão `pending` e nova
sessão `completed`) e a sessão ainda corrente. Eles devem permanecer como prova do contrato quando o
owner integrar o método atômico.

## Escopo do restante do RED

As outras 29 falhas do JSON são de fatias de estado, digest, recorder, async, canais e lista pertencentes
aos owners correspondentes. Elas não são atribuídas à projeção material sem prova. O lint agregado do
job `m2-b20d7658e3aa4664b3c543ecd1efb905` foi reportado inicialmente com 172 ocorrências em 84 arquivos
(log consolidado posterior: `/tmp/chat2you-agentes-b2-lint15.log`); a correção deste owner deve
ler a saída completa e tratar as ofensas reais nos arquivos de Material/Stats/Sources/Ingest/Process/
Reviewer/FAQ, incluindo métricas de método/classe, sem desativar cops. Nenhum número de linha de lint é
inventado neste registro porque a saída completa não está neste checkout.

## Estado da revisão

Ainda não é revisão normal B2. O bloco está em diagnóstico pré-correção; após resolver a causa do teste e
receber a decisão do owner de Agent para a corrida, os arquivos serão validados apenas estaticamente antes
do próximo snapshot coordenado.

## Correção documental e estática deste owner

Após o RED, o helper `projection` do spec deixou de memoizar o resultado. A projeção agora mantém o
digest determinístico, a precisão de seis casas no timestamp e o contrato de `uses_reason: nil` para
fontes prontas em escopo. Os escritores Ingest/Process, Reviewer, FAQ e exclusão de Source fotografam a
sessão antes da mutação e carregam a fotografia até a invalidação; nenhuma callback nova foi criada.

O spec acrescentou os cenários da sessão nova `pending`, da sessão nova `completed` e da sessão do
writer ainda corrente, contra `AgentStateStore.invalidate_if_current!`. A implementação do método
atômico continua com o owner do Agent/estado, conforme o contrato acima.

Validações locais: `ruby -c` sob Ruby 3.4.4 nos arquivos tocados e RuboCop direcionado sem ofensas nos
10 arquivos próprios (MaterialProjection, ListStats, Source, SourcesController, IngestJob, ProcessJob,
Reviewer, KnowledgeWriter e os dois specs). RSpec, banco, serviços e produção não foram executados neste
bloco.

## Snapshot16 — causas confirmadas antes da correção deste bloco

O snapshot coordenado no M2 (`/tmp/chat2you-agentes-b2-initial16.json`) reportou 124 exemplos, 20
falhas; esta seção registra somente as duas falhas desta fatia. A contagem não foi reproduzida nesta
worktree e nenhum RSpec, banco ou serviço foi executado localmente.

### B2-B-03 — associação de fontes obsoleta no caminho normal

O exemplo `spec/services/autonomia/agents/material_projection_spec.rb:236` falhou na asserção da
linha 243: depois de `source.update!(metadata: { 'fingerprint' => 'fp-used-v2' })`, o digest da
projeção nova permaneceu igual ao baseline. A causa antiga documentada em B2-B-01 não explica esse
snapshot: o helper `projection` atual da cópia examinada na linha 29 constrói um
`MaterialProjection` novo a cada chamada.

A causa verificável agora é o cache do Active Record. A primeira projeção sem `sources:` carrega
`agent.sources`; depois, `source.update!` grava por outra instância do registro, enquanto a associação
já carregada conserva a instância com o fingerprint antigo. A projeção seguinte consulta a associação
cacheada, portanto não reentra no fingerprint usado. O caminho de produção já chama `reset` em pontos
de escrita, mas o contrato do serviço sem `sources:` não deve depender de o chamador lembrar desse
detalhe. A correção mínima é recarregar a associação somente nesse caminho; o caminho explícito
`sources:` continua usando as fontes pré-carregadas e não faz consulta, como o spec exige. Não se deve
adicionar `reload` por fonte nem alterar o digest para mascarar o dado stale.

### B2-B-04 — chamada inválida de `match_array` na prova de paridade

O segundo erro desta fatia é `spec/services/autonomia/agents/material_projection_spec.rb:272`, com
`ArgumentError: wrong number of arguments (given 3, expected 1)`. A expectativa passa três ids
posicionais a `match_array`, cuja API recebe uma única coleção. Isso impede chegar à chamada real do
Retriever e não prova divergência entre Retriever e MaterialProjection. A correção mínima é envolver
os três ids em uma matcher que aceite os argumentos posicionais (`contain_exactly`); nenhum código de
produção ou comportamento de retrieval deve mudar.

### Correções aplicadas depois do registro da causa

`MaterialProjection#source_rows` agora usa `agent.sources.reload` apenas quando o chamador não fornece
`sources:`; fontes e agregados explicitamente pré-carregados continuam sem consulta. A expectativa de
paridade agora usa `contain_exactly` com os três ids. Não foi executado RSpec, banco, serviço ou
produção após essas alterações; a verificação desta etapa foi somente `ruby -c`, RuboCop direcionado e
`git diff --check`.
