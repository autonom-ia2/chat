# Prepend em WhatsappHybrid::SessionManager (chat#1709, fase 3): com a flag `whatsapp_rich_native`, a sessão do plano B
# também assina os eventos `poll.vote` (o voto na enquete nativa volta ao painel, WhatsappHybrid::RichNative::PollVoteJob)
# e `event.response` (a resposta ao convite de evento, rodada 2, WhatsappHybrid::RichNative::EventResponseJob). A sessão
# que já assinava só o voto ganha a resposta SÓ na assinatura agendada (`subscribe_poll_vote!`, um reinício a mais, numa
# janela combinada): nas outras sincronizações, ter o `poll.vote` basta (revisão da rodada 2: sem isso, toda sessão
# híbrida com a flag reiniciaria na primeira sincronização depois do deploy, sem janela).
# Gravar a configuração REINICIA a sessão no motor. Por isso:
# - no envio de mensagem e ao reconectar (modo :skip do `sync_remote_config!`), a assinatura NÃO é conferida: a sessão
#   conta como configurada e nada é gravado;
# - a gravação acontece ao criar a sessão, no `refresh!` com proxy (a aba da conexão aberta por alguém) ou, o caminho
#   certo, pela assinatura agendada: `subscribe_poll_vote!` (WhatsappHybrid::RichNative::PollVoteSubscribeJob, rake
#   `whatsapp_hybrid:poll_vote:subscribe`), que só grava o webhook, sem mexer no proxy. Ligar a flag numa conta = um
#   reinício de cada sessão híbrida dela, num horário escolhido. Desligar não regrava: o controller ignora o voto sem a
#   flag.
module WhatsappHybrid::RichNative::PollVoteEvents
  EVENT = 'poll.vote'.freeze
  # Rodada 2: a resposta ao convite de evento (WhatsappHybrid::RichNative::EventResponseJob) vem na MESMA assinatura.
  EVENT_RESPONSE = 'event.response'.freeze
  EVENTS = [EVENT, EVENT_RESPONSE].freeze

  # Grava a assinatura que falta (reinicia a sessão uma vez). Devolve :subscribed, :already ou :skipped (pausada, sem
  # flag ou sem sessão no motor).
  def subscribe_poll_vote!
    return :skipped if connection.paused? || !poll_vote_wanted?

    remote = fetch_remote
    return :skipped if remote.blank?

    @poll_vote_config_mode = :subscribe
    return :already if webhook_configured?(remote)

    write_config!(remote, nil)
    :subscribed
  ensure
    @poll_vote_config_mode = nil
  end

  private

  def session_config(proxy = nil)
    config = super
    return config unless poll_vote_wanted?

    config.merge(webhooks: config[:webhooks].map { |hook| hook.merge(events: (hook[:events] + EVENTS).uniq) })
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

    required = required_events
    Array(remote.dig('config', 'webhooks')).any? do |hook|
      hook.is_a?(Hash) && hook['url'] == connection.webhook_url && (required - Array(hook['events'])).empty?
    end
  end

  # `event.response` só é exigido na assinatura agendada; nas outras sincronizações, o `poll.vote` basta.
  def required_events
    @poll_vote_config_mode == :subscribe ? EVENTS : [EVENT]
  end

  def poll_vote_wanted?
    Waha::RichNative.enabled?(connection.account)
  rescue StandardError => e
    Rails.logger.warn("[whatsapp_hybrid] poll vote flag inbox=#{connection.inbox_id} #{e.class}")
    false
  end
end
