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

    expect { described_class.call(connection) { (durante = travada_por_outro?) && raise('x') } }.to raise_error(RuntimeError)

    expect(durante).to be(true)
    expect(travada_por_outro?).to be(false)
  end

  it 'com a vez presa por outro além do limite, segue sem ela e deixa no log' do
    stub_const("#{described_class}::ESPERA_MAXIMA", 0.3.seconds)
    stub_const("#{described_class}::INTERVALO", 0.1)
    outro_processo.exec(sql('pg_advisory_lock'))
    allow(Rails.logger).to receive(:warn)

    executou = described_class.call(connection) { :abriu }

    expect(executou).to eq(:abriu)
    expect(Rails.logger).to have_received(:warn).with(/abertura sem a vez connection=#{connection.id}/)
  end
end
