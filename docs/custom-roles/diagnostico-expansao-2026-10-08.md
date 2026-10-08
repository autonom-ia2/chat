# Funções personalizadas — diagnóstico e proposta de expansão
Data: 08/10/2026 · Issue [#1135](https://github.com/autonom-ia2/chat/issues/1135)
Base inspecionada: `81fd4d88d4c1c1a5b6a121d2c2b84c7d874f18fc`.
Status: proposta para avaliação; nenhuma alteração de permissões ou de produção nesta tarefa.

## 1. Conclusão
A base atual oferece **34 chaves de permissão, 16 áreas no editor e 8 perfis prontos**, mas a função guarda uma lista de capacidades. Ela não guarda condições por caixa, time, funil, etapa ou responsável.

A expansão deve separar três decisões:
1. **Áreas:** quais módulos a pessoa pode abrir.
2. **Dados:** quais registros ela pode enxergar.
3. **Ações:** o que pode fazer com esses registros.

Uma visão salva organiza os dados que a pessoa já pode acessar. O limite de acesso é aplicado no servidor e não desaparece quando ela limpa um filtro ou usa a API.

## 2. Escopo e força da evidência
- Investigação de código OSS e Enterprise, interface, contratos, policies, consultas, filtros e histórico de Issues.
- Agentes especializados em servidor, interface e escopos; consolidação e conferência pelo agente principal.
- A captura enviada mostra a listagem e os resumos. Não demonstra todas as permissões efetivas nem a versão do servidor.
- As conclusões sobre comportamento são estáticas: leitura de código e de testes existentes. **Nenhum teste foi executado**, nem usuário real impersonado.
- Não houve leitura de banco, alteração de conta, mudança de auth, merge ou deploy.
- Cobertura dos caminhos citados; não é garantia de auditoria integral de todos os endpoints/realtime/jobs do produto.

## 3. O que existe hoje

### 3.1 Editor e modelo de dados
O editor já tem criação em dois passos, perfil inicial, ajustes por área, explicação do que a pessoa poderá fazer, prévia de navegação, duplicação e atribuição a agentes.
Os perfis são Atendente, Supervisor, SDR, Gerente comercial, Marketing, Financeiro, Operações e Somente leitura; também é possível começar do zero.

A função pertence à conta e guarda `name`, `description` e `permissions[]`. A API aceita esses campos, sem contrato de condições ou escopos. A associação ao membro usa um `custom_role_id`, não uma composição de várias funções.
Fontes: `enterprise/app/models/custom_role.rb:47-100`; `enterprise/app/controllers/api/v1/accounts/custom_roles_controller.rb:25-34`; `app/javascript/dashboard/routes/dashboard/settings/customRoles/permissionMatrix.js:325-414`.

### 3.2 Capacidades disponíveis
| Área | Controle atual | Limite relevante |
|---|---|---|
| Conversas | Nenhuma / Limitadas / Todas; não atribuídas e participação | Não há somente leitura; “Todas” não significa todas as caixas da conta |
| Contatos | Sem acesso / Ver / Editar | Editar também libera importação/exportação; sem carteira por função |
| Base de conhecimento | Sem acesso / Ver / Editar | Controle por módulo |
| Relatórios de atendimento | Sem acesso / Ver (`report_manage`) | Nome técnico antigo não significa editar relatórios |
| Respostas prontas | Uso como base; gerenciamento separado | Não são três níveis completos |
| CRM | Ver / Editar; mover cards, relatórios, funis, IA, exportar e acesso total | Criar, editar e excluir cards compartilham chave; editar já permite mover |
| Agentes Autonom.ia | Ver / Editar | “Ver” inclui testar no playground; não equivale a ausência de custo |
| Prospecção | Ver / Editar; ver todas as buscas | Busca/enriquecimento e outras operações compartilham gerenciamento |
| Cotação | Ver / Editar | Controle por módulo |
| Campanhas | Ver / Editar | Criar, enviar e importar listas ficam no mesmo pacote |
| Conexões / caixas | Ver / Editar configurações | Visibilidade de configuração não é visibilidade das conversas |
| Automações | Ver / Editar | Configurar automação é diferente de operar conversa |
| Etiquetas | Aplicar como base; gerenciar separado | Sem leitura/edição individual por etiqueta |
| Atributos | Preencher como base; gerenciar separado | Sem restrição de leitura por campo |
| Macros | Pessoais como base; macros da equipe separado | Baseline permanece |
| SLA | Gerenciar | Sem nível de visualização separado no editor |

Fonte do catálogo: `enterprise/app/models/custom_role.rb:55-90`.
Fonte do agrupamento: `app/javascript/dashboard/routes/dashboard/settings/customRoles/permissionMatrix.js:36-174`.

Regras atuais:
- Nos módulos com par correspondente, `*_manage` implica `*_view`.
- `crm_admin` concede todas as capacidades CRM reconhecidas pelas policies, inclusive exportação.
- Administrador mantém capacidades administrativas; agente sem função segue o comportamento nativo, que difere de uma função vazia.
- O CRM já nega a agente comum sem função as capacidades de configurar funis, IA, credenciais CRM e exportação.
Fontes: `enterprise/app/models/enterprise/account_user.rb:2-14`; `enterprise/app/policies/crm_permissions.rb:13-30`.

### 3.3 Como a visão de registros funciona
| Recurso | Regra atual |
|---|---|
| Lista de conversas | Para agentes/funções, caixas das quais o usuário é membro, depois as chaves de conversa da função; administrador passa sem esse recorte |
| Conversa individual | A base admite caixa **ou time**; o Enterprise acrescenta as chaves da função |
| Cards CRM | Caixa e configuração `assigned_only`; em caixas restritas, dono/atribuição/participação; cards sem caixa dependem do dono |
| Contatos | Consultas dos contatos da conta; não há recorte por caixa/time/responsável equivalente ao CRM |
| Prospecção | Existe capacidade explícita para passar de buscas próprias a todas as buscas |
| Resumo CRM (Summary verificado) | Gate de acesso ao relatório; calcula cards do funil da conta, sem receber o escopo visível do usuário |

Fontes: `app/services/conversations/permission_filter_service.rb:11-22`; `app/policies/conversation_policy.rb:10-43`; `enterprise/app/services/enterprise/conversations/permission_filter_service.rb:18-44`; `app/services/crm/cards/visible_scope_query.rb:9-66`; `app/services/contacts/filter_service.rb:32-34`; `app/controllers/api/v1/accounts/crm/reports_controller.rb:46-56`; `app/services/crm/reports/summary.rb:37-46`.

### 3.4 Condições e visões já disponíveis
Filtros de conversas/contatos aceitam atributos e operadores como igual, diferente, contém, preenchido, vazio, maior/menor e datas, de acordo com o atributo. Aceitam conectores AND/OR.
A base da consulta de conversas passa pelo filtro de permissão antes dos critérios pessoais.

Entretanto, o formato é uma sequência de condições; o construtor concatena os conectores. Não existe contrato comum de grupos explícitos para expressões como `(A OU B) E C`.
Filtros salvos pertencem ao usuário e podem ser de conversas, contatos ou relatórios. Não são regras de acesso atribuídas à função, nem um catálogo de visões compartilhadas por equipe.

Fontes: `app/services/filter_service.rb:25-44,194-207`; `app/helpers/filters/filter_helper.rb:112-119`; `app/services/conversations/filter_service.rb:26-42`; `app/models/custom_filter.rb:19-30`; `app/controllers/api/v1/accounts/custom_filters_controller.rb:30-51`; `lib/filters/filter_keys.yml`.

## 4. Limitações e inconsistências prioritárias

### 4.1 Não existe “ler conversas sem operar”
As três chaves de conversa são de gerenciamento, com diferentes recortes de visão. O perfil “Somente leitura” não concede conversas.
Marketing não pode hoje receber uma opção nativa “ler conversas desta caixa, sem responder/atribuir/alterar”.
Isso exige novas capacidades e verificação dos caminhos de escrita; trocar apenas o rótulo do editor seria insuficiente.

### 4.2 Condições não são parte da função
Não é possível configurar na função “caixas A e B”, “meus times”, “apenas estes funis” ou combinar responsável + etapa + etiqueta.
Membresia da caixa e `assigned_only` do CRM resolvem parte da necessidade, mas ficam fora da função e podem afetar outras pessoas.
Conceder `inbox_view` não resolve: essa chave é de configuração de caixas.

### 4.3 Listagem e abertura de conversa podem discordar
O filtro Enterprise usa `if/elsif`: ao ter não atribuídas **e** participação, aplica apenas não atribuídas + minhas.
A policy individual verifica cumulativamente não atribuídas e participação.
Exemplo derivado do código: se também satisfizer a base de caixa ou time da policy, participante de uma conversa atribuída a outro usuário pode abrir o registro por ID, mas a combinação das duas chaves pode omiti-lo da lista.

Há também diferença da base: listagem parte de caixas; abertura admite caixa ou time.
Não classificamos isso automaticamente como vazamento: pode ser desenho herdado. A diferença precisa ser decidida e validada antes de acrescentar combinações.
O spec atual inclusive preserva a prioridade exclusiva; corrigir exige tratar essa regra explicitamente.
Fontes: `enterprise/app/services/enterprise/conversations/permission_filter_service.rb:18-44`; `enterprise/app/policies/enterprise/conversation_policy.rb:2-29`; `spec/enterprise/services/enterprise/conversations/permission_filter_service_spec.rb:172-211`.

### 4.4 Escopo CRM não implica escopo de relatórios/contatos
Um usuário com cards limitados por caixa pode receber relatório do funil inteiro quando tem `crm_view_reports`.
O resumo `Summary` verificado usa `account.crm_cards`, não o escopo de cards do usuário. Essa amplitude está no código; falta confirmar a intenção do produto. Não generalizamos essa conclusão para todo relatório existente.
Da mesma forma, restringir cards não cria automaticamente uma carteira restrita de contatos.
Precisamos distinguir “relatórios do que posso ver” de uma concessão explícita de “relatórios globais”.

### 4.5 Algumas ações sensíveis vêm dentro de “Editar”
- `contact_manage`: criar/atualizar + importar/exportar; excluir contato continua reservado ao administrador.
- `crm_manage_cards`: criar/editar/excluir, além de mover.
- `campaign_manage`: criar/editar + importar + enviar.
- `crm_admin`: agrega todas as capacidades CRM, com efeitos sobre credenciais.

Fontes: `enterprise/app/policies/enterprise/contact_policy.rb:20-26`; `enterprise/app/policies/enterprise/crm/card_policy.rb:16-29`; catálogo do modelo e `enterprise/app/policies/crm_permissions.rb:19-29`.
O editor sinaliza como sensíveis apenas IA CRM, exportação CRM e acesso total CRM (`permissionMatrix.js:32-34`); isso não cobre todo o efeito dos pacotes.

### 4.6 Excluir a função pode devolver o baseline de agente
A associação dos membros usa `dependent: :nullify`. Excluir uma função restritiva deixa seus membros sem função e eles voltam à regra nativa.
Logo, exclusão não equivale a revogar todo acesso. A futura tela deve mostrar o destino dos membros e exigir uma escolha explícita quando necessário.
Fonte: `enterprise/app/models/custom_role.rb:48-49`; regras do membro/CRM citadas acima.

### 4.7 Tela oculta não é garantia de autorização
Menu e rota são uma camada. A concessão precisa coincidir com controller/policy, consultas e payloads associados.
A pendência [#726](https://github.com/autonom-ia2/chat/issues/726) é um exemplo: acesso a Modelos pela área de Campanhas e ação de sincronizar têm permissões distintas.
Ainda demanda conferência específica antes da implementação; a Issue não substitui evidência de execução.

## 5. Proposta de produto

### 5.1 Manter o editor e acrescentar “Dados visíveis”
Manter os perfis iniciais e os grupos atuais. Cada área relevante passa a explicar:
- **Pode fazer:** consultar, operar e ajustes específicos.
- **Pode enxergar:** recorte dos registros.
- **Visões disponíveis:** atalhos opcionais de trabalho.

A prévia do menu deve continuar, mas o resumo principal descreve o alcance:
“Lê conversas das caixas selecionadas. Não responde. Edita cards do funil Comercial atribuídos ao próprio usuário. Não exclui nem exporta.”

Os perfis servem como ponto de partida, não como regras escondidas. Alterar o catálogo de um perfil não deve mudar funções já salvas automaticamente.

### 5.2 Primeira entrega útil
Priorizar **conversas e cards CRM**:
| Decisão | Opções propostas |
|---|---|
| Conversas: ação | Sem acesso / Consultar / Operar |
| Conversas: alcance | Todas dentro da base autorizada / minhas / não atribuídas / participadas / meus times |
| Recorte de conversas | Caixas selecionadas, sempre dentro da base de acesso aprovada |
| CRM: alcance | Cards visíveis na base atual / meus cards / recorte de caixas e funis |
| Ações CRM | Criar/editar, mover, excluir e exportar como capacidades distinguíveis |
| Combinação inicial | Várias caixas ou funis selecionados; responsável e time com semântica explícita |

Não delegar usuários, funções, secrets, auth, billing ou infraestrutura neste pacote. Não implantar automaticamente as 18 permissões mencionadas na proposta antiga do editor.

### 5.3 Regras de combinação
Usar dois níveis legíveis:
- **Dentro de um grupo: TODAS as condições (E).**
- **Entre grupos: QUALQUER grupo (OU).**

Exemplo de regra de visão:
```text
(Caixa é Comercial E responsável sou eu)
OU
(Caixa é Comercial E está sem responsável)
```

Equivalência de agrupamento:
`(A OU B) E C` pode ser escrito como `(A E C) OU (B E C)`.
Isso cobre combinações úteis sem um editor de parênteses ilimitado.
Seleção de múltiplos valores numa condição significa “um destes valores”, e não “todos”.

O teto de acesso nunca fica dentro desse OU:
```text
registros visíveis =
  registros da conta
  E base de acesso aprovada
  E alcance concedido pela função
  E (grupo 1 OU grupo 2)
  E filtro escolhido na tela
```

Grupos condicionais completos são uma etapa posterior ao primeiro recorte por caixa/funil/responsável. Não transportar filtros SQL atuais diretamente para autorização.

### 5.4 Condições por etapa
| Etapa | Condições | Motivo |
|---|---|---|
| Inicial | Caixa, funil, próprio responsável, não atribuído, participação, time | Relações já existentes e claras |
| Seguinte | Etapa do funil, etiquetas, status e prioridade | Compor filas de trabalho e regras controladas |
| Posterior | Atributos personalizados tipados, datas e faixas numéricas | Exige validar tipos, desempenho e explicação |

O catálogo é específico por recurso: funil e etapa pertencem ao CRM; responsável, caixa, time, status e etiquetas devem usar as relações corretas de conversa ou card. Não oferecer funil como atributo nativo de conversa.

Status, etiquetas e atributos podem ser alterados por usuários/automação. Quando usados como limite de acesso, é obrigatório decidir quem pode alterá-los e como revalidar as ações. Não criar um caminho em que mudar uma etiqueta permita ampliar a própria permissão.
Valores inexistentes, tipos errados ou IDs de outra conta devem ser recusados na entrada, sem coerção silenciosa.

### 5.5 Exemplos de funções possíveis
| Função | Enxerga | Faz |
|---|---|---|
| Marketing analista | Conversas das caixas A/B e cards do funil Marketing | Consulta; não responde, exclui ou exporta |
| SDR | Conversas próprias OU sem responsável na caixa Comercial; cards próprios | Responde, cria/edita cards; não dispara campanhas |
| Supervisor | Conversas dos times selecionados e cards dos funis da equipe | Opera, redistribui conforme concessão; relatórios do mesmo recorte |
| Auditor | Registros do recorte aprovado | Só consulta; exportação exige concessão separada |
| Gestão comercial | Funis selecionados e métricas autorizadas | Gerencia cards; configura funis/IA somente se concedido |

São possibilidades propostas, não capacidades atuais. Alcance por time não deve significar acesso a qualquer caixa da conta.

### 5.6 Visões compartilhadas
Depois do escopo confiável, permitir salvar visões:
- Pessoais, do time ou vinculadas à função.
- Nome e condições; compartilhamento separado de permissão de dados.
- Cada pessoa vê a interseção da visão com seu acesso.
- Exemplo: “Leads sem responsável” ou “Pós-venda com SLA perto de vencer”.
- Mostrar por que um registro aparece e diferenciar “nenhum resultado” de “sem permissão”.

Não usar a mesma palavra “visão” para concessão de acesso e filtro opcional. Sugestão de UI: **Dados visíveis** para autorização e **Visões salvas** para atalhos.

## 6. Proposta técnica e invariantes
1. Conservar as chaves existentes e introduzir um contrato tipado/versionado de alcance, separado de `permissions[]`. A coluna/associação exata fica para o plano de implementação após aprovação.
2. Escopos compartilhados por recurso aplicados no primeiro ponto comum da consulta; policies individuais verificam o mesmo conjunto. Não repetir motores independentes por endpoint.
3. Capacidade de escrita exige também acesso ao registro. Exportação exige capacidade específica e o mesmo escopo.
4. Usar a mesma semântica para lista, busca, contagem, detalhe, exportação, relatórios e entrega realtime/notificações. Auditar os caminhos que hoje fazem consultas diretas.
5. Reutilizar componentes de filtros e seletores da aplicação; validar o novo contrato no servidor. Não reutilizar cegamente SQL concatenado nem permitir campos/operadores livres.
6. A IA pode ajudar a rascunhar/explicar uma regra. A decisão de acesso é determinística e validada pelo servidor.
7. Preservar OSS e o overlay Enterprise. Novas concessões de função ficam no modelo/overlay correspondente; o escopo comum não deve depender só do menu.
8. Alterações de alcance devem invalidar caches/contadores e revalidar a sessão/realtime conforme os canais afetados.
9. Não acumular várias funções por pessoa nesta primeira expansão: exigiria regras de união/negação, prioridades e diagnóstico próprio.
10. Mascaramento de telefone/e-mail/valor é outro contrato, pois os campos aparecem em payloads, busca, exportação e eventos. Deixar para etapa específica.

O Guia hoje consulta os endpoints reais como o usuário (`app/services/autonomia/guide/chamada_interna.rb:25-46`). As novas restrições precisam funcionar por esse caminho também.
Sua execução de escrita tem gate próprio de administrador (`app/services/autonomia/guide/acoes.rb:206-213`); delegá-la a funções personalizadas não faz parte desta expansão inicial.

## 7. Sequência recomendada
| Etapa | Entrega | Dependência / critério |
|---|---|---|
| 0 — Coerência | Reproduzir e decidir divergências lista/detalhe/time; decidir métricas globais e exclusão da função | Contrato explícito, sem “corrigir” ampliando acesso silenciosamente |
| 1 — Consulta e alcance | Somente leitura real em conversas; recortes por caixa, responsável e funil | Escritas negadas no servidor; manter funções antigas |
| 2 — Ações separadas | Excluir/exportar/atribuir, conforme priorização; separar preparar de enviar campanha | Mapa completo dos caminhos da ação; não refatorar todos os módulos de uma vez |
| 3 — Combinações | E dentro de grupos / OU entre grupos; critérios por etapa | Mesmo resultado em lista, detalhe, métricas e eventos |
| 4 — Visões de trabalho | Compartilhar visões por time/função; explicar alcance | Visão não amplia o acesso |
| Posterior | Campos sensíveis, prazo de acesso, delegação administrativa e múltiplas funções | Escopo próprio e aprovação específica |

Esforço relativo: etapa 0 pequeno/médio; etapa 1 grande; etapa 2 variável por módulo; etapa 3 grande; etapa 4 médio.
São avaliações de complexidade, não estimativas de prazo. O plano posterior deve dimensionar paths reais e critérios antes de prometer datas.

## 8. Compatibilidade, validação e liberação
- Funções antigas mantêm contrato legado até uma adoção explícita. Não transformar ausência de escopo em concessão ampla para regras novas.
- Distinguir “legado sem novo escopo”, “nenhum registro” e “todo o alcance autorizado”; não usar um array vazio ambíguo.
- Novas capacidades sensíveis começam desabilitadas, exceto mapeamento explícito aprovado para preservar concessões legadas.
- Não fazer backfill amplo nem ajustar membresias de caixas automaticamente.
- Ao apagar/substituir função, mostrar o baseline resultante e os membros afetados.
- Verificação necessária na implementação: pessoa própria/outro time/outro inbox, participação com dupla chave, acesso direto por ID, API e Guia, escrita sob consulta, filtros removidos, exportação e contagem/relatórios.
- Testar isolamento entre contas, mudança de permissões com sessão aberta e payload realtime; não basta ausência no menu.
- Rotas/menu/explicações exigem gerar e checar o Guia; strong params/validações alcançadas exigem regenerar os formatos das ações.
- Merge/deploy/produção somente após aprovação explícita do Rodrigo.
- Rollout proposto por capacidade habilitada explicitamente, preservando o legado e oferecendo prévia de impacto.
- Rollback deve considerar compatibilidade de chaves e versão de escopo. Reverter apenas código pode fazer a validação antiga rejeitar funções com novas chaves; preservar valores/snapshot e planejar reversão antes da escrita.
- Esta PR contém somente documentação: não requer deploy de comportamento nem alteração de banco.

## 9. Histórico relacionado
- [#452](https://github.com/autonom-ia2/chat/issues/452): matriz por módulo, entregue.
- [#888](https://github.com/autonom-ia2/chat/issues/888): novo editor; as 18 novas capacidades citadas ficaram fora daquele PR.
- [#879](https://github.com/autonom-ia2/chat/issues/879) e [#894](https://github.com/autonom-ia2/chat/issues/894): limite de caixa por membresia e ausência de conversa somente leitura já apareceram em pedidos reais; corrigir a explicação não criou as capacidades.
- [#726](https://github.com/autonom-ia2/chat/issues/726): decisão pendente sobre Modelos na área de Campanhas.
- `docs/audit/2026-09-18-custom-roles-matrix.md` e `docs/audit/2026-10-03-custom-roles-editor.md`: decisões/validações históricas; resultados antigos não foram rerrodados nesta investigação.

## 10. Recomendação para decisão
Aprovar primeiro a direção **área + dados visíveis + ações**, concentrando a primeira implementação em conversas e CRM.
Definir, antes de codificar, se relatórios são do recorte visível ou globais por concessão explícita, e qual base caixa/time deve valer igualmente para listagem e abertura.
Depois dessa decisão, abrir tarefas de implementação com critérios e PRs pequenos. Não começar por um pacote de dezenas de novas chaves administrativas.
