# #792 — Parte 11: primeira revisão integrada e correções de integridade

## Autorização, base e limite desta entrega

Rodrigo aprovou as partes 1–10 e autorizou a revisão integrada M01–M08, incluindo a pendência dos papéis personalizados. Base `bb45b0fec6f5afe9907d0c6337daacab05959b4f`, branch `feat/792-crm-relacionamentos`, worktree exclusivo, Issue #792 e PR #793 em rascunho. Esta entrega corrige dois defeitos reproduzidos e registra bloqueios que impedem a aprovação global. **Não é liberação de merge/deploy e não conclui a revisão independente.** Sem alteração de produção, usuários reais, credenciais ou infraestrutura da AWS.

## Correções implementadas

### 1. Navegação do papel personalizado sem ciclo de redirecionamento

`defaultRedirectPage`, em `app/javascript/dashboard/helper/routeHelpers.js`, considerava `contact_manage`, mas não `contact_view`. Ao tentar uma ficha empresarial cuja rota exige administrator/agent, o papel sintético contact_view/crm_view era encaminhado para o dashboard, também não autorizado, e a navegação não se estabilizava. Essa era a falha de carregamento registrada nas partes 10 e retomada.

O destino alternativo agora inclui a permissão já existente `contact_view` e encaminha para **Contatos**, rota que esse usuário já pode abrir. Não se alterou o gate da empresa, nenhuma lista de permissões foi ampliada e a ficha empresarial não passou a ser editável por consequência. Abrir a empresa com esse papel continua não autorizado, mas não prende mais a aplicação em um ciclo. O browser real confirmou a URL de destino, GET de contatos 200, lista visível, recarregamento estável e a consulta das duas oportunidades permitidas do contato.

Três testes foram adicionados a `routeHelpers.spec.js`; dois falharam antes da correção (dashboard em vez de contatos). Permanecem as asserções de não concessão de acesso à empresa e de que crm_view sozinho não concede acesso a contatos. A UI e a permissão empresarial em si são decisões separadas.

### 2. Proteção também no sentido conversa → oportunidade

A proteção de `ContactLinker` validava trocar o contato quando já havia conversas. Porém, `ConversationLinker` ainda permitia o inverso: anexar uma conversa de João ao card de Mariana. Esse serviço também calculava a escolha implícita da conversa primária no construtor, antes de ler o estado atualizado do banco, e podia remover uma primária mais nova ao desvincular com uma instância antiga.

`ConversationLinker#link` e `#unlink` agora usam o mesmo lock de card utilizado pelo vínculo de contato. Sob esse lock, a inclusão confere o contato do card, a conversa primária legada e as secundárias; uma incompatibilidade retorna o erro 422 já existente, sem dados pessoais no erro e sem deixar vínculo/histórico parcial. A escolha automática da primária é feita após recarregar o card. Desvincular lê a primária atual antes de removê-la. Conversas legítimas da mesma pessoa e os campos comerciais continuam preservados.

Nove testes de integridade foram adicionados: sete falhavam no código anterior, inclusive mistura de pessoas, primária decidida com estado antigo e remoção da primária mais nova. Após a correção, os nove passaram, juntamente com os testes legados e um novo teste do endpoint reverso. Não se alterou a semântica das outras integrações nem se afirmou que todos os escritores estão protegidos.

A concorrência foi ensaiada adicionalmente com duas conexões PostgreSQL reais, uma segurando o lock enquanto a outra tenta o caminho oposto. Foram seis cenários, três com troca de pessoa primeiro e três com vínculo de conversa primeiro: sempre uma confirmação e uma recusa por conflito, com pessoa coerente e título/valor intactos. O ensaio criou somente fixtures identificadas em banco local; esses registros não fazem parte das capturas de contato.

## Bloqueios descobertos e reproduzidos — NÃO corrigidos neste incremento

### P1 — Consulta não está separada de escrita nas políticas de cadastro

O teste diagnóstico com transações isoladas demonstrou três resultados reais:

| Papel / operação | Resposta e efeito observado |
|---|---|
| contact_view + crm_view → PATCH de contato | HTTP 200; alteração persistida durante a transação do teste. |
| contact_view + crm_view → PATCH de empresa | HTTP 200; alteração persistida durante a transação do teste. |
| contact_view + crm_view + crm_manage_cards, sem contact_manage → cadastro composto | HTTP 201; uma pessoa, uma empresa e uma oportunidade criadas durante a transação do teste. |

São **reproduções de defeitos**, não testes de segurança aprovados. Todos os registros dessas sondagens foram revertidos pelo isolamento RSpec. Não foi consultada a AWS nem testado um usuário real.

As políticas `ContactPolicy` e `CompanyPolicy` permitem as operações básicas incondicionalmente; o overlay de ContactPolicy só trata importação/exportação. Esses arquivos são idênticos aos da base da branch (`git diff e45fbe6..bb45b0f` sem mudança nesses caminhos). O fluxo novo chama essas políticas, logo herda a permissividade. A matriz de papéis já descreve contact_view como leitura e contact_manage como edição; esconder botões ou simplesmente liberar a rota empresarial não corrige a autorização no servidor.

**Próximo incremento proposto:** alinhar autorização de consulta/escrita de contato/empresa, seus atributos, mídia/avatar, notas e vínculo empresarial, além dos caminhos CRM que os reutilizam; manter explicitamente a compatibilidade de administrador/agente padrão e tratar o acesso de papéis personalizados sem lhes atribuir novos direitos. Separar gerenciar oportunidade de gerenciar cadastro. A alteração de contrato e todos os testes/UI correspondentes precisam ser revisados antes de liberar o conjunto. Nenhuma dessas políticas foi alterada nesta parte 11.

### Revisão independente bloqueada

Foi tentada uma execução independente com o Codex local já instalado e autenticado pelo plano ChatGPT. A execução ignorou a configuração do usuário, usou sandbox read-only, nenhum servidor MCP e o modelo configurado `gpt-6.1-sol`, esforço high. A ferramenta recusou o modelo com HTTP 400: `The 'gpt-6.1-sol' model is not supported when using Codex with a ChatGPT account.`

Resultado: **BLOCKED_MODEL_TIER** para a revisão independente. Não houve fallback, downgrade, cobrança via chave API ou aprovação produzida. A revisão e os testes conduzidos pelo implementador não são apresentados como revisão independente. O prompt completo, identificadores de sessão e dados de autenticação não são publicados.

### CI específico de Relacionamentos está desabilitado

A consulta autenticada ao GitHub confirmou `.github/workflows/relationships.yml` (ID 370172507, Relationships - isolated regression and Linux runtime) em `disabled_manually`. `Testes do fork` também está desabilitado. Portanto, a ausência dessas verificações não é apenas uma execução que ainda está aguardando.

Os workflows ativos de traduções, Guia/Central e proteção de e-mail concluíram suas verificações no checkpoint anterior, mas não substituem a prova do runtime Linux de Relacionamentos. A seleção backend no YAML foi ampliada com os testes do vínculo de conversa, sem reabilitar workflows ou alterar deploy. Definir a execução desse gate antes de aprovar merge; nenhuma configuração remota foi modificada nesta entrega.

## Matriz integrada neste checkpoint

| Referência | Resultado da revisão até aqui |
|---|---|
| M01 / M08 — Dados compartilhados, atributos e mídias | Telas previamente aprovadas; revisão de permissões de escrita é bloqueadora e está aberta. |
| M02 — Vínculos posteriores | Corrigido o caminho reverso de conversa e a disputa entre ContactLinker/ConversationLinker. Outros escritores, merges e upserts ainda exigem revisão. |
| M03 / M04 / M05 — Nova oportunidade e duplicidades | Cadastro composto aprovado visualmente; separação contact_manage/crm_manage_cards e concorrência entre escritores externos continuam pendentes. |
| M06 — Ficha do contato | Navegação de contact_view corrigida e lista autorizada revalidada em desktop/celular. O perfil de leitura ainda tem a falha de escrita na API descrita acima. |
| M07 — Ficha empresarial | Administrador/agente mantêm o trecho aprovado. Papel personalizado não ganha acesso à ficha por este patch; o ciclo de fallback foi corrigido. |

Não foi certificado o comportamento de integrações externas. A atividade CRM possui callback after_commit que pode emitir eventos aos webhooks assinantes; a ausência de novas mensagens nos ensaios locais não prova ausência de ações de sistemas externos em produção. Preservar esse contrato e revisar os efeitos antes da liberação, sem desativar callbacks globalmente.

Os quatro testes antigos suspensos, incluindo três de projeção/visibilidade de conversas, continuam bloqueios de revisão específicos; sua condição histórica não é evidência de segurança. Não foram removidos, relaxados ou incluídos na contagem de aprovados.

## Validação local executada

| Verificação | Resultado |
|---|---|
| Frontend completo | 7.081 testes em 634 arquivos aprovados. |
| Backend de Relacionamentos/CRM ampliado | 544 exemplos: 540 aprovados, zero falhas, quatro suspensos históricos. |
| Vínculos, teste direcionado | 37 exemplos aprovados, incluídos na bateria maior; não somados novamente. |
| Concorrência real | Seis cenários com duas conexões PostgreSQL, ambos os ordenamentos dos escritores; invariantes preservadas. |
| Browser desta correção | Cinco verificações e três capturas da aplicação compilada. |
| Regressão de oportunidades do contato | 14 verificações, totalizando 19 checks de navegador, com erro/retentativa e permissões de consulta. |
| Persistência da regressão | 49 contatos, 23 empresas, 87 oportunidades, 33 mensagens e oito conversas antes/depois; contato e seus oito cards integralmente preservados. Os seis cards/conversas adicionais vêm da fixture de concorrência preparada antes desse baseline. |
| Build / qualidade | Vite test, ESLint, Prettier, RuboCop, Guia, Central e AST sem regex novos verificados. Avisos legados de bundle/Browserslist não foram ocultados. |

Ambiente exclusivo: Rails test/CI=true em 127.0.0.1:3792, PostgreSQL de testes de UI e requests separados, Redis 6792, dados fictícios e sem workers de entrega. Browser plugin não disponível; usado Playwright/Chrome existente, sem instalar dependências. Capturas 1620×1000 e 390×844, mais regressão notebook 1366×768. O card mantém os 640px da parte aprovada, sem mudança de desenho.

Um ensaio inicial do roteiro novo falhou por usar o seletor do painel empresarial no contato. O roteiro foi corrigido para o seletor real já validado na parte 9 e reexecutado; nenhuma alteração de produto foi feita para contornar esse erro. A captura da lista espera também o resumo terminar de carregar. Os caminhos concluídos não tiveram exceção JavaScript ou erro de renderização; erros HTTP locais e o GET interrompido deliberadamente permanecem registrados.

## Reprodução e evidências

Testes versionados: `routeHelpers.spec.js`, `conversation_linker_integrity_spec.rb`, `card_contact_links_spec.rb` e os testes anteriores. A seleção backend é a de `.github/workflows/relationships.yml`. Frontend: `pnpm test --maxWorkers=2 --minWorkers=1`; build: `pnpm exec vite build --mode test`. Demais verificações: ESLint direcionado, RuboCop, `pnpm guia:check`, `pnpm central:check`, `pnpm relationships:check` e `git diff --check`.

Roteiros temporários e logs ficam em `.codex/792/part11-*`, incluindo o diagnóstico explícito das permissões e o ensaio de duas conexões. As provas compartilháveis, hashes e capturas finais ficam em `docs/relationships/screenshots/792-part11/`; não publicar credenciais, fixtures completas, prompt da revisão nem logs com dados não necessários.

**Ponto de parada:** correções pequenas encerradas para aprovação, revisão integrada ainda aberta. Solicitar aceite de Rodrigo antes do próximo incremento de autorização de cadastros. Não pedir merge enquanto os bloqueios descritos não forem tratados; nenhum deploy executado.
