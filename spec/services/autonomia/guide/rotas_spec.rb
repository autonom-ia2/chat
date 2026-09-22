require 'rails_helper'

# As configurações da PRÓPRIA conta (nome, idioma, fuso) entravam no catálogo
# com o caminho inteiro, e o Guia montava `/api/v1/accounts/16//api/v1/...`:
# "muda o fuso da conta" falhava calado (#593). Aqui, contra a aplicação.
RSpec.describe Autonomia::Guide::Rotas do
  let(:conta_e_admin) { create_account_and_user }
  let(:conta) { conta_e_admin.first }
  let(:admin) { conta_e_admin.last }

  describe 'de rota para recurso' do
    it 'traduz as rotas de dentro da conta e as da própria conta', :aggregate_failures do
      expect(described_class.recurso('/api/v1/accounts/:account_id/inboxes/:id')).to eq('inboxes/:id')
      expect(described_class.recurso('/api/v1/accounts/:id')).to eq('conta')
      expect(described_class.recurso('/api/v1/accounts/:id/cache_keys')).to eq('conta/cache_keys')
      expect(described_class.recurso('/api/v1/profile')).to be_nil
    end

    it 'monta o endereço sempre com o id da conta de quem pergunta', :aggregate_failures do
      expect(described_class.caminho(16, %w[inboxes 3])).to eq('/api/v1/accounts/16/inboxes/3')
      expect(described_class.caminho(16, %w[conta])).to eq('/api/v1/accounts/16')
    end
  end

  it 'nenhum recurso dos catálogos sai com o caminho inteiro', :aggregate_failures do
    leituras = Autonomia::Guide::Consulta.new(account: conta, user: admin).catalogo
    acoes = Autonomia::Guide::Acoes.new(account: conta, user: admin).catalogo

    expect(leituras.select { |r| r.start_with?('/') }).to eq([])
    expect(acoes.select { |a| a.split(' ', 2).last.start_with?('/') }).to eq([])
    expect(leituras).to include('conta')
    expect(acoes).to include('PATCH conta')
  end

  it 'lê as configurações da própria conta' do
    expect(Autonomia::Guide::Consulta.new(account: conta, user: admin).ler('conta')).to include(conta.name)
  end

  it 'muda as configurações da própria conta, depois de confirmado', :aggregate_failures do
    acoes = Autonomia::Guide::Acoes.new(account: conta, user: admin)
    dados = { corpo: { name: 'Corretora Nova' }, descricao: 'Renomear a conta para Corretora Nova.' }

    expect(acoes.descrever('PATCH conta', dados)[:frase]).to include('Corretora Nova')
    expect(acoes.executar('PATCH conta', dados).ok).to be(true)
    expect(conta.reload.name).to eq('Corretora Nova')
  end
end
