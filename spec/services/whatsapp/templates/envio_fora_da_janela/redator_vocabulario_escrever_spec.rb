require 'rails_helper'

# #2034: o modelo que a IA escreve fora das 24 h nasce no vocabulário da conta (pacote do servidor, #1550). O redator
# não lê conversa: o pedido ao modelo ganha a linha da conta, sem mudar nada para conta sem pacote.
RSpec.describe Whatsapp::Templates::EnvioForaDaJanela::Redator, '#escrever' do
  let(:nicho) { Autonomia::Agents::Nicho }
  let(:perfil) { 'corretora' }
  let!(:account_and_user) { create_account_and_user }
  let(:account) { account_and_user.first }
  let(:inbox) { create_crm_whatsapp_api_inbox(account: account) }
  let(:tipo) { Whatsapp::Templates::EnvioForaDaJanela::Tipos.buscar('retorno') }
  let(:pacote) { 'true' }
  let(:pedidos) { [] }
  let(:linha_corretora) do
    'Fale como a corretora: diga corretor, cotação e apólice; chame de cliente só quem já contratou e de segurado só quem tem apólice.'
  end

  around do |example|
    GlobalConfig.clear_cache(nicho::PADRAO_KEY)
    with_modified_env(AUTONOMIA_PACOTES_ENABLED: pacote) { example.run }
  ensure
    GlobalConfig.clear_cache(nicho::PADRAO_KEY)
  end

  before do
    account.update!(internal_attributes: { nicho::NICHO_KEY => 'seguros', nicho::PERFIL_KEY => perfil })
    allow(Ai::Redacao::Escrever).to receive(:call) do |**args|
      pedidos << args[:pedido]
      { opcoes: [] }
    end
  end

  def pedido_escrito
    described_class.new(inbox: inbox, tipo: tipo).escrever
    pedidos.sole
  end

  it 'a corretora recebe a linha dela no pedido, depois da regra do tipo' do
    pedido = pedido_escrito

    expect(pedido).to include(tipo.proposito, linha_corretora)
    expect(pedido.index(linha_corretora)).to be > pedido.index(tipo.proposito)
  end

  describe 'com o perfil saude_beneficios' do
    let(:perfil) { 'saude_beneficios' }

    it 'recebe a linha da saúde, que nunca diz segurado' do
      expect(pedido_escrito).to include('Fale de plano, vidas, titular e dependentes')
    end
  end

  it 'a linha vem no fim do pedido, depois de "só o corpo"' do
    expect(pedido_escrito).to end_with("#{described_class::SO_CORPO} #{linha_corretora}")
  end

  describe 'com o interruptor de pacotes desligado' do
    let(:pacote) { nil }

    it 'o pedido é o de sempre' do
      regra = described_class::REGRA_DA_CATEGORIA.fetch(tipo.categoria)

      expect(pedido_escrito).to eq([tipo.proposito, regra, described_class::SO_CORPO].join(' '))
    end
  end

  describe 'em conta fora do nicho de seguros, com os pacotes ligados' do
    before { account.update!(internal_attributes: {}) }

    it 'o pedido é o de sempre' do
      regra = described_class::REGRA_DA_CATEGORIA.fetch(tipo.categoria)

      expect(pedido_escrito).to eq([tipo.proposito, regra, described_class::SO_CORPO].join(' '))
    end
  end
end
