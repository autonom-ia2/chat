# frozen_string_literal: true

# #1786: a conversa de e-mail nova. Os arquivos do Chatwoot ficam intactos; os módulos do fork entram por cima:
# - resposta com histórico ou encaminhado formatado (app/builders/conversa_canal/message_builder_com_citacao.rb);
# - encaminhado com "Enc:" e fora do fio do cliente (app/mailers/conversa_canal/encaminhado_no_mailer.rb);
# - tradução pela IA da conta quando o Google Tradutor não está ligado (app/services/conversa_canal/traducao_sem_google.rb);
# - Spam e Lixeira do painel nas listas de conversa e conversa nova de bloqueado direto no Spam (#1809).
Rails.application.config.to_prepare do
  Messages::MessageBuilder.prepend(ConversaCanal::MessageBuilderComCitacao) unless Messages::MessageBuilder <= ConversaCanal::MessageBuilderComCitacao
  ConversationReplyMailer.prepend(ConversaCanal::EncaminhadoNoMailer) unless ConversationReplyMailer <= ConversaCanal::EncaminhadoNoMailer
  tradutor = Integrations::GoogleTranslate::ProcessorService
  tradutor.prepend(ConversaCanal::TraducaoSemGoogle) unless tradutor <= ConversaCanal::TraducaoSemGoogle
  ConversationFinder.prepend(ConversaCanal::ConversationFinderComPastas) unless ConversationFinder <= ConversaCanal::ConversationFinderComPastas
  Conversation.include(ConversaCanal::SpamDoBloqueado) unless Conversation <= ConversaCanal::SpamDoBloqueado
end
