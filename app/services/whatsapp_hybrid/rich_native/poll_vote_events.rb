# Prepend em WhatsappHybrid::SessionManager (chat#1709, fase 3): com a flag `whatsapp_rich_native`, a sessão do plano B
# também assina o evento `poll.vote` (o voto na enquete nativa volta ao painel, WhatsappHybrid::RichNative::PollVoteJob).
# Gravar a configuração REINICIA a sessão no motor: a assinatura só é gravada fora do envio de mensagem (o modo :skip do
# `sync_remote_config!` conta a sessão como configurada), ou seja, na próxima atualização da aba, ao reconectar ou ao
# criar a sessão. Ligar a flag numa conta = um reinício da sessão híbrida (agendar). Desligar não regrava: o controller
# ignora o voto sem a flag.
module WhatsappHybrid::RichNative::PollVoteEvents
  EVENT = 'poll.vote'.freeze

  private

  def session_config(proxy = nil)
    config = super
    return config unless poll_vote_wanted?

    config.merge(webhooks: config[:webhooks].map { |hook| hook.merge(events: (hook[:events] + [EVENT]).uniq) })
  end

  def sync_remote_config!(remote, proxy_mode:)
    @poll_vote_config_mode = proxy_mode
    super
  ensure
    @poll_vote_config_mode = nil
  end

  def webhook_configured?(remote)
    configured = super
    return configured unless configured && @poll_vote_config_mode != :skip && poll_vote_wanted?

    Array(remote.dig('config', 'webhooks')).any? do |hook|
      hook.is_a?(Hash) && hook['url'] == connection.webhook_url && Array(hook['events']).include?(EVENT)
    end
  end

  def poll_vote_wanted?
    Waha::RichNative.enabled?(connection.account)
  rescue StandardError => e
    Rails.logger.warn("[whatsapp_hybrid] poll vote flag inbox=#{connection.inbox_id} #{e.class}")
    false
  end
end
