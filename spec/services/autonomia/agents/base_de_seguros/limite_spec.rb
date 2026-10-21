require 'rails_helper'

# F3 do tema 8 (#1429): o limite do antes e depois. O dia das 10 comparações por conta é o dia NO FUSO DA CONTA (o mesmo
# dos relatórios e do painel, Crm::Timezone::Resolver), não o da aplicação: quem compara às 22h em São Paulo ainda está
# no mesmo dia, e a meia-noite local libera.
RSpec.describe Autonomia::Agents::BaseDeSeguros::Limite do
  let(:conta) { create(:account) }
  let(:agentes) { Array.new(described_class::POR_DIA + 1) { |indice| criar_principal(conta, nome: "Agente #{indice}") } }

  around { |example| with_modified_env(AUTONOMIA_AGENTS_ENABLED: 'true') { example.run } }

  before { conta.update!(reporting_timezone: 'America/Sao_Paulo') }

  after do
    Redis::Alfred.delete(described_class.chave_da_conta(conta))
    agentes.each { |agente| described_class.liberar!(agente) }
  end

  def gastar_o_dia
    agentes.first(described_class::POR_DIA).each { |agente| described_class.reservar!(agente) }
  end

  it 'às 22h em São Paulo (01h UTC do dia seguinte) conta no dia local, e a 11ª é recusada' do
    travel_to Time.utc(2026, 10, 22, 1, 0)

    expect(described_class.chave_da_conta(conta)).to end_with(':2026-10-21')
    gastar_o_dia
    expect { described_class.reservar!(agentes.last) }.to raise_error(described_class::Excedido) { |erro| expect(erro.motivo).to eq('amanha') }
  end

  it 'a meia-noite local libera' do
    travel_to Time.utc(2026, 10, 22, 1, 0)
    gastar_o_dia

    travel_to Time.utc(2026, 10, 22, 3, 30) # 00h30 de 22/10 em São Paulo

    expect(described_class.chave_da_conta(conta)).to end_with(':2026-10-22')
    expect { described_class.reservar!(agentes.last) }.not_to raise_error
  end

  it 'a contagem do dia expira com o dia local, não um prazo fixo' do
    travel_to Time.utc(2026, 10, 22, 1, 0) # 22h em São Paulo: faltam 2 horas para a meia-noite local

    described_class.reservar!(agentes.first)

    ttl = Redis::Alfred.ttl(described_class.chave_da_conta(conta))
    expect(ttl).to be_between(1, 3.hours.to_i)
  end

  it 'conta sem fuso usa o padrão do produto (o mesmo do painel)' do
    conta.update!(reporting_timezone: nil)
    travel_to Time.utc(2026, 10, 22, 1, 0)

    padrao = Crm::Timezone::Resolver.default_timezone
    hoje = Time.current.in_time_zone(padrao).to_date
    expect(described_class.chave_da_conta(conta)).to end_with(":#{hoje.iso8601}")
  end

  it 'o aviso do dia diz em palavras simples quando libera, sem hora' do
    expect(I18n.t('autonomia.base_de_seguros.comparar_amanha', locale: :pt_BR)).to include('Amanhã você pode atualizar de novo.')
    expect(I18n.t('autonomia.base_de_seguros.comparar_amanha', locale: :en)).to include('You can update again tomorrow.')
    expect(I18n.t('autonomia.base_de_seguros.comparar_amanha', locale: :pt_BR)).not_to include('UTC')
  end
end
