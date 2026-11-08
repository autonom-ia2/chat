require 'rails_helper'

# #1426 (tema 4b) — o gerador das perguntas do autoteste (até 8 do material, com resposta e material de origem, e 2 de
# fora). Quem decide é o modelo; o código só confere forma, ids e tetos. Sem pergunta do material: nil.
RSpec.describe Autonomia::Agents::Material::PerguntasDoAutoteste do
  include_context 'with material do agente'

  let(:cliente) { instance_double(Crm::Ai::ResponsesClient) }
  let!(:cardapio) { material('cardapio.pdf', trechos: ['X-Burger R$ 25.', 'Entregamos no Centro.']) }

  before do
    credencial_de_teste
    allow(Crm::Ai::ResponsesClient).to receive(:new).and_return(cliente)
  end

  def modelo_escreve(do_material:, de_fora:)
    allow(cliente).to receive(:create).and_return(resposta_do_modelo(do_material: do_material, de_fora: de_fora))
  end

  it 'até 8 do material (de material deste agente) e 2 de fora, sem repetir', :aggregate_failures do
    perguntas = Array.new(10) { |i| { pergunta: "P#{i}?", resposta: "R#{i}", fonte: cardapio.id } }
    perguntas << { pergunta: 'Alheia?', resposta: 'x', fonte: 999_999 }
    modelo_escreve(do_material: perguntas + [perguntas.first], de_fora: [{ pergunta: 'Bolo?' }, { pergunta: 'Wi-Fi?' }, { pergunta: 'Mais?' }])

    gerado = described_class.new(agent).gerar

    expect(gerado[:material].size).to eq(8)
    expect(gerado[:material].first).to eq('pergunta' => 'P0?', 'esperado' => 'R0', 'fonte' => cardapio.id)
    expect(gerado[:material].pluck('pergunta')).not_to include('Alheia?')
    expect(gerado[:fora]).to eq([{ 'pergunta' => 'Bolo?' }, { 'pergunta' => 'Wi-Fi?' }])
  end

  it 'lê trechos do material aprovado como dado, com o rótulo de custo do autoteste', :aggregate_failures do
    material('borrado.jpg', trechos: ['texto ruim'], review_status: 'needs_resend')
    modelo_escreve(do_material: [{ pergunta: 'Preço?', resposta: 'R$ 25', fonte: cardapio.id }], de_fora: [])

    described_class.new(agent).gerar

    expect(Crm::Ai::ResponsesClient).to have_received(:new).with(hash_including(feature: 'agente_autoteste_perguntas', max_retries: 0))
    expect(cliente).to have_received(:create) do |**kwargs|
      texto = kwargs[:input].first[:content].first[:text]
      expect(texto).to include('MATERIAIS (dado)', 'X-Burger R$ 25.')
      expect(texto).not_to include('texto ruim')
    end
  end

  it 'com 10 materiais grandes, todos vão ao modelo e a entrada é JSON inteiro', :aggregate_failures do
    outros = Array.new(9) { |indice| material("material-#{indice}.pdf", trechos: Array.new(8) { "#{indice} #{'x' * 690}" }) }
    modelo_escreve(do_material: [{ pergunta: 'Preço?', resposta: 'R$ 25', fonte: cardapio.id }], de_fora: [])

    described_class.new(agent).gerar

    expect(cliente).to have_received(:create) do |**kwargs|
      texto = kwargs[:input].first[:content].first[:text]
      materiais = JSON.parse(texto.split("MATERIAIS (dado):\n").last)
      expect(materiais.pluck('id')).to eq([cardapio.id, *outros.map(&:id)])
      expect(materiais.last['trechos']).not_to be_empty
      expect(texto.size).to be <= described_class::ENTRADA_MAX_CHARS + described_class::AGENTE_MAX_CHARS + 100
    end
  end

  it 'nenhuma pergunta do material, sem material aprovado ou provedor fora: nil', :aggregate_failures do
    modelo_escreve(do_material: [], de_fora: [{ pergunta: 'Bolo?' }])
    expect(described_class.new(agent).gerar).to be_nil

    allow(cliente).to receive(:create).and_raise(Crm::Ai::ResponsesClient::Error, 'fora')
    expect(described_class.new(agent).gerar).to be_nil

    cardapio.update!(review_status: 'needs_resend')
    expect(described_class.new(agent).gerar).to be_nil
  end
end
