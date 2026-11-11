require 'rails_helper'

# #2858: o que o Construtor e o cartão "pode ganhar" sugerem passa por DOIS filtros, que valem juntos (nota de merge da
# Funções, 11/11/2026): a fonte de uso interno não é sugerida (#2909, `Fonte#na_vitrine?` falso: Produtos das
# seguradoras), e a Premium também não (F7: consulta paga só entra no agente pela escolha de uma pessoa, na vitrine).
# A vitrine segue mostrando a Premium. O modelo é dublado: nenhuma chamada paga.
RSpec.describe Autonomia::FerramentasProntas, '.sugeriveis' do
  include FerramentasProntasHelper

  let(:account) { create(:account) }
  let(:agent) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Ana EXEMPLO', agent_type: 'sdr', instruction: 'Você cota seguro de carga.')
  end
  let(:interna) { 'produtos_seguradoras' }
  let(:premium) { Autonomia::FerramentasProntas::Catalogo.premium.map(&:chave) }
  # O que o modelo escolheria se pudesse: a de uso interno, duas Premium e duas grátis.
  let(:escolha_do_modelo) { [interna, 'historico_placa', 'conferir_pessoa', 'cep', 'corretor_susep'] }

  before do
    ligar_consultas(account)
    ligar_premium(account)
    account.enable_features!('agente_ferramentas_prontas_lote2', Autonomia::FerramentasProntas::FLAG_VITRINE,
                             Autonomia::FerramentasProntas::FLAG_CONSTRUTOR)
  end

  it 'as duas estão liberadas para a conta: a falta delas aqui não vem da flag' do
    disponiveis = described_class.disponiveis(account).map(&:chave)

    expect(disponiveis).to include(interna, *premium)
  end

  it 'a vitrine mostra a Premium e esconde a de uso interno' do
    da_vitrine = described_class.da_vitrine(account).map(&:chave)

    expect(da_vitrine).to include(*premium)
    expect(da_vitrine).not_to include(interna)
  end

  it 'as sugeríveis ficam sem as duas, e com as grátis da vitrine' do
    sugeriveis = described_class.sugeriveis(account).map(&:chave)

    expect(sugeriveis).not_to include(interna, *premium)
    expect(sugeriveis).to include('cep', 'corretor_susep')
    expect(sugeriveis).to eq(described_class.da_vitrine(account).reject(&:premium?).map(&:chave))
  end

  it 'o Construtor não oferece nem guarda nenhuma das duas' do
    sugeridas = Autonomia::Agents::Builder::ProntasSugeridas

    contexto = sugeridas.contexto(account)
    expect(contexto).to include('- cep:', '- corretor_susep:')
    ([interna] + premium).each { |chave| expect(contexto).not_to include("- #{chave}:") }

    dividido = sugeridas.dividir(account, { 'ferramentas_prontas' => escolha_do_modelo })
    expect(dividido).to eq(sugeridas: %w[cep corretor_susep], tambem: [])
  end

  it 'o cartão "pode ganhar" não oferece ao modelo nem mostra nenhuma das duas, mesmo guardadas pelo Construtor' do
    cliente = instance_double(Crm::Ai::ResponsesClient)
    allow(Crm::Ai::CredentialResolver).to receive(:new)
      .and_return(instance_double(Crm::Ai::CredentialResolver, resolve: { api_key: 'chave-de-teste', source: :system }))
    allow(Crm::Ai::ResponsesClient).to receive(:new).and_return(cliente)
    allow(cliente).to receive(:create).and_return({ text: { ferramentas: escolha_do_modelo }.to_json })

    expect(Autonomia::FerramentasProntas::SugestaoParaAgente.new(agent).call).to eq(%w[cep corretor_susep])
    expect(cliente).to have_received(:create) do |**kwargs|
      enum = kwargs[:schema][:schema][:properties][:ferramentas][:items][:enum]
      expect(enum).not_to include(interna, *premium)
      expect(enum).to include('cep')
    end

    agent.update!(config: { 'ferramentas_sugeridas' => escolha_do_modelo })
    Autonomia::FerramentasProntas::SugestaoParaAgente.semear_do_construtor!(agent)
    expect(Autonomia::FerramentasProntas::SugestaoParaAgente.para_tela(agent.reload)).to eq(%w[cep corretor_susep])
  end
end
