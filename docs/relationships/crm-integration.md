# CRM + Relacionamentos — implementação incremental (#792)

## Autorização e referência

Rodrigo autorizou iniciar em 30/09/2026, com uma entrega pequena por vez. Ao concluir cada parte, revisar, testar, apresentar o resultado e **parar até novo de acordo**. A aprovação de uma parte não autoriza iniciar as demais, fazer merge ou publicar. Somente após concluir o plano inteiro será solicitada autorização de merge; os efeitos de deploy precisam ser explicitados antes disso.

A referência visual/funcional é o HTML aprovado `chat2you-crm-relacionamentos.html`, SHA-256 `d2d172f0336de23aa211d346c27ee5ec7c3eabf45ac5202169a3416ab8cf4f9b`, entregue na conversa com Rodrigo. As imagens conceituais anteriores não são referência. O plano completo entregue é `Plano_Implementacao_CRM_Relacionamentos_Chat2You.md`.

Modelo: **oportunidade → contato → empresa opcional**. As fichas e o CRM usam as mesmas entidades. Não criar cadastros paralelos, vínculos empresariais independentes no card, tabelas de relacionamento novas ou um segundo aplicativo para reproduzir o HTML.

## Rastreabilidade e estado

| Cenário | Entrega esperada | Estado neste checkpoint |
|---|---|---|
| M01 — Card com relacionamento | Aba Relacionamento, editores independentes, atributos e mídias. | Não iniciada. |
| M02 — Card sem vínculo | Vincular/criar depois; troca consistente sem transferir conversas. | Parte 1 implementa somente a proteção no serviço de vínculo existente. UI e cadastro posterior pendentes. |
| M03 — Existente | Criar oportunidade usando um contato existente, sem duplicá-lo. | Nova experiência não iniciada. |
| M04 — Do zero | Contato + empresa opcional + oportunidade, atômicos e idempotentes. | Não iniciada. |
| M05 — Duplicidade | Reaproveitamento explícito; nome igual não implica mesma pessoa/empresa. | Não iniciada. |
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

## Próximo checkpoint proposto, ainda não autorizado

Criar um contato a partir de uma oportunidade sem vínculo e associá-lo ao mesmo card, com transação e autorização, sem criar uma segunda oportunidade. Antes de adicionar novos caminhos de escrita, revisar sua compatibilidade com o serviço de vínculo e a preservação de conversas. A interface completa continua sujeita às etapas e aceites M01–M08.

## Validação e publicação

Evidência da parte 1: [auditoria e limites](../audit/2026-09-30-792-crm-relationships-part-1.md).

Nenhuma alteração de frontend, migração, flag, infraestrutura, configuração de produção ou dependência foi feita nesta parte. Os testes do protótipo não contam como teste desta implementação. Comparação visual, revisão independente do conjunto, concorrência entre fluxos e validação de produção permanecem exigidos antes da liberação final.

O merge de código na main pode disparar os dois workflows blue-green; portanto não fazer merge parcial para testar. O checkpoint fica em branch/PR de rascunho. Uma futura reversão de código não apaga cadastros; este incremento não exige exclusão de dados ou reversão de schema. A versão efetiva publicada na AWS e as flags precisam de conferência própria antes da integração visual/publicação: SHA de GitHub não é prova de deploy.
