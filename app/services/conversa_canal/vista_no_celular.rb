# #2246, opção C: a leitura feita no aparelho do negócio marca a conversa como vista no painel. Quem atende pelo
# WhatsApp do celular abre a conversa lá; o aparelho avisa que leu as mensagens do cliente, e o "visto" do agente
# (agent_last_seen_at) anda até elas. É a leitura que prova que uma pessoa leu, não a resposta (o eco do celular não
# separa pessoa, resposta automática do app Business e robô: ver ConversaCanal::VistaAoResponder).
#
# Quem chama decide se a leitura veio de uma pessoa (o canal). Aqui só o "visto":
# - anda só para a frente, numa gravação condicionada (a leitura mais nova do painel fica), como no
#   ConversaCanal::VistaAoResponder, de quem reaproveita `gravar`, `nao_lida_ate?` e `avisar`;
# - vai até o FIM do segundo da mensagem lida, não até a hora da leitura: ler a mensagem X não prova que a pessoa viu
#   as que chegaram depois. O fim do segundo faz a tela e o servidor concordarem (a tela compara em segundos inteiros,
#   ver o comentário de VistaAoResponder). EFEITO: outra mensagem do cliente no MESMO segundo da lida conta como lida;
#   chegam juntas e o aparelho mostra as duas;
# - sem sino: não se sabe QUEM leu no celular, então nenhum aviso de ninguém é marcado como lido
#   (Notification::MarkConversationReadService fica de fora). Só a tela e os contadores são avisados, e só quando
#   havia não lida.
# Atrás da flag `leitura_no_celular` (por conta).
module ConversaCanal::VistaNoCelular
  FLAG = 'leitura_no_celular'.freeze

  def self.enabled?(account)
    account.present? && account.feature_enabled?(FLAG)
  end

  # -> true quando o "visto" andou.
  def self.marcar!(mensagem)
    return false unless mensagem&.incoming?

    conversation = mensagem.conversation
    visto = ate_a_mensagem(mensagem)
    havia_nao_lida = ConversaCanal::VistaAoResponder.nao_lida_ate?(conversation, visto)
    return false unless ConversaCanal::VistaAoResponder.gravar(conversation, visto)

    ConversaCanal::VistaAoResponder.avisar(conversation) if havia_nao_lida
    true
  end

  def self.ate_a_mensagem(mensagem)
    mensagem.created_at.change(usec: 0) + 1.second - ConversaCanal::VistaAoResponder::UM_MICROSSEGUNDO
  end
end
