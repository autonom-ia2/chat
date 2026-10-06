# WAHA — todas as contas e histórico nas novas conexões

Data: 2026-10-06. Issue #1071. Branch codex/waha-all-accounts-history.

## Autorização e escopo

Rodrigo autorizou a correção em todas as contas do Hub2You e da Autonom.ia,
e confirmou que ninguém mais alteraria a configuração das conexões durante a operação.
Atendimento e mensagens podem continuar. Histórico já gravado é preservado.
As caixas antigas compartilhadas e as desconectadas permanecem como histórico, conforme decisão anterior.
Nenhum logout, QR, novo pareamento ou importação retroativa de mensagens nas caixas existentes foi executado.

## Inventário verificado

Hub2You: 39 caixas WAHA em sete contas, 31 elegíveis e oito preservadas/excluídas.
Autonom.ia: duas caixas WAHA, uma elegível já conforme e uma FAILED preservada.
As 25 caixas elegíveis da conta 17 do Hub2You já estavam conformes.
As seis pendentes eram das contas 6/16/18/45/47/50, caixas 49/69/56/64/62/104, respectivamente.

O destino foi conferido separadamente: Hub2You usa wa-hub.autonomia.site (VPS hubsegs);
Autonom.ia usa wa-autonomia.autonomia.site (VPS autonomia). As outras duas VPS WAHA não foram alteradas.
Runtime publicado nas duas instalações antes da operação: 0d28f1a52485ec4d81569bf98930dd9f791ecde8.

## Aplicação operacional das seis pendentes

Usado exclusivamente o planner/executor publicado, preservando R1–R5/N1–N3.
Snapshot completo local/remoto em área privada, cifrado AES-256-GCM/RSA-OAEP SHA-256.
A cópia anterior foi copiada para fora da instância; tamanho/hash, autenticação da cifra,
descriptografia e hash do conteúdo foram verificados antes de qualquer escrita.
Não há credenciais nem conteúdo de cliente neste registro.

Gates: instalação/conta/caixa exatas; filtro Status desejado true; backup de até 15 minutos;
igualdade do estado local/remoto; releitura N1 antes do PUT; janela exclusiva confirmada;
flock e intent sem replay; memória livre de pelo menos 1 GiB antes de uma única inicialização Rails.
Lote para na primeira falha, sem retry cego. Cada sucesso tem verificação e snapshot posterior selado.
Recuperação após falha de pós-verificação exige estado remoto completo ainda igual ao desejado,
incluindo status e todos os campos dos Apps. Mudança concorrente impede restauração automática.
Processo morto exige diagnóstico pelo ledger/backup; execução desconhecida nunca é repetida.

SSM backup bb0416c1-5c66-4a30-9987-add8c6f7afcc: Success/0, seis planos.
Backup externo anterior: 20.383 bytes, SHA256 725b7ba3d715584edb3fd380658890aa779e5f5b502adee0c1c6cdc523053bfd.
SSM APPLY 5d706e95-eac9-45db-8377-785224d1756d: Success/0, updated=6, halted=false,
seis verificações individuais conformes, zero skipped/failed/recovered/recovery_failed.
Backup posterior externo: 21.839 bytes, SHA256 4c66e617cef58655c751e334fb3e02adb1ae61a9311c1e76794cabf10e3316f1,
descriptografia autenticada confirmada, seis itens.

## Conferência global posterior

Leitura independente confirmou 32 caixas elegíveis conformes (31 Hub2You, uma Autonom.ia).
As 25 caixas elegíveis previamente ajustadas e as nove excluídas permaneceram sem mudança.
Apps não relacionados foram preservados. Instâncias running/SSM Online, ALBs saudáveis,
frontends HTTP 200 e runtime de referência conferidos nas duas instalações.
A verificação não iniciou Rails, não reiniciou processos e não escreveu em produção.

## Implementação em andamento — histórico apenas de novas conexões

O marcador e job nascem somente no InboxProvisioner, usado pela criação no painel e pelo convite SSO.
Caixas existentes, migration updater e reconnect não iniciam importação.
Leituras paginadas do histórico armazenado pelo WAHA, sem corte inferior de seis meses.
Rodrigo escolheu completar até a conexão, inclusive o intervalo entre criação da caixa e leitura do QR.
Isso exige identidade original compartilhada entre o conector ao vivo e o importador, com bloqueio
por contato/caixa na gravação; a proposta anterior de cortar na criação foi substituída.
O limite superior deve ser fixado uma única vez ao observar WORKING, após verificar essa capacidade.
Releituras de reconciliação permitem aproveitar dados que chegam depois da primeira consulta.
Mensagens mantêm datas/IDs/direção, são públicas e deduplicadas por caixa.
Anexos disponíveis são importados; ausência/expiração/tamanho não suportado ficam explícitos.
A importação suprime respostas, eventos, bots, atribuição, CRM, notificações e métricas de atendimento.
Dados históricos não viram novas mensagens não lidas; mensagens ao vivo conservam seu comportamento.

Fontes primárias: https://waha.devlike.pro/docs/how-to/chats/ e https://waha.devlike.pro/docs/how-to/contacts/.
Código instalado GOWS 2026.9.2 exclui events.HistorySync do stream ao vivo.
O App nativo Chatwoot não fornece source_id nem timestamp original na gravação ao vivo;
a camada adicional do conector deve resolver essa limitação antes de ativar a importação.
Datas originais ficam no histórico; o timestamp externo de uma mensagem ao vivo não deve alterar
a data de recebimento nem o comportamento de atendimento.
Fila exclusiva waha_history impede workers antigos de consumir a classe nova durante blue-green.
Conversas exclusivamente históricas e suas mensagens não entram em volumes de relatórios.
A primeira mensagem real inicia a contabilização; áudio histórico não dispara transcrição.

## Proteções adicionadas após revisão

A criação de uma conexão verifica ausência remota: somente 404 permite prosseguir.
Sessão existente ou consulta indisponível interrompem antes da criação local.
409, timeout ou resultado desconhecido do POST não autorizam excluir Apps/sessão.
O rollback local desativa o callback de exclusão remota antes de destruir a caixa temporária.
Uma sessão que tenha sido criada remotamente após timeout requer diagnóstico; nenhum retry cego.

O conector ao vivo fornece ID original e timestamp externo, sem alterar a data de atendimento.
Envios do painel recebem o ID primário e uma lista com os IDs de texto/anexos.
Um retry do PATCH após mappings persistidos reaproveita os IDs sem reenviar ao WhatsApp.
A importação aguarda identidades pendentes, inclusive mensagem marcada failed cujo envio pode ser ambíguo.
O campo de identidade exige o token API do proprietário configurado no conector; login do painel
ou token de outro agente são recusados. O proprietário é resolvido pelo token real, inclusive no SSO.
Vínculos divergentes não são sobrescritos. Lock transacional por caixa serializa a disputa de IDs.

Limite preexistente no conector nativo: envio concluído seguido de falha antes de saveMapping
pode ser repetido pelo próprio provider. A camada não afirma exactly-once nessa janela.

## Validação

Snapshot 20261006-163410: 173 exemplos focados, zero falhas; regressão 616 exemplos,
zero falhas e quatro pendências preexistentes. Snapshot 20261006-164859: 192 exemplos,
zero falhas. Snapshot final 20261006-165840: 195 exemplos focados, zero falhas;
regressão 666 exemplos, zero falhas e cinco pendências preexistentes explicitamente em quarentena.
RuboCop dos 35 arquivos Ruby alterados: zero ofensas; git diff --check aprovado.
Proteções de concorrência são verificadas com conexões PostgreSQL reais e bloqueio observado.
Self-test do conector executa os sete artefatos compilados originais, valida seus hashes,
reproduz texto + dois anexos e falha do primeiro PATCH após persistir mappings; retry sem reenvio.
Mappings GOWS armazenam IDs brutos; a vinculação usa SerializeWhatsAppKey para produzir
o mesmo ID completo retornado na leitura do histórico. O teste reproduz os campos Info do GOWS.
Revisão independente do recorte Ruby não encontrou P1/P2; a revisão final do conector está em andamento.

## Proteção do reinício do provider

Inventário global dos dois WAHA: Hub tem 34 sessões (31 WORKING, três FAILED);
Autonom.ia tem 11 (duas WORKING, nove FAILED). Isso inclui sessões sem caixa ativa no Chat2You.
O binário original tem WHATSAPP_RESTART_ALL_SESSIONS=true e tentaria iniciar todas.
A camada exige uma lista JSON privada de exclusão do início automático, por instalação;
ausência/formato inválido falham antes do início. As sessões excluídas não chegam a logger,
lock ou start nas rotinas automática e predefinida. O início manual conserva o contrato original.
Os testes cobrem esses caminhos e erros sem expor nomes/configuração privada.

## Publicação e recuperação previstas

WAHA PLUS é licenciada: não publicar a imagem em registry público.
VPS corretos têm Swarms independentes de um nó x86_64. Base observada nos dois:
devlikeapro/waha-plus@sha256:ac5d6c131155df16e4a29c29efdbdf977788a0a4908dbe9d8edf4366202e9598.
A imagem candidata deve ser construída uma vez, transportada privadamente e conferida por image ID.
Tag local não é digest de manifesto; não fabricar repo@sha256 com image ID.
Portainer 2.21.4 usa resolve-image=never quando PullImage=false, conforme fonte oficial:
https://raw.githubusercontent.com/portainer/portainer/2.21.4/api/exec/swarm_stack.go.

Preservar Compose, imagem anterior, autenticação e mídia; comparar estado antes da operação.
Implantação sequencial stop-first, uma instalação por vez, com retorno à imagem anterior segura
se capacidade, saúde ou identidade divergir. Não executar logout ou novo pareamento nas sessões existentes.
A atualização candidata troca imagem e desliga o reinício global/worker na mesma operação,
com sessões predefinidas vazias e update/rollback failure_action=pause. Isso impede que
falha no staging reabra automaticamente a revisão original com início amplo. A candidata
mantém o início automático desligado; a recuperação usa explicitamente a imagem original
com os mesmos controles desligados.
Em recuperação, iniciar manualmente somente a allowlist observada como WORKING antes da operação.
Persistir as revisões correspondentes no Compose, conservando volumes, redes e demais variáveis.
Aplicação Rails segue PR/review/merge queue/checks e blue-green; confirmar workers antigos drenados.
Nova conexão real exige validar chegada pública, ID único, histórico datado e ausência de respostas automáticas.
Quantidade e profundidade dependem dos dados entregues pelo WhatsApp/WAHA; seis meses não são garantidos.

## Pendências para fechamento

Revisão final e plano operacional verificável, PR/checks, publicação autorizada
e verificação direta das duas instalações.
Este registro de andamento não afirma que a funcionalidade de histórico já foi publicada.

## Revisão após a retomada autorizada

Marcadores de Message/Conversation passaram a ser reservados ao contexto interno do
importador. Criação externa, inclusive false/null/chaves simbólicas, é recusada; update
ordinário preserva o marcador persistido. Exclusão do conteúdo preserva a exclusão de
relatórios. A primeira rodada dos testes novos teve 13 falhas de setup porque Current
é um módulo do projeto, sem método set; os fixtures foram corrigidos com restauração
do contexto em ensure. Nenhuma alteração de produção decorreu dessa rodada.

Snapshot 20261006-182646-eff0d284-21d6019c31-1b415f6c: 52 exemplos focados da proteção,
builder e concorrência, zero falhas. A regressão completa anterior foi repetida nesse
snapshot: 666 exemplos, zero falhas e as mesmas cinco pendências preexistentes.
Esses resultados não validam alterações posteriores na captura da primeira conexão.
Todos os comandos usaram o wrapper Ruby 3.4.4 e serviços de teste isolados do MacCluster.

A revisão do provider encontrou o timestamp de status após um delay de até dois
segundos e histórico limitado aos últimos três estados. Capturar o horário do polling
ou assumir que esse timestamp é o instante real da conexão não é seguro. A captura
precisa ocorrer na mudança real para WORKING e sobreviver a retries/reconexões.
Mensagens usam precisão de segundos, exigindo um corte que exclua a segunda parcial
da conexão para preservar o tratamento de mensagens ao vivo. Implementação em andamento.

O job agora serializa páginas por instalação, com intervalo de cinco segundos, timeout
de oito minutos incluindo preparação e TTL de dez minutos. Não há importação nas caixas
existentes. O Guia de formatos foi regenerado oficialmente em ambiente isolado após
uma falha no CI; deve ser regenerado novamente se o controlador de caixas mudar.

Os manifests operacionais anteriores não serão aplicados: conservavam start-first,
início amplo e rollback automático. O gerador v2 prepara uma única atualização com
stop-first, ALL=false, WORKER=false e failure_action=pause, além de uma recuperação
explícita na imagem original com início automático desligado. A allowlist vem do
inventário anterior verificado, nunca do estado transitório após a parada.
O início manual será individual, limitado à allowlist, com acompanhamento de memória
e saúde das duas instalações. Não usar docker service rollback para recuperar.

## Validação final da retomada

Integrado main df75602eac65fe0b5ba49d3d2d4743061b2930e5 sem sobrescrever trabalho de
outras frentes. O Guia de formatos foi regenerado oficialmente nesse código combinado,
em Rails/test isolado no M2: 527 ações. Os dois outputs foram copiados por hash para a
branch; o snapshot original foi restaurado e verificado nos dois nós. pnpm guia:check
aprovado no snapshot 20261006-190225: 192 fluxos, 186 telas, zero sem explicação.

O corte usa o primeiro WORKING capturado antes do delay do provider, com prova de QR,
valor canônico no Redis por App e registro imutável pelo token API do dono. Mudança
concorrente do marcador não é perdida na persistência do estado do importador.
Revisão independente final não encontrou bloqueadores concretos.

Snapshot 20261006-190511-eff0d284-a7285f033e-f174da27, SHA256
a7285f033e02a75ccd5abe66bd5ca899fe9579340032e1e1e1abcf97efff8317:
370 exemplos focados, zero falhas, após corrigir três ofensas de organização/estilo.
O ajuste lê status uma única vez e mantém o tratamento de WORKING/FAILED/outros estados.
A regressão completa no mesmo snapshot passou: 666 exemplos, zero falhas e as mesmas
cinco pendências preexistentes. RuboCop: 41 arquivos inspecionados, zero ofensas.
Self-test local dos bundles reais e git diff --check aprovados. Resultados lidos antes
de qualquer commit; validação e commit executados em comandos separados.

Imagem candidata privada chat2you/waha-plus-history:2026.9.2-20de19526f construída
sobre a base fixada, com self-test dos 12 bundles reais aprovado. Image ID
sha256:4236c31658d67de7a3e428b10a78ccbfde58c6975ede2959c1320916eb72a937.
Smoke isolado sem rede, sem volumes de produção e zero sessões confirmou os dois
marcadores v1. O container de teste e seus volumes anônimos foram removidos.
Nenhuma sessão real foi reiniciada por esse teste.

Revisão independente dos scripts operacionais privados aprovada; dez casos sintéticos
passaram sem Docker/SSH/produção. O Compose de cada fase faz parte do selo; início
exige atualização aceita, saúde e mesma versão do serviço; persistência exige check
final. Recuperação exige releitura completa: com API indisponível, interromper para
diagnóstico, sem rollback cego ou restauração automática de volumes.

Às 22:08 UTC, os dois frontends respondiam HTTP 200. Hub2You tinha 757,7 MiB livres
no RDS, swap 0,5 MiB. Autonom.ia tinha 116,8 MiB livres e swap 78,2 MiB, aumento
acima do limite de 5 MiB em relação à referência da retomada. O gate bloqueou
publicação; não houve merge, deploy, início de sessões ou importação neste intervalo.
Confirmado via AWS: RDS da Autonom.ia continua db.t4g.micro, sem modificações pendentes,
backup retido sete dias. Aumentar essa instalação para 2 GB foi submetido separadamente
ao Rodrigo por envolver infraestrutura/custo e possível interrupção.

Pre-commit executado separadamente, com Ruby 3.4.4 e Node 24.11.0: ESLint dos 29
arquivos JS/Vue integrados de main passou. Nenhum arquivo foi reescrito (hashes
conferidos). O xargs BSD do hook emitiu aviso de comprimento de comando na integração
de 131 arquivos; o hook retorna zero por seu comportamento preexistente. A validação
independente e completa dos 41 arquivos Ruby do recorte passou no snapshot, incluindo
os arquivos que esse pipeline não alcançou. Nenhum --no-verify foi usado.
git diff df75602eac65fe0b5ba49d3d2d4743061b2930e5 --check passou no recorte WAHA.
O check contra o HEAD antigo apontou espaços finais/EOF já presentes nos templates
MJML de main; esses arquivos foram preservados exatamente como publicados.
