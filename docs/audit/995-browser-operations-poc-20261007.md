# Instagram assistido — prova de operações no Chrome da VPS

## Escopo autorizado

Rodrigo autorizou em 07/10/2026 continuar o plano discutido: validar operações administrativas dentro do Chrome existente antes de integrar a plataforma. A primeira observação é somente leitura, sem convite, nova publicação de sessão, alteração de proxy, instalação de runtime ou deploy AWS. Perfil, sandbox, identidades e locks permanecem protegidos. A aprovação do plano não declara sucesso nem dispensa revisão da release.

Issue #995; branch `codex/995-browser-operations-20261007`, base `496258e375939e9c531e38a39128ea096397f676`. Continuidade documental anterior na PR #1124, commit `4f0907a186d926776fcf909d7cf52ecb5b88261a`: navegador Roles 200, Client Rails 400, causa específica ainda desconhecida. A PR #1112 já foi merged/instalada; não reinstalar as correções anteriores.

## Estado revalidado antes da observação

- 18:44 UTC: acesso SSH normal à VPS confirmado; release selecionada `2cc6b4fb6e275e26c04ae126c06ac1b4f0b63b26`. Oito units Instagram ativas/running, sem restarts automáticos registrados.
- Memória disponível aproximadamente 18 GiB; carga do host aproximadamente 7. Os limites dos managers continuam CPU 150%, MemoryHigh 1536 MiB, MemoryMax 2 GiB e TasksMax 256. Nenhum aumento proposto; n8n não foi alterado.
- 18:45 e 18:48 UTC: AWS das duas stacks executa `496258e375939e9c531e38a39128ea096397f676`, com sessão administrativa presente, ponteiro ativo e gestor saudável; contas restritas 1/18 preservadas. Isso é saúde/publicação, não comprovação de busca, OAuth ou caixa conectada.
- Diff da base vigente contra `383ed42f82659a2891ca59e506e9ea86e8002e1d`: nenhum delta nos scripts Instagram e serviços Instagram da aplicação.

## Responsabilidades e critérios

Íris revisa o contrato/controle de busca; Atlas revisa comunicação e concorrência; Nexo faz revisão independente. Root é o único executor de produção. O candidato local é diagnóstico, não release.

Primeira etapa: abrir somente a página Roles, exigir resposta 200 validada pelo observer existente e ler estrutura limitada do DOM. Nenhum clique/preenchimento. Saída somente com enums públicos de interface, contagens, flags e status/tamanhos; sem textos livres, IDs, HTML, valores de campo, cookies, headers ou respostas. Encontrar um controle não equivale a executar busca.

O runner pausa/drena somente manager Autonomia, exige exclusividade do perfil, lança uma unit temporária com limites e proteções equivalentes e só restaura o manager após encerramento/lock comprovados. Os sete outros serviços e os limites são comparados antes/depois. Fonte fixada por SHA-256, prazo global e recibo próprio.

Revisão inicial encontrou mismatch entre campos do candidato e do runner; corrigir e revisar o SHA final antes de executar. Nenhum diagnóstico executado até este checkpoint.

## Integração condicionada à prova

O Chrome headless já renova sessões na VPS. O canal publisher é iniciado pela VPS e não executa pedidos administrativos enviados pelo painel; não reutilizar a fila de reconexão humana como fila de operações. Implementação futura exige contrato separado para search/status/invite, entradas fixas, correlação/deadline, claim único e resultado sanitizado. Não transportar cookies para Rails nem expor URLs/JavaScript arbitrários.

Para busca/status, comprovar primeiro a ação natural e seu contrato; convite depende de seleção explícita e reconciliação de resultado incerto. OAuth/reautorização da caixa permanece no fluxo existente e é distinto da sessão administrativa. Release deve seguir PR, Project, revisão, aprovação, fila/MERGED e deploy/instalação com rollback separado por stack.

## Resultado

Pendente: observação estrutural revisada, busca real autorizada, integração, convite/OAuth e reconexão completa. Não encerrar #995 nem declarar conexão funcional.

## Primeira observação executada — 18:54 UTC

Unit temporária `instagram-autonomia-browser-search-20261007-185335`; fonte SHA-256 `c4d147a6659dbf2d10e320591b2570db3e02c8bceee2178ed1f6b99b99d94d8b`; runner SHA-256 `c5f45c1d43187e336a3dff907bf378401d232197ba5cb97d1a4e59e59690aaa6`. Antes de executar, a revisão independente exigiu alinhar predicado/recibo, conferir marcador humano em cada exclusividade e validar flags de não busca/convite/publicação do próprio observer; mudanças aplicadas e validadas localmente (`node --check`, AST Python).

O Chrome headless recebeu Roles HTTP 200 com JSON e papéis completos validados, 3232 bytes. Encerramento do navegador, settle do launch e liberação do lock comprovados. Manager restaurado ativo/running; sete units restantes inalteradas, limites e drop-ins preservados. Nenhuma busca, clique, convite ou publicação de sessão ocorreu nesse diagnóstico.

A amostra de DOM atingiu80 nós, dos quais52 com nome fora do dicionário. Os flags tester/search false não comprovam ausência: `[role]` inclui elementos de apresentação e a ordenação truncou a amostra. Nexo confirmou segurança/restauração e recusou elevar o recibo a aceite de busca. Próximo ajuste necessário: controles semânticos, cap de inspeção explícito e prioridade de labels públicos conhecidos, ainda sem interação.

Após restauração, leitura de backend às18:55:45 UTC confirmou manager Autonomia healthy e sessão publicada às18:55:13 UTC (captura18:54:48). Essa publicação pertence ao manager retomado, não ao diagnóstico; não é reconexão da caixa nem duas renovações naturais.

## Segunda observação executada — 18:58 UTC

Novo seletor semântico com cap de inspeção500 e snapshot80 foi revisado e aprovado antes da execução. SHA-256 `2baa02a96cf66a94a6ba052e3f96fec9b781c410306840462aee6f125074909f`; runner preservado `c5f45c1d43187e336a3dff907bf378401d232197ba5cb97d1a4e59e59690aaa6`. Unit `instagram-autonomia-browser-search-20261007-185749`, conclusão18:58:44 UTC.

Roles200 validado novamente;66 controles inspecionados, sem truncagem. Reconhecido um controle `Add people`. Não se comprovou ainda visibilidade/habilitação desse botão nem abertura de diálogo. Não houve clique, busca, convite ou publicação. Cleanup, restauração, sete units e limites preservados.

Nexo aprovou a interpretação estrutural. Próximo candidato abre somente o diálogo por um clique exato/único após exigir visibilidade/habilitação e Roles200; mutações permanecem bloqueadas pelo guard original. Não preencher/selecionar/confirmar nesse estágio.

## Terceira observação executada — 19:06 UTC

Candidato de clique único revisado e aprovado por Nexo antes da execução: observer SHA-256 `abf0d93af78d1ba3ef434a24ec4bc0b7eb8438311a4bd0681bd44f2e14be3608`, runner `ccf3f09de0f26dce264bb068ef98d7ecd345b8236e16ea90c8a5dfcfc7eddf93`. Unit `instagram-autonomia-browser-dialog-20261007-190506`, conclusão19:06:09 UTC.

Roles200 validado; botão Addpeople único/visível/habilitado clicado uma vez, diálogo visível único aberto. O diálogo mostrou2controles div/button sem rótulo reconhecido no dicionário; nenhum input/select/radio apareceu na amostra completa desses candidatos. Não se comprovou prontidão do formulário: pode haver carregamento, consulta bloqueada ou mensagem de outro caminho de gestão. Não clicar próxima ação sem distinguir essas hipóteses.

Nenhuma busca, seleção de perfil, confirmação, convite ou publicação. Cleanup, lock, manager, sete units e limites preservados. Nexo confirmou a interpretação limitada; próxima observação mantém o mesmo clique, acrescentando estabilidade/loading e classificação de mensagens/metadados bloqueados, sem ampliar a allowlist de rede.

## Quarta observação — 19:16 UTC, falha de diagnóstico

Unit `instagram-autonomia-browser-dialog-20261007-191456`, observer `09ee2d29aa40a901651828b93d1a426b84c408a7f9a640cb6438b0372278a91b`, runner `a58bba478233efdc21cd3d8c581271a642212080003fc12bc5d559f83f8c4221`. Roles200 validado, clique único e diálogo aberto. Captura/estabilidade incompletas: recibo `dialog_dom_incomplete`, validação recusada. Três consultas bloqueadas de779bytes; o cap20campos truncou metadados antes de nome/documento/variáveis. Nenhuma consulta nova permitida.

Cleanup comprovado, manager restaurado e sete outros serviços/limites preservados. Root identificou provável erro no próprio observer: Locator.evaluate aceita um único argumento serializado, mas readDialogState passou definitions e mentionPhrases separadamente. Íris corrige e Nexo revisa antes de repetir. Isso não prova falha da Meta nem falta de permissão; não houve busca, convite ou publicação pelo diagnóstico.

## Quinta observação — 19:21 UTC, captura corrigida

Correção single-argument evaluate e cap32 revisados antes da execução. Observer SHA `401c50574cecccf867890f24be97fac78b65e7487d3da49b1f2c0b0b0af4beb5`, runner `a58bba478233efdc21cd3d8c581271a642212080003fc12bc5d559f83f8c4221`, unit `instagram-autonomia-browser-dialog-20261007-192004`, conclusão19:21:12 UTC.

Roles200 full; diálogo capturado estável/completo,8controles incluindo5radios, Cancel e2botões sem nome reconhecido. Estado menciona Instagram e permissões; nenhum flagBusiness verdadeiro. Isso não basta para classificar o texto inteiro, mas refuta a conclusão prematura de que não haveria formulário nessa amostra. Os3POSTs bloqueados são exclusivamente `MetaDeveloperAssistantPageOverlayQuery`, já excluída no contrato de carregamento; todos os metadados completos. Não há evidência para liberar uma query nova aqui.

Nenhuma busca, seleção, convite ou publicação. Cleanup/restauração/7units/limites preservados. Próximo candidato identifica o rádio de Instagram tester e a navegação legítima ao formulário, sem confirmação de convite.
