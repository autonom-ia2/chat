# #995 — retomada confirmada e bloqueio de carregamento observado

## Estado comprovado em 07/10/2026

Rodrigo retomou os sete serviços antes ativos após instalar a #1089. Leitura às09:25:58UTC confirmou os mesmos PIDs enviados pelo operador, sete serviços active/NRestarts0 e manager Autonomia inactive/PID0. Ambos gateways responderam401 sem grant. Recibo: /opt/instagram-meta-staging/upgrade-1089-20261007/resume-observed.json. O runtime selecionado é9a48a2de08e93f2f7dc6916d7a4c79729f88dec4. A manutenção de instalação/retomada não está mais pendente.

## Diagnóstico finito, sem publicação

A primeira execução,09:19:51–09:20:19UTC, parou no bootstrap após aproximadamente25s; não chegou à navegação. A segunda, instagram-autonomia-observe-1089-092216, concluiu09:23:12UTC: Chrome aberto912ms, bootstrap canônico22.232ms, navegação para papéis23.185ms. Foram observadas três requisições naturais GeoNextAppControllerContainerQuery. Cada uma tinha exatamente uma variável appID correspondente ao app; __bid, __user e av correspondiam à configuração; doc_id diferia do documento RolesTable canônico. As três falharam. Nenhuma RolesTable_Query foi observada. O título de papéis não apareceu no DOM observado.

O diagnóstico preservou o route gate instalado, sandbox, identidade, proxy e lock exclusivo. Só bootstrap foi permitido ao publisher; publish/heartbeat foram recusados pelo wrapper. Nenhum novo login ou reconnect foi enviado. Abrir perfil persistente pode atualizar caches do próprio Chrome; o perfil não foi apagado ou substituído. Exit0 significa que o diagnóstico terminou, não homologação Meta.

O predicado isAllowedBrowserRequest só aceita POST GraphQL identificado por rolesQueryFields como RolesTable_Query. Isso demonstra incompatibilidade com a consulta inicial observada. Não comprova que liberar a consulta inicial produzirá a tabela de papéis, nem prova por seu nome que o documento seja somente leitura.

## Revisão e limites

Iris-carga5623 e Argos-contrato5624 concluíram revisões locais, exit0. Aprovaram separar carregamento e captura, sem aceitar fetch__Application.id como publicação. Exigem evidência do documento inicial e resposta real antes de ampliar o gate. Iris também apontou que o observer deve classificar a requisição antes de allHeaders/reservar publication para que respostas de carregamento não ocupem a captura de papéis.

Uma observação adicional tentou ler apenas metadados do módulo GraphQL compilado na página, mantendo os gates; terminou antes da navegação por outra falha de bootstrap. Sua nova tentativa recebeu Native routing blocked: enrollment outcome unavailable; no local replay., sem PID. Não foi repetida por outro canal. A leitura posterior09:31:14UTC confirmou nenhuma unidade diagnóstica ativa e lock ausente. Não há evidência de metadados compilados ou da resposta da consulta inicial nesta rodada.

## Continuidade

Não reaplicar1089 nem repetir login. Obter evidência autorizada do documento e da resposta inicial; somente então ajustar o contrato de carregamento separado, preservando validação integral de papéis, metadados canônicos e CAS. A latência de bootstrap também continua intermitente: não foi corrigida pelo restart. Os seis deltas reprovados no worktree995-operator-recovery ficaram intocados; esta worktree nasceu limpa de6242e31695fd1c6b8b088f2fcb819c027fc5083c. Nenhuma alteração funcional foi instalada nesta rodada. Assistido permanece sem liberação.

## Correção local da disputa pela captura

A revisão focal Iris-carga identificou um defeito independente da permissão de carregamento: uma resposta GET/HEAD para o endpoint GraphQL podia reservar publication enquanto allHeaders permanecia pendente. A resposta posterior da consulta válida de papéis era ignorada.
Foram adicionadas duas regressões determinísticas ao harness existente, que usa o filtro real e o publisher simulado. Com o código original, ambos os casos falharam: os cabeçalhos da resposta não elegível foram lidos e a captura válida ficou bloqueada.
A correção classifica sincronamente URL/método/campos de papéis antes de reservar publication ou ler os cabeçalhos. Reutiliza rolesQueryFields; não amplia isAllowedBrowserRequest, não aceita GeoNext como sessão e não modifica o publisher Rails, metadados, documento canônico ou CAS.
Depois da alteração, os 68 testes de manager/observer passaram. ESLint e diff check passaram. Os cenários são sintéticos e não comprovam captura ou publicação Meta.
Esta correção elimina a disputa entre respostas. Não resolve sozinha a consulta inicial bloqueada; a observação do documento compilado e sua natureza de leitura permanece pendente.

Validação final desta correção:290 testes Node aprovados, zero falhas/skips/cancelamentos; ESLint, sintaxe e diff check aprovados. Além dos dois cenários GET/HEAD inicialmente reproduzidos no código antigo, foram acrescentados POST não relacionado e POST com campos de papéis inválidos. O código do gate de navegação e do publisher continua sem alteração.
Nexo-revisao PID65637 aprovou o diff de classificação antecipada, sem bloqueador estático; os dois casos negativos POST foram acrescentados após o parecer, sem nova alteração do código funcional. Iris-carga40282, Atlas-latencia40283 e Argos-guard40284 também concluíram revisões focais locais, todos exit0. Esses pareceres não representam homologação de produção.
Uma consulta real somente de bootstrap, após a retomada, retornou configuração completa em19.002ms às09:38:49UTC, sem ponteiro de sessão; um resultado isolado não comprova estabilidade do transporte.
As novas tentativas de diagnóstico com navegador e de disponibilização de uma variante limitada aos metadados públicos foram recusadas pela ferramenta. Nenhuma delas forneceu um novo resultado operacional. Não houve publicação, novo pedido de reconexão nem reinício da VPS nesta etapa. A captura completa e a ativação continuam pendentes.
