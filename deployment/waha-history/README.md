# Histórico de novas conexões — WAHA 2026.9.2

Camada restrita sobre a imagem PLUS instalada. A base é fixada pelo digest e
os artefatos originais são conferidos por SHA-256 antes de qualquer substituição.
Não distribuir a imagem PLUS em registry público.

O conector transmite o ID original em mensagens ao vivo e vincula os IDs de
texto/anexos aos envios do painel. Isso permite importar o histórico disponível
até a primeira conexão sem repetir mensagens. Datas externas não alteram a data
de atendimento de mensagens ao vivo. O marcador `chat2youHistorySourceIds=v1`
é obrigatório para criar uma conexão com importação habilitada.

## Início automático e recuperação

A imagem exige `WAHA_AUTO_START_SKIP_SESSIONS_JSON`, um array JSON de nomes
exatos. A lista é privada, levantada por instalação antes do reinício e
persistida no Compose. Inclui todas as sessões que devem permanecer desligadas.
JSON ausente ou inválido interrompe o início; não há fallback para lista vazia.
O filtro cobre as rotinas automáticas de reinício e sessões predefinidas.
O endpoint de início manual continua com o comportamento original.

Não atualizar diretamente uma imagem original com reinício amplo habilitado:
o rollback automático para ela ignoraria a nova proteção. Primeiro preparar
uma revisão segura da imagem original com `WHATSAPP_RESTART_ALL_SESSIONS=false`,
`WAHA_WORKER_RESTART_SESSIONS=false`, sem `WHATSAPP_START_SESSION`, e com falha
de atualização configurada para `pause`. Essa revisão mantém todas paradas.
Somente depois instalar a candidata com a lista de exclusão e restaurar o
reinício amplo. Seu rollback anterior terá o início automático desligado.

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
