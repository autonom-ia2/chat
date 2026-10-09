# #960 — metadados pós-deploy e próximo limite operacional

## Executado

Após o deploy controlado `afcc85bf7961a5ac23d671136f969f0a75e27169`, Rodrigo
aprovou continuar a configuração/homologação. As sessões SuperAdmin existentes
no Chrome do M2 permitiram abrir `/super_admin/instagram_automation` em ambas
as stacks. Os cinco campos visíveis foram conferidos e enviados pelo formulário
normal. As duas instalações responderam `Instagram automation configuration saved.`

Foram preservados os valores já configurados: App pai `544486745144318`, Business
`1455428945005668`, nome `Autonom.ia`, administrador `100000766120707` e RolesTable
`doc_id=24715790494688123`. App pai não substitui o App OAuth. O serviço Metadata
persiste esses registros e invalida somente as chaves correspondentes de cache.
Não houve mudança nas caixas, tokens OAuth, outcomes ou Redis de coordenação.

## Estado observado após salvar

Nos dois painéis: configuração, proxy e coordenação presentes; sessão gerenciada
**ausente**; gestor **unknown**, sem heartbeat; automação **disabled** e reconexão
indisponível. Isso é estado local da tela, não prova remota da Meta.

## Limite desta rodada

A ferramenta bloqueou a chamada automatizada do publisher antes da execução.
Não iniciar a mesma chamada por outro canal automatizado. Nenhum bootstrap,
publicação de sessão ou gestor iniciado foi comprovado. Íris prepara somente
código para execução pessoal posterior; Argos revisou a persistência/efeitos,
e Nexo delimitou os critérios de homologação. Global OFF e registros anteriores
permanecem preservados; novos convites ainda exigem reconciliação/expiração real.

## Inicializador pessoal entregue, não executado

Íris produziu o inicializador; Argos revisou e pediu corrigir PATH. O coordenador
aplicou o PATH confirmado e mensagens fixas por etapa. A bateria final passou:
**25 testes, zero falhas/erros**, somente subprocessos simulados e ambiente
sintético; job `m4-fddfe7160a12408cbbd0c93aad66785a`. Argos aprovou o arquivo final
para execução pessoal, SHA-256 `f7d19c120c2deab6d081406024eb7e4cb28ecfde789753d7aa693d8d3a64ac5e`.

Fonte: `tmp/activation-20261004/human-start/human_start.py`. Launcher preparado
e conferido, mas não iniciado: `/Users/rodrigovictor/Downloads/iniciar_gestores_instagram_m2.command`.
A execução pelo M2 usa SSH confiável até o M4; o programa exige TTY e confirmação
pessoal `ATIVAR GESTORES`. Não cria login AWS, copia credenciais ou cookies, altera
OAuth ou liga a flag global. Prepara fontes versionadas/perfis independentes,
valida bootstrap em ambas as stacks e só depois solicita os dois carregamentos.
Carregamento não comprova sessão ou renovação; falha parcial é preservada.

O gestor, quando efetivamente iniciado pelo operador, usa o perfil Meta e pode
publicar sessão cifrada e heartbeat no Redis da instalação. Não é uma operação
sem efeitos. Nenhum desses efeitos foi executado nesta preparação. A automação
geral e novos convites continuam bloqueados até os gates documentados.

## Bloqueio do inicializador corrigido — 04/10/2026, 23:45 UTC

O operador rodou o launcher no M2. A falha foi em `local_idle`: a verificação
rejeitava qualquer Singleton do Chrome. Inspeção somente leitura no M4 mostrou
host local, PID 73083 ausente, nenhum processo referenciando o perfil e socket
Unix do usuário sem opener (`lsof` exit 1, stdout/stderr vazios). Release e dois
plists inexistentes: não houve preparação parcial ou início de gestores.

Correção local: aceitar apenas Singletons órfãos verificados, sem removê-los;
rejeitar dono vivo, host divergente, socket ocupado/ambíguo, alteração de links
ou perfil em uso. Lock do gestor continua bloqueado. Rechecagem por stack,
antes do carregamento, e diagnóstico sanitizado por etapa preservados.

Íris revisou a causa; Argos aprovou o patch final SHA-256
`1ad9be1b6e87a1446717286b4d7e58998bd0e3f89e90a5d9fe2faed08e55b2f0`.
37 testes offline passaram; job `m4-58cf6b3bd64d4bd08c514676ebee8684`.
A checagem local real corrigida passou e os 18 hashes públicos conferiram.
Nenhum arquivo de perfil foi alterado e nenhuma chamada AWS/publisher/Meta,
bootstrap ou carregamento de gestor foi executada nesta correção.

O inicializador referenciado pelo launcher M2 foi substituído atomicamente após
conferência do hash anterior e ausência de execução concorrente. Mesma chamada
pessoal, mesmo TTY e confirmação. Não repetir a versão antiga nem apagar locks.
Sessão, renovação e conexão das caixas continuam pendentes. Evidências e patch:
`tmp/fix-initializer-20261004/`. Não houve novo commit/CI da aplicação ou deploy.

## Correção PR #988 publicada e cópia local alinhada — 05/10/2026

Rodrigo autorizou merge pela fila, deploy corretivo OFF nas duas stacks e atualização
local para retomada pessoal. Merge confirmado às 06:54:37 UTC, SHA
`8800a6ac2f003f3f099daf27f6f255ae08414d01`. Os workflows Hub2You `37274826257`
e Autonom.ia `37274826265` concluíram com success, sem dispatch duplicado.

Inspeção nas novas instâncias: Hub `i-0a7802cf2c40ea98b`, Aut `i-08661dfb317476789`;
web/worker no SHA, API 200, assistido OFF e fonte SSM OFF, auxiliar active/running.
Os três scripts corrigidos e o wrapper instalado conferiram pelos hashes. Recibos
SSM `b7516843-d317-45c7-982d-7c5e1c9b0d5a` e `9a2964df-f9b1-412d-8f12-5de46d929cc5`.
PREVIOUS de cada stack foi reconfirmado e está stopped, preservado para rollback.
Não foi executado rollback real; nenhum publisher ou novo convite iniciado.

O atualizador local passou 47 testes sintéticos e revisão Argos; o inicializador
alinhado passou os 45 testes de retomada. Após dry-run real, somente três scripts
públicos e o inicializador foram substituídos; 18 hashes finais conferidos, wrapper
e dois plists preservados. Nenhum cookie/perfil/lock/Redis/credencial foi removido.
Launcher no Downloads do M2 agora passa `--resume`, mantendo TTY e confirmação
`ATIVAR GESTORES`; SHA-256 `ba891d177d0497164f2e53af515e4ae2f33fc40c0efae431908612d488c71ea7`.

A tentativa de preparar inspeção de argumentos de processos foi bloqueada e
abandonada; foi adotada checagem limitada aos labels/arquivos de controle próprios.
A chamada autenticada bloqueada do publisher não foi repetida ou contornada.
Gestores ainda não iniciados; bootstrap real, sessão, renovação e mensagens pendentes.
Recibos e revisão: `tmp/release-988-20261005/`. Esta atualização de auditoria é local,
ainda sem novo commit; resultados também registrados na Issue #960/PR #988.

## Hostname do M4 mudou — correção local de 05/10/2026, 07:35 UTC

A retomada pessoal parou em `singleton_host_mismatch`, antes de bootstrap.
Inspeção confirmou hostname atual `MacBook-Air-de-Rodrigo.local`, HostName não
fixado e o mesmo lock antigo `mac.lan-73083`. PID ausente, socket Unix do usuário
sem opener e nenhum label Instagram carregado. A preparação existente foi preservada.

O inicializador agora tolera hostname divergente somente em Darwin, com perfil
privado em APFS interno confirmado no mesmo device do mountpoint, sem exportação
NFS configurada ou compartilhamento SMB cobrindo perfil/ancestrais/subdiretórios.
Aliases APFS são comparados também por device/inode, não apenas pelo caminho.
PID vivo/inconclusivo, socket ocupado, inspeção incompleta, alteração de links ou
lock do gestor continuam bloqueando. Nenhum Singleton foi apagado ou renomeado.

Íris revisou a causa; Argos apontou o caso dos firmlinks e aprovou sua correção.
63 testes sintéticos passaram, zero falhas/erros. O helper de hostname/disco/share
passou no M4 real, sem chamar main/environment, publisher, AWS ou navegador.
Essa prova é parcial: não demonstra bootstrap, sessão Meta, renovação ou caixas.

Aplicado somente o inicializador, com substituição atômica e hash anterior conferido.
SHA-256 final: `3b530f8e9476d7a3f54af65e7acf1ccc60a9c1f85aeefa7d8ff9b8b5054f6a0e`.
Os 18 scripts, wrapper, dois plists e metadados dos locks permaneceram iguais.
O launcher M2 continua em `--resume`; não foi executado nesta correção.
Não houve novo deploy, alteração de hostname, Redis, credenciais ou cookies.
Evidências: `tmp/hostname-guard-20261005/`. Operador retoma uma vez o mesmo comando;
se falhar, preservar preparação. A checagem não elimina a janela de concorrência.
