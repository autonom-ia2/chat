class AsyncDispatcher < BaseDispatcher
  def dispatch(event_name, timestamp, data)
    EventDispatcherJob.perform_later(event_name, timestamp, data)
  end

  def publish_event(event_name, timestamp, data)
    event_object = Events::Base.new(event_name, timestamp, data)
    publish(event_object.method_name, event_object)
  end

  def listeners # rubocop:disable Metrics/MethodLength
    [
      AutomationRuleListener.instance,
      Autonomia::Agents::Operate::MessageListener.instance,
      Autonomia::Agents::Faq::ConversationListener.instance,
      CampaignListener.instance,
      Crm::ConversationObserverListener.instance,
      CsatSurveyListener.instance,
      HookListener.instance,
      InstallationWebhookListener.instance,
      NotificationListener.instance,
      ParticipationListener.instance,
      Conversations::UnreadCounts::Listener.instance,
      ReportingEventListener.instance,
      WebhookListener.instance,
      Crm::MetaCapiListener.instance,
      Crm::GoogleOfflineListener.instance,
      # #1305: a confirmação da IA na conversa dispensa o aviso "ao marcar" repetido.
      Crm::BookingNoticeToldListener.instance,
      # #1524: o toque em "Parar avisos" no modelo do aviso para os avisos do contato.
      Crm::BookingNoticeStopReplyListener.instance,
      # #1601: a memória das IAs (autoria das mensagens); só enfileira, atrás da flag `memoria_ia`.
      Crm::MemoriaListener.instance,
      # #1813: o e-mail recebido completa o contato; só enfileira, atrás da flag `contato_pelo_email`.
      Autonomia::ContatoPeloEmailListener.instance,
      # #2212: a IA cuida dos comentários; só enfileira, atrás da flag `meta_ads_comentarios_ia`.
      Crm::MetaAdsComentariosIaListener.instance
    ]
  end
end

AsyncDispatcher.prepend_mod_with('AsyncDispatcher')
