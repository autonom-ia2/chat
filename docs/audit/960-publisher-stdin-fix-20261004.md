# #960 — correção local da entrada AWS CLI, 04/10/2026

Escopo: utilitário humano de parâmetros, sua suíte offline e runbook. Nenhuma publicação, SSH real, acesso ao Redis, merge ou deploy nesta correção.

## Evidência e correção

Rodrigo confirmou STS Hub2You e consulta SSM por flags. A entrada `--cli-input-json file:///dev/stdin` falhou com Invalid JSON. O teste skeleton de `--value file:///dev/stdin` passou; skeleton não prova publicação.
Atlas substituiu JSON stdin por argumentos explícitos em STS, Describe e Get. Put usa `--no-overwrite` e recebe somente Value cru por stdin. Nenhum valor é acrescentado a argv, arquivos ou ambiente.
TTY/consentimento, contas fixas, validação da origem, comparação completa antes das escritas e readback exato permanecem. O erro informa profile/serviço/operação conhecidos; antes de qualquer Put informa nenhuma publicação iniciada nesta execução.

## Validação e revisão

Coordenador: 28 testes mockados aprovados em ambiente externo sintético; 19 casos anteriores preservados. Argos repetiu 28 testes e aprovou o snapshot somente para repetir o check humano sem --apply.
Coordenador: AWS CLI 2.34.42 real contra servidor HTTP exclusivamente loopback, sem assinatura, configuração AWS ou credenciais. Três casos fictícios (texto simples, multiline e Unicode/escapes) preservaram Value e Overwrite=false. Não houve chamada à AWS externa.
Os mocks não simulam a corrida de criação concorrente; verificam --no-overwrite. Igualdade refere-se ao texto carregado: o leitor remoto preexistente normaliza CRLF.
Recibos em `tmp/ssm-cli-input-fix-20261004/`: parent-validation.json, parent-tests.log, aws-local-value-proof.json, review-snapshot.json e safety-final.md.

## Incidente de teste

Uma falha na primeira rodada de testes registrou o ambiente herdado, incluindo a variável GEMINI_API_KEY, no log local do subagente. Nenhum valor é reproduzido aqui. Todos os testes agora recebem ambiente sintético; o log da sessão e logs desta rodada foram restringidos a 0600. A chave não foi utilizada nem rotacionada nesta rodada; recomenda-se substituição pelo canal legítimo.

## Entrega local e próxima ação

Arquivos corrigidos no M4; sem commit/push nesta etapa. As duas alterações preexistentes do provisionador foram preservadas e conferidas por hash. Não presumir sincronismo da worktree com os commits remotos anteriores.
Rodrigo deve repetir pessoalmente o comando padrão do utilitário, sem --apply. Essa consulta não lê valores secretos nem escreve parâmetros. Publicação humana e homologação entre stacks continuam pendentes; esta correção não contorna o bloqueio da transferência automática.
