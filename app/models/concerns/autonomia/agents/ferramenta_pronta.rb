# A FERRAMENTA PRONTA dentro da tabela das ferramentas do agente (#2858, F0). Com `fonte_pronta`, a linha aponta para
# uma fonte do catálogo (`Autonomia::FerramentasProntas::Catalogo`), e não para um link: o endereço, os cabeçalhos e o
# formato dos parâmetros são do catálogo, e o que fica na linha é só a fonte, a frase "Use quando…" (`description`), o
# liga/desliga e o prazo. Quem cria é o "Incluir" (`FerramentasProntas::Incluir`); o cadastro manual não a enxerga
# (`manuais`).
module Autonomia::Agents::FerramentaPronta
  extend ActiveSupport::Concern

  included do
    scope :manuais, -> { where(fonte_pronta: nil) }

    validate :validate_fonte_pronta, if: :pronta?
  end

  def pronta?
    fonte_pronta.present?
  end

  def fonte_do_catalogo
    Autonomia::FerramentasProntas::Catalogo.buscar(fonte_pronta) if pronta?
  end

  private

  def schema_da_pronta
    fonte_do_catalogo.openai_schema(slug: slug, usar_quando: description)
  end

  # A fonte existe no catálogo e a linha não carrega nada do cadastro manual (link, cabeçalho, corpo, recorte): a pronta
  # nunca manda à fonte o que alguém digitou.
  def validate_fonte_pronta
    return errors.add(:fonte_pronta, :inclusion) if fonte_do_catalogo.nil?

    manuais = { endpoint_url: endpoint_url.presence, headers_config: headers_config.presence,
                request_body_template: request_body_template.presence, response_mapping: response_mapping.presence,
                param_schema: param_schema.presence }
    manuais.compact.each_key { |campo| errors.add(campo, :present) }
  end
end
