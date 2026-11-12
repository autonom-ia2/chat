require 'rails_helper'

# #2918: cada nativa do catálogo declara se ESCREVE (`escreve?`), na própria ferramenta; nunca pelo nome. Nas rodadas das
# prontas, a que escreve roda uma vez por turno (`Tools::UmaEscritaPorTurno`). Uma nativa nova sem a declaração reprova
# aqui: o padrão do `Base` (escrita) é só a rede de segurança.
RSpec.describe Autonomia::Agents::Tools::Native::Base do
  let(:nativas) { Autonomia::Agents::Tools::Native }
  let(:escrevem) do
    [nativas::InsuranceQuote, nativas::InsuranceQuoteProposal, nativas::AgendarReuniao, nativas::EnviarLocalizacao,
     nativas::EnviarContato, nativas::GuiaAcao, nativas::GuiaExecucao, nativas::GuiaLembrar, nativas::GuiaEsquecer,
     nativas::GuiaTarefa]
  end

  it 'toda nativa do catálogo declara escreve? na própria ferramenta' do
    sem_declaracao = Autonomia::Agents::Tools::Registry::TOOLS.select do |nativa|
      nativa.method(:escreve?).owner == described_class.singleton_class
    end

    expect(sem_declaracao).to be_empty
  end

  it 'escrevem as que marcam, mandam ao cliente, abrem cotação ou gravam na conta; as demais leem', :aggregate_failures do
    catalogo = Autonomia::Agents::Tools::Registry::TOOLS

    expect(catalogo.select(&:escreve?)).to match_array(escrevem)
    expect(catalogo.reject(&:escreve?)).to include(nativas::HorariosDisponiveis, nativas::CepLookup, nativas::GuiaLeitura)
  end

  it 'sem declaração, vale escrita (o lado seguro)' do
    expect(Class.new(described_class).escreve?).to be(true)
  end
end
