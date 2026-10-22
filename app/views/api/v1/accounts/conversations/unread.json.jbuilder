# #2067: marcar como lida/não lida não calcula de qual IA a conversa veio (consulta a cada troca de conversa); a tela não
# lê o meta desta resposta e guarda o que já sabia (veioDaIaPreservado).
json.partial! 'api/v1/conversations/partials/conversation', formats: [:json], conversation: @conversation, veio_da_ia: {}
