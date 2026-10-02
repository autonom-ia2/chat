# #792 — Parte 14: controles legados do atendimento e ações do CRM

## Autorização e limites

Rodrigo aprovou as partes 1–13 e autorizou o próximo trecho da revisão integrada: controles antigos de edição e ações do atendimento. Base `b2a8cfd1518030cb9fa2b8a644590e5eee166b78`, branch/worktree exclusiva `feat/792-crm-relacionamentos`, Issue #792, PR #793 em rascunho. Parar para aceite depois das evidências. Sem merge, deploy, acesso à AWS, alteração de usuários reais, dependências ou migração.

Este incremento alinha as telas às permissões que o servidor já aplica. Não cria permissões novas, não muda o acesso de administrador/agente padrão nem a quantidade de oportunidades. O card conserva 40rem/640px, componentes, cores e navegação aprovados. Permissão de atender conversas, editar cadastro compartilhado, gerenciar negociação e gerenciar IA permanecem independentes.

## Caminhos corrigidos

### Contato dentro do atendimento

`ContactInfo` consulta `useRelationshipPermissions`, o mesmo contrato das fichas canônicas. Um leitor recebe nome, e-mail, telefone, dados já confirmados, copiar/abrir e o aviso de consulta, sem edição de nome/campos, gaveta cadastral ou mesclagem. O handler de atualização revalida a capability, inclusive em ações antigas ou após revogação. A edição autorizada continua usando o mesmo `contacts/update`, não uma cópia do cadastro.

`ContactInfoRow` também revalida editabilidade antes de emitir o valor, inclusive no blur. `EditContact` remove o formulário quando a permissão deixa de existir. O callback antigo de salvar **rejeita** nesse estado, em vez de resolver sem gravação e induzir o formulário a mostrar sucesso. Fechar a gaveta continua disponível.

As notas existentes permanecem legíveis. Criar, excluir e o atalho de salvar exigem gestão cadastral; o atalho só atua enquanto a composição está realmente aberta. O texto oculto após revogação não é enviado por um evento de teclado. A proteção efetiva dos endpoints de notas continua sendo a policy adicionada na parte 12.

Atributos do **contato** são apresentados em leitura pelo `FieldEditor` existente, também quando a habilitação opcional da nova Central não está ativa. Zero e falso continuam distintos de vazio. As definições/configuração não foram modificadas. Os atributos da **conversa** mantêm seu caminho anterior: não recebem bloqueio cadastral indevido. Atualizar/excluir valor no caminho de contato revalida a capability; a remoção usa o mesmo identificador canônico já empregado na atualização.

### Ações comerciais dentro do atendimento e do card

`ConversationAction` mantém o link e a etapa para quem consulta o CRM, mas só busca escolhas de funil/etapa e oferece Criar card para quem gerencia oportunidades. O handler também verifica o estado atual. Assignee/time, prioridade da conversa, etiquetas da conversa, envio e demais funcionalidades de atendimento não foram convertidos em permissões cadastrais.

No drawer, o leitor conserva os valores do Resumo em leitura e os follow-ups existentes, sem Salvar, Arquivar, criar/concluir/cancelar follow-up ou iniciar agendamento. A confirmação de arquivamento adiada por um rascunho revalida a permissão ao executar. Confirmar ganhar/perder/reabrir e os callbacks de gravação revalidam a capability; revogar o direito não deixa uma ação antiga continuar válida. A criação de reunião já exige `Crm::FollowUp#create?` e `Card#update?` no controlador; o botão passa a espelhar esse requisito. Nenhuma reunião externa foi criada.

O estado de follow-up automático permanece visível. Reiniciar/reativar usa `canManageAi`, enquanto mudar a exclusão de follow-up no contato usa `canManageRecords`. Uma capability não concede a outra. O controle de contato em leitura permanece desabilitado e mostra seu estado; confirmação antiga de reset/toggle não dispara nova requisição após revogação.

## Reprodução e testes

Os testes novos primeiro evidenciaram controles de escrita no leitor, arquivamento diferido executado após revogação, callbacks sem verificação e criação comercial oferecida no atendimento. Os ensaios iniciais também identificaram ajustes necessários no harness: stub de input sem método focus, transição sem slot e mocks reiniciados entre exemplos. Esses problemas de preparação foram corrigidos no teste, não mascarados por alterar o produto. O atributo `disabled` do Switch foi verificado como atributo nativo, e não como prop inexistente.

A bateria direcionada final inclui os caminhos autorizado/negado, revogação, atributos de contato com a habilitação opcional ligada/desligada, zero/falso e preservação dos atributos da conversa. Três testes antigos que executavam operações legítimas passaram a declarar explicitamente `canManageCards: true`, mantendo as mesmas expectativas de proteção de rascunho. Não foi removida nenhuma asserção ou criado novo skip.

O novo request spec `legacy_ui_action_permissions_spec.rb` possui dez casos. Com `conversation_manage + contact_view + crm_view`, a conversa e o lembrete permitido continuam legíveis, mas escrever contato, arquivar/alterar card, completar/cancelar/criar lembrete, resetar cadência e criar a partir da conversa são recusados. Contagens e registros são comparados integralmente. Com permissão comercial explícita, concluir o lembrete continua permitido sem alterar o contato. São testes do contrato existente, não uma alegação de que uma nova policy foi criada nesta parte.

## Validação real

Baterias completas executadas sequencialmente para evitar a carga simultânea que afetou as medições anteriores. Nenhum limite de tempo foi aumentado. Resultados finais, qualidade, capturas e prova de persistência são registrados no fechamento desta parte.

O roteiro de navegador usa aplicação compilada com Rails e PostgreSQL locais reais, porta 3792 e Redis exclusivo 6792. O banco de UI `chat2you_792_ui_test` é separado do RSpec `chat2you_792_test`; adaptadores de teste e nenhum worker de envio. Browser plugin não disponível: Playwright/Chrome existente, sem instalação. Não simular respostas de negócio para provar gravação. Capturas desktop 1620×1000 e celular 390×844.

A fixture exercita especificamente a lateral legada com `relationships_attributes` desativada somente na conta sintética e conserva o estado anterior para restauração. Os testes unitários também cobrem a configuração nova habilitada. Um perfil pode atender conversas sem editar o cadastro; outro tem a gestão explícita. O roteiro consulta dados/notas/atributos, verifica as ações do CRM, tenta requisições negadas diretamente e confirma uma edição autorizada no mesmo contato. Nenhuma mensagem, reunião, campanha ou reset de cadência é solicitado pelo navegador.

## Retomada e fechamento da validação de navegador

A retomada encontrou a parte 14 já implementada, sem commit, com as baterias completas anteriores aprovadas e o roteiro de navegador incompleto. Não houve reimplementação nem mudança de produto para contornar o teste. A espera de confirmação usava igualdade da URL sem o parâmetro que `ContactAPI.update` efetivamente envia (`include_contact_inboxes=false`). O servidor já recebia a edição, mas o observador de resposta não a reconhecia. O roteiro passou a conferir caminho, parâmetro e método PATCH reais; a expectativa de HTTP 200 e a leitura posterior do mesmo registro foram mantidas.

A preparação repetida também tentou inserir membros que já pertenciam à caixa sintética. Foi corrigida somente a fixture para reutilizar o ID da conversa/caixa registrado e adicionar membros ausentes. As validações nativas de unicidade permaneceram ativas. Os logs do timeout e da fixture rejeitada foram conservados, separados do roteiro concluído.

O roteiro concluído executou **12 verificações**, gerou **sete capturas** e confirmou seis recusas HTTP 401 por tentativa direta. A única escrita cadastral solicitada foi o nome do mesmo contato, via edição inline autorizada. A consulta seguinte pelo perfil leitor mostrou o valor confirmado sem habilitar edição. O card continuou com 640px no desktop e ajustado à largura disponível no celular.

Conferência direta do banco: 51 contatos, 23 empresas, 91 oportunidades, 11 conversas, 33 mensagens, um follow-up e uma nota antes e depois. Apenas `name` e `updated_at` do contato mudaram, conforme a ação explícita. Card e lembrete permaneceram integralmente iguais. As chamadas nativas `update_last_seen` foram contabilizadas separadamente, sem envio de mensagens; nesse ensaio não houve diferença persistida nos campos da conversa. A habilitação opcional de atributos da conta sintética foi restaurada ao estado anterior.

## Resultado das baterias na retomada

| Verificação | Resultado confirmado |
|---|---|
| Frontend completo | **7.120 testes em 639 arquivos**, todos aprovados na reexecução da retomada. |
| Backend ampliado | **751 exemplos: 744 aprovados, zero falhas e sete suspensos históricos**. |
| Contratos adicionados | Dez exemplos de API e 22 testes frontend adicionados nesta parte, incluídos nas contagens maiores. |
| Navegador | **12 verificações**, sete capturas, seis tentativas diretas recusadas e uma edição cadastral autorizada. |
| Dados persistidos | Contagens preservadas; mesmo contato; card e follow-up intactos. |
| Build | Compilação Vite em modo test aprovada na retomada; mesmo asset `dashboard-DuS2Z0nf.js` utilizado nas capturas. Avisos anteriores de tamanho de chunks/Browserslist foram mantidos. |
| Qualidade | ESLint em 12 arquivos, zero bloqueadores e quatro avisos de chaves dinâmicas; RuboCop no novo request spec sem infrações; Prettier e whitespace aprovados. |
| Traduções e documentação | Oito catálogos/16.232 mensagens, Guia/Central conferidos, AST de 389 fontes/testes sem novos regex. |

Os sete suspensos são os mesmos identificados na seleção ampliada da parte 13; nenhum foi adicionado ou contabilizado como aprovado nesta entrega. Os 47 testes direcionados já tinham sido reexecutados após os handlers finais; a retomada voltou a executar também as baterias completas, sem alterar limites de tempo ou expectativas.

Comandos e saídas: `.codex/792/part14-resume-validation.sh`, `part14-resume-backend.json/log`, `part14-resume-frontend.log`, `part14-resume-build.log`, `part14-resume-status.json`, `part14-resume-browser.log` e `part14-resume-persistence.log`. O roteiro sequencial executa primeiro RSpec, depois Vitest e por último a compilação, com os mesmos bancos/portas exclusivos. A política do servidor não é substituída pelos testes de componentes.

## Evidências e continuidade

Roteiros/logs privados: `.codex/792/part14-*`. Evidências compartilháveis em `docs/relationships/screenshots/792-part14/`; não versionar senhas, headers, tokens ou snapshots completos. Fonte e imagem têm hashes conferidos após commit.

A revisão integrada ainda precisa tratar os sete testes históricos suspensos da seleção ampliada, as demais entradas de escrita/concorrência e os efeitos externos. Os workflows de runtime/testes desabilitados e a revisão independente bloqueada pelo tier de modelo continuam gates, não foram contornados. Este patch não revisa todas as ações nativas de atendimento ou a revogação de jobs já autorizados. Aprovação das telas não substitui esses gates e não autoriza merge/deploy.
