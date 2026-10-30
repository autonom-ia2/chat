# The bell when a search by conversation ends (#2277): the person may have left the screen ("Pode sair desta tela.
# A procura continua e avisamos no sininho quando terminar"). Rings for the person who asked, when the list is
# ready and also when it stopped by itself (ceiling or AI error), since then it waits for them. In-app only: no
# e-mail or push flag, the notification just shows in the bell.
module ConversationAudience::Bell
  RINGS_ON = [ConversationAudienceSearch::DONE, ConversationAudienceSearch::CEILING, ConversationAudienceSearch::FAILED].freeze

  module_function

  def ring(search)
    return unless RINGS_ON.include?(search.status) && search.user.present?
    return unless search.account.account_users.exists?(user_id: search.user_id)

    Notification.create!(notification_type: 'conversation_audience_ready', user: search.user, account: search.account,
                         primary_actor: search)
  end
end
