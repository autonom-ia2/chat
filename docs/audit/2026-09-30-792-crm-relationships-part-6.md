# #792 — Parte 6: Nova oportunidade com cadastro existente ou sem vínculo

## Aprovação e limite do incremento

Rodrigo aprovou a parte 5 e autorizou somente o primeiro trecho de Nova oportunidade. Referência: HTML aprovado `chat2you-crm-relacionamentos.html`, cenários M03 e criação sem vínculo. Worktree `chat2you-792-crm-relacionamentos`, branch `feat/792-crm-relacionamentos`, Issue #792, PR #793 em rascunho. Base desta parte: `144015e3801506cb5bf06d2cad54e941dc1c5425`.

Não houve merge, deploy, mudança de flags na AWS, migração ou credencial nova. O cadastro composto de contato/empresa/oportunidade continua em outra parte, dependente de aprovação. O plano M01–M08 não está concluído.

## Experiência entregue

`CrmOpportunityForm` substitui o formulário antigo de Novo card. A lateral mantém 40rem e usa os componentes e tokens existentes. São duas seções na mesma tela, sem assistente de páginas:

1. **Relacionamento**: buscar e selecionar contato existente ou escolher explicitamente continuar sem vínculo. O resumo mostra pessoa, empresa canônica, e-mail e telefone. Trocar a pessoa ou o modo conserva os dados comerciais preenchidos. Não há botão de criação do zero inativo ou tela simulada neste incremento.
2. **Oportunidade**: título, funil, etapa, valor e responsável; Mais opções conserva descrição, prioridade inclusive urgente, previsão, score, moeda e caixa de entrada opcional. Funis e etapas vêm das APIs autorizadas, não dos dados do protótipo.

O rodapé fixa Cancelar e Criar oportunidade e informa se o resultado inclui vínculo com contato existente. A validação não apresenta erro de título antes de qualquer interação. Um campo inválido em Mais opções é revelado antes de solicitar a validação nativa.

A confirmação de descarte protege Cancelar, fechamento pela lateral e tentativa de abrir outro card no Kanban/lista durante a criação. Uma gravação pendente bloqueia nova submissão e essas saídas. O comportamento de outras rotas e do fechamento do navegador não foi transformado em um guard global neste incremento.

Depois da criação confirmada, abre-se o card retornado pela API. Com contato, abre em Relacionamento; sem contato, em Resumo, mantendo disponível o vínculo/cadastro posterior já entregue. Uma falha ao atualizar a listagem não transforma uma criação confirmada em falha de gravação.

## Busca compartilhada e compatibilidade

O endpoint nativo de contatos ganhou uma opção explícita: `GET /api/v1/accounts/:account_id/contacts/search?include_company=true&q=...`.

Sem a opção, pesquisa e envelope continuam como antes. Com a opção e Empresas habilitadas, a extensão Enterprise inclui nome/domínio da empresa atualmente vinculada na busca e devolve `company: { id, name, domain }` ou nulo. A consulta é limitada à conta, usa IDs reais e paginação nativa de 15 itens/`has_more`, com preload de empresa. Texto legado `company_name` não é tratado como vínculo. Não altera a pesquisa OSS quando a extensão não se aplica.

O seletor não carrega toda a base ao abrir. Consulta após pelo menos dois caracteres, distingue carregamento/erro/resultado vazio, pagina no servidor e cancela/descarta respostas antigas. Selecionar não grava pessoa, empresa ou oportunidade.

## Integridade da criação e repetição

A interface envia somente os atributos da oportunidade e, quando selecionado, `contact_id`. A chave de idempotência vai no cabeçalho; não é um atributo do card. Duplo clique é bloqueado e a mesma intenção mantém a mesma chave depois de erro. Alterar o conteúdo enviado caracteriza outra intenção e recebe outra chave; não há deduplicação de oportunidades por título.

A inspeção identificou que a criação nativa não abrangia a chave e a captura da resposta na transação. O endpoint `cards#create` agora confirma chave, card, atividade e resposta juntos. Validação ou falha da captura reverte tudo, sem chave `processing` abandonada. O broadcast de criação/upsert é executado depois da confirmação. Os demais endpoints do concern de idempotência não tiveram seu protocolo alterado.

A autorização de criação ocorre antes de uma eventual repetição. O replay revalida a visibilidade atual do card e usa o mesmo ID, com uma representação atualmente autorizada, não um payload histórico que possa conter conversas antes acessíveis. **Diferença de contrato documentada:** se a oportunidade mudou depois da primeira solicitação, o replay de criação devolve seu estado atual autorizado, não necessariamente os mesmos bytes históricos. Registro excluído não é recriado pela repetição. O fluxo de `external_id` conserva o upsert e foi verificado com chaves independentes.

A store não condiciona sucesso do POST ao sucesso de outro GET. Respostas de outra conta não são inseridas no estado atual, e o indicador de criação é liberado. O formulário mantém também seu próprio estado de gravação pendente.

Não há transação abrangendo serviços externos nem promessa de desligar automações globais. Os callbacks nativos permanecem. A validação local verifica ausência de novas pessoas, empresas, conversas ou mensagens nas fixtures; integrações configuradas na AWS continuam no gate de publicação do conjunto.

## Validação

| Verificação executada | Resultado |
|---|---|
| Frontend CRM, Relacionamentos, APIs de contatos/CRM, stores e cancelamento de requisições | 362 testes em 36 arquivos aprovados. |
| Backend de criação/vínculo de CRM e controladores OSS/Enterprise de contatos | 160 exemplos: 157 aprovados, nenhuma falha e os mesmos 3 suspensos históricos. |
| Novos testes deste incremento | 38 de frontend e 19 de backend. |
| Navegador, incremento atual | 14 verificações com APIs e banco locais reais; nove screenshots finais. |
| Navegador, regressão da parte 5 no código atual | 11 verificações reexecutadas, sem exceções JavaScript não tratadas. |
| Persistência conferida diretamente no banco de UI | 11 → 15 oportunidades, correspondentes a quatro IDs únicos. Permaneceram 7 contatos, 5 empresas, 33 mensagens e 2 conversas. |
| Lint cumulativo | 26 arquivos JS/Vue, zero bloqueadores, 23 avisos de chaves dinâmicas permitidos pela política existente; Prettier aprovado. |
| RuboCop | Cinco arquivos Ruby alterados, nenhuma infração. |
| Build Vite em modo de teste | Aprovado; não representa publicação ou certificação de produção. |
| Traduções | Oito catálogos e 16.062 mensagens, com en/pt_BR e parâmetros conferidos. |
| Guia e regra sem regex novos | 169 fluxos/170 telas; checker de AST aprovado sobre 302 fontes/testes alterados desde a base do módulo. |

Os 25 checks de navegador correspondem a 14 desta parte e 11 de regressão, não a 25 cenários novos. Logs e roteiros locais ficam em `.codex/792/part6-*`; evidência compartilhável em `docs/relationships/screenshots/792-part6/`. O manifesto registra hashes das fontes e dos PNGs, dimensões da lateral e a falha de rede controlada. Nenhuma validação suspensa é contada como aprovada.

O cenário de perda da confirmação gravou no servidor real antes da interrupção da resposta. A interface conservou o preenchimento e, ao repetir pelo próprio botão Criar oportunidade, recebeu `Idempotency-Replayed: true` com o mesmo ID. Duas requisições realmente simultâneas também retornaram um único ID. O request spec injeta falha na captura da resposta para verificar rollback e nova tentativa, além de autorização, exclusão do registro, etapa incompatível e upsert externo.

Na captura final não houve exceção JavaScript não tratada. O console registrou 15 avisos nativos de `onClose` obsoleto, 5 avisos de Lit em desenvolvimento, 5 erros HTTP 404 da consulta local de limites Enterprise e um `ERR_FAILED` provocado pelo ensaio de perda da confirmação. Esses registros não foram apagados ou classificados como sucesso HTTP.

Um ensaio encontrou fechamento do seletor nativo durante a rolagem automática do roteiro. `ChoiceSelect` fecha seu popover quando uma seção rola. O roteiro passou a posicionar o controle e aguardar dois frames antes de abri-lo, verificando `aria-expanded`; não houve troca de componente, clique forçado ou afrouxamento da validação.

Ambiente: Rails/API/PostgreSQL reais no banco exclusivo `chat2you_792_ui_test`, testes Ruby em `chat2you_792_test`, Redis exclusivo em loopback na porta 6792 com DBs separados. URL local `http://127.0.0.1:3792`, Vite 35792. Cadastros fictícios, autenticação normal, jobs/e-mails com adaptadores de teste e sem worker de entrega. Não foram usadas credenciais de produção.

Browser plugin não disponível: usado Playwright já instalado com Chrome. APIs de negócio não foram substituídas por respostas de sucesso fictícias. No cenário de perda de confirmação, a requisição real confirma no servidor e somente a entrega da resposta ao navegador é interrompida deliberadamente; a nova tentativa usa a mesma chave.

## Pontos de revisão e riscos restantes

- O nome de empresa legado não é promovido a associação por aproximação.
- A seleção de funil usa a listagem nativa de funis ativos; trocar funil limpa imediatamente a etapa antiga e ignora respostas fora de ordem.
- Os rascunhos pertencem ao formulário de criação, separado do editor do card existente. O botão externo de rodapé continua ligado ao formulário HTML real.
- O limite de classes/métodos foi respeitado extraindo o escopo de busca e a criação autorizada, sem relaxar o lint. As expectativas usam o matcher negativo já existente e falhas direcionadas a instâncias específicas.
- Os três exemplos de visibilidade que já estavam suspensos na suíte histórica não foram reclassificados como aprovados. A revisão de permissões, escritores concorrentes e regressão integral permanece gate antes do merge.
- A consulta de limites Enterprise no ambiente local pode retornar o 404 já documentado nas partes anteriores; isso deve constar no manifesto, não ser apresentado como resposta bem-sucedida.
- Build local e screenshots não provam publicação nem estado da AWS. Safari/Firefox, integração entre todas as frentes e revisão independente do conjunto permanecem pendentes.

## Comandos e seleção reproduzível

As execuções usaram o Ruby do projeto via rbenv e os bancos de teste isolados, nunca a configuração da AWS. Frontend: `pnpm test --no-watch --maxWorkers=2 --minWorkers=1` com `routes/dashboard/crm`, `components-next/Relationships/specs`, `api/specs/contacts.spec.js`, `api/specs/crmKanban.spec.js`, `store/modules/specs/crmKanban`, `stores/specs/companies.spec.js` e `composables/spec/useAbortableRequest.spec.js`, sob `app/javascript/dashboard/`.

Backend: `bundle exec rspec` selecionou `spec/requests/api/v1/accounts/crm/{cards,opportunity_creation,card_contact_creation,card_contact_links}_spec.rb`, `spec/services/crm/cards/creator_spec.rb`, `spec/enterprise/requests/relationships/crm_contact_lookup_spec.rb`, `spec/controllers/api/v1/accounts/contacts_controller_spec.rb` e `spec/enterprise/controllers/api/v1/accounts/contacts_controller_spec.rb`.

Demais verificações: `pnpm exec vite build --mode test`, `pnpm guia:check`, `pnpm i18n:fork:check`, `pnpm relationships:check`, `git diff --check`, RuboCop dos cinco arquivos Ruby alterados e `.github/scripts/email-protection-eslint.mjs`/Prettier sobre a seleção cumulativa JS/Vue desde `e45fbe68945f948525dcc0a2997eae5c3c9dc74f`.

## Próximo checkpoint

Parar para aprovação visual desta parte. Somente depois do novo de acordo, implementar o cadastro de contato novo e empresa opcional na Nova oportunidade, com confirmação composta. O merge será solicitado somente ao concluir e revisar/testar todo o plano; workflows de main podem publicar duas stacks e não devem ser usados como teste parcial.
