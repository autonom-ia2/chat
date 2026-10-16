# Os votos de uma enquete nativa nossa, AGREGADOS na própria mensagem da enquete (chat#1709; formato da tela do
# Frontend geral, #1702):
#   content_attributes.poll_votes = [{ "sender_type" => "Contact", "sender_id" => 12, "options" => ["Sim"], "at" => ISO 8601 }]
# Um por eleitor: o voto novo substitui o anterior; voto retirado = options [] (o eleitor continua na lista). Comum à
# caixa WAHA comum (Waha::RichNative::Inbound::PollVote) e ao plano B do Híbrido (WhatsappHybrid::RichNative::
# PollVoteJob). A mensagem do voto em si vira atividade escondida (`poll_vote_applied_to`). Grava sob trava e sem as
# validações do modelo (a de rajada recusaria numa conversa movimentada); o `message_updated` leva a mudança à tela e
# não vai ao conector (Waha::RichNative::SilentUpdate).
module Waha::RichNative::PollVotes
  KEY = 'poll_votes'.freeze

  module_function

  # sender: o contato que votou; titles: os títulos das opções marcadas (já conferidos com Waha::RichNative::PollVote);
  # timestamp: a hora do voto no WhatsApp (Waha::RichNative::EventTime). O voto guardado do mesmo eleitor só é
  # substituído por um igual ou mais novo: um job refeito com o voto antigo não troca a escolha atual.
  def apply!(poll, sender:, titles:, timestamp: nil)
    at = Waha::RichNative::EventTime.iso8601(timestamp)
    poll.with_lock do
      current = Array(poll.content_attributes.to_h[KEY])
      previous = current.find { |vote| same_voter?(vote, sender) }
      next if previous && !Waha::RichNative::EventTime.replaces?(at, previous['at'])

      votes = current.reject { |vote| same_voter?(vote, sender) }
      votes << { 'sender_type' => sender.class.name, 'sender_id' => sender.id, 'options' => Array(titles), 'at' => at }
      poll.content_attributes = poll.content_attributes.to_h.merge(KEY => votes)
      poll.save!(validate: false)
    end
  end

  def same_voter?(vote, sender)
    vote.is_a?(Hash) && vote['sender_type'] == sender.class.name && vote['sender_id'] == sender.id
  end
end
