# #792 — Parte 2: contato novo no mesmo card

**Data:** 30/09/2026. **Estado:** parte concluída localmente; pausar para novo de acordo de Rodrigo. A parte 1 foi aprovada para continuidade, não para merge. PR #793 permanece em rascunho. Nenhum merge/deploy desta frente.

## Base, autorização e isolamento

- Branch: `feat/792-crm-relacionamentos`, worktree `/Users/rodrigosilva/dev/worktrees/chat2you-792-crm-relacionamentos`.
- Retomada limpa em `e9afc8024d269176891ece8f4b0e5b161eb6ad49`; base main `e45fbe68945f948525dcc0a2997eae5c3c9dc74f`.
- Autorização desta parte: criar contato a partir de card sem vínculo, vinculando ao mesmo card; revisar/testar e parar. Não inclui empresa nova, outra oportunidade, frontend completo ou publicação.
- Banco da bateria: PostgreSQL local exclusivo `chat2you_792_test`. Prova de commits/concorrência: banco scratch separado `chat2you_792_probe_test`.
- Redis exclusivo loopback na porta 6792; DB 0 para bateria, DB 1 para a prova. O Redis compartilhado da porta 6379 não foi usado.
- `RAILS_ENV=test`, ActionMailer/ActiveJob de teste e WebMock sem HTTP externo. Somente fixtures. Nenhuma conexão/dado/credencial da AWS foi usada; nenhuma mensagem real foi enviada.

## O que foi implementado e revisado

Novo endpoint `POST .../crm/cards/:card_id/contact`, em controller pequeno próprio, reutiliza as políticas atuais de vínculo/criação e o serviço de vínculo da parte 1. Cria apenas o contato e mantém o ID e os campos comerciais da oportunidade existente. Exige chave de idempotência e valida tipos/shape do payload; IDs/permissões, empresa e identificador externo não são aceitos no novo contrato.

`ContactCreator` recarrega e trava o card, recusa card já vinculado e cria o contato como lead explícito. A transação inclui pessoa, vínculo, atividade, claim e resposta de idempotência. Falhar no vínculo, auditoria ou captura da resposta não deixa registros parciais. O mesmo retry pode retornar a resposta já confirmada; duas intenções concorrentes no mesmo card não geram duas pessoas.

A nova rota continua negada aos tokens de integração pelo mapa default-deny. Nenhum perfil, scope ou mecanismo de autenticação foi ampliado. Usuário com apenas `crm_view`, contato sem permissão de criação e IDs de outra conta foram cobertos. A autorização atual é verificada antes de replay.

### Mudança intencional para cadastro somente com nome

O cadastro usa `contact_type=lead`, sem e-mail/telefone/identifier fictícios. A lista clássica passa a incluir leads explícitos sem identificação (inclusive antigos); não inclui visitantes anônimos apenas por terem nome. A lista `crm_v2` mantém a regra existente de leads. Uma expectativa antiga de `spec/models/contact_spec.rb` foi atualizada porque descrevia exatamente a exclusão que o requisito aprovado remove; os demais casos de tipos, conta e identificação permanecem testados.

A rotina de limpeza agora seleciona visitantes sem conversas e sem cards; não apaga leads/clientes só por faltar identificação. Foram testados nome-only após unlink, oportunidade arquivada e visitante legado com card. Nenhum registro histórico foi classificado, migrado, fundido ou limpo em produção.

### Eventos

O broadcast do card é registrado para depois do commit. Os callbacks nativos de contato também ocorrem após commit, sem anunciar uma criação revertida. A prova real confirmou que, quando o callback roda, o vínculo e a resposta de idempotência já estão persistidos.

**Limite importante:** os webhooks normais de `contact.created` são preservados, não desligados globalmente. Integrações externas configuradas podem reagir a eles; seus efeitos precisam ser verificados antes de prometer silêncio global na UI/produção. O endpoint não inicia conversa/inbox, não cria mensagens, follow-ups ou convites, nem cria outro card. Nenhum destinatário real foi utilizado.

## Evidências executadas

| Execução | Resultado |
|---|---|
| Baseline antes do incremento: CRM, contato e limpeza | 130 exemplos; 127 passaram; 0 falhas; 3 suspensos antigos. |
| API nova | 36 exemplos; 36 passaram. |
| Bateria intermediária CRM + contato + limpeza, seed 792 | 175 exemplos; 172 passaram; 0 falhas; 3 suspensos antigos. |
| Bateria final ampliada, incluindo serviços de contato e controllers OSS/Enterprise, seed 793 | 306 exemplos; 303 passaram; 0 falhas; os mesmos 3 suspensos. |
| Testes novos nesta parte | 49: 36 requisições, 9 serviços e 4 permissões Enterprise. Todos passaram na bateria final. |
| Prova local com commits reais e duas conexões concorrentes | 3 cenários passaram, inclusive após a revisão/formatação do script. |
| RuboCop | 9 arquivos Ruby inspecionados; sem infrações na execução final. |
| `pnpm guia:check` | Em dia: 169 fluxos, 170 telas, nenhuma sem explicação. |
| `pnpm i18n:fork:check` | 8 catálogos, 15.786 mensagens; chaves/parâmetros en/pt_BR cobertos. |
| `git diff --check` | Sem erros. |

O conjunto final inclui testes existentes adicionais ao baseline; não se afirma que os 306 foram todos executados antes da mudança. Os três suspensos continuam em `spec/requests/api/v1/accounts/crm/cards_spec.rb`, linhas 333, 556 e 583, já documentados na parte 1. Não foram removidos ou contados como aprovados. Warnings antigos de Rails, Rack, Browserslist e logger do mapa não foram suprimidos.

A API foi primeiro exercitada sem a nova rota para registrar a ausência do comportamento. A primeira inicialização do script de prova falhou por load path do `spec_helper`; a inicialização foi corrigida e ganhou guardas de banco/Redis ANTES de carregar Rails. Regras de estilo/complexidade identificadas pelo lint foram corrigidas sem desativar cops. Todas as execuções finais listadas acima passaram.

### Prova de concorrência e atomicidade

Script versionado: `spec/probes/crm_contact_creation_probe.rb`. Não participa automaticamente da suíte: exige banco scratch vazio com o nome exato e Redis exclusivos; recusa outra configuração antes de carregar Rails.

1. Duas requisições HTTP simultâneas, mesma chave e mesmo card: respostas 201/201, uma com `Idempotency-Replayed`; delta de 1 contato, 0 cards, 1 atividade, 1 chave.
2. Duas requisições simultâneas, chaves diferentes e mesmo card: respostas 201/422; mesmo delta, sem pessoa extra nem claim abandonado.
3. Falha injetada ao persistir a resposta: contato, vínculo, atividade e claim revertidos; callback de contato não executado. Retentar a mesma chave depois da remoção da falha retorna 201.

A prova usa requisições reais pela aplicação Rails, threads/conexões distintas e commits de PostgreSQL reais. Não é apenas simulação de objeto desatualizado ou fixture transacional. O isolamento é da instância local; não é um teste de carga da AWS.

## Reexecução e logs

A bateria final usa `.codex/792/test.sh` local (ignorado), que fixa Ruby 3.4.4, ambiente de teste, PostgreSQL loopback e Redis exclusivo. Com esses serviços disponíveis:

```bash
bash .codex/792/test.sh rspec \
  spec/models/crm/card_spec.rb spec/services/crm/cards \
  spec/requests/api/v1/accounts/crm/cards_spec.rb \
  spec/requests/api/v1/accounts/crm/card_contact_links_spec.rb \
  spec/requests/api/v1/accounts/crm/card_contact_creation_spec.rb \
  spec/enterprise/requests/api/v1/accounts/crm/card_contact_creation_spec.rb \
  spec/models/contact_spec.rb spec/services/contacts \
  spec/services/internal/remove_stale_contacts_service_spec.rb \
  spec/controllers/api/v1/accounts/contacts_controller_spec.rb \
  spec/enterprise/controllers/api/v1/accounts/contacts_controller_spec.rb \
  --seed 793 --format progress --format json --out .codex/792/part2-final.json
```

A prova exige `RAILS_ENV=test`, `DATABASE_URL=postgresql://postgres@127.0.0.1:5432/chat2you_792_probe_test` e `REDIS_URL=redis://127.0.0.1:6792/1`, além das dependências de teste do lockfile. O wrapper `.codex/792/probe.sh` usa essas variáveis e `bundle exec`. Carregar o schema somente num banco scratch novo/vazio e executar `bash .codex/792/probe.sh ruby spec/probes/crm_contact_creation_probe.rb`. Para repetir, reconstruir SOMENTE esse banco de prova; nunca usar uma base compartilhada/produção. O script não faz limpeza automática de bancos arbitrários.

Logs/JSON locais: `part2-baseline.*`, `part2-red.log`, `part2-api.*`, `part2-regression.*`, `part2-final.*`, `part2-probe-final.log` e logs de lint. Os dois bancos de teste são separados; reconstruir o banco de prova não afetou o da bateria.

## Limites e checkpoint

A revisão desta parte é a releitura do código, regras de autorização, transações/callbacks e testes, incluindo reexecução após ajustes. Não é revisão independente por outra pessoa/agente. A revisão independente do conjunto permanece para antes do pedido final de merge.

A garantia de concorrência demonstrada é sobre este endpoint no mesmo card. Concorrência de identidade (especialmente telefone) entre cards diferentes/outros escritores, `ConversationLinker`, upserts, resolução completa de duplicidades e automações externas continuam na revisão transversal do plano. Não se considera M02 ou M05 inteiramente concluído.

Nenhum frontend foi alterado; não há nova tela para homologar nesta parte. Criação de empresa, criação composta de oportunidade, editores, atributos, mídias e navegação completos permanecem pendentes. SHA/flags efetivos da AWS não foram inferidos a partir da main.

Próximo passo proposto, ainda não autorizado: primeiro trecho visual de M01, aba Relacionamento com contato/empresa reais e estados vazios, fiel ao HTML. Ao apresentar a parte 2, parar novamente. Só pedir merge após todas as partes revisadas/testadas; os workflows atuais podem publicar duas stacks, exigindo autorização de escopo.

Não foram adicionadas migrações, flags, dependências, regex ou alterações de produção. A reversão do código não precisa apagar cadastros. Atenção: voltar à regra antiga de listagem/limpeza pode ocultar/expor à limpeza leads sem identificação já criados; o rollback futuro precisa preservar a proteção desses cadastros ou suspender a limpeza por procedimento aprovado antes da reversão. Isso não será executado automaticamente.
