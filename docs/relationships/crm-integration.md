# CRM + Relacionamentos — implementação incremental (#792)

## Autorização e referência

Rodrigo autorizou iniciar em 30/09/2026, com uma entrega pequena por vez. Ao concluir cada parte, revisar, testar, apresentar o resultado e **parar até novo de acordo**. A aprovação de uma parte não autoriza iniciar as demais, fazer merge ou publicar. Somente após concluir o plano inteiro será solicitada autorização de merge; os efeitos de deploy precisam ser explicitados antes disso.

A referência visual/funcional é o HTML aprovado `chat2you-crm-relacionamentos.html`, SHA-256 `d2d172f0336de23aa211d346c27ee5ec7c3eabf45ac5202169a3416ab8cf4f9b`, entregue na conversa com Rodrigo. As imagens conceituais anteriores não são referência. O plano completo entregue é `Plano_Implementacao_CRM_Relacionamentos_Chat2You.md`.

**Checkpoint atual:** Rodrigo aprovou a parte 1 e autorizou a parte 2 em 30/09/2026. A parte 2 foi executada localmente; aguardar um novo de acordo antes da parte 3. Não houve autorização para merge/deploy.

Modelo: **oportunidade → contato → empresa opcional**. As fichas e o CRM usam as mesmas entidades. Não criar cadastros paralelos, vínculos empresariais independentes no card, tabelas de relacionamento novas ou um segundo aplicativo para reproduzir o HTML.

## Rastreabilidade e estado

| Cenário | Entrega esperada | Estado neste checkpoint |
|---|---|---|
| M01 — Card com relacionamento | Aba Relacionamento, editores independentes, atributos e mídias. | Não iniciada. |
| M02 — Card sem vínculo | Vincular/criar depois; troca consistente sem transferir conversas. | Partes 1 e 2: proteção do vínculo e API transacional para contato novo no mesmo card. UI de vínculo/cadastro ainda pendente. |
| M03 — Existente | Criar oportunidade usando um contato existente, sem duplicá-lo. | Nova experiência não iniciada. |
| M04 — Do zero | Contato + empresa opcional + oportunidade, atômicos e idempotentes. | Não iniciada. |
| M05 — Duplicidade | Reaproveitamento explícito; nome igual não implica mesma pessoa/empresa. | Parte 2 respeita as validações nativas e não faz fusão. Experiência de reutilização e concorrência entre escritores diferentes pendentes. |
| M06 — Ficha do contato | Ficha real, retorno ao card e criação contextual. | Integração não iniciada. |
| M07 — Ficha da empresa | Contatos, mídias e oportunidades autorizadas da mesma empresa. | Integração não iniciada. |
| M08 — Atributos | Reutilizar catálogo e exibição por conta sem apagar valores. | Integração não iniciada. |

## Parte 1 — Contrato do vínculo existente

O endpoint `POST /api/v1/accounts/:account_id/crm/cards/:id/link_contact` continua recebendo `contact_id`. A conta, visibilidade do card e autenticação continuam sendo verificadas pelos caminhos atuais. A regra nova fica em `Crm::Cards::ContactLinker`, compartilhado com o desvínculo existente.

- A troca lê o estado persistido sob lock do card. O objeto antigo de outra requisição não determina o vínculo anterior nem o registro de auditoria.
- Antes de alterar para outra pessoa, confere a conversa primária, inclusive legada sem linha intermediária, e todas as conversas secundárias vinculadas.
- Se qualquer uma pertencer a outro contato, a operação falha com o envelope existente de HTTP 422: `message` e `attributes: ["contact"]`. Não inclui identidade nem conteúdo das conversas no erro.
- Em uma troca válida, preserva o ID e os dados comerciais da oportunidade; não exclui nenhum dos contatos. O evento `contact_linked` conserva `contact_id` e acrescenta `previous_contact_id` quando existia vínculo anterior.
- Repetir o mesmo vínculo ou desvincular um card já sem contato não muda timestamps nem cria outro evento de atividade.
- O desvínculo explícito remove somente a associação do contato. Não remove ou transfere conversas. Desvincular antes não permite depois vincular uma pessoa incompatível.
- A atualização e a atividade permanecem na mesma transação. Falha da atividade reverte a alteração do card.

### Exemplo e resolução de conflito

Uma oportunidade contém conversas de Mariana. Tentar vinculá-la a João retorna 422 e mantém o card e as conversas de Mariana. Para resolver, um operador autorizado deve revisar os vínculos de conversa pelo fluxo existente; não há desvínculo automático, transferência de mensagens ou fusão de pessoas. Depois de remover explicitamente os vínculos incompatíveis, o contato pode ser trocado.

### Limite desta proteção

Este incremento protege o serviço explícito de vínculo de contato. **Não é uma garantia global sobre todo escritor de dados:** criação, upsert externo, vinculação de conversas e concorrência entre serviços diferentes ainda precisam de revisão nas partes seguintes. Não altera registros históricos inconsistentes. Não afirma impedir duplicação de broadcast ou outras ações externas em toda repetição; o no-op testado se refere aos dados do card e à atividade.

## Regras preservadas para as próximas partes

A lateral terá Resumo, Relacionamento, Conversas, Follow-ups e Timeline, preservando os recursos reais que o HTML simplifica. Contato e empresa salvam separadamente da oportunidade. Criar oportunidade terá duas seções na mesma lateral, sem assistente de páginas: Relacionamento e Oportunidade. Modos: usar existente, criar novo ou continuar sem vínculo.

Novos cadastros e oportunidade devem ser confirmados pelo backend em uma transação abrangente, reutilizando idempotência. Um contato somente com nome precisa aparecer na listagem e resistir às rotinas de limpeza aplicáveis. Empresa textual legada não vira vínculo por suposição. Atributos, tipos, chaves, outras opções e visibilidade do atendimento permanecem preservados.

Mídias/conversas continuam sujeitas à autorização da origem. A empresa não concede acesso adicional a conversas. Criar/vincular por esse fluxo não envia mensagens ou convites; a criação composta ainda precisará provar isso para seus próprios callbacks. Não introduzir regex, dependência/credencial nova, alteração de branding ou migração em lote.

## Parte 2 — Cadastro novo no mesmo card

`POST /api/v1/accounts/:account_id/crm/cards/:card_id/contact` recebe um objeto `contact` e exige `Idempotency-Key`. Retorna HTTP 201 com o payload de detalhes do MESMO card. Não cria outra oportunidade nem empresa. A chave deve ser mantida no retry da mesma intenção; outra intenção exige outra chave.

Campos aceitos: `name` obrigatório e não vazio; `email` e `phone_number` opcionais como texto/nulo; `additional_attributes` opcional com `city` e `country`; `custom_attributes` opcional como objeto, usando os campos existentes, inclusive `job_title` e `address`. Nome/e-mail/telefone são aparados, o e-mail segue a normalização nativa e o telefone deve chegar no formato internacional E.164, validado pelo modelo existente. Não há novo validador por regex.

Campos de identidade/permissão como `id`, `account_id`, `identifier`, `contact_type` ou `company_id` são recusados neste contrato. Empresa será tratada numa etapa própria. Nome igual não é usado como identificador. E-mail/telefone já cadastrados falham pelas validações existentes, sem sobrescrever/fundir o cadastro; o fluxo de reutilizar um existente permanece em `link_contact`.

A conta, a visibilidade e a permissão de vínculo do card, bem como a permissão de criar contato, são verificadas antes de gravar OU reproduzir uma resposta. O mapa default-deny continua recusando tokens de integração CRM nessa rota nova; nenhum scope/perfil foi ampliado.

`ContactCreator` trava e recarrega o card, recusa um vínculo já preenchido, cria a pessoa real e chama o `ContactLinker` da parte 1. A transação externa também abrange a chave de idempotência e a resposta salva. Se criação, vínculo, auditoria ou captura da resposta falhar, não sobra pessoa parcial nem chave travada. Duas requisições na mesma oportunidade não produzem duas pessoas: chave igual reproduz a resposta; chaves diferentes deixam somente uma criação e a outra recebe 422.

### Contato somente com nome

O cadastro intencional nasce com o tipo nativo `lead`, sem e-mail, telefone ou identificador artificial. A listagem clássica passa a incluir leads explícitos sem identificação, como a listagem `crm_v2` já faz; visitantes anônimos continuam excluídos. Isso também torna visíveis leads antigos explicitamente classificados assim. Foi atualizada somente a expectativa do teste existente que descrevia sua antiga exclusão, como mudança funcional intencional deste requisito, não como ocultação de falha.

A limpeza de visitantes passa a selecionar somente `visitor`, sem conversas e sem cards. Leads/clientes sem identificação são preservados, inclusive após desvincular ou arquivar a oportunidade. Nenhuma base real foi limpa ou migrada.

### Eventos e limites

O broadcast do card é agendado após a confirmação da transação. Os callbacks nativos de criação de contato permanecem após commit: a prova local verificou que já enxergam vínculo e resposta persistidos, e que não executam no rollback. Os eventos/webhooks normais de contato não foram desligados; os efeitos de integrações externas configuradas na AWS ainda precisam ser conferidos antes de anunciar uma promessa global de criação silenciosa. O endpoint não cria conversa, vínculo de inbox, mensagem, follow-up, convite ou oportunidade adicional.

A concorrência comprovada aqui é de requisições deste endpoint sobre o mesmo card. A unicidade global de telefone perante outros cards/escritores, os upserts externos e o protocolo do `ConversationLinker` continuam na revisão transversal futura. A parte 2 não conclui M02 nem M05 completos.

## Próximo checkpoint proposto, ainda não autorizado

Primeiro trecho visual de M01: substituir a aba Contato por Relacionamento e apresentar o contato compartilhado, a empresa realmente vinculada e os estados sem vínculo, na composição do HTML. Não iniciar essa parte antes do novo de acordo. Edição completa, formulário composto, mídia e demais ações continuam sujeitos aos aceites próprios.

## Validação e publicação

Evidência da parte 1: [auditoria e limites](../audit/2026-09-30-792-crm-relationships-part-1.md). Evidência da parte 2: [testes, concorrência e limites](../audit/2026-09-30-792-crm-relationships-part-2.md).

Nenhuma alteração de frontend, migração, flag, infraestrutura, configuração de produção ou dependência foi feita nesta parte. Os testes do protótipo não contam como teste desta implementação. Comparação visual, revisão independente do conjunto, concorrência entre fluxos e validação de produção permanecem exigidos antes da liberação final.

O merge de código na main pode disparar os dois workflows blue-green; portanto não fazer merge parcial para testar. O checkpoint fica em branch/PR de rascunho. Uma futura reversão de código não apaga cadastros; este incremento não exige exclusão de dados ou reversão de schema. A versão efetiva publicada na AWS e as flags precisam de conferência própria antes da integração visual/publicação: SHA de GitHub não é prova de deploy.
