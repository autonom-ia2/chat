# Erro dos Formulários dos anúncios (#2195). `code` é o que a tela recebe; nunca a mensagem da Meta.
class Crm::MetaAds::LeadForms::Error < StandardError
  attr_reader :code

  def initialize(code)
    @code = code
    super(code)
  end
end
