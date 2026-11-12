# As conversas de pessoas da conta que quem pede pode LER: a regra de caixa, de funil e de função personalizada do
# Conversations::PermissionFilterService, com quem só lê incluído (for_reading, #1849). Uma regra só para o histórico do
# contato de hoje (Contacts::ConversationsController) e para a ficha de Relacionamentos (#2895).
# `pessoas`: um id de contato, vários, ou a consulta que os escolhe.
module Contacts::ConversasLegiveis
  def self.call(pessoas, user:, account:)
    Conversations::PermissionFilterService.new(account.conversations.where(contact_id: pessoas), user, account, for_reading: true).perform
  end
end
