# #960 — bloqueio do bootstrap e correção do transporte/CLI

## Evidência operacional, sem reexecutar o publisher

A execução pessoal no M2, em 04/10/2026 às 23:49 UTC, preparou a release local,
os dois plists e o perfil exclusivo Autonom.ia. `STARTING` existe; `LOADED`
não existe; a consulta local ao launchd não encontrou gestor carregado.
Essas evidências juntas, não o marcador isolado, sustentam a interrupção anterior
à inicialização. Não repetir o modo de instalação inicial sobre esses artefatos.

A sessão SSM criada pela execução pessoal terminou antes da autenticação SSH.
A leitura do log na janela exata 23:49:30–23:50:00 UTC encontrou:

```text
Forwarding to IP address 127.0.0.1 is forbidden.
```

Recibo sanitizado: `tmp/bootstrap-diagnosis-20261004/host-inspection-window-state.json`.
A consulta de chave pública dessa tentativa terminou com Success. O SSH do host
estava ativo e ouvindo porta 22. O erro é do tipo de encaminhamento escolhido;
não comprova sessão Meta expirada ou falta de acesso AWS.
A instância atual já executava outra release, preservada nesta inspeção.

**Correção:** usar `AWS-StartPortForwardingSession` com as portas, sem `host`,
porque o destino é o SSH da própria instância gerenciada. Não desabilitar proteção
de loopback, substituir endereço para escapar dela ou ampliar IAM. O documento
`AWS-StartPortForwardingSessionToRemoteHost` é para outro host.

Referência primária: https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-sessions-start.html

## Defeito adicional no canal JSON

Independente da causa observada acima, a revisão identificou que `rails runner`
carrega o Rails antes de entrar no script. Logs do boot misturam-se ao JSON de
uma linha exigido pelo comando forçado. A configuração observada na Hub2You
mantinha `RAILS_LOG_TO_STDOUT=true` e um initializer com logs de boot.
Não atribuímos essa segunda falha à tentativa que morreu antes do SSH.

O wrapper passa a executar o CLI Ruby, que reserva os descritores de protocolo
antes do boot e silencia stdout/stderr comuns, inclusive durante `at_exit`.
Apenas JSON ou mensagem fixa de erro saem pelos canais reservados. O CLI deve
preservar `load_runner` e `executor.wrap` do Rails. Não modifica logger global,
configuração ou processos web/worker. Schemas, limite de entrada de 2 MiB,
validação de resposta, host key, usuário restrito e prazo do túnel permanecem.

## Retomada e publicação

CLI e wrapper devem ser publicados juntos, após CI/review e aprovação nova.
O código Node local também precisa da versão corrigida; deploy remoto sozinho
não substitui os arquivos já preparados no M4. Nenhum arquivo instalado foi
substituído e nenhum publisher bloqueado foi reexecutado automaticamente.

A candidata local `--resume` verifica integralmente fontes, wrapper, dois plists,
perfis e estado inativo, sem recriar artefatos. Revalida bootstrap, version e
operator_read nas duas stacks antes de carregar a primeira. O pacote permanece
pendente de alinhamento com a revisão corrigida. Não instruir o operador a usar
o inicializador antigo enquanto isso. Falha parcial não autoriza limpeza.

Rollback: preservar global OFF e gestores suspensos; reverter aplicação pelos
workflows blue/green, conforme runbook. Não apagar cookies, locks, outcomes,
metadados, parâmetros ou dados Redis para liberar. Não executar novo convite.

## Validações locais desta correção

- Node: **130 testes aprovados**, zero falhas/skips/cancelamentos; includes
  contratos de manager, observer, transporte, controle e 17 casos de isolamento
  do CLI. Job `m4-40e716e3c6944efd87cdddace0358bad`.
- Candidata de retomada: **45 testes Python aprovados**, zero falhas/erros,
  incluindo preservação/rejeição de arquivos parciais e verificações das duas
  stacks antes da inicialização. Job `m4-ede0443eaf774de3a4235048153300f4`.
- ESLint dos quatro módulos alterados: exit 0, sem erros.
- RuboCop do CLI: um arquivo inspecionado, sem infrações.

As rodadas intermediárias expuseram fixture que ainda interceptava `rails runner`
e ausência dos hooks do executor Rails. Foram corrigidas e revalidadas; resultados
anteriores não substituem a rodada final. Íris implementou o isolamento; Argos
identificou a diferença de ciclo Rails e revisou a retomada. A revisão final do
candidato e o CI do SHA enviado devem ser registrados na PR antes de aprovação.

Todos esses testes usam dados/serviços simulados ou análise local. A chamada real
do publisher permanece não homologada e não foi reencaminhada pela ferramenta.
Não há prova de sessão Meta, renovação ou caixa conectada nesta correção.
