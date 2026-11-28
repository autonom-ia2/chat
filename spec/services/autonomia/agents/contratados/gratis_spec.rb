require 'rails_helper'

# #3270 — os 7 dias grátis do agente contratado, contados da PRIMEIRA contratação do modelo na conta, e a pausa depois
# deles sem a liberação do super admin. CAMINHO DO DINHEIRO: cada fronteira da contagem tem um exemplo.
RSpec.describe Autonomia::Agents::Contratados::Gratis do
  let(:account) { create(:account) }
  let(:chave) { 'seguro_viagem_universal' }
  # 10:00 UTC = 07:00 de 02/11 em São Paulo, o fuso da conta (Crm::Timezone::Resolver, sem fuso na conta: o padrão).
  # O último dia grátis é 09/11, inteiro, no fuso da conta; a pausa começa à meia-noite de 10/11.
  let(:comeco) { Time.zone.local(2026, 11, 2, 10, 0, 0) }
  let(:sao_paulo) { ActiveSupport::TimeZone['America/Sao_Paulo'] }
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

  # Um modelo novo sem preço quebraria o turno de todo agente dele (`Gratis.estado` lê os três com fetch): o catálogo
  # inteiro precisa deles, com valores que fazem sentido.
  it 'todo modelo do catálogo diz os dias grátis, o preço em centavos e a moeda' do
    Autonomia::Agents::Contratados::MODELOS.each do |chave_do_modelo, modelo|
      expect(modelo).to include(:dias_gratis, :preco_mensal_centavos, :moeda), chave_do_modelo
      expect(modelo[:dias_gratis]).to be_a(Integer).and(be >= 0)
      expect(modelo[:preco_mensal_centavos]).to be_a(Integer).and(be_positive)
      expect(modelo[:moeda]).to be_a(String).and(be_present)
    end
  end

  describe 'a contagem' do
    before { contratar(quando: comeco) }

    it 'no dia em que contratou, a qualquer hora: faltam os 7 dias' do
      expect(estado_em(comeco)).to have_attributes(situacao: 'gratis', dias_restantes: 7)
      expect(estado_em(sao_paulo.local(2026, 11, 2, 23, 59, 59))).to have_attributes(situacao: 'gratis', dias_restantes: 7)
    end

    it 'na véspera do último dia: falta 1' do
      expect(estado_em(sao_paulo.local(2026, 11, 8, 0, 0, 0))).to have_attributes(situacao: 'gratis', dias_restantes: 1)
      expect(estado_em(sao_paulo.local(2026, 11, 8, 23, 59, 59))).to have_attributes(situacao: 'gratis', dias_restantes: 1)
    end

    it 'o último dia vale inteiro: 0 da meia-noite às 23:59:59, mesmo depois da hora em que contratou' do
      expect(estado_em(sao_paulo.local(2026, 11, 9, 0, 0, 0))).to have_attributes(situacao: 'gratis', dias_restantes: 0)
      expect(estado_em(comeco + 7.days)).to have_attributes(situacao: 'gratis', dias_restantes: 0)
      expect(estado_em(sao_paulo.local(2026, 11, 9, 23, 59, 59))).to have_attributes(situacao: 'gratis', dias_restantes: 0)
    end

    it 'à meia-noite do dia seguinte ao último: pausado, sem contagem' do
      expect(estado_em(sao_paulo.local(2026, 11, 10, 0, 0, 0))).to have_attributes(situacao: 'pausado', dias_restantes: nil)
    end

    it 'um mês depois: continua pausado' do
      expect(estado_em(comeco + 30.days)).to be_pausado
    end
  end

  # A hora da contratação não muda o último dia: conta o dia do calendário em que contratou, no fuso da conta.
  describe 'a hora da contratação' do
    it 'contratou às 00:05: o grátis vai até 23:59:59 do 7º dia depois' do
      contratar(quando: sao_paulo.local(2026, 11, 2, 0, 5, 0))

      expect(estado_em(sao_paulo.local(2026, 11, 9, 23, 59, 59))).to have_attributes(situacao: 'gratis', dias_restantes: 0)
      expect(estado_em(sao_paulo.local(2026, 11, 10, 0, 0, 0))).to be_pausado
    end

    it 'contratou às 23:50 (já 02:50 do dia seguinte em UTC): o último dia é o mesmo, pelo dia de São Paulo' do
      contratar(quando: sao_paulo.local(2026, 11, 2, 23, 50, 0))

      expect(estado_em(sao_paulo.local(2026, 11, 2, 23, 55, 0))).to have_attributes(situacao: 'gratis', dias_restantes: 7)
      expect(estado_em(sao_paulo.local(2026, 11, 9, 23, 59, 59))).to have_attributes(situacao: 'gratis', dias_restantes: 0)
      expect(estado_em(sao_paulo.local(2026, 11, 10, 0, 0, 0))).to be_pausado
    end
  end

  describe 'conta com outro fuso (Tóquio, UTC+9)' do
    let(:toquio) { ActiveSupport::TimeZone['Asia/Tokyo'] }

    before { account.update!(reporting_timezone: 'Asia/Tokyo') }

    # 20:00 de 02/11 em São Paulo (23:00 UTC) já é 08:00 de 03/11 em Tóquio: o dia da contratação é 03/11.
    it 'o dia da contratação, o último dia e a meia-noite da pausa são os do fuso da conta' do
      contratar(quando: toquio.local(2026, 11, 3, 8, 0, 0))

      expect(estado_em(toquio.local(2026, 11, 3, 8, 0, 0))).to have_attributes(situacao: 'gratis', dias_restantes: 7)
      expect(estado_em(toquio.local(2026, 11, 10, 23, 59, 59))).to have_attributes(situacao: 'gratis', dias_restantes: 0)
      expect(estado_em(toquio.local(2026, 11, 11, 0, 0, 0))).to be_pausado
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
      expect(described_class.pausado?(agente, agora: comeco + 7.days)).to be(false)
      expect(described_class.pausado?(agente, agora: comeco + 8.days)).to be(true)
      liberar
      expect(described_class.pausado?(agente.reload, agora: comeco + 8.days)).to be(false)
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
