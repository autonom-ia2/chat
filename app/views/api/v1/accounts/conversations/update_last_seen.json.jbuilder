# #2067: marcar como lida/não lida não calcula de qual IA a conversa veio (consulta a cada troca de conversa) nem leva a
# chave (null diria "não veio da IA"); a tela não lê o meta desta resposta e guarda o que já sabia.
json.partial! 'api/v1/conversations/partials/conversation', formats: [:json], conversation: @conversation, veio_da_ia: false
