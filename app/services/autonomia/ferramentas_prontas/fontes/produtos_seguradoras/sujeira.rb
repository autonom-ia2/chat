# O FILTRO DE SUJEIRA dos Produtos das seguradoras (#2858). O diretório de PRODUÇÃO do Open Insurance aponta endereços
# para servidor de teste (medido em 11/11/2026, nos três ramos: garantia pública 3, privada 3, transporte 1), e as
# seguradoras publicam link e produto de exemplo como se fossem reais. Sem este filtro, o agente erra com cara de verdade.
# Corta:
#   - o host de teste: um rótulo do host (as partes entre pontos e hífens) que é marca de teste ("api-hml",
#     "open-api-sandbox", "openinsurance-dev"). Rótulo inteiro, nunca pedaço de palavra: "devonseguros" passa;
#   - o link das condições que não abre (o da Bradesco sem pontuação, "HTTPSWWW…") ou que é de exemplo
#     (exemplo.com.br, www.seguradora.com.br, example.com, o próprio site do Open Insurance);
#   - o produto e a cobertura de sandbox ("Produto de Seguro", "string").
# Tudo por método de string, sem expressão regular.
module Autonomia::FerramentasProntas::Fontes::ProdutosSeguradoras::Sujeira
  # O rótulo inteiro do host que marca servidor de teste.
  # "apihm": o servidor de homologação da Caixa no diretório (MEDICAO.md), fora dos 3 ramos hoje.
  ROTULOS_DE_TESTE = %w[dev desenv uat qa stg stage staging test teste tst mock preprod hom apihm].freeze
  # O pedaço que, em qualquer ponto do rótulo, marca servidor de teste ("apihml", "homologacao").
  PEDACOS_DE_TESTE = %w[hml homolog sandbox].freeze
  # O domínio de exemplo (ele e os subdomínios dele): o da especificação, o genérico e o do próprio Open Insurance.
  DOMINIOS_DE_EXEMPLO = %w[exemplo.com.br example.com example.org example.net seguradora.com.br empresaa1.com
                           openinsurance.com.br].freeze
  PRODUTO_DE_EXEMPLO = 'produto de seguro'.freeze
  COBERTURA_DE_EXEMPLO = 'string'.freeze
  PONTO = '.'.freeze
  HIFEN = '-'.freeze

  module_function

  def servidor_de_teste?(host)
    rotulos = host.to_s.downcase.split(PONTO).flat_map { |parte| parte.split(HIFEN) }
    rotulos.any? { |rotulo| ROTULOS_DE_TESTE.include?(rotulo) || PEDACOS_DE_TESTE.any? { |pedaco| rotulo.include?(pedaco) } }
  end

  # O link abre (HTTPS, com host de domínio de verdade, sem espaço) e não é de exemplo.
  def link_das_condicoes?(link)
    texto = link.to_s.strip
    return false if texto.empty? || texto.include?(' ')

    destino = URI.parse(texto)
    destino.is_a?(URI::HTTPS) && destino.host.to_s.include?(PONTO) && !de_exemplo?(destino.host)
  rescue URI::InvalidURIError
    false
  end

  def de_exemplo?(host)
    nome = host.downcase
    DOMINIOS_DE_EXEMPLO.any? { |dominio| nome == dominio || nome.end_with?("#{PONTO}#{dominio}") }
  end

  def produto_de_exemplo?(nome)
    Autonomia::FerramentasProntas::Lista.comparavel(nome) == PRODUTO_DE_EXEMPLO
  end

  def cobertura_de_exemplo?(texto)
    Autonomia::FerramentasProntas::Lista.comparavel(texto) == COBERTURA_DE_EXEMPLO
  end
end
