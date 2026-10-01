# CRM + Relacionamentos — implementação incremental (#792)

## Autorização e referência

Rodrigo autorizou iniciar em 30/09/2026, com uma entrega pequena por vez. Ao concluir cada parte, revisar, testar, apresentar o resultado e **parar até novo de acordo**. A aprovação de uma parte não autoriza iniciar as demais, fazer merge ou publicar. Somente após concluir o plano inteiro será solicitada autorização de merge; os efeitos de deploy precisam ser explicitados antes disso.

A referência visual/funcional é o HTML aprovado `chat2you-crm-relacionamentos.html`, SHA-256 `d2d172f0336de23aa211d346c27ee5ec7c3eabf45ac5202169a3416ab8cf4f9b`, entregue na conversa com Rodrigo. As imagens conceituais anteriores não são referência. O plano completo entregue é `Plano_Implementacao_CRM_Relacionamentos_Chat2You.md`.

**Checkpoint atual:** Rodrigo aprovou as partes 1–9. Parte 10 implementada: oportunidades dos contatos vinculados na ficha empresarial. Após a reconexão do Mac, foram concluídos os caminhos de administrador/agente, persistência e regressão da ficha do contato. Aguardando aprovação visual antes da revisão integrada. A navegação empresarial com papel personalizado permanece bloqueada, não contada como aprovada. Sem autorização de merge/deploy.

Modelo: **oportunidade → contato → empresa opcional**. As fichas e o CRM usam as mesmas entidades. Não criar cadastros paralelos, vínculos empresariais independentes no card, tabelas de relacionamento novas ou um segundo aplicativo para reproduzir o HTML.

## Rastreabilidade e estado

| Cenário | Entrega esperada | Estado neste checkpoint |
|---|---|---|
| M01 — Card com relacionamento | Aba Relacionamento, editores independentes, atributos e mídias. | Partes 3–5: contato/empresa canônicos, editores separados, atributos/mídias e vínculo empresarial dentro da lateral de 40rem. Trechos visuais até a parte 5 aprovados; revisão transversal pendente. |
| M02 — Card sem vínculo | Vincular/criar depois; troca consistente sem transferir conversas. | Partes 1–3: proteção, API e UI para buscar/vincular/criar pessoa no mesmo card; trecho visual aprovado. |
| M03 — Existente | Criar oportunidade usando um contato existente, sem duplicá-lo. | Parte 6 aprovada: duas seções nativas, busca por contato/empresa, seleção, criação e repetição segura; revisão transversal pendente. |
| M04 — Do zero | Contato + empresa opcional + oportunidade, atômicos e idempotentes. | Parte 7 aprovada: nome obrigatório, empresa ausente/existente/nova, dados e atributos compartilhados; revisão transversal pendente. |
| M05 — Duplicidade | Reaproveitamento explícito; nome igual não implica mesma pessoa/empresa. | Parte 7: reutilização explícita por identidade/domínio, sem fusão por nome; concorrência deste fluxo protegida. A revisão entre todos os escritores continua pendente. |
| M06 — Ficha do contato | Ficha real, retorno ao card e criação contextual. | Partes 3, 8 e 9 aprovadas: ficha real, criação contextual e lista autorizada. Regressão reexecutada na parte 10 após compartilhar apresentação/consulta. Revisão transversal pendente. |
| M07 — Ficha da empresa | Contatos, mídias e oportunidades autorizadas da mesma empresa. | Parte 10 lista oportunidades por contatos canônicos atuais, com nomes, filtros, paginação e abertura do mesmo card. Aguardando aceite visual; navegação de papel personalizado e revisão transversal pendentes. |
| M08 — Atributos | Reutilizar catálogo e exibição por conta sem apagar valores. | Parte 4 aprovada: editores/configurador nativos, superfícies da ficha e stores compartilhados. Fluxos revalidados na parte 5; revisão transversal permanece. |

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

## Parte 3 — Primeiro trecho visual

A aba mantém sua identificação interna e passa a mostrar Relacionamento. `CrmCardRelationshipPanel` e `CrmRelationshipLinkForm` usam as APIs reais. Contato e empresa são consultados por ID; dados textuais de empresa não viram associação por inferência. O editor de pessoa salva separadamente da negociação e tem ação fixa no rodapé. O rascunho comercial não é perdido ao atualizar o contato.

A largura usa os mesmos `40rem` de Editar funil, limitada à tela. Foram medidos 640px no desktop/notebook e 390px no celular. Capturas reais, mapa de validação e limites estão na [auditoria da parte 3](../audit/2026-09-30-792-crm-relationships-part-3.md) e em [screenshots](screenshots/792-part3/README.md).

A abertura das fichas é em nova aba nesta parte. O acesso usa rotas e permissões existentes; não há cópia das fichas ou customização de branding. Criação de oportunidade completa, atributos personalizados, mídias e edição empresarial inline ainda não foram entregues neste painel.

A atenção aos efeitos nativos permanece: `Enterprise::Concerns::Contact` pode associar empresa após commit quando o primeiro e-mail é cadastrado. A seleção empresarial explícita deverá ser conciliada com esse comportamento antes de concluir M04; este incremento não desliga callbacks globais.

## Parte 4 — Atributos e mídias no mesmo cadastro

`CrmRelationshipResources` apresenta seções expansíveis de atributos e mídias. Contato e empresa usam seus respectivos registros canônicos. O catálogo/configuração de campos usa `contact_details` e `company_details`; ocultar não apaga valores e não substitui a configuração de `contact_sidebar`. O editor nativo confirma cada valor separadamente da oportunidade e participa do guard de rascunhos.

O modo `embedded` de `RelationshipMedia` reutiliza busca, filtros, miniaturas e autorização. Mostra 5 arquivos ou 25 por página sem alterar a URL do CRM. Empresa usa os contatos realmente vinculados. Origem e arquivo abrem pelo fluxo nativo em outra aba. Não há cópia de arquivos nem ampliação de acesso.

A empresa em Pinia e o contato em Vuex são os mesmos registros das fichas. Leituras usam a proteção de valores confirmados para não substituir uma gravação por uma resposta antiga. Estados vazios/erro e flags continuam sendo respeitados.

Evidências: [auditoria da parte 4](../audit/2026-09-30-792-crm-relationships-part-4.md) e [screenshots reais](screenshots/792-part4/README.md).

## Parte 5 — Cadastro e vínculo da empresa na lateral

Editar empresa altera nome, domínio e descrição do cadastro compartilhado. Salvar empresa tem ação própria no rodapé, sem salvar dados comerciais. Buscar e selecionar empresa existente não grava antes da confirmação. Trocar mantém as empresas existentes; Desvincular remove apenas a associação, após confirmação própria. Nenhuma dessas operações cria outra oportunidade ou exclui arquivos.

O vínculo usa o `company_id` real e é compartilhado pelas oportunidades do contato. Mídias empresariais seguem os contatos atualmente vinculados e as permissões existentes. Empresa textual legada exige seleção explícita. Uma resposta sem `company_id`, possível se Empresas foi desligado, não é tratada como confirmação de desvínculo.

São reutilizadas as APIs nativas e a store de empresa, enviando só os campos editados. O novo formulário participa do guard de rascunhos; as ações de Ganhar/Perder/Reabrir também respeitam essa proteção. Uma mudança de vínculo observada bloqueia salvar e mantém o preenchimento; não foi introduzido protocolo global de versionamento para gravações simultâneas.

Evidências: [auditoria da parte 5](../audit/2026-09-30-792-crm-relationships-part-5.md) e [telas reais](screenshots/792-part5/README.md).

## Parte 6 — Nova oportunidade com contato existente ou sem vínculo

Novo card passa a Nova oportunidade. A primeira seção escolhe um contato existente, com resumo de pessoa/empresa/e-mail/telefone, ou permite continuar sem vínculo. A segunda seção reúne dados comerciais e Mais opções. A lateral mantém a largura de Editar funil; sua gravação não altera os cadastros selecionados.

Buscar por empresa usa a opção `include_company=true` da pesquisa de contatos, implementada no overlay Enterprise quando Empresas está habilitado. São empresa e vínculo canônicos; não se usa texto legado como associação. A busca padrão permanece inalterada e a paginação continua no servidor.

O formulário preserva valores durante busca, troca de contato, troca de modo e seleção de funil. A etapa passa a ser carregada do funil escolhido; uma resposta antiga não substitui as opções atuais. Cancelar, fechar a lateral ou abrir outro card do Kanban/lista durante a criação passam pela confirmação de descarte. Criar abre a oportunidade confirmada; contato existente abre em Relacionamento, sem vínculo abre em Resumo.

A chave de idempotência é enviada separadamente no cabeçalho e permanece igual na repetição da mesma intenção. `cards#create` confirma chave, card e captura da resposta na mesma transação, com broadcast posterior. Um replay revalida o acesso ao mesmo card e devolve sua representação atual autorizada, não necessariamente os bytes de uma resposta histórica. O contrato sem cabeçalho e o upsert externo permanecem disponíveis. Uma leitura de atualização da listagem não altera o resultado de uma criação já confirmada.

Evidências: [auditoria da parte 6](../audit/2026-09-30-792-crm-relationships-part-6.md) e [telas reais](screenshots/792-part6/README.md). Esta parte não conclui cadastro composto nem criação contextual a partir de todas as fichas.

## Parte 7 — Novo contato e empresa opcional na mesma confirmação

Criar novo adiciona pessoa, detalhes complementares e atributos compartilhados, sem sair da lateral. Empresa oferece Sem empresa, Selecionar existente ou Nova empresa. Rascunhos são mantidos entre modos, mas somente o modo ativo entra no payload. O contato pode ter somente nome, sem identificadores artificiais, e nasce como lead explícito preservado pelas rotinas de limpeza.

`card.relationship` no endpoint de criação existente recebe `mode: new`, `contact` e `company`. A empresa informa `mode: none`, `mode: existing` com ID real, ou `mode: new` com seus atributos. `Idempotency-Key` é obrigatório neste contrato; a mesma intenção confirma empresa, contato, vínculo, oportunidade e resposta numa transação. Não se mistura esse modo com `contact_id`, `conversation_id` ou `external_id`; o contrato legado permanece disponível.

O servidor normaliza e confere e-mail/telefone e domínio; não funde pessoas nem empresas por nome igual. Candidatos de outras contas ou sem acesso não são expostos. Usar existente é uma decisão explícita e não sobrescreve o cadastro. O bloqueio transacional serializa este novo fluxo; não substitui a revisão de unicidade/concorrência com outros escritores antes do release.

Sem empresa prevalece sobre a inferência nativa por e-mail somente nesta instância de criação. Os callbacks de outros caminhos não foram desativados. A cidade da empresa agora é devolvida em `additional_attributes.city` pela API e pode ser vista/editada tanto no CRM quanto na ficha canônica. O serializer não expõe outras chaves de metadados; a atualização parcial mescla os atributos em vez de apagar seus irmãos. Limpar cidade usa nulo.

Atributos conservam tipos, zero, falso e datas; erros recolhidos abrem a seção afetada. Campos com validação antiga por padrão permanecem no editor legado da ficha, sem introduzir novo regex. O novo método público de validação de telefone permite vazio, mas não aceita texto inválido usando silenciosamente um número válido anterior.

A validação encontrou um conflito real no cache IndexedDB ao atualizar a aplicação e a ficha simultaneamente. A substituição do snapshot agora limpa e insere numa única transação, observando todas as requisições e preservando o snapshot anterior em caso de falha. O comportamento de inclusão não passou a sobrescrever dados. Testes direcionados e o ensaio real no Chrome documentam o antes/depois; não houve nova dependência.

Evidências e limites: [auditoria da parte 7](../audit/2026-09-30-792-crm-relationships-part-7.md) e [11 telas reais](screenshots/792-part7/README.md). Bateria local: 429 testes frontend; 302 backend aprovados e três suspensos antigos; 39 checks funcionais de navegador e conferência direta dos registros. Revisão independente e cobertura integral continuam pendentes.

## Parte 8 — Criar oportunidade pela ficha do contato

A barra de ações da ficha em Relacionamentos agora oferece Nova oportunidade para quem pode visualizar CRM e gerenciar cards. O CRM abre em outra aba, com indicação visual/acessível, preservando campos não salvos na ficha original. Não copia esses rascunhos: consulta contato e empresa confirmados pelas APIs nativas e seleciona o ID existente no mesmo formulário de oportunidade.

A URL leva somente `new_contact_id`, com conta do roteador; a intenção é validada e consumida após abrir o formulário. Contato/empresa indisponível mostra erro e permite tentar novamente ou cancelar, nunca vira cadastro avulso implicitamente. A leitura espera um funil com etapa disponível. Mudança de conta/intenção cancela o uso das respostas antigas. O contato previamente selecionado não é tratado como edição não salva; alterar a seleção ou os campos comerciais é. Voltar ao contato passa pelo guard de descarte existente.

A largura continua igual à de Editar funil. Não foram adicionados endpoints, modelos, novas dependências ou permissão implícita. A consulta não grava dados; confirmar cria somente a oportunidade usando o contato escolhido. Mensagem/chamada/menu da ficha permanecem disponíveis como antes. O Guia recebeu instruções do novo caminho.

Evidências: [auditoria da parte 8](../audit/2026-09-30-792-crm-relationships-part-8.md) e [telas reais](screenshots/792-part8/README.md).

## Parte 9 — Lista de oportunidades na ficha do contato

Acompanhamento recebeu a aba Oportunidades, sem remover os controles existentes e mantendo Notas como entrada padrão. Lista título, funil, etapa, situação, valor/moeda, responsável e previsão. Por padrão mostra não arquivadas; filtros permitem consultar todas, abertas, ganhas, perdidas e arquivadas. Busca e paginação de cinco itens são realizadas no servidor. O total corresponde somente à consulta e aos registros permitidos.

A projeção read-only `GET /api/v1/accounts/:account_id/crm/contacts/:contact_id/opportunities` exige acesso ao CRM e ao contato, aplica o escopo nativo de cards e retorna só os campos comerciais necessários. Não usa o serializer amplo do CRM e não retorna conversas, mensagens ou metadados de IA. Não são criados vínculos/tabelas novos. A consulta por ID canônico não agrega homônimos nem outros contatos da mesma empresa.

Desktop e celular compartilham o estado da mesma consulta. Trocar conta/contato/aba ou perder permissão invalida respostas antigas. Voltar ao foco da ficha ou clicar em Atualizar busca os dados atuais; não se promete atualização contínua enquanto a ficha estiver sem foco. Abrir uma oportunidade usa outra aba e preserva o formulário da pessoa. Filtros não modificam o Kanban. Valores zero e moedas individuais são preservados, sem soma/conversão.

Evidências: [auditoria da parte 9](../audit/2026-09-30-792-crm-relationships-part-9.md) e [11 telas reais](screenshots/792-part9/README.md). Bateria local: 484 testes frontend selecionados, 507 backend aprovados e quatro suspensos antigos separados, 28 checks de navegador com bundle compilado. Consulta sem gravações confirmada diretamente no banco. O CI remoto e a revisão independente permanecem gates próprios.

## Parte 10 — Oportunidades na ficha da empresa

A aba Oportunidades foi adicionada ao Acompanhamento da empresa, mantendo Contatos como entrada. Reúne as negociações dos contatos atualmente vinculados por `company_id`, com identificação da pessoa, situação, funil/etapa, valor/moeda, responsável e previsão. Busca e paginação são feitas no servidor; homônimos e texto legado não geram vínculo. Trocar/desvincular contato muda o conjunto da próxima consulta sem apagar negociações.

`GET /api/v1/accounts/:account_id/crm/companies/:company_id/opportunities` existe somente no overlay Enterprise e exige CRM, Empresas da conta, leitura da empresa e escopo nativo de cards. Retorna apenas a projeção comercial e `contact: {id,name}`; não expõe mensagens, notas, metadados de IA ou dados de contato desnecessários. Linhas e total têm a mesma visibilidade.

Contato e empresa compartilham `RelationshipOpportunities`, `useRelationshipOpportunities` e a projeção de `ProfileOpportunitiesController`, preservando o contrato e os seletores anteriores. Abertura em outra aba mantém a ficha e seu rascunho. O card do CRM continua com 640px; a ficha empresarial mantém o painel nativo, com abas equilibradas em duas linhas. Sem alteração de modelos, dependências ou migrações.

**Limite conhecido:** a rota da ficha aceita administrator/agent e não carrega para o papel personalizado sintético contact_view/crm_view. Esse cenário está bloqueado, não aprovado. Não houve ampliação de acesso. A API desse papel foi testada separadamente; a UI com agente padrão mostrou somente os dois cards autorizados. O alinhamento de papéis deverá ser tratado antes de liberar o conjunto.

Evidências: [auditoria da parte 10](../audit/2026-09-30-792-crm-relationships-part-10.md) e [12 telas reais](screenshots/792-part10/README.md). Reexecutados 502 testes frontend, 527 backend aprovados e quatro suspensos antigos, 28 checks de navegador concluídos (empresa + regressão do contato). A comparação direta no banco confirmou consulta sem alterações. O cenário bloqueado não está incluído nos aprovados.

## Próximo checkpoint proposto, ainda não autorizado

Após o aceite visual da parte 10, iniciar a revisão integrada M01–M08: consistência entre telas, permissões — incluindo o bloqueio de papéis personalizados —, concorrência entre escritores, efeitos externos e regressão do conjunto. Não fazer merge/deploy por consequência desta entrega. CI remoto e revisão independente continuam obrigatórios antes do pedido final de merge.

## Validação e publicação

Evidência da parte 1: [auditoria e limites](../audit/2026-09-30-792-crm-relationships-part-1.md). Evidência da parte 2: [testes, concorrência e limites](../audit/2026-09-30-792-crm-relationships-part-2.md).

A parte 3 modifica frontend e seus testes. Não houve migração, nova dependência de produto, flag ou alteração de produção. Os testes do protótipo não contam como teste desta implementação. Comparação visual, revisão independente do conjunto, concorrência entre fluxos e validação de produção permanecem exigidos antes da liberação final.

O merge de código na main pode disparar os dois workflows blue-green; portanto não fazer merge parcial para testar. O checkpoint fica em branch/PR de rascunho. Uma futura reversão de código não apaga cadastros; este incremento não exige exclusão de dados ou reversão de schema. A versão efetiva publicada na AWS e as flags precisam de conferência própria antes da integração visual/publicação: SHA de GitHub não é prova de deploy.
