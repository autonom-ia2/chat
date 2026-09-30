# #792 — Parte 7: novo contato, empresa opcional e oportunidade

## Autorização e escopo

Rodrigo aprovou a parte 6 e autorizou a parte 7 em 30/09/2026: cadastrar contato novo, com empresa opcional, na mesma confirmação de Nova oportunidade. Referência: HTML aprovado `chat2you-crm-relacionamentos.html`, M04 e tratamento de duplicidade M05. Base deste incremento: `7709b14c5c22a8590b1cda237279c492203b3ef8`; branch `feat/792-crm-relacionamentos`, Issue #792 e PR #793 em rascunho.

Não há autorização de merge/deploy neste checkpoint. Não foram alterados AWS, credenciais, flags de produção, dependências ou esquema de banco. O plano M01–M08 ainda não está concluído.

## Experiência e integridade dos dados

A lateral de 40rem preserva as duas seções e o rodapé fixo. Relacionamento oferece usar existente, criar novo e continuar sem vínculo. Criar novo permite nome obrigatório, e-mail e telefone opcionais, detalhes adicionais e atributos compartilhados. Empresa pode ficar ausente, ser selecionada na conta ou ser cadastrada por nome, domínio opcional, cidade e atributos.

Os formulários de criação mantêm rascunhos, não gravam a cada campo. O payload contém somente o modo ativo. Reutilizar um contato descarta o uso dos campos de criação no envio, sem sobrescrever a pessoa encontrada; reutilizar uma empresa envia seu ID, não os dados digitados como uma atualização. Valores comerciais permanecem separados e não são apagados pela troca de modo. A confirmação de descarte já entregue continua protegendo o preenchimento.

Os atributos são os selecionados nas superfícies `contact_details` e `company_details`; reutilizam catálogo, tipos e conversão compartilhados. Zero, falso e data escrita são conservados, e atributos de empresa não são copiados para contato. Chaves de cargo/endereço com definição própria respeitam o tipo definido, sem um segundo campo textual concorrente. Campos com validação antiga baseada em padrão continuam acessíveis na ficha, pelo editor legado, e não ganham um novo validador por regex nesta criação.

`PhoneNumberInput` recebeu API pública de validação do texto efetivamente digitado: telefone vazio é permitido; texto inválido não pode reaproveitar silenciosamente um número válido emitido antes. As opções novas `ariaLabel` e `compact` preservam os padrões dos demais consumidores. Só esta tela usa o tamanho regular de 40px, alinhado aos demais campos.

### Cidade empresarial compartilhada

O primeiro ensaio completo encontrou uma lacuna real: a cidade era persistida em `additional_attributes`, mas o serializer nativo de empresa não a devolvia. A API passou a expor somente `additional_attributes.city`, mantendo outras chaves fora da resposta. A ficha da empresa e seu editor no card passaram a usar esse mesmo campo; atualizações parciais preservam os demais metadados. Testes verificam leitura, edição, limpeza por nulo e ausência de exposição de outras chaves. O roteiro conserva a asserção da cidade em vez de removê-la.

## Contrato composto e autorização

O endpoint existente `POST /api/v1/accounts/:account_id/crm/cards` aceita opcionalmente `card.relationship`, com `mode: new`, `contact` e `company`. A empresa usa `mode: none`, `mode: existing` com ID inteiro positivo, ou `mode: new` com `attributes`. IDs de funil/etapa e dados comerciais continuam no mesmo objeto `card` e passam pela resolução/autorização nativa.

Neste caminho, `Idempotency-Key` é obrigatório. Não se aceita misturar cadastro novo com `contact_id`, `conversation_id` ou `external_id` no mesmo card. O formato legado sem `relationship` continua disponível. Campos e tipos desconhecidos são rejeitados na fronteira, antes de criar registros; não há coerção de arrays ou objetos em textos de cadastro.

A autorização de CRM ocorre antes de replay. Criar contato e consultar/criar empresa passam também pelas políticas próprias e pela conta atual. IDs empresariais estrangeiros não são aceitos. Credenciais de integração restritas ao CRM não recebem implicitamente permissão de criar contato/empresa: o composto as rejeita, sem ampliar scopes. Respostas de autorização preservam o status nativo do projeto, inclusive `401` para recusas de Pundit.

A interface usa a API e a store de criação já existentes. Erros estruturados preservam rascunhos e identificam contato, empresa ou oportunidade; erros de atributos indicam sua chave. Se um campo recolhido precisa de correção, a seção correspondente é aberta. Falha de busca preliminar é visível e não dispensa a conferência autoritativa no servidor.

## Transação, repetição e efeitos

A criação reutiliza `Crm::Cards::Creator` e o envoltório transacional/idempotente da parte 6. Chave, nova empresa quando necessária, contato, associação, oportunidade, atividade e resposta confirmada integram a mesma transação. Erro do contato após preparar uma empresa, erro da oportunidade ou falha na captura da resposta revertem o conjunto. Os eventos/webhooks nativos de criação ficam após o commit; os eventos de criação não são emitidos em uma tentativa revertida.

O replay devolve o mesmo card com sua representação atual autorizada, conforme o contrato documentado na parte 6. Repetir o mesmo conteúdo reutiliza a chave; alterar o conteúdo representa outra intenção. Não há deduplicação de oportunidades por título ou de pessoas pelo nome.

A inspeção encontrou um efeito nativo importante: um contato novo sem empresa pode inferir/criar empresa a partir do domínio do e-mail depois do commit. O novo fluxo marca apenas a instância em registro com `skip_company_auto_association`. Assim, a escolha explícita Sem empresa é respeitada; a inferência dos demais caminhos de cadastro permanece inalterada. Nenhuma flag persistente ou configuração global foi criada.

Continuam existindo callbacks/webhooks nativos depois de uma criação válida. Os testes locais não autorizam afirmar que automações ou integrações configuradas na AWS estão desligadas. Por isso não foi adicionada a promessa de ausência de mensagens ao rodapé.

## Duplicidade e concorrência

A interface faz consultas preliminares paginadas nas APIs existentes; não carrega a base toda. Resultados aproximados são filtrados por identidade exata. Essa consulta ajuda o operador, mas não é certificação de unicidade: o servidor verifica novamente os campos normalizados na conta, independentemente da paginação do navegador.

E-mail é tratado sem diferença de maiúsculas/minúsculas. Telefone internacional usa a biblioteca já instalada, sem inventar país para um número local. E-mail e telefone pertencentes a pessoas diferentes não são fundidos. Os candidatos só incluem identificadores/dados mínimos quando a política permite sua visualização. Sem acesso, a resposta não expõe o cadastro encontrado.

Domínio empresarial opcional é normalizado por parser de URL/URI: caixa, protocolo/caminho e ponto terminal não criam domínios falsamente distintos. Não se inventa domínio a partir do nome nem se reduz subdomínios por aproximação. Domínio já existente pede reutilização explícita. Nome empresarial igual é somente aviso; empresas diferentes podem ter o mesmo nome.

As confirmações deste novo fluxo usam bloqueio transacional da conta, além da chave idempotente e dos índices nativos. Isso serializa os cadastros concorrentes por este caminho, inclusive com chaves diferentes. **Limite de liberação:** a unicidade global de telefone entre todos os outros escritores não foi resolvida por uma migração neste incremento. O índice de telefone existente não é único e outros caminhos não passam por este bloqueio. Essa revisão transversal continua obrigatória antes da liberação do conjunto; os testes deste fluxo não são apresentados como garantia global.

### Concorrência real: correção do modo de bloqueio

O ensaio simultâneo com chaves diferentes encontrou um deadlock real: cada inserção da chave idempotente já referenciava a conta e a tentativa seguinte de `FOR UPDATE` criava uma disputa de upgrade de locks. O novo fluxo passou a usar `FOR NO KEY UPDATE`, que continua serializando os registros entre si, sem competir com `FOR KEY SHARE` das referências à conta. Não foi adicionado retry para mascarar o erro nem removido o cenário concorrente. Um request spec verifica o SQL efetivamente emitido e o navegador repete as duas requisições reais.

Referência primária: PostgreSQL 17, seção 13.3.2 e tabela 13.3, `https://www.postgresql.org/docs/17/explicit-locking.html`. Os dois modos compatíveis e o uso de lock exclusivo sem alterar a chave fundamentam a correção; os resultados da aplicação são verificados separadamente.

## Correções encontradas na retomada

A revisão da cidade também conferiu a coluna JSONB opcional de empresas antigas: ela pode estar nula no banco. O serializer e a atualização parcial tratam esse nulo como objeto vazio, sem expor outros metadados. Um request spec grava deliberadamente uma empresa com esse estado legado e verifica leitura e atualização da cidade. Não houve alteração do esquema.

O primeiro roteiro completo da retomada passou pelas 14 verificações de cadastro, mas falhou na exigência de ausência de exceções JavaScript: `ConstraintError: Key already exists in the object store.` O problema foi reproduzido separadamente no Chrome com o módulo real `CacheHelper/DataManager`, usando duas instâncias e duas substituições simultâneas do mesmo cache. A implementação anterior limpava a coleção numa transação e inseria em outra; além disso, não observava as promises de cada `add`. O ensaio retornou uma operação rejeitada e as exceções de chave duplicada/aborto.

A correção mantém limpar e inserir o snapshot na mesma transação do IndexedDB e aguarda cada requisição e a transação. Não usa retry, não transforma erro em sucesso e não sobrescreve itens no método de inclusão. Se uma substituição falha por duplicidade interna, a limpeza é revertida e o snapshot anterior permanece. O mesmo ensaio real passou depois: duas operações confirmadas, último snapshot completo e nenhuma exceção. Foram adicionados seis testes desse contrato; os oito testes existentes do cliente de cache também passaram. Esse ajuste de suporte foi necessário para validar a navegação CRM/ficha em mais de uma aba, sem esconder o erro do roteiro.

## Correção do teste que falhou no CI da parte 6

A execução `36751144276`, job `110009777359`, apontou duas comparações de timestamp em `crm_company_operations_spec.rb`. Os snapshots de factory estavam em memória com precisão diferente daquela persistida pelo PostgreSQL. O teste agora recarrega card, contato e conversa antes de guardar os snapshots. A comparação de todos os campos/timestamps continua existindo; não foram removidas as verificações de preservação nem alterada a aplicação para fazer o teste passar.

## Validação e evidências

| Verificação executada no código deste checkpoint | Resultado |
|---|---|
| Frontend selecionado: CRM, Relacionamentos, telefone, cache, APIs e stores | 429 testes em 43 arquivos aprovados. |
| Backend selecionado: CRM, empresas/contatos, Relacionamentos e limpeza de contatos | 305 exemplos: 302 aprovados, zero falhas e os mesmos três suspensos históricos. |
| Navegador: cadastro composto atual | 14 verificações com API e banco reais aprovadas, sem exceções JavaScript não tratadas. |
| Navegador: regressões das partes 6 e 5 | Respectivamente 14 e 11 verificações reexecutadas e aprovadas; total de 39 checks funcionais de navegador. |
| Persistência conferida diretamente no banco de UI após o roteiro composto | 39 → 47 oportunidades, 29 → 36 contatos, 14 → 17 empresas. Mantidas 33 mensagens e duas conversas. Oito IDs de oportunidade distintos, vínculos reais e contatos presentes na listagem compartilhada. |
| Cache do navegador | Ensaio simultâneo real no Chrome aprovado após a correção; seis novos testes e oito testes existentes do cliente de cache incluídos na bateria frontend. |
| ESLint e Prettier | 19 fontes/testes JS/Vue deste incremento, zero bloqueadores e 11 avisos de chaves dinâmicas já permitidos pela política; formatação aprovada. |
| RuboCop | 11 arquivos Ruby, nenhuma infração. |
| Build Vite em modo de teste | Aprovado. Os avisos existentes de tamanho de chunks não foram ocultados. |
| Traduções, Guia, regra sem regex novos e whitespace | Oito catálogos/16.154 mensagens; 169 fluxos/170 telas; AST de 322 fontes/testes alterados desde a base do módulo; verificações aprovadas. |

Os três suspensos de visibilidade permanecem em `cards_spec.rb` (333, 556 e 583); não contam como aprovados e a revisão de permissões continua obrigatória antes do release. Esta é uma bateria local selecionada, não a certificação de toda a aplicação nem a conclusão do CI remoto do futuro commit.

O cadastro composto foi reexecutado após reiniciar o servidor exclusivo de teste com o código revisado. A perda da confirmação é provocada só depois de uma gravação real e a nova tentativa pela UI recupera os mesmos IDs. As requisições simultâneas com chaves iguais e diferentes são requisições HTTP reais, não respostas simuladas. A contagem foi conferida antes dos roteiros de regressão seguintes para não misturar gravações de testes diferentes.

Scripts/logs temporários ficam em `.codex/792/part7-*`. As evidências compartilháveis ficam em `docs/relationships/screenshots/792-part7/`, com hashes das fontes/PNGs, manifesto, persistência, regressões e ensaio de cache. O console conserva os avisos nativos de depreciação, a consulta local de limites Enterprise que retorna 404, os erros de validação esperados e a interrupção de rede deliberada. Nenhum desses eventos foi apagado para apresentar um console artificialmente limpo.

### Seleção reproduzível e fidelidade visual

Frontend: `pnpm test --no-watch --maxWorkers=2 --minWorkers=1` em `routes/dashboard/crm`, `components-next/Relationships/specs`, `components-next/phonenumberinput/PhoneNumberInput.spec.js`, `helper/CacheHelper/DataManager.spec.js`, `api/specs/{CacheEnabledApiClient,contacts,crmKanban}.spec.js`, `store/modules/specs/crmKanban`, `stores/specs/companies.spec.js` e `composables/spec/useAbortableRequest.spec.js`, sob `app/javascript/dashboard`.

Backend: `bundle exec rspec` nos requests CRM de cards, criação, cadastro composto e vínculo; serviços Creator/ContactCreator/ContactLinker; `spec/enterprise/requests/relationships`; request Enterprise de cadastro no card; controladores de contato e empresa; associação de empresas e limpeza de contatos. A lista exata, os resultados JSON e os logs da execução estão em `.codex/792/part7-acceptance-*`.

Demais verificações: `pnpm exec vite build --mode test`, `pnpm guia:check`, `pnpm i18n:fork:check`, `pnpm relationships:check`, `.github/scripts/email-protection-eslint.mjs`, Prettier, RuboCop e `git diff --check`. O workflow de Relacionamentos foi ampliado para incluir os requests/serviços CRM e mantém a regressão frontend completa sem relaxar os critérios.

| Referência aprovada | Evidência real | Resultado |
|---|---|---|
| Duas seções na mesma lateral, não assistente de páginas | Nova pessoa/empresa e dados da oportunidade no mesmo formulário | Mantido. |
| Largura de Editar funil | Capturas desktop e notebook medem 640px | Mantido; celular ocupa a largura disponível de 390px. |
| Cadastro compartilhado e atributos expansíveis | Edição/leitura com APIs reais, zero/falso/data preservados e ficha da empresa exibindo a cidade | Mantido. |
| Duplicidade explícita | Reutilização de pessoa por identidade/domínio da empresa; nome igual gera somente aviso | Regra real preservada sem fusão automática. |
| Identidade Chat2You | Componentes/tokens existentes, tipografia, ícones, opções e rodapé fixo | Sem iframe, seletores nativos ou aplicativo paralelo. |

Ambiente exclusivo: Rails e PostgreSQL reais em `chat2you_792_ui_test`, request specs em `chat2you_792_test`, Redis local na porta 6792, app em `http://127.0.0.1:3792`, Vite na porta 35792. Somente cadastros sintéticos, adaptadores de teste para jobs/e-mails e nenhum worker de entrega. Navegador: Chrome/Playwright já instalado; Browser plugin não disponível. Nesta parte o roteiro autentica pela tela normal de login e opera a aplicação/API local.

## Próximo checkpoint

Parar para aprovação visual da parte 7. Não iniciar outra parte, fazer merge ou publicar a partir deste aceite. Continuam pendentes a criação contextual a partir de todas as fichas, a revisão de todos os escritores concorrentes/efeitos, a revisão independente e a validação integral antes do pedido final de merge e do plano de deploy/rollback.
