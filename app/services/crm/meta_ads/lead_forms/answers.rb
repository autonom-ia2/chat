# As respostas do formulário do anúncio da Meta (#2195) ficam no metadata do card, em meta_lead_form.fields, e trazem
# nome, telefone e e-mail de quem preencheu. Quem não vê o contato inteiro, e a IA, recebem só a origem (formulário,
# anúncio, campanha).
#
# A origem identifica o anúncio (#2558): ad_id, ad_name, campaign_name e também form_id e form_name, porque o nome do
# formulário é escolhido pelo anunciante e muitas vezes repete o da campanha. Quem não vê o anúncio de origem
# (Crm::AnuncioDeOrigem) recebe só a hora da captura, e as respostas pela regra de cima.
module Crm::MetaAds::LeadForms::Answers
  KEY = 'meta_lead_form'.freeze
  SEM_ANUNCIO = %w[captured_at fields].freeze

  module_function

  def without(metadata)
    return metadata unless lead_form?(metadata)

    metadata.merge(KEY => metadata[KEY].except('fields'))
  end

  def sem_anuncio(metadata)
    return metadata unless lead_form?(metadata)

    metadata.merge(KEY => metadata[KEY].slice(*SEM_ANUNCIO))
  end

  # O metadata do card para quem lê: sem as respostas, se não vê o contato inteiro; sem o anúncio, se não vê o anúncio.
  def para(metadata, contato_inteiro:, anuncio_visivel:)
    metadata = without(metadata) unless contato_inteiro
    anuncio_visivel ? metadata : sem_anuncio(metadata)
  end

  def lead_form?(metadata)
    metadata.is_a?(Hash) && metadata[KEY].is_a?(Hash)
  end
end
