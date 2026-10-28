# A Meta não respondeu agora (rede, 5xx, limite de uso, #2195): a tela diz "tente de novo" e o job tenta de novo.
class Crm::MetaAds::LeadForms::Unavailable < Crm::MetaAds::LeadForms::Error
  def initialize
    super('meta_unavailable')
  end
end
