> Registro histórico de uma rodada de implementação. Para o estado consolidado, consultar [QA e aceite](qa-acceptance.md) e a PR #760.

# Issue #757 — correções da revisão backend

Data: 29/09/2026. Base e HEAD conferidos: `8396d7255e097ba79507a22081701eb41ddb6ce5`.
Escopo desta rodada: backend, specs Ruby e este relatório. Sem commit/push, operações
remotas, produção, instalação global, modelos pagos ou escalada de permissões.
JS, auth, UI, Playwright, package.json e os seis documentos gerais ficaram a cargo do
supervisor. Nenhuma lógica de autenticação foi alterada: a mudança em ContactIdentifyAction
é somente o lock anterior à leitura/merge dos atributos.

Fontes lidas: `.codex/relationships/review-backend-final.md`,
`.codex/relationships/review-initial.md`, aditivos de `implementation-plan.md` e
`attributes-and-visibility.md`, `company-media.md`, código e specs atuais dos caminhos
abaixo. As alterações preexistentes/concorrentes do worktree foram preservadas.

## Escritores internos e contrato externo

Os seguintes caminhos agora recarregam o registro sob lock antes de decidir/preencher,
mesclar JSON e gravar:

- `app/services/data_import/contact_manager.rb`: contatos existentes são validados e
  atualizados dentro de `with_lock`; contatos novos continuam no caminho de criação/importação.
  Retirada a segunda aplicação redundante do snapshot após salvar o contato existente.
  A validação anterior à aplicação do CSV continua existindo, dentro do lock.
- `app/services/data_imports/importer.rb`: importador compartilhado dos provedores lê
  campos vazios e faz os merges dentro do lock. Mantém o `update_columns` preexistente.
- `app/services/crm/ai/attribute_extractor_applier.rb`: reavalia `already_filled` após
  adquirir o lock do contato/conversa. A auditoria também mescla metadata sob lock do card.
  Não faz nova chamada de IA nem altera coerções, confiança ou whitelist históricas.
- `app/services/autonomia/prospecting/contact_converter.rb`: contato existente é
  bloqueado antes do enriquecimento, dentro da transação que já bloqueava o lead.
- `app/actions/contact_identify_action.rb`: bloqueia o contato resultante das mesclas
  antes de ler e atualizar seus atributos, na transação existente.
- `app/actions/contact_merge_action.rb`: bloqueia os dois contatos em ordem de ID antes
  de montar os JSONs da mescla. Mantém a precedência do contato base e a lógica de opt-out.

Esses locks protegem as leituras internas que compõem uma gravação. Não inferem intenção
em snapshots externos. Se um cliente antigo envia `{a: 0, b: 1}` depois de outro ter salvo
`a: 1`, o payload completo sem base/revisão continua podendo restaurar `a: 0`.
Isso é o contrato legado de última gravação, indistinguível de uma edição intencional.
Não foi adicionada rejeição de payload histórico legítimo. O supervisor está corrigindo
callers oficiais para enviar somente o campo editado; abas antigas/integrações externas
continuam sujeitas ao contrato legado.

O protocolo novo `{key, value, previous}` faz comparação otimista por valor da chave.
Ele não é uma revisão global, não detecta ABA (um valor mudar e voltar ao original) e
não impede uma escrita legada posterior de substituir essa chave. Não há promessa de
preservação universal contra clientes arbitrários ou de auditoria de todos os JSONs do sistema.

## Definição e valor na mesma transação

`app/services/relationships/value_patch.rb` consulta a definição com `FOR UPDATE`, bloqueia
contato/empresa, valida a definição e o valor e grava dentro da mesma transação.
O lock da definição dura até o commit da transação externa, quando houver.

Ordem inspecionada: Configuration usa conta → definição; ValuePatch usa definição → registro,
sem adquirir conta depois desses locks. DefinitionWriter continua sendo chamado dentro da
transação de Configuration. Não foi acrescentado um lock invertido de conta.
Uma alteração/exclusão anterior libera o writer para ler a definição atual (ou devolver
not-found). Uma alteração posterior espera o valor terminar. Remover uma opção depois de
um valor já confirmado continua permitido pelo contrato de definições; não há migração
retroativa dos valores existentes.

Nenhum padrão histórico foi removido, interpretado ou reimplementado. O novo caminho
continua recusando atributos com validação histórica, inclusive limpeza. A fixture de
concorrência reutiliza metadados do spec histórico, sem introduzir expressão nova.
O lock exclusivo serializa gravações que compartilham uma definição; medir contenção
sob carga continua sendo necessário.

## Preview e recuperação

`enterprise/app/jobs/relationships/company_preview_job.rb`:

- `failure: content` identifica conversão recusada/corrompida/limitada; mantém fallback
  para o mesmo blob. Exceções do storage/IO/cache entram no caminho transitório.
- Falha transitória registra `failure_count`; no máximo três falhas por demanda, com
  reagendamentos de 10 e 20 segundos. Enquanto aguarda, permanece `pending`.
  Depois de esgotar, fica `unavailable` temporariamente.
- GET autorizado existente volta a enfileirar depois do TTL de dez minutos contado
  desde `requested_at`. Retry antes do TTL não ignora o backoff/limite. Não há API nova.
- Estados antigos `unavailable` sem classificação também expiram. Troca do blob inicia
  nova demanda. `enqueue_preview` considera blob, idade e `force:` interno explícito;
  o GET público não expõe force.
- Slot global ocupado continua `pending`, sem gastar `failure_count`, reagendando dentro
  da janela de demanda. O job recarrega elegibilidade após obter o slot.
- O derivado é enviado ao storage antes de associar/publicar `ready`. Isso evita publicar
  sucesso antes de um upload que ainda pode falhar após commit. IOs locais são fechados
  em blocos; derivado enviado mas não associado é encaminhado para purge.

Não é garantia de recuperação se banco/fila também estiverem indisponíveis. O estado
transitório depende de conseguir persistir metadata; falhas nessa etapa propagam para
as regras existentes da fila. Bibliotecas/conversores ausentes e limites de execução
continuam exigindo verificação do runtime. Não foi introduzido isolamento de SO.

## Renderer

`enterprise/app/services/relationships/preview_renderer.rb` confere assinaturas reais
PNG/JPEG/WebP e escolhe `pngload`, `jpegload` ou `webpload`, sem autodetecção de imagem.
Cabeçalhos incompatíveis são recusados antes de iniciar subprocesso; um cabeçalho válido
não substitui a validação pelo decoder. PDF também exige cabeçalho PDF.
MOV usa explicitamente `enable_drefs=0` e `use_absolute_path=0`; demuxers fixos e whitelist
de protocolo permanecem. URLs não são passadas como entrada. Os testes disfarçados de
imagem contêm referências locais/HTTP, mas o renderer as recusa antes de executar conversor.

Isso não comprova ausência de vulnerabilidades nos parsers nativos. Não foram medidas
leituras/syscalls de arquivos/rede em Linux. Limites de memória Linux, expansão adversarial,
fontes/PDFs e drefs de vídeos reais continuam gates de runtime.

## Testes e evidência desta rodada

Specs acrescentados:

- `spec/services/relationships/value_patch_internal_writers_spec.rb`: seis escritores
  reais, conexões PG distintas, espera verificada por `pg_blocking_pids`, preservação da
  chave confirmada e reavaliação `already_filled` do extractor. Sem mock dos escritores.
- `spec/services/relationships/value_patch_interleaving_spec.rb`: opção removida,
  definição excluída e validação histórica inserida durante a espera; retenção do lock
  até commit externo e enquanto espera o contato; concorrência com Configuration real.
- `spec/requests/relationships/value_patch_legacy_contract_spec.rb`: contato/empresa
  aceitam payload completo sem versão como última gravação; o patch novo detecta previous obsoleto.
- `spec/enterprise/jobs/relationships/company_preview_job_capacity_spec.rb`: advisory
  lock PG real em outra conexão, 25 anexos, quatro disputas de slot, contagem intacta e
  conversão após liberar capacidade.

Specs ampliados:

- `spec/enterprise/jobs/relationships/company_preview_job_spec.rb`: falha única de
  download/upload seguida de recuperação do mesmo blob com storage/conversor reais;
  falha injetada somente na fronteira do storage; backoff, limite, TTL, estado histórico,
  force interno e conteúdo corrompido. Esses exemplos precisam do PostgreSQL.
- `spec/relationships_unit/relationships/preview_renderer_spec.rb`: conversão real
  JPEG/WebP, além de PNG/PDF/MP4 existentes; GIF/SVG/PDF/playlist disfarçados; assinatura
  incompatível e PNG truncado. Esses exemplos foram executados nativamente.

Resultados executados:

| Verificação | Resultado | Log em `/private/tmp/` |
| --- | --- | --- |
| Ruby unit sem Rails, incluindo conversores nativos | 16 exemplos, zero falhas | `relationships-backend-fix-unit-native.log` |
| Gate AST contra base 8396 | 92 fontes/specs do worktree, nenhuma regex nova | `relationships-backend-fix-ast.log` |
| RuboCop dos 14 arquivos selecionados, exceto extractor | zero infrações | `relationships-backend-fix-rubocop-final.log` |
| RuboCop extractor base/atual | sete infrações em ambos; ABC 26,32→27,24 e tamanho 21→23 no método envolvido pelo lock | `relationships-backend-fix-ai-baseline-lint.log`, `relationships-backend-fix-ai-current-lint.log` |
| Diff whitespace | passou | `relationships-backend-fix-diff-check.log` |
| Rails/PG | bloqueado antes dos exemplos: `127.0.0.1:55757 Operation not permitted` | `relationships-backend-fix-pg.log` |
| Linux local | host Darwin arm64; nenhum Docker/Podman/Colima/Lima localizado | `relationships-backend-fix-linux-runtime.log` |

A primeira execução unitária teve cinco falhas por carregamento das bibliotecas portáteis
via shebang; a invocação direta do Ruby preservou o ambiente de bibliotecas e os 16 exemplos
passaram. Nenhuma dependência instalada, teste relaxado ou erro de sandbox contornado.
RuboCop completo **não está verde**: as sete categorias do extractor já falhavam na base;
foram preservadas as coerções/estrutura legadas para limitar o diff. Logs intermediários
também estão no prefixo `relationships-backend-fix-*`.

## Execução pendente para o supervisor

O runner `/private/tmp/relationships-backend-fix-rspec.rb` desativa carga de `.env` via
configuração de Dotenv para `/dev/null`. A tentativa usou somente o ambiente sintético
já preparado em `.codex/relationships/test-env.sh`. Não iniciar outra infraestrutura
nem usar banco real para liberar este gate.

Com PostgreSQL isolado permitido e as bibliotecas disponíveis:

```sh
eval "$(rbenv init -)"
source .codex/relationships/test-env.sh
ruby -S bundle exec ruby /private/tmp/relationships-backend-fix-rspec.rb \
  spec/services/relationships spec/requests/relationships \
  spec/enterprise/jobs/relationships \
  spec/enterprise/services/relationships spec/enterprise/requests/relationships \
  spec/services/crm/ai/attribute_extractor_applier_spec.rb \
  spec/services/autonomia/prospecting/contact_converter_spec.rb \
  spec/services/data_imports/freshdesk/importer_spec.rb \
  spec/services/data_imports/intercom/importer_spec.rb \
  spec/jobs/data_import_job_spec.rb \
  spec/actions/contact_identify_action_spec.rb spec/actions/contact_merge_action_spec.rb \
  --options /dev/null
ruby -S bundle exec ruby -S rspec spec/relationships_unit --options /dev/null
```

Não executar os specs concorrentes deste grupo em paralelo no mesmo banco: o slot de
preview é global por banco. Revalidar também os controllers legados de contatos/empresas
e configurações, E2E do supervisor e runtime Linux real. Esta rodada não fornece evidência
de aceite PG/E2E/Linux, latência, ausência global de deadlocks ou zero regressões.
Issue/branch preexistentes; PR/Project/review externo, aprovação e deploy seguem pendentes
e fora da autorização desta rodada. Nenhum dos seis documentos gerais foi reescrito aqui.
