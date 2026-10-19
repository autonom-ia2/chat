require 'rails_helper'

RSpec.describe Autonomia::ContatoPeloEmail::Freios do
  subject(:freios) { described_class.new(account_id: 7, contato_id: 9) }

  let(:chave_do_dia) { "#{described_class::PREFIXO}:teto:7:#{Time.now.utc.to_date.iso8601}" }

  before { Redis::Alfred.scan_each(match: "#{described_class::PREFIXO}:*") { |key| Redis::Alfred.delete(key) } }

  # Pega (LOW do #1813): o contador do teto ficar sem prazo e não zerar nunca.
  it 'o teto conta uma chamada por vez, numa chave que sempre expira', :aggregate_failures do
    2.times { expect(freios.dentro_do_teto?).to be(true) }

    expect(Redis::Alfred.get(chave_do_dia)).to eq('2')
    expect(Redis::Alfred.ttl(chave_do_dia)).to be_within(60).of((1.day + 1.hour).to_i)
  end

  # Pega: a pausa barrar o e-mail que chegou antes dela.
  it 'pausado? só para o e-mail que chegou depois do começo da pausa', :aggregate_failures do
    expect(freios.pausado?(Time.current)).to be(false)

    freios.pausar_por_nada_novo

    expect(freios.pausado?(1.minute.ago)).to be(false)
    expect(freios.pausado?(Time.current)).to be(true)
  end

  # Pega (revisão final): o "nada novo" de 24 h trocar a pausa de 30 dias dos automáticos.
  it 'a pausa curta não encurta a longa que já está valendo' do
    3.times { freios.automatico! }

    freios.pausar_por_nada_novo

    expect(Redis::Alfred.ttl("#{described_class::PREFIXO}:pausa:9")).to be > 24.hours.to_i
  end

  # Pega (revisão final): a chave da instalação pagar sem teto total.
  it 'o teto da instalação só conta com a chave da instalação', :aggregate_failures do
    chave_da_instalacao = "#{described_class::PREFIXO}:teto_instalacao:#{Time.now.utc.to_date.iso8601}"

    expect(freios.dentro_do_teto?).to be(true)
    expect(Redis::Alfred.get(chave_da_instalacao)).to be_nil

    Redis::Alfred.set(chave_da_instalacao, described_class::TETO_DIARIO_DA_INSTALACAO, ex: 60)
    expect(freios.dentro_do_teto?(chave_da_instalacao: true)).to be(false)
    expect(freios.dentro_do_teto?).to be(true)
  end
end
