# frozen_string_literal: true

# #1786: a conversa de e-mail nova. Os arquivos do Chatwoot ficam intactos; os módulos do fork entram por cima:
# - resposta com histórico ou encaminhado formatado (app/builders/conversa_canal/message_builder_com_citacao.rb);
# - encaminhado com "Enc:" e fora do fio do cliente (app/mailers/conversa_canal/encaminhado_no_mailer.rb);
# - tradução pela IA da conta, num job, quando o Google Tradutor não está ligado
#   (app/controllers/concerns/conversa_canal/traducao_em_segundo_plano.rb);
# - Spam e Lixeira do painel nas listas de conversa, conversa nova de bloqueado direto no Spam e resposta do cliente
#   tirando a conversa da Lixeira (#1809);
# - "Encaminhar sem Para" na criação da conversa pela API devolve 422, não 500
#   (app/controllers/concerns/conversa_canal/recusa_do_email_na_api.rb);
# - conversa no Spam sem pesquisa de satisfação, sem o robô da caixa e sem automações (app/listeners/conversa_canal/
#   *_fora_do_spam.rb; opção (b) do Rodrigo, 18/10). Relatórios, CRM, webhooks da conta e LeadSquared seguem normais.
# - cópia do e-mail enviado pelo painel na pasta de enviados da conta do cliente, com a chave `email_enviados` (#1938,
#   app/services/conversa_canal/copia_no_enviados_no_envio.rb).
# - convite de reunião (parte text/calendar) guardado em content_attributes.email.convite (#1984;
#   app/services/conversa_canal/convite_no_email_recebido.rb); o convite antigo da mesma reunião, mudada ou cancelada
#   num e-mail mais novo, deixa de perguntar (#1995; app/services/conversa_canal/convite_substituido_na_mensagem.rb).
Rails.application.config.to_prepare do
  Messages::MessageBuilder.prepend(ConversaCanal::MessageBuilderComCitacao) unless Messages::MessageBuilder <= ConversaCanal::MessageBuilderComCitacao
  ConversationReplyMailer.prepend(ConversaCanal::EncaminhadoNoMailer) unless ConversationReplyMailer <= ConversaCanal::EncaminhadoNoMailer
  mensagens = Api::V1::Accounts::Conversations::MessagesController
  mensagens.prepend(ConversaCanal::TraducaoEmSegundoPlano) unless mensagens <= ConversaCanal::TraducaoEmSegundoPlano
  ConversationFinder.prepend(ConversaCanal::ConversationFinderComPastas) unless ConversationFinder <= ConversaCanal::ConversationFinderComPastas
  Conversation.include(ConversaCanal::SpamDoBloqueado) unless Conversation <= ConversaCanal::SpamDoBloqueado
  Message.prepend(ConversaCanal::PastaNaMensagemDoCliente) unless Message <= ConversaCanal::PastaNaMensagemDoCliente
  conversas = Api::V1::Accounts::ConversationsController
  conversas.include(ConversaCanal::RecusaDoEmailNaApi) unless conversas <= ConversaCanal::RecusaDoEmailNaApi
  CsatSurveyListener.prepend(ConversaCanal::PesquisaForaDoSpam) unless CsatSurveyListener <= ConversaCanal::PesquisaForaDoSpam
  AgentBotListener.prepend(ConversaCanal::RoboForaDoSpam) unless AgentBotListener <= ConversaCanal::RoboForaDoSpam
  AutomationRuleListener.prepend(ConversaCanal::AutomacaoForaDoSpam) unless AutomationRuleListener <= ConversaCanal::AutomacaoForaDoSpam
  envio = Email::SendOnEmailService
  envio.prepend(ConversaCanal::CopiaNoEnviadosNoEnvio) unless envio <= ConversaCanal::CopiaNoEnviadosNoEnvio
  MailPresenter.prepend(ConversaCanal::ConviteNoEmailRecebido) unless MailPresenter <= ConversaCanal::ConviteNoEmailRecebido
  Message.prepend(ConversaCanal::ConviteSubstituidoNaMensagem) unless Message <= ConversaCanal::ConviteSubstituidoNaMensagem
end
