# Histórico de novas conexões — WAHA 2026.9.2

Camada restrita sobre a imagem PLUS instalada. A base é fixada pelo digest e
os artefatos originais são conferidos por SHA-256 antes de qualquer substituição.
Não distribuir a imagem PLUS em registry público.

O conector transmite o ID original em mensagens ao vivo e vincula os IDs de
texto/anexos aos envios do painel. Isso permite importar o histórico disponível
até a primeira conexão sem repetir mensagens. Datas externas não alteram a data
de atendimento de mensagens ao vivo. Os marcadores `chat2youHistorySourceIds=v1`
e `chat2youHistoryFirstConnectionTimestamp=v1` são obrigatórios para criar uma
conexão com importação habilitada. O App Chatwoot dessa conexão também leva
`chat2youHistoryOnboarding=true`; o consumidor só faz o PATCH do timestamp e
envia IDs extras para esse App. Apps antigos da mesma instalação continuam no
fluxo original.

## Início automático e recuperação

A imagem exige `WAHA_AUTO_START_SKIP_SESSIONS_JSON`, um array JSON de nomes
exatos. A lista é privada, levantada por instalação antes do reinício e
persistida no Compose. Inclui todas as sessões que devem permanecer desligadas.
JSON ausente ou inválido interrompe o início; não há fallback para lista vazia.
O filtro cobre as rotinas automáticas de reinício e sessões predefinidas.
O endpoint de início manual continua com o comportamento original.

Operar uma instalação por vez, em modo stop-first. A única atualização troca a
imagem e desliga `WHATSAPP_RESTART_ALL_SESSIONS` e `WAHA_WORKER_RESTART_SESSIONS`,
mantém `WHATSAPP_START_SESSIONS` vazio e configura a ação de falha como `pause`.
O preflight recusa a variável singular `WHATSAPP_START_SESSION`. Não há retorno
automático à revisão anterior com início amplo. Conferir a saúde da candidata e
iniciar manualmente apenas a allowlist que estava `WORKING` antes da atualização.
Persistir o Compose somente depois da conferência final. A lista de exclusão
continua persistida para proteger qualquer rotina automática futura.

Em uma falha, voltar explicitamente à imagem original segura, manter os
controles automáticos desligados e iniciar manualmente somente a allowlist
confirmada. Não usar rollback Docker automático nem restaurar início amplo como
parte da recuperação.

A recuperação exige uma nova leitura completa e comparação de sessões/Apps.
Se a API não responder, interromper e diagnosticar; não executar a recuperação
nem iniciar sessões usando somente o snapshot antigo.

Preservar os volumes de autenticação/mídia, configuração completa do serviço,
Compose e snapshot completo de sessões/Apps. Fazer backup consistente de cada
SQLite por sua API de backup, cifrar e conferir uma cópia externa autenticada.
O backup é por arquivo; não representa uma transação única entre todos os bancos.
Restauração dos volumes exige diagnóstico e autorização operacional específica.

Construir uma única imagem privada, transportar entre os hosts e conferir o
mesmo image ID. Tag local não é digest de manifesto. Para uma implantação sem
registry, usar resolução de imagem desabilitada; no Portainer 2.21.4,
`PullImage=false` corresponde a `--resolve-image=never`.

Aplicar uma instalação por vez. Conferir capacidade, número de sessões
saudáveis, nenhuma sessão em pareamento e igualdade de configuração/Apps após
o reinício. Em falha, retornar à revisão original segura e iniciar manualmente
apenas os nomes observados como `WORKING` antes da operação. Não fazer logout,
repareamento ou replay de atualização com resultado desconhecido.

## Verificação

O Dockerfile roda self-test contra os bundles reais antes de aplicar a camada.
O teste inclui mapping bruto GOWS, serialização do ID completo, texto + dois
anexos, primeiro PATCH com falha e retry sem novo envio. Também verifica a
exclusão de início automático e falha fechada de configuração/hashes.

Depois da publicação do conector e da aplicação, confirmar a versão das duas
instalações e a drenagem de workers antigos. Uma nova conexão real deve validar
histórico datado, identidade única, mensagens públicas e nenhuma resposta
automática provocada pela importação. A quantidade depende do histórico
efetivamente disponibilizado pelo WhatsApp/WAHA; não há promessa de seis meses.

## Corte temporal e exclusão entre páginas

Cada página do job de histórico é exclusiva por instalação. A disputa pelo lock
global é reagendada em cinco segundos antes de criar cliente, consultar WAHA ou
alterar o cursor; a página seguinte também espera cinco segundos. Isso impede
que uma nova execução faça um retry cego da página que outra execução ainda está
processando. A preparação e as consultas remotas ficam dentro do limite de oito
minutos, abaixo do TTL do lock.

O corte correto exige o primeiro `WORKING` depois de `SCAN_QR_CODE`. O instante
é capturado no `setStatus` antes do atraso de até dois segundos do provedor e
fica privado na sessão; o consumidor da fila, somente para o App com
`chat2youHistoryOnboarding=true`, grava-o no Redis em uma chave sem TTL por UUID
do App com `SET NX` e relê o valor vencedor em caso de disputa. Isso evita que
retries, processos diferentes ou eventos fora de ordem escolham outro corte.
Sem `SCAN_QR_CODE` antes do primeiro `WORKING`, sem o valor canônico ou com o
valor inválido, o evento não registra corte e o job permanece `waiting_connection`;
não há substituição por `GET /api/sessions/:session` ou pelo horário do polling.

A API aceita somente a sessão, o usuário dono e o marcador da caixa; depois do
primeiro registro, o corte fica imutável. Sem os dois marcadores de capacidade,
a provisão e o job falham fechado. Como mensagens WAHA chegam em segundos e o
evento chega em milissegundos, o job usa o segundo inteiro anterior ao evento
(`floor(timestamp_ms / 1000) - 1`). Essa margem descarta toda a segunda em que a
conexão foi observada, evitando classificar como histórico uma mensagem ao vivo
que compartilhe o mesmo segundo. Sem captura canônica, as novas tentativas usam
os intervalos de conexão de um minuto e, após 24 horas, quinze minutos; não
fazem polling rápido de cinco segundos.
