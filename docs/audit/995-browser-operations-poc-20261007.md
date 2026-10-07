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

Comprovados: leitura Roles, diálogo/papel Instagram tester e transporte de busca HTTP 200 no Chrome. Busca do alvo autorizada comprovada na Hub2You. Pendentes: alvo Autonom.ia, integração, contrato de convite/OAuth e reconexão completa; status de role Hub2You comprovado como ausente. Não encerrar #995 nem declarar conexão funcional.

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

## Sexta observação — 19:28 UTC, seleção do papel

Observer `4bb37a1d5e4653d5a06575bb99cecdfe1e972d2c14a610debc41aa1a561fe99f`, runner `99bf6c878229090731d8d77f8a5510a31244c3d3b8b38015d195b528bed7dd36`, unit `instagram-autonomia-browser-role-20261007-192722`. Revisão exigiu seletor por quatro nomes completos fechados e confirmação de checked após estabilidade; aplicado antes da execução. Nexo confirmou SHA final e guards.

Rádio Instagramtester exato/único/visível/habilitado selecionado, estado marcado persistente após estabilidade. Apareceu um input texto com rolecombobox dentro do diálogo, agora9controles. Sem Next/Continue nem busca de perfil. Cleanup/manager/7units/limites preservados, sem convite/publicação. Próximo candidato preenche somente o usuário autorizado e observa a requisição natural/resultado, mantendo POSTs desconhecidos bloqueados e sem selecionar perfil/confirmar.

## Drift externo de runtime — 19:32 UTC

Reader independente confirmou as duas stacks AWS em `9960b3a518ac52a8696283579618864176d7a02b`, ambas com sessão/gestor saudáveis e restrições1/18 preservadas. Essa publicação veio de outro fluxo, não desta PR. Fetch e diff contra496 confirmaram nenhum delta nos scripts/serviços/controllers/composable/client/componentes de Instagram desta análise. Próximo preflight usa996; branch/PR de auditoria permanecem em sua base sem rebase/merge. VPS permanece2cc6.

## Sétima observação — 19:42 UTC, contrato natural POST observado

Observer `b391795939bd1a9bfaec82b6fb193c6ceea23fd69bffacc54b6eca92e393bc4f`, runner `a9a74dc8dd1d3be087808fb2b96aa1c2ad00c8526bbf41acb5890d00d8272aba`, unit `instagram-autonomia-browser-search-20261007-194132`. Candidato anterior109b foi rejeitado antes de executar: parser genérico/aliases podia associar IDs de outra entrada; corrigido para contrato exato do ResponseParserRuby e hash somente do alvo único. Runner exige uma requisição/uma resposta e não aceita unknowns.

Combobox único/visível/habilitado/editável preenchido uma vez e valor autorizado confirmado. Um POST natural para `/roles/instagram/typeahead/user/`, query somentevaluecomalvoautorizado,575bytes/16campos completos foi abortado pelo guard original. Zero resposta; aceite funcional recusado em validate_search, embora a observação da interação esteja completa. POST é o método real da UI: hipótese de que o Client usaria POST indevidamente fica refutada para esta operação. Isso não explica Rails400.

Cleanup/restauração/7units/limites preservados. Próxima medida exige exceção somente local de leitura para esse POST exato/único, canonicalapp/business/admin, corpo/fields/query estritos e fase/UI verificadas. Não alterar guard global, liberar GraphQL desconhecido nem permitir `/roles/add/`. Não houve seleção de sugestão ou convite.

## Oitava observação — 19:53 UTC, pin AAID recusado

Observer `943db4cfead2f1467eaf369672d75489f2fd0f17eeec7f27f742e71c392edc61`, runner `0db03fadf56fcb5927a55332edefb6385b45103a6b3f3a7ef4715d1875cc6de2`, unit `instagram-autonomia-browser-search-20261007-195221`. Exceção local/única foi revisada antes da execução; guard global intacto.

A requisição natural passou origem/path/queryvalue único/16campos/tokensnão-vazios/faseUI. `__bid`, `__user` e `__a` corresponderam; `__aaid` NÃO foi igual a config.appId. O POST continuou abortado e nenhuma resposta foi recebida. A igualdade AAID=aplicativo foi uma hipótese nossa, não contrato demonstrado; não relaxar silenciosamente. Próximo candidato deverá ancorar eventual contexto AAID na requisição Roles canônica cuja resposta200full foi validada, conservando appbinding por variável app_id e URL canonical, e abortar caso não haja igualdade comprovada. Essa prova/gate pode ser condicional no mesmo run, antes do únicoPOSTpermitido, sujeito à revisão.

Cleanup/restauração/7units/limites preservados; nenhum convite, seleção de sugestão ou publicação pelo diagnóstico.

## Nona observação — 20:04 UTC, busca respondeu 200 sem alvo exato

Observer `f40d4fbbbea36ad0a41a9ed6f870fccbdf7e4ab8a6589627f131461aa13f7a9e`, runner `9e8add2b0c4442fcf318bfd0da8568bf328e2dcbee05961a5c361dcc893ac78a`, unit `instagram-autonomia-browser-search-20261007-200244`. Revisão inicial encontrou lacuna de invalidação persistente do contexto, corrigida antes de executar. Root encontrou ainda AAID ausente sendo ignorado; corrigido, SHA final revisado por Nexo. Ausência, valor inválido, página não canônica ou conflito impedem reativação do contexto neste run.

Roles200 completo/canônico validou contexto fresco; AAID numérico do typeahead igual ao Roles, embora não igual a config.appId. Business/admin/a, query única autorizada, corpo exato, tokens e fase UI conferiram. Um POST natural foi permitido e uma resposta HTTP200 JSON completa de28717bytes recebida, com8entradas válidas pelo contrato atual e sem erros. Zero correspondência exata para o alvo autorizado; runner recusou aceite funcional em validate_search. Transporte de busca do Chrome comprovado, identificação do alvo ainda não. Não há evidência para selecionar outro resultado ou enviar convite.

Cleanup/lock/manager restaurados, sete units e limites preservados. Sem convite, seleção de sugestão ou publicação pelo diagnóstico. Próxima investigação somente leitura deve distinguir estrutura/semântica dos campos e ausência real do alvo, emitindo apenas schema/flags/contagens, sem dados de outras contas. Confirmação do @ atual solicitada ao Rodrigo, sem alterar o alvo durante a espera.

## Décima observação — 20:09 UTC, prefixo e schema conferidos

Observer `ef1ba2ac21e5507bfbc587d04067d27d6a5f3b54dfde18b81bea5b6aeb06259f`, runner `490954c922d07b411af79faf485a117403661547d9928831d3298bbdc99593a8`, unit `instagram-autonomia-browser-search-20261007-200815`. Ambos revisados antes da execução. Stack explícita e mapa fechado de alvo/socket; esse mapa não é prova independente de vínculo real da conta. O preflight verifica o backend/conta restrita e a sessão/configuração canônica.

Teste usou a forma `@username` já usada pelo Client Rails, com um preenchimento e um POST natural; prefixo confirmado no input e query. Resposta200 JSON completa de28725bytes,8entradas válidas. Schema contém somente uniqueID/text/subtitle/photo, semcampo username ou campo adicional. Comparações somente em memória emitiram zero match literal, por caixa, normalização ou prefixo em text e demais campos conhecidos. Não é um alias ou diferença de caixa demonstrada; o alvo autorizado não apareceu nesses resultados. Runner manteve a recusa funcional.

Cleanup/manager/7units/limites preservados, sem convite/publicação. Nome atual do alvo permanece aguardando confirmação; não trocar pelo resultado aproximado. O mesmo diagnóstico revisado será aplicado isoladamente à Hub2You, após preflight novo.

## Décima primeira observação — 20:11 UTC, busca Hub2You comprovada

Mesmo observer `ef1ba2ac21e5507bfbc587d04067d27d6a5f3b54dfde18b81bea5b6aeb06259f` e runner `490954c922d07b411af79faf485a117403661547d9928831d3298bbdc99593a8`, com `--stack hub2you` explícito e preflight novo. Unit `instagram-hub2you-browser-search-20261007-200954`; conclusão20:11:14UTC. Fonte permaneceu intacta durante o bloco sequencial aprovado por Nexo.

POST único autorizado recebeuHTTP200, JSON completo24373bytes,2entradas válidas e uma correspondênciaexataúnica do alvoemtext, comIDnumérico válido. Runneraprovou observation_completed. Não selecionar outra conta. Hash somente doID doalvo permanece no reciboprivado; auditoriapública registra apenascontagem1, semvalor.

Nexo confirmou que isso prova a busca no Chrome para aHub2You, não OAuth/token/convite/roleaplicado nemintegraçãoRuby. Cleanup/manager restaurados,7units/limitespreservados. Reader20:12:59 confirmouambosgestoressaúde e sessãorepublicadapósrestauração (não nova contagemderenovação natural). Próximocandidato somenteleitura destatus: manterIDapenasemmemória, fazeruma nova navegaçãoRoles, ignorar resposta inicial, validar novo request/response200full e espelhar apenas o parser puro de status. NenhumClientstatus/callbackRedis/reconcile/convite.

## Décima segunda observação — 20:21 UTC, status fresco Hub2You ausente

Observer `b59e449d3c54123ede6165224e2ada5a2ad6301d6a4682c790f4f67ea27b75b0`, runner `4fe76ce735c04152f31fc40a0cdfa8cddf8d9e77a1fce69a4350350a0d12f36a`, unit `instagram-hub2you-browser-status-20261007-201959`. Node/Python checks e revisão final antes da única execução. Prazo diagnóstico120s+cleanup25; unit155s, espera185s, SSH externo345s; CPU/RAM originais. A segunda navegação exige esse orçamento explícito. Um parecer inicial sobre usuários de grupos não-Instagram foi retificado após confronto com group_testersRuby: shape validado para todos os grupos; users validados só após filtro instagramtesters. Contrato não ampliado.

Busca provou o alvo único/ID numérico, mantido somente em memória. Depois uma nova navegação Roles canônica produziu exatamente um request/respostaHTTP200 completo; resposta inicial não contou. Parser puro replicou grupos/paginação/status e conflito do ResponseParserRuby, semClient/callbackRedis/Outcome.reconcile. Resultado fechado `absent`, semconflito: o alvo não aparece na lista atual de testers desse documento naquele instante. Não provarOAuth/token ou permissãodeconvite a partir disso.

Runner observation_completed, Nexo confirmourecibo. Cleanup/manager/7units/limites preservados; nenhumconvite/publicação. Hash doID continua só noreciboprivado, auditoria apenascontagem1. PróximoPOC13 será seleção exata no DOM/estado final semconfirmação; contrato de confirmação bloqueada ficará paraPOC14 apósconhecer ocontrole real.

## Décima terceira observação — 20:37 UTC, seleção recusada antes do clique

Observer `d4fd61234e81fe6ef31c809c8fde2d2dce729fe162dd6909eed364b8acca4f86`, runner `c41bb04f025b6517156c346c1b94955f23834277677322657d07f85cd49c488e`, unit `instagram-hub2you-browser-selection-20261007-203613`. Nexo aprovou uma execução após corrigir falso positivo que associava qualquer chip selecionado ao alvo. Preflight AWS falhou temporariamente no acesso ao serviço de administração; nenhuma execução ocorreu durante essa falha. Reader às20:35:55UTC voltou a confirmar ambas as sessões saudáveis e runtime996, sem mudança de produção feita aqui.

Busca natural voltou a trazer o alvo exato e único. A inspeção completa dos cinco controles do resultado encontrou zero controle com nome acessível exatamente igual ao username autorizado. A seleção falhou antes de qualquer clique de resultado; existência do botão Add não autoriza clicar. É uma diferença ainda não explicada da estrutura da interface, não falha de transporte da busca nem prova de que outro item seja o alvo.

Navegador encerrado, launch settled, lock liberado e manager restaurado. Outros sete serviços, limites e drop-ins preservados. Nenhum convite, confirmação ou publicação pelo diagnóstico. Próximo passo: observar apenas propriedades e correspondências booleanas da estrutura do resultado autorizado, sem textos livres nem clique.

## Implementação local em revisão — sem release

Fundação local em fila própria separa search/status/authorization da reconexão humana. Novo gate desligado por padrão; claims, correlação e resultados privados possuem expiração. A autorização final exige observação nova accepted e mantém validações do callback OAuth. O convite está bloqueado antes do enqueue até a prova do contrato de escrita. Controller/client adaptados para resposta assíncrona e cancelamento pelo painel; manager/predicate ainda em revisão independente. Nenhum desses arquivos funcionais foi committed, merged, deployed ou instalado.

`node --check` passou em client/protocol/manager; Atlas conferiu syntax Ruby nos três arquivos sob sua responsabilidade e `git diff --check` passou. Testes funcionais ainda não executados: planner MacCluster recusou nós por cwd-missing/node-modules-missing, sem forçar execução nem sobrescrever checkout. Preparar snapshot isolado após estabilizar os arquivos.

## Décima quarta observação — 20:48 UTC, estrutura dentro do diálogo

Observer `80ead48e0339cb173a81cb662d092fa9c10376a1c2f65f664cb475425658f5da`, runner `c264144c1780c21bef2405bd6ac6085bd0cb55a820888a41d573530530759209`, unit `instagram-hub2you-browser-result-shape-20261007-204623`. Revisão independente autorizou uma execução Hub2You somente de leitura; preflight às20:46:10UTC confirmou ambas as sessões/gestores saudáveis em996.

Busca natural e alvo JSON exato/único/ID válido novamente comprovados. A inspeção completa dos controles semânticos dentro do diálogo retornou zero correspondência por token, text, username ou name do alvo. `json_id_bound=false`. Isso não prova ausência em outro escopo da página nem valida um seletor clicável; portal externo ao diálogo ou controle sem papel semântico são hipóteses, não causas confirmadas.

Nenhum resultado selecionado, confirmação, convite ou publicação. Cleanup/lock/manager restaurados, sete units e limites preservados. Próxima observação precisa distinguir escopo do popup/combobox e estrutura semântica, mantendo saída sanitizada e nenhum clique de resultado.

Validação local posterior: 19 testes existentes de client/composable passaram em snapshot MacCluster isolado no M4, preservando o checkout ativo. Cobrem os contratos anteriores e regressão da UI; a nova resposta202 não foi exercitada por esses exemplos. ESLint passou nos três arquivos JS alterados pelo root. Wrapper de transporte aceitou9envelopes canônicos e recusou13formas inválidas em harness offline; nenhum comando Docker/SSH foi executado por esse harness. `pnpm guia:build` passou, sem delta nos arquivos gerados; formato das ações e testes completos do manager ainda pendentes.


## Décima quinta observação — 21:05 UTC, resultado fora do diálogo

Observer `11ac44934ce2b59be5ff7b3a7754d608038f9e65129ba6f322522f4689e5be25`, runner `3ae94973f96aa6fb465e1374f00adba5a6c10f25315733b0bfca0038eab9ec1c`, unit `instagram-hub2you-browser-result-scope-20261007-210317`. Revisão independente autorizou uma única observação Hub2You somente leitura. Runner recusou o aceite global em validate_result_scope:155 controles inspecionados sem truncagem, mas o snapshot de80 itens ficou truncado. Não aumentar limites para declarar sucesso.

A inspeção separada dos253text nodes não truncou e encontrou um token do alvo fora do diálogo, sob ancestrais option/listbox. Há um listbox visível e um combobox ligado a ele por aria-controls. Isso é evidência parcial de escopo externo ao diálogo; não comprova texto acessível exato, vínculo completo da opção ou seletor clicável. Não se comprovou loading. Próxima leitura fica restrita ao popup ligado ao input preenchido, com identificação em memória e saída sanitizada.

Navegador encerrado, launch settled, lock liberado, manager restaurado; sete units e limites preservados. Nenhuma seleção de resultado, confirmação, convite ou publicação pelo diagnóstico.

Validação isolada em snapshot chat2you:229 testes Node do runtime passaram,136 exemplos Ruby de controllers/requests/helpers/publisher/OAuth (incluindo Enterprise) passaram e19 testes UI legados passaram. Esses testes não exercitam o novo protocolo202/CAS/ACL; não são aceite funcional. Guia build/check passou. Gerador de formatos executado somente com ENV test/serviços locais55432/56379, gerou três arquivos com delta limitado a Instagram; formatos:check passou no snapshot seguinte. A tentativa inicial de discovery Python carregou zero testes por nomes com hífen: não contar como teste aprovado; execução explícita dos arquivos está em andamento. RuboCop encontrou53ofensas nos três arquivos de fundação; correção pendente antes de publicar código.


## Décima sexta observação — 21:13 UTC, predicado de diálogo recusado

Observer `77a4d24144ccf51e4ed51a19887b84a0b6fbcbb61dd5ff0eda85f9ed309cbcd7`, runner `ee1cd658caecf3d4f72cf17f8ffb156795fe933ddfa28aa89cf0472573e5d5de`, unit `instagram-hub2you-browser-result-popup-20261007-211109`. Após revisão e preflight21:11UTC, busca/alvo novamente validados, mas a inspeção restrita devolveu defaults. A interpretação inicial de predicado de diálogo sem correspondência foi invalidada pela descoberta posterior de ReferenceError no sanitizador local da POC17 e pela constatação de que o catch mascara falhas de leitura como contagens zero; não há evidência válida de contagem de diálogo nessa saída. Antes do preenchimento o diálogo/input já tinham sido validados. Não confundir esse predicado incompleto com sessão expirada ou ausência do resultado. Próximo candidato deve ancorar a leitura na referência do input já preenchido, com identidade/conexão/valor e vínculo de popup revalidados.

Nenhum clique em resultado, confirmação, convite ou publicação. Cleanup e restauração do manager, sete serviços restantes e limites novamente comprovados. O campo bound_to_response_entry do candidato significa coincidência de textos com entradaJSON deIDválido; não prova ID literal noDOM nem opção visível/habilitada. Não elevá-lo a aceite funcional.

Revisão do protocolo local:erro desconhecido no polling deve virar meta_unavailable; códigos conhecidos permanecem fechados. Prazo agora limita intervalo, impedeGETpós-expiração e configura timeout no Axios. Nove cenários offline passaram; nenhum provider/produção acessado. ESLint focal passou. Atlas corrigiu estilo Ruby e registrou RuboCop0ofensas nos três arquivos de fundação, sem alterarCAS/ACL/deadline.

Os dois workflows precisavam permitir a chave nova e verify-pair precisava aceitá-la opcionalmente só no manager; correções locais aplicadas, preservando ausência=false. Nenhuma alteraçãoENV/SSM/instalação emprodução. Python59examples inicialmente mostrou2erros reais de parser do novo flag e5erros deancestral/temporário noMac; parser corrigido e TMPDIRprivado parafixtures aplicável. O loader seguinte noM2 carregou79testes, com1limitação depermissões por workspace em/Users/Shared e16falhas desetup(tmp ausente), não aceites. RuboCop root noM2 nãoexecutou porcss_parser3.2.0 ausente; não instalar runtime para mascarar isso. Proteção térmicaM4 respeitada; snapshot foi replicado/verificado noM2 porchecksum, sem sobrescrevercheckoutativo. Dependênciasgeradas antigas desnapshots próprios foram removidas; fontes/manifestos/recibos preservados.


## Décima sétima observação — 21:21 UTC, erro local de sanitização identificado

Observer `bca6febad7a4eec7f0854e0d2dab87f7b2a9db4844510705d7160d5c1db31166`, runner `02c5bb19d2bfd1285b1bb84a0f895a15d56051b3c4b3e7dae565164696cc04da`, unit `instagram-hub2you-browser-result-popup-handle-20261007-211946`. Busca voltou a validar alvo exato/único. Leitura pela referência original do input devolveu todos os defaults, incluindo validade do ID independente do DOM. Isso levou à inspeção offline do diagnóstico: o sanitizador declara `optionMatches` mas retorna a variável inexistente `option_matches`, lançando ReferenceError escondido pelo catch. A falha local comprovada é da POC17. Os defaults das POCs16/17 não provam ausência do resultado, diálogo ou input sem demonstrar leitura completa. Correção e harness offline antecedem qualquer nova execução.

Nenhum clique em resultado, confirmação, convite ou publicação. Navegador fechado, lançamento concluído, lock liberado, manager restaurado, sete serviços restantes e limites preservados.

Validação posterior: client novo passou dez cenários offline com código real, incluindo rejeição de erro desconhecido; códigos aceitos são a lista fechada de14 valores Ruby. Python explicitamente carregou63 testes:62 passaram e1 ficou skipped por ancestral `/Users/Shared` gravável, que o validador de produção corretamente recusa; Linux CI permanece necessário. Os16 exemplos de coordenação da tentativa anterior falharam no setup e não foram declarados aprovados. Atlas registrou RuboCop1.75.6 por CLI Ruby3.4.4 direto fora do Bundler, três arquivos/zero ofensas; execução equivalente no Bundler M2 segue impedida por css_parser ausente. Nenhum runtime instalado para contornar a limitação.

Validação adicional offline:13 cenários do harness Atlas passaram carregando serviços reais com Redis/modelos em memória. Cobriu enqueue/claim/complete/CAS, reclaim vencido, recusa de claim tardio, isolamento account/actor e permissão revogada no claim/completion. Isso valida lógica sequencial, não concorrência Redis real, transações Rails, controller202/poll ou transporte publisher. Nenhuma spec nova ou fonte Ruby alterada por esse harness.

Check de Redis real:18 cenarios passaram com Redis local56379, Ruby3.4.4 e gemRedis5.0.6, namespace exclusivo de harness e zero chaves residuais (sem FLUSH). Exercitou TTL, reclaim, resultado tardio e conflito WATCH/MULTI real, preservando resultado novo/queued, account/actor e ACL revogada. A implementacao usa WATCH/MULTI, nao Lua. O planner recusou por cwd M2 ausente/termica M4; o harness curto foi executado diretamente pelo agente, nao por MacCluster work run/wrapper RSpec. Nenhuma dependencia/servico instalado; nao elevar a prova de controller, transacao Rails ou CI. Execucoes futuras respeitarao a recusa do scheduler.

Preflight21:29:27UTC:Hub2You em8ec672cf0a89b017726e3f9334554c23a86bb41d e Autonom.ia em9960b3a518ac52a8696283579618864176d7a02b. Compare GitHub996->8ec:emailAI/CIapt, nenhum codigo runtime/controller/service/clientInstagram; unico workflow deInstagram alterou apt somente noCI. Sessoes saudaveis/contasrestritas, VPS2cc preservada. Publicacao externa, nao pertence aPR1129. POC18 usa expectedruntime8ec e fonte/runner revisados; nenhum rebase/merge/deploy desta branch.


## Decima oitava observacao - 21:31 UTC, popup lido e opcao exata provada

Observer `1c3ecbf9579b0400a65e9c1373dc554090cca8890c58cdeaba7a3298ab7d9166`, runner `95d8a5f356aceeb6d681dd49a2b6a44e58a5de6dc43cd06cd09c2e55a0da6a82`, unit `instagram-hub2you-browser-result-popup-fixed-20261007-212959`. Revisao independente e novo preflight precederam unica execucao. Runner observation_completed. Corrigir sanitizador eliminou falha do diagnostico. Harness `.codex/verify-result-popup-sanitizer.mjs` reproduziu ReferenceError antigo e validou retorno corrigido offline.

Input original conectado/visivel/habilitado/valor confirmado, aria-controls unico/listbox unico, popup estavel e dois options completos. Uma opcao div/roleoption tem username/text exatos do autorizado, visivel/habilitada; a outra nao corresponde. Nome secundario subtitle teve zero correspondencias, portanto predicado anterior que exigia fullname alem de username nao foi provado pelo UI real. IDJSON validado/entrada unica nao equivale a ID literal noDOM. Proximo candidato separado conserva fullname como observacao e usa identidade username/text exatos unicos + entradaJSON unica IDvalid, sem resultado aproximado.

Nenhuma selecao de resultado, confirmacao, convite ou publicacao. Navegador encerrado, launch settled, lock liberado, manager restaurado, outros sete servicos e limites preservados. A prova ainda nao e OAuth, tester aplicado ou conexao pelo painel.


## Decima nona observacao - 21:39 UTC, selecao provada e estado posterior recusado

Observer `c6771755c2edb479b9b97db8894836bb55e9cbd95d4d7361ffee35862ae32b64`, runner `8d73ae5f2dd460c90db56cfa7a2ee0331ddaf2a439afe701e985fd5b9c945999`, unit `instagram-hub2you-browser-invite-contract-dry-20261007-213750`. Revisao independente de ambos hashes e preflight fresco precederam unica execucao. Dois candidatos anteriores foram recusados localmente por ainda exigir fullname no popup/estado; nao foram executados.

Popup novamente completo, identidade username/text exatos unica, IDJSONvalido e opcao visivel/habilitada. Selecao nativa ocorreu, mas o estado posterior foi recusado:seis controles completos contem um div/rolebutton com tokenusername e um Add unico habilitado. SourcesFor do leitor antigo nao examinava leaftext viaTreeWalker, e o chip exigia aria-selected nao observado. Nao confundir recusa desse predicado com falha de selecao ou ausencia de conta. Proximo candidato usa predicado de leaftext exato ja provado e compara estado fresco antes/depois da selecao para identificar registro unico do autorizado; nao chama registro aria-selected sem prova.

Nao houve clique Add, request de convite, confirmacao, convite real ou publicacao. Chrome encerrado, launch settled, lock liberado, manager restaurado, sete units e limites preservados. Contrato de escrita permanece nao comprovado e invite fechado antesenqueue no produto.


## Vigesima observacao - 21:46 UTC, recibo vazio e recuperacao independente

Observer `89aab5b3898cd35efcd425c2927a104990c72c473960bb26212472b24738290e`, runner `4c06ecab230ce5693785a2a17b2e13ace7b7bd9637577a6cddce2f0b1d82f7a5`, unit `instagram-hub2you-browser-invite-state-contract-dry-20261007-214525`. Revisao e preflight precederam uma execucao. Node terminou exit1/stdout vazio; runner registrou JSONDecodeError e nao restaurou automaticamente o gestor porque exigia recibo de cleanup. Nao existe resultado sanitizado da UI nessa tentativa; os falsos/defaults do envelope externo nao provam ausencia de busca, clique ou estado Meta. O candidato revisado bloqueava escritas; nao ha contrato de convite comprovado.

Root retomou somente o gestor Hub2You as21:47:18UTC apos prova independente: unit terminalfailed/MainPID0/KillModecontrol-group, nenhum Chrome do usuario, ownlock/marker ausentes e SingletonLock sem PID vivo. Nenhum lock vivo foi apagado. Gestor voltou active/running com CPU150%, MemoryHigh1536M, MemoryMax2G e Tasks256. Outros sete servicos e limites foram preservados no recibo original; recuperacao ficou em recibo privado separado.

Causa local reproduzida offline: declaracao inviteStateContractTransitionIdentityRole divergia das referencias inviteStateContractTransitionIdentityButtonRole, que lancavam ReferenceError inclusive no emissor final. Fonte original preservada. Correcao de uma linha SHA `c794b046a44a2b14835183e65d243e78e9c91ac445108e5873306e93e6a25208`. Harness executa emissor completo com bootstrap stubado, JSON valido mesmo em falha. Deno no-undef com somente globais Node/browser explicitos reproduziu duas referencias indefinidas na fonte antiga e zero na corrigida. Checks de sintaxe nao eram suficientes. Runner seguinte exige encerramento/cgroup vazio/perfil exclusivo independentemente de JSON para recuperar gestor, mantendo a falha diagnostica e sem elevar recuperacao a sucesso funcional.


## Vigesima primeira observacao - 21:53 UTC, emissor recuperado e predicado posterior ainda recusado

Observer `c794b046a44a2b14835183e65d243e78e9c91ac445108e5873306e93e6a25208`, runner `b436dc0429b49032379857f399dd386eb295a49dad9250246e1c79df0c387c04`, unit `instagram-hub2you-browser-invite-state-contract-dry-20261007-215216`. Checks de fonte/no-undef/emissor/embeddedPython, revisao independente e preflight21:52:12UTC precederam uma unica execucao. Recibo voltou completo, confirmando correcao local do emissor; nao houve crash local.

Popup/entradaJSON/identidade da opcao exatos e unicos validados e selecao nativa comprovada. Baseline e estado posterior foram lidos sem truncagem, mas igualdade leaftext+username continua zero aposselecionar. Snapshot posterior de6controles tem um div/rolebutton com token lexical inteiro do username autorizado, visivel/habilitado. Nao se comprovou que seu texto seja apenas o username nem que a palavra Remove exista; isso nao foi emitido pelo sanitizador. O predicado antigo recusou antes do Add. Nova investigacao local confronta igualdade do campo isolado com token lexical inteiro/correlacao antes-depois, sem aceitar substring ou alvo aproximado.

Nenhum clique Add, confirmacao ou request de convite. Navegador encerrado, launch settled, lock liberado e gestor restaurado automaticamente por prova independente terminal/cgroup/perfil exclusivo. Outros sete servicos e recursos originais preservados. Invitation continua recusada antes do enqueue na implementacao local.


Verificacao de isolamento21:57:07UTC: leitura viaRedis::Alfred deINFOserver.run_id, emitindo somenteSHA256, comprovou servidoresRedis fisicos distintos nas duasAWS. Ambos runtimes8ec e allowlists exatamente conta1/18; sessoes/gestores saudaveis. Os fingerprints e endpoints nao foram publicados. A fila global e segura nesse escopo de backends fisicamente separados/uma conta autorizada; compartilharRedis entre stacks exigira afinidade antes de ativar. Essa precondicao deve ser reconfirmada no release, nao inferida somente dos nomes AWS. Nenhum filtro/esquema novo foi adicionado para um compartilhamento nao observado.


Preparacao local do candidato seguinte: textos normalizados de120caracteres/64fontes possuem flag de truncagem nos tres leitores; qualquer limite excedido impede captura e selecao. Root corrigiu ainda o if anterior ao clique nativo para exigir !sourceTruncated, apos revisao independente apontar que a recusa externa ocorria tarde demais. Nenhuma fonte draft recusada foi executada. Fixtures14cenarios e emissor completo/no-undef45estados passaram offline; verificacao do callback real antes do clique em andamento. Harness da funcao real de recuperacao do runner passou10cenarios (processo/grupo/perfil vivo recusam); zeroSSH/mutacao de servico pelo harness. Isso nao acrescenta uma observacao remota nem comprova convite.


## Vigesima segunda observacao - 22:08 UTC, contrato UI de convite capturado e abortado

Observer `d1da003c641d5ad0adfc32969d8e202b93deecfdcbb189fd3a9441d8cd1d4955`, runner `2ad0f8fd3d386ace94f72419349d2182af30f589c48054893c3aecdb0d34a245`, unit `instagram-hub2you-browser-invite-token-contract-dry-20261007-220720`. Revisao independente,14fixtures adversariais, emissor real/no-undef45estados, harness real do callback de clique e preflight22:07:16UTC antecederam uma unica execucao. Harness real provou clique normal1 e clique0 se qualquer opcao tiver fonte acima120caracteres/64fontes. Drafts recusados nao foram executados.

Runner observation_completed. Popup exato/unico e opcao vinculada ao mesmoJSONvalidID, clique nativo uma vez. Baseline fresco noDialog0token/0button; depois exatamente1controlebutton com token lexical inteiro do username, visivel/habilitado/novo, sem truncagem. Texto isolado leafidentity permanece0 e e apenas observacao. RadioInstagramtester marcado; Addunico visivel/habilitado. Nao inferir formato literal do rotulo a partir dos booleans.

O clique Add protegido produziu exatamente1POST na origemdevelopers.facebook.com e path /apps/<app_id>/async/instagram/roles/add/. Corpo664bytes,19campos completos e sem duplicatas:16campos do typeahead maisrole,user_id_or_vanitys[0],reload_on_success. Aplicativo no path, business/admin/AAIDfreshRoles e IDdoalvo correspondem aos pins; role igualinstagramtesters e reloadfalse. Uma escrita observada/abortada, zero falhas de abort, sem truncagem. confirmation_performed=true significa tentativa de clique com rede abortada; NAO significa convite aplicado. Nao ha resposta de sucesso do provider nem tester aplicado, OAuth, inbox ou reconexao provados.

Chrome encerrado, launch settled, lock liberado, gestor restaurado automaticamente apos terminal/cgroup/perfil exclusivo, sete units e limites preservados. Essa prova permite implementar localmente o contrato no executor; convite real continua proibido ate revisao/release/aprovacao. Permit duravel de uso unico reutilizara claimUUID internamente e OutcomeNX/WAITAOF; nunca substituir clique autenticado do usuario ou autorizacao de release. Nenhuma nova key/grant planejada.


## Implementação local após POC22 — revisão e validação

O convite foi implementado somente após o contrato observado: 19 campos, alvo exato, uma escrita, permissão fresca no backend e claim de uso único com o token interno da operação. A flag nova continua ausente/false em produção; nenhum merge, deploy, instalação permanente ou convite real desta implementação.

Revisão independente encontrou e corrigiu duas falhas de proteção: no-op pending não pode apagar marcador a partir de status sintético; `unwatch` retorna `OK`, portanto divergência de geração precisa retornar falso explicitamente. Erro genérico, captura inválida ou ACL revogada preservam unknown; liberação ocorre apenas em erro pré-write validado ou resposta estrita HTTP200/payload.success=false. Accepted observado fresco pode reconciliar. O polling autorizado não depende de sessão/proxy disponíveis para ler o resultado terminal.

Revisão adicional exige âncoras Roles/typeahead intactas antes do Add, antes do permit e antes de continuar o POST. Atualização extra da Meta invalida a operação. Harness privado carrega o módulo real e cobre 34 cenários de formulário/permit/resposta/fronteira de escrita; todos passaram sem rede/provider. Dois casos revalidam âncora inválida antes/depois do permit. A primeira fixture não fornecia rolesResult.ok e falhou corretamente; só a execução corrigida conta como aprovada. Harness Ruby privado carrega as classes reais com Redis/modelos sintéticos:23 verificações passaram, incluindo9 casos novos de marcador/CAS/ACL; não é Redis real nem Rails completo.

Snapshot com checksum foi replicado aos dois Macs; testes pesados usam M2 pelo scheduler, com M4 excluído por espaço/temperatura. Primeira execução Node com8arquivos falhou em entrypoints por dependências runtime ausentes; preparar dependências locked no snapshot antes de repetir. ESLint completo encontrou7 erros no executor, incluindo maxControls inexistente no callback DOM; correção e novo check necessários. RSpec do snapshot não iniciou por css_parser3.2.0 ausente; não declarar aprovado. Preparação dessa dependência no runtime de testes M2, sem reinstalar Ruby ou alterar produção, foi planejada explicitamente no nó M2.

Plano novo: `docs/audit/995-browser-operations-release-plan-20261007.md`. A aprovação final permanece pendente após revisão/checks do head concreto. Redis Alfred distinto e allowlists exatas são pré-requisitos a reconfirmar; metadata fica congelada na janela de ativação. Não ampliar para compartilhamento de fila entre instalações.


Rodada final isolada:240/240 testes Node passaram no snapshot192310;144 exemplos Ruby passaram sem falhas no snapshot192010, usando o wrapper que limpa ENV e fixa PostgreSQL55432/Redis56379. Os nove arquivos Ruby validam regressão dos caminhos existentes; não substituem integração202/poll/provider. Dependência css_parser3.2.0 e sua dependência ssrf_filter1.6.0 foram preparadas somente no runtime de teste M2. ESLint completo dos quatro arquivos JS/Node alterados passou sem erros/avisos após correção do maxControls e sombreamentos. Callback DOM real validou baseline0/token1 e recusa acima de500controles; nenhum provider acessado. O scheduler recusou um check adicional por M2thermalunknown/M4disco; não forçar nó. RuboCop CLI parcial anterior não equivale a check Bundler completo pendente.


Validação final adicional:4 CAS passaram contra Redis de teste real56379 no M2, namespace UUID exclusivo limpo sem FLUSH:pending da mesma geração; geração diferente retornafalse mesmo com UNWATCH=OK;release antigo preserva nova geração;reconcile concorrente preserva geração instalada após snapshot. Não exercitou WAITAOF/Redis de produção. RuboCop via Bundler inspecionou8arquivos alterados sem ofensas no runtime Ruby3.4.4 explícito do M2. A tentativa de initrbenv no ambiente limpo do worker retornou comando não encontrado; o binário Ruby/Bundler e GEM_HOME/GEM_PATH foram fixados nos test tools, não houve downgrade/reinstalação de runtime. Não elevar isso a validação do ambiente local M4.


Guia:check final passou no M2:199fluxos,190telas,0sem explicação. Warnings de Browserslist/logger não alteraram o resultado; nenhuma biblioteca atualizada para escondê-los. Main avançou externamente para caca5eae44705d6d9449d00b005fae67b2da454c; diff desde8ec é email/identidade visual, sem sobreposição nos arquivos funcionais Instagram. Não rebasear/mergear automaticamente; revalidar main/CI na fila após aprovação.


Preflight de leitura22:27:51UTC:ambas AWS já executam caca5eae44705d6d9449d00b005fae67b2da454c por publicação externa. Sessoes disponíveis, managershealthy, ponteirosactive e restrição exata1/18 confirmados; nenhuma solicitação humana em andamento. Capturas recentes verificadas, sem atribuir essa renovação/publicação a esta PR.


Leitura22:28:26UTC, observerb51cc6009d465f9dc220761585a38846e5797d6ee1bd197f08ac6925dbbffb78:flag nova explicitamenteunset nas duas AWS, portanto defaultfalse. Inspeção só emitiu unset/true/false/invalid; nenhum valor de secret. Mesmos runtimescaca/sessoes/allowlists saudáveis, sem mutação.


Revisão final independenteNexo:verde condicional para commit/CI/revisão da PR, sem novo bloqueio funcional ou de segurança. Todos os achados anteriores fechados nos hashes registrados. Duas correções documentais aplicadas:Chrome faz busca/status/convite;backend prepara URL OAuth depois do accepted. Alvo do teste é autorizado, mas a ativação do piloto ainda depende da aprovação final. Parecer não autoriza merge/deploy/instalação nem declara aceite de provider. Maincaca revalidada; CI deve executar no head final antes da liberação.
