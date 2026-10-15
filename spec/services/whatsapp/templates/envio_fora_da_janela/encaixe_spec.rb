require 'rails_helper'

# Follow-up livre agendado pela pessoa para mais de 24 h (decisão do Rodrigo, 15/10/2026: "IA encaixa num tipo"). Quem lê
# o texto é o Jev (dublê aqui); o código só confere que a resposta é um tipo da lista.
RSpec.describe Whatsapp::Templates::EnvioForaDaJanela::Encaixe do
  let(:account) { create(:account) }
  let(:jev) { instance_double(TypesafeAi::Decisor) }
  let(:texto) { 'Perguntar se o seguro do carro já foi emitido e avisar que a apólice chega por e-mail' }

  before do
    allow(TypesafeAi::Config).to receive(:configured?).and_return(true)
    allow(TypesafeAi::Decisor).to receive(:new).and_return(jev)
  end

  def resultado(resposta, certeza: 0.9)
    TypesafeAi::Decisor::Resultado.new(resposta: resposta, certeza: certeza, modelo: 'jev-1.13.0')
  end

  it 'devolve o tipo que o Jev escolheu, perguntando com todos os tipos e "nenhum"' do
    perguntas = []
    allow(jev).to receive(:decidir) do |decisor:, estado:|
      perguntas << { chaves: decisor.respostas.pluck('chave'), estado: estado.para_o_jev(decisor) }
      resultado('andamento')
    end

    expect(described_class.call(account: account, texto: texto)).to eq('andamento')
    expect(perguntas.sole[:chaves]).to match_array(Whatsapp::Templates::EnvioForaDaJanela::Tipos.todos.map(&:chave) + ['nenhum'])
    expect(perguntas.sole[:estado]).to include(text: texto)
    expect(TypesafeAi::Decisor).to have_received(:new).with(feature: 'modelo_compativel')
  end

  it 'nenhum tipo serve, ou o Jev sem certeza: nil (vira equipe no Followup)' do
    allow(jev).to receive(:decidir).and_return(resultado('nenhum'))
    expect(described_class.call(account: account, texto: texto)).to be_nil

    allow(jev).to receive(:decidir).and_return(resultado('andamento', certeza: 0.5))
    expect(described_class.call(account: account, texto: texto)).to be_nil
  end

  it 'resposta que não é tipo da lista: nil, nunca um tipo inventado' do
    allow(jev).to receive(:decidir).and_return(resultado('promocao_relampago'))

    expect(described_class.call(account: account, texto: texto)).to be_nil
  end

  it 'Jev sem chave ou fora do ar: nil, sem estourar' do
    allow(jev).to receive(:decidir).and_raise(TypesafeAi::Decisor::Error, 'typesafe_unavailable')
    expect(described_class.call(account: account, texto: texto)).to be_nil

    allow(TypesafeAi::Config).to receive(:configured?).and_return(false)
    expect(described_class.call(account: account, texto: texto)).to be_nil
  end

  describe 'cache de 24 h por conta e texto' do
    before { allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::MemoryStore.new) }

    it 'a 2ª chamada com o mesmo texto (mesmo com espaços nas pontas) não paga a IA; texto diferente paga' do
      allow(jev).to receive(:decidir).and_return(resultado('andamento'))

      expect(described_class.call(account: account, texto: texto)).to eq('andamento')
      expect(described_class.call(account: account, texto: "  #{texto}\n")).to eq('andamento')
      expect(jev).to have_received(:decidir).once

      described_class.call(account: account, texto: 'Avisar que o boleto venceu ontem')
      expect(jev).to have_received(:decidir).twice
    end

    it 'guarda também o "nenhum"' do
      allow(jev).to receive(:decidir).and_return(resultado('nenhum'))

      2.times { expect(described_class.call(account: account, texto: texto)).to be_nil }
      expect(jev).to have_received(:decidir).once
    end

    it 'outra conta com o mesmo texto paga a própria pergunta' do
      allow(jev).to receive(:decidir).and_return(resultado('andamento'))

      described_class.call(account: account, texto: texto)
      described_class.call(account: create(:account), texto: texto)

      expect(jev).to have_received(:decidir).twice
    end

    it 'Jev fora do ar não fica guardado: a próxima chamada pergunta de novo' do
      allow(jev).to receive(:decidir).and_raise(TypesafeAi::Decisor::Error, 'typesafe_unavailable')

      2.times { expect(described_class.call(account: account, texto: texto)).to be_nil }
      expect(jev).to have_received(:decidir).twice
    end
  end

  it 'texto vazio não pergunta' do
    allow(jev).to receive(:decidir)

    expect(described_class.call(account: account, texto: '  ')).to be_nil
    expect(jev).not_to have_received(:decidir)
  end
end
