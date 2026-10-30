json.partial! 'api/v1/models/message', message: @message
# #2067: o ícone "ficar com a conversa" estava ligado e não deu (trava ocupada, outro dono): a tela avisa.
json.ficar_com_a_conversa_nao_deu true if @message.ficar_com_a_conversa_nao_deu
