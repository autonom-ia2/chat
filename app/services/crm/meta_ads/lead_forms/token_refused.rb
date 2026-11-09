# A Meta recusou o token do cliente (código 190) numa leitura dos Formulários (#2740). Para a tela continua sendo
# `meta_refused`; quem lê em segundo plano usa `meta_message` para marcar a conexão (Crm::MetaAdsConnection#mark_invalid!,
# que limpa o texto), como o webhook leadgen já faz.
class Crm::MetaAds::LeadForms::TokenRefused < Crm::MetaAds::LeadForms::Error
  attr_reader :meta_message

  def initialize(meta_message = nil)
    @meta_message = meta_message
    super('meta_refused')
  end
end
