# Assina o `poll.vote` nas sessões híbridas de uma conta (chat#1709, fase 3), num horário escolhido depois de ligar a
# flag `whatsapp_rich_native` (WhatsappHybrid::RichNative::PollVoteEvents#subscribe_poll_vote!). Cada sessão que ainda
# não assina REINICIA uma vez no motor. Uma sessão com erro não para as outras: vai ao log só com a classe.
class WhatsappHybrid::RichNative::PollVoteSubscribeJob < ApplicationJob
  queue_as :low

  def perform(account_id)
    WhatsappHybrid::Connection.where(account_id: account_id).find_each do |connection|
      result = WhatsappHybrid::SessionManager.new(connection).subscribe_poll_vote!
      Rails.logger.info("[whatsapp_hybrid] poll vote subscribe inbox=#{connection.inbox_id} #{result}")
    rescue StandardError => e
      Rails.logger.warn("[whatsapp_hybrid] poll vote subscribe failed inbox=#{connection.inbox_id} #{e.class}")
    end
  end
end
