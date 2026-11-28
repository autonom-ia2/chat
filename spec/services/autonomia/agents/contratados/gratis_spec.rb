require 'rails_helper'

# #3270 — os 7 dias grátis do agente contratado, contados da PRIMEIRA contratação do modelo na conta, e a pausa depois
# deles sem a liberação do super admin. CAMINHO DO DINHEIRO: cada fronteira da contagem tem um exemplo.
RSpec.describe Autonomia::Agents::Contratados::Gratis do
  let(:account) { create(:account) }
  let(:chave) { 'seguro_viagem_universal' }
  let(:comeco) { Time.zone.local(2026, 11, 2, 10, 0, 0) }
  let(:marca) do
    { 'modelo' => chave, 'nome_agente' => 'Bia', 'nome_corretora' => 'Corretora Exemplo', 'sobre_corretora' => 'Desde 2010.' }
  end

  # O contratado nascido em `em` (o `created_at` é o começo do grátis).
  def contratar(quando:, conta: account)
    agente = Autonomia::Agents::Agent.create!(account: conta, name: 'Bia', agent_type: 'sdr', instruction: 'retrato',
                                              config: { 'contratado' => marca })
    agente.update_columns(created_at: quando) # rubocop:disable Rails/SkipsModelValidations
    agente
  end

  def liberar(conta = account)
    Autonomia::Agents::Contratados::Liberacao.atribuir(conta, [chave])
    conta.save!
  end

  def estado_em(momento) = described_class.estado(account, chave, agora: momento)

  it 'o preço e os dias grátis moram no catálogo: 7 dias e R$ 197,00 por mês' do
    modelo = Autonomia::Agents::Contratados::MODELOS.fetch(chave)

    expect(modelo.slice(:dias_gratis, :preco_mensal_centavos, :moeda)).to eq(dias_gratis: 7, preco_mensal_centavos: 19_700, moeda: 'BRL')
  end

  describe 'a contagem' do
    before { contratar(quando: comeco) }

    it 'dia 0: grátis, faltam os 7 dias' do
      expect(estado_em(comeco)).to have_attributes(situacao: 'gratis', dias_restantes: 7)
    end

    it 'dia 6 completo: falta 1' do
      expect(estado_em(comeco + 6.days)).to have_attributes(situacao: 'gratis', dias_restantes: 1)
    end

    it 'no último segundo do dia 7 ainda falta 1' do
      expect(estado_em(comeco + 7.days - 1.second)).to have_attributes(situacao: 'gratis', dias_restantes: 1)
    end

    it 'meio dia depois de contratar: faltam 7 (arredonda para cima)' do
      expect(estado_em(comeco + 12.hours)).to have_attributes(situacao: 'gratis', dias_restantes: 7)
    end

    it 'dia 7 completo: pausado, sem contagem' do
      expect(estado_em(comeco + 7.days)).to have_attributes(situacao: 'pausado', dias_restantes: nil)
    end

    it 'um mês depois: continua pausado' do
      expect(estado_em(comeco + 30.days)).to be_pausado
    end
  end

  it 'conta que nunca contratou: os dias inteiros, sem começar a contar' do
    expect(estado_em(comeco + 30.days)).to have_attributes(situacao: 'gratis', dias_restantes: 7)
  end

  describe 'a liberação do super admin' do
    before { contratar(quando: comeco) }

    it 'liberada, nunca pausa e não tem contagem' do
      liberar

      expect(estado_em(comeco)).to have_attributes(situacao: 'liberado', dias_restantes: nil)
      expect(estado_em(comeco + 7.days)).to have_attributes(situacao: 'liberado', dias_restantes: nil)
      expect(estado_em(comeco + 365.days)).not_to be_pausado
    end

    it 'desligada a liberação depois dos 7 dias, volta a pausar' do
      liberar
      Autonomia::Agents::Contratados::Liberacao.atribuir(account, [])
      account.save!

      expect(estado_em(comeco + 8.days)).to be_pausado
    end

    it 'a liberação de outra conta não vale nesta' do
      liberar(create(:account))

      expect(estado_em(comeco + 8.days)).to be_pausado
    end
  end

  describe 'contratar de novo não reinicia' do
    it 'o agente antigo apagado conta: o novo nasce com os dias que sobraram' do
      antigo = contratar(quando: comeco)
      Autonomia::Agents::SoftDelete.new(agent: antigo, actor: nil).perform
      contratar(quando: comeco + 5.days)

      expect(estado_em(comeco + 5.days)).to have_attributes(situacao: 'gratis', dias_restantes: 2)
    end

    it 'contratado de novo depois dos 7 dias: o novo nasce pausado' do
      antigo = contratar(quando: comeco)
      Autonomia::Agents::SoftDelete.new(agent: antigo, actor: nil).perform
      novo = contratar(quando: comeco + 10.days)

      expect(described_class.pausado?(novo, agora: comeco + 10.days)).to be(true)
    end

    it 'duas cópias na conta: vale a mais antiga' do
      contratar(quando: comeco + 3.days)
      contratar(quando: comeco)

      expect(described_class.inicio(account, chave)).to eq(comeco)
    end
  end

  it 'o contratado de outra conta não conta nesta' do
    contratar(quando: comeco, conta: create(:account))

    expect(described_class.inicio(account, chave)).to be_nil
  end

  it 'agente comum (não contratado) não conta e nunca está pausado' do
    comum = Autonomia::Agents::Agent.create!(account: account, name: 'Ana', agent_type: 'sdr')
    comum.update_columns(created_at: comeco) # rubocop:disable Rails/SkipsModelValidations

    expect(described_class.inicio(account, chave)).to be_nil
    expect(described_class.pausado?(comum, agora: comeco + 30.days)).to be(false)
    expect(described_class.pausado?(nil)).to be(false)
  end

  describe '.pausado?' do
    let(:agente) { contratar(quando: comeco) }

    it 'no grátis, não; depois dos 7 dias, sim; liberado, não' do
      expect(described_class.pausado?(agente, agora: comeco + 6.days)).to be(false)
      expect(described_class.pausado?(agente, agora: comeco + 7.days)).to be(true)
      liberar
      expect(described_class.pausado?(agente.reload, agora: comeco + 7.days)).to be(false)
    end
  end

  describe '.para_tela' do
    it 'o preço do catálogo e o estado da conta, com os nomes que a tela lê' do
      contratar(quando: comeco)
      travel_to(comeco + 4.days) do
        expect(described_class.para_tela(account, chave)).to eq(
          'dias_gratis' => 7, 'preco_mensal_centavos' => 19_700, 'moeda' => 'BRL', 'situacao' => 'gratis', 'dias_restantes' => 3
        )
      end
    end

    it 'pausado e liberado vão sem dias restantes' do
      contratar(quando: comeco)
      travel_to(comeco + 9.days) do
        expect(described_class.para_tela(account, chave)).to include('situacao' => 'pausado', 'dias_restantes' => nil)
        liberar
        expect(described_class.para_tela(account.reload, chave)).to include('situacao' => 'liberado', 'dias_restantes' => nil)
      end
    end
  end
end
