# As respostas do formulário do anúncio da Meta (#2195) ficam no metadata do card, em meta_lead_form.fields, e trazem
# nome, telefone e e-mail de quem preencheu. Quem não vê o contato inteiro, e a IA, recebem só a origem (formulário,
# anúncio, campanha).
module Crm::MetaAds::LeadForms::Answers
  KEY = 'meta_lead_form'.freeze

  module_function

  def without(metadata)
    return metadata unless metadata.is_a?(Hash) && metadata[KEY].is_a?(Hash)

    metadata.merge(KEY => metadata[KEY].except('fields'))
  end
end
