require 'rails_helper'

# #1669: os invisíveis que somem antes de comparar (a categoria Cf e os de fora dela que passam por letra ou espaço
# vazio), a comparação sem diferenciar caixa e a posição em janelas, sem regex.
RSpec.describe Autonomia::Agents::Operate::TextoSemDisfarce do
  {
    'ZWSP (U+200B, Cf)' => 0x200B,
    'seletor de variação (U+FE0F)' => 0xFE0F,
    'seletor de variação suplementar (U+E0100)' => 0xE0100,
    'combinante que não junta (U+034F)' => 0x034F,
    'preenchimento do Hangul (U+3164)' => 0x3164,
    'preenchimento inicial do Hangul (U+115F)' => 0x115F,
    'preenchimento medial do Hangul (U+1160)' => 0x1160
  }.each do |nome, codepoint|
    it "tira #{nome} antes de comparar" do
      invisivel = [codepoint].pack('U')

      expect(described_class.normalizado("EQUI#{invisivel}PE#")).to eq('EQUIPE#')
      expect(described_class.contem?(described_class.normalizado("x EQ#{invisivel}UIPE# y"), 'equipe#')).to be(true)
    end
  end

  it 'mantém as quebras de linha e unifica os espaços de cada linha' do
    expect(described_class.normalizado("a  b\n\nc   d")).to eq("a b\n\nc d")
  end

  it 'acha a posição sem diferenciar caixa, a partir de um ponto' do
    expect(described_class.posicao('x ESCREVEU ao Cliente y escreveu ao cliente', 'escreveu ao cliente')).to eq(2)
    expect(described_class.posicao('x ESCREVEU ao Cliente y escreveu ao cliente', 'escreveu ao cliente', 3)).to eq(24)
    expect(described_class.posicao('nada aqui', 'escreveu ao cliente')).to be_nil
  end
end
