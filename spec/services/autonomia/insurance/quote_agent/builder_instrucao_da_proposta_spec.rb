require 'rails_helper'

# A INSTRUÇÃO DA LIA E A PROPOSTA INDIVIDUAL (entrega 8 do Agente de Cotação, #396).
#
# Até 12/09/2026 `principal.md` proibia "gerar proposta", listava "não propõe" entre as proibições e
# mandava ESCALAR em "gostei dessa". A proposta em PDF da seguradora que cotou passou a ser dela
# (`proposta_da_seguradora`); o que continua com pessoa é emitir, contratar e pagar. O que esta spec
# guarda não é o texto: é que ele NÃO PROMETE O QUE O CÓDIGO NÃO TEM e NÃO PROÍBE O QUE O CÓDIGO
# FAZ — cada promessa amarrada, pela frase exata, ao que a sustenta (a mesma régua de
# `builder_instrucao_do_especialista_spec`). Sem md5: a §7 do mesmo arquivo é da entrega 9, e um
# carimbo aqui faria as duas entregas brigarem pela mesma linha.
module InstrucaoDaProposta
  ARQUIVO = Autonomia::Insurance::QuoteAgent::Builder::INSTRUCOES.join('principal.md')
  SLUG = Autonomia::Agents::Tools::Native::InsuranceProposal.slug

  module_function

  def builder
    Autonomia::Insurance::QuoteAgent::Builder
  end

  def ferramenta
    Autonomia::Agents::Tools::Registry.find(SLUG)
  end

  # CADA PROMESSA, PELA FRASE EXATA, E O QUE A SUSTENTA. Se a frase sumir, o exemplo reprova; se a
  # capacidade sumir do código, o exemplo reprova.
  PROMESSAS = {
    # A quarta ferramenta é a da proposta: está no catálogo, é do principal e é assíncrona.
    "### `#{SLUG}`" => -> { ferramenta.present? && builder::TOOLS_DO_PRINCIPAL.include?(SLUG) && ferramenta.async? },
    # "Quatro" = as três do principal mais os especialistas de ramo (uma função por ramo).
    'Você tem quatro.' => -> { builder::TOOLS_DO_PRINCIPAL.size == 3 },
    # Uma ou duas por vez é regra da ferramenta, não do texto.
    'com uma ou duas seguradoras por vez' => -> { ferramenta::MAX_SEGURADORAS == 2 },
    # O nome vai como saiu na lista: é o mapa `nomes_entregues` que a cotação grava.
    'como saiu na lista de preços' => -> { Autonomia::Agents::Tools::Native::InsuranceQuote::NOMES_KEY == 'nomes_entregues' },
    # As recusas que o texto ensina a tratar existem, com frase no catálogo.
    'há mais de uma com aquele nome' => -> { Autonomia::Agents::Tools::Recusa::MOTIVOS.key?('seguradora_ambigua') },
    'aquela não cotou' => -> { Autonomia::Agents::Tools::Recusa::MOTIVOS.key?('seguradora_nao_cotou') },
    # TERMO 3, pela frase inteira (mutação M3 da rodada de correção): invertida para "mande a
    # comparação no lugar", a instrução mandaria o modelo fazer o que o termo proíbe.
    'nunca mande a comparação no lugar, em silêncio' => -> { Autonomia::Agents::Tools::Recusa::MOTIVOS.key?('seguradora_nao_cotou') },
    # A origem que mudou debaixo do pedido (rodada de correção, P1 do Codex): as duas recusas existem.
    'cotação foi refeita ou ainda está em andamento' => lambda {
      Autonomia::Agents::Tools::Recusa::MOTIVOS.key?('cotacao_substituida') && Autonomia::Agents::Tools::Recusa::MOTIVOS.key?('cotacao_em_andamento')
    },
    # "Gostei dessa" deixa de escalar: vira a proposta daquela seguradora.
    'primeiro entregue a proposta daquela seguradora' => -> { builder::TOOLS_DO_PRINCIPAL.include?(SLUG) }
  }.freeze

  # O que o texto NÃO pode mais dizer: a proposta era proibida, e agora é dela.
  PROIBICOES_REVOGADAS = ['gerar proposta', 'não propõe'].freeze

  # O que o texto CONTINUA proibindo: emitir e pagar são com pessoa.
  PROIBICOES_MANTIDAS = ['Emitir apólice', 'Não emite, não cobra', 'Nunca peça dado de emissão antes de escalar'].freeze
end

RSpec.describe Autonomia::Insurance::QuoteAgent::Builder do
  let(:texto) { InstrucaoDaProposta::ARQUIVO.read }

  describe 'promessa e capacidade' do
    InstrucaoDaProposta::PROMESSAS.each do |frase, sustenta|
      it "«#{frase}» tem o que a sustenta" do
        expect(texto).to include(frase)
        expect(sustenta.call).to be_truthy
      end
    end
  end

  describe 'proposta não é emissão' do
    InstrucaoDaProposta::PROIBICOES_REVOGADAS.each do |frase|
      it "não proíbe mais «#{frase}»" do
        expect(texto).not_to include(frase)
      end
    end

    InstrucaoDaProposta::PROIBICOES_MANTIDAS.each do |frase|
      it "continua proibindo «#{frase}»" do
        expect(texto).to include(frase)
      end
    end
  end

  # O TEXTO SÓ DOCUMENTA POR SLUG O QUE EXISTE (`builder_spec` já varre os `###`); aqui, o inverso: a
  # ferramenta do principal que o texto não ensina a usar é capacidade que o agente tem e não sabe.
  it 'ensina, por slug, cada ferramenta do principal' do
    citadas = texto.scan(/^### `([a-z_]+)`$/).flatten

    expect(citadas).to match_array(described_class::TOOLS_DO_PRINCIPAL)
  end
end
