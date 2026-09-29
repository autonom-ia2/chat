# Retomada da Issue #757 — resultado local

Base/HEAD confirmados: `8396d7255e097ba79507a22081701eb41ddb6ce5`.
Worktree exclusivo `chat2you-757-relacionamentos`, branch `feat/757-relacionamentos`.
Sem add/commit/push/merge/deploy, GitHub, SSH, produção, instalação global ou chamadas pagas.
As modificações da implementação anterior foram preservadas. Nenhum outro worktree foi editado.

## Correções

- Regra sem regex aplicada: campos e traduções removidos do modal; endpoint novo recusa
  parâmetros de regras; nenhuma interpretação Ruby/Node. Os testes reutilizam metadados de
  fixtures históricas, sem definir padrões novos. Valores com validação histórica usam
  CustomAttribute e endpoints legados; `ValueValidator` recusa também limpar pelo caminho novo.
  Nova chave usa caracteres explícitos; edição não envia chave, regras ou opções inalteradas.
- Account settings e custom_attributes de Contato/Empresa legados agora leem/mesclam/gravam
  sob o mesmo lock. Definição/layout continuam transacionais, com revisão e rollback conjunto.
  `legacy_interleaving_spec.rb` faz duas requisições, conexões e usuários reais, aguardando
  `pg_blocking_pids` comprovar a sobreposição antes de confirmar o novo fluxo.
- Datas compartilham helper de calendário sem regex, preservando o dia escrito em date-only
  e timestamps ISO históricos. Zero não vira vazio. Checkbox acompanha props e usa o evento
  correto do Switch, sem alterar o componente global.
- FieldEditor aplica somente a chave confirmada sobre o store vivo; protege contexto,
  rascunho, desmontagem e confirmações antigas. Testes usam mutations/getters de Contatos e
  Pinia Empresas reais com respostas invertidas. Compacto tem link HTTP(S), copiar, editar,
  limpar por confirmação e informação acessível; modo legado mantém CustomAttribute.
- Dois botões diretos, Input/TextArea e ChoiceSelect no modal; descrição obrigatória; aviso
  global por conta; superfície inicial contextual. Guards incluem custom_attributes,
  companies e gestão. Alteração de conta/entidade/permissão fecha o rascunho.
- Cache por store/sessão, usuário e conta; CLEAR_USER invalida, foco revalida. Reads anteriores
  a saves/contextos são descartados. Revisões no store de atributos impedem GET legado atrasado
  de apagar definições confirmadas. Um read compartilhado continua para superfícies montadas.
- Mídia: cinco recentes na lateral, tipo/tamanho reais, filtros preservados no detalhe, busca
  e agrupamento no servidor. Notas entram somente em conversas autorizadas. URLs externas não
  são buscadas no servidor; escopo e fallback pela conversa original estão explícitos.
  Downloads/visualizações atrasados não abrem após desmontagem ou troca de contexto.
- Miniaturas por viewport; polling de cinco segundos por até onze minutos e retry explícito;
  ícones por tipo, sem onda inventada. Fila low, slot global e demanda de dez minutos;
  capacidade ocupada permanece pending e não transforma arquivo válido em falha permanente.
  Blob alterado invalida derivado. Renderer valida resultado/assinatura, força demuxers de
  vídeo e limita entrada/saída/tempo/CPU; memória limitada no Linux. ffmpeg declarado no runtime.
- AST automático via Babel/Vue e Prism, comparando com a base aprovada. `relationships:test`
  roda o gate antes dos componentes. Nenhuma regra de lint/testes foi reduzida.
- README, contratos, aditivo, Central e Guia atualizados; gerados somente pelos comandos próprios.

## Evidências locais

| Verificação | Resultado | Log local |
| --- | --- | --- |
| JS/Vue, componentes e stores reais + regressões legadas selecionadas | 15 arquivos, 74 testes passaram | `/private/tmp/relationships-js-final.log` |
| Ruby unit sem Rails/banco, conversões nativas e validações | 12 exemplos, zero falhas | `/private/tmp/relationships-unit-final.log` |
| RuboCop, controllers legados + código/specs novos | 25 arquivos, zero infrações | `/private/tmp/relationships-rubocop.log` |
| ESLint de todos os JS/Vue/MJS alterados | zero erros, 287 avisos | `/private/tmp/relationships-eslint-final.log` |
| Gate AST sem regex | 73 arquivos parseados, passou | `/private/tmp/relationships-ast-final.log` |
| Prettier dos fontes alterados | passou | `/private/tmp/relationships-prettier-final.log` |
| Guia build/check | 169 fluxos, 170 telas, nenhuma sem explicação | `/private/tmp/relationships-guia-build.log`, `relationships-guia-check.log` |
| Central geração de roteiro/check | 174 artigos, 170 telas; roteiro regenerado sem diff | `/private/tmp/relationships-central-build.log`, `relationships-central-check.log` |
| `git diff --check` | passou | saída da ferramenta |
| Build Vite final | passou, exit 0; avisos de Browserslist/chunks | `/private/tmp/relationships-build-final.log` |

Comandos finais:

```sh
pnpm test app/javascript/dashboard/components-next/Relationships/specs app/javascript/dashboard/store/modules/specs/attributes app/javascript/dashboard/routes/dashboard/companies/pages/CompanyDetailView.spec.js app/javascript/dashboard/stores/specs/companies.spec.js app/javascript/dashboard/routes/dashboard/settings/attributes/specs/Index.spec.js app/javascript/dashboard/components-next/Contacts/ContactOptOut/ContactOptOutSection.spec.js --maxWorkers=2 --minWorkers=2
bundle exec rspec spec/relationships_unit --options /dev/null
pnpm relationships:check
pnpm exec vite build --mode test --logLevel warn
pnpm guia:build
pnpm guia:check
pnpm central:prints
pnpm central:check
```

As rodadas intermediárias falharam em fixtures/mocks incompletos (store.subscribe,
accountId, axios global, URL.createObjectURL), corrida de desmontagem de read compartilhado
e limite de memória macOS. Foram corrigidas e repetidas. Uma rodada paralela sob carga
excedeu o timeout de teste/conversor; a execução consolidada usou dois workers, mantendo
os timeouts originais. Nenhuma asserção, timeout ou regra de lint foi relaxada.
Warnings: i18n estático/dinâmico, sourcemap ausente de dependência, Browserslist, diretivas
não registradas em alguns mounts e evidências antigas da Central. Não são prova de ausência
de regressão visual. Rails/PostgreSQL e E2E não foram executados nesta retomada sandboxed.

## Gates que o supervisor deve executar

Não é ready e não é autorização de release. Permanecem obrigatórios:

1. Rails/PostgreSQL: toda a suíte nova, incluindo interleaving, transação/rollback, revisão,
   papéis, cross-account, notas privadas permitidas/restritas, autorização de originais/preview,
   agrupamento entre dois contatos/páginas, blob alterado e disputa de capacidade com 25 arquivos.
2. Browser com backend real e fixtures sintéticas: baseline/off/on, duas contas e papéis,
   fichas/lateral/aba completa, criar/salvar/reabrir, foco/teclado/mobile/scroll, contexto e falhas.
3. Runtime Linux: imagem com vips/poppler/ffmpeg, memória/expansão adversarial, CPU/timeout,
   contenção real de fila, expiração e medições de consultas/p95 estabelecidas no plano.
   macOS não aceita os limites RLIMIT_AS/RSS; o resultado nativo não comprova esse gate.
4. Revisão independente, Project/PR e aprovação do Rodrigo. Operações remotas continuam proibidas
   nesta retomada. Plano de rollback por flags/binário permanece em rollout-rollback.md.

Comando Rails sugerido ao supervisor:

```sh
bundle exec rspec spec/services/relationships spec/requests/relationships spec/enterprise/services/relationships spec/enterprise/requests/relationships spec/enterprise/jobs/relationships spec/controllers/api/v1/accounts/custom_attribute_definitions_controller_spec.rb spec/enterprise/controllers/api/v1/accounts/companies_controller_spec.rb
```

## Local dos logs

O sandbox negou a tentativa de escrever `.codex/relationships/continuation-result.md`.
Sem contornar permissões: resumo neste arquivo; logs em `/private/tmp/relationships-*`.
O supervisor pode copiar este resumo e os logs finais para `.codex/relationships`.
