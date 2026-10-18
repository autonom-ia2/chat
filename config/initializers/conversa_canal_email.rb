# frozen_string_literal: true

# #1786: a conversa de e-mail nova. Os arquivos do Chatwoot ficam intactos; os módulos do fork entram por cima:
# - resposta com histórico ou encaminhado formatado (app/builders/conversa_canal/message_builder_com_citacao.rb);
# - tradução pela IA da conta quando o Google Tradutor não está ligado (app/services/conversa_canal/traducao_sem_google.rb).
Rails.application.config.to_prepare do
  Messages::MessageBuilder.prepend(ConversaCanal::MessageBuilderComCitacao) unless Messages::MessageBuilder <= ConversaCanal::MessageBuilderComCitacao
  tradutor = Integrations::GoogleTranslate::ProcessorService
  tradutor.prepend(ConversaCanal::TraducaoSemGoogle) unless tradutor <= ConversaCanal::TraducaoSemGoogle
end
