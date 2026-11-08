# Prepend em Conversations::FilterService (#1941, item 5): a conversa "Integração WhatsApp" do conector sai também dos
# filtros avançados e das visões salvas (Waha::IntegracaoDoConector). A contagem de não lidas das visões salvas
# (FilterQueryCounter, que tem a própria base) fica com Waha::NaoLidasSemIntegracao.
module Waha::FilterServiceSemIntegracao
  def base_relation
    super.fora_da_integracao_whatsapp
  end
end
