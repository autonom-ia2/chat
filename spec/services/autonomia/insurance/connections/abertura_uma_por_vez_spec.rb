require 'rails_helper'

# UMA ABERTURA DE COTAÇÃO POR VEZ, POR CONEXÃO (chat#612). A trava é o que faz a segunda abertura encontrar o
# veredito de login da primeira no adapter, em vez de conferir as mesmas seguradoras ao mesmo tempo.
#
# "O outro processo" é uma conexão Postgres própria: nos testes transacionais o pool do Rails entrega a mesma sessão a
# todo mundo, e a trava consultiva é reentrante na mesma sessão.
RSpec.describe Autonomia::Insurance::Connections::AberturaUmaPorVez do
  let(:account) { create(:account) }
  let(:connection) do
    enable_test_encryption!
    Autonomia::Insurance::Connection.create!(account: account, username: 'c@x.com', password: 'segredo')
  end
  let(:outro_processo) { PG.connect(ActiveRecord::Base.connection.raw_connection.conninfo_hash.compact) }

  after { outro_processo.close }

  def sql(funcao)
    "SELECT #{funcao}(#{described_class::ESPACO}, #{connection.id})"
  end

  def travada_por_outro?
    livre = outro_processo.exec(sql('pg_try_advisory_lock')).getvalue(0, 0) == 't'
    outro_processo.exec(sql('pg_advisory_unlock')) if livre
    !livre
  end

  it 'segura a vez enquanto a abertura corre e a devolve no fim, mesmo quando a abertura levanta' do
    durante = nil

    expect { described_class.call(connection, pedido_em: Time.current) { (durante = travada_por_outro?) && raise('x') } }
      .to raise_error(RuntimeError)

    expect(durante).to be(true)
    expect(travada_por_outro?).to be(false)
  end

  it 'com a vez presa por outro, não abre e levanta sem dormir: o motor reagenda' do
    outro_processo.exec(sql('pg_advisory_lock'))
    abriu = false

    expect { described_class.call(connection, pedido_em: 10.seconds.ago) { abriu = true } }
      .to raise_error(described_class::SemAVez)

    expect(abriu).to be(false)
  end

  it 'com a vez presa e o pedido mais velho que o limite, segue sem ela e deixa no log' do
    outro_processo.exec(sql('pg_advisory_lock'))
    allow(Rails.logger).to receive(:warn)

    executou = described_class.call(connection, pedido_em: described_class::ESPERA_MAXIMA.ago - 1.second) { :abriu }

    expect(executou).to eq(:abriu)
    expect(Rails.logger).to have_received(:warn).with(/abertura sem a vez connection=#{connection.id}/)
  end

  it 'sem o instante do pedido não há quem reagende: segue sem a vez' do
    outro_processo.exec(sql('pg_advisory_lock'))

    expect(described_class.call(connection, pedido_em: nil) { :abriu }).to eq(:abriu)
  end

  it 'sem a vez é falha comum para o motor, antes da chamada paga (não é envio incerto)' do
    expect(described_class::SemAVez.ancestors).to include(StandardError)
    expect(described_class::SemAVez.ancestors).not_to include(Autonomia::Agents::Tools::Native::EnvioIncerto)
  end
end
