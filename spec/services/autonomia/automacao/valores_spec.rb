require 'rails_helper'

RSpec.describe Autonomia::Automacao::Valores do
  let(:account) { create(:account) }
  let(:contato) { create(:contact, account: account, name: 'Maria', custom_attributes: { 'apolice.numero' => '991' }) }
  let(:conversa) { create(:conversation, account: account, contact: contato, custom_attributes: { 'origem' => 'anuncio' }) }
  let(:valores) { described_class.new(alvo: conversa) }

  it 'lê campos da conversa e do contato' do
    expect(valores.ler('conversa.id')).to eq(conversa.display_id)
    expect(valores.ler('mensagem.tipo')).to be_nil
    expect(valores.ler('conversa.caixa_id')).to eq(conversa.inbox_id)
    expect(valores.ler('contato.nome')).to eq('Maria')
  end

  it 'lê a mensagem do gatilho: recebida, enviada ou nota', :aggregate_failures do
    tipo = lambda do |message_type, privada = false|
      mensagem = build(:message, conversation: conversa, account: account, message_type: message_type, private: privada)
      described_class.new(alvo: conversa, mensagem: mensagem).ler('mensagem.tipo')
    end

    expect([tipo.call(:incoming), tipo.call(:outgoing), tipo.call(:outgoing, true)]).to eq(%w[recebida enviada nota])
  end

  # #2496: o salvar recusa o que não está em FECHADOS; se a lista e o que a mensagem devolve divergirem, a condição
  # certa seria recusada, ou a errada passaria e nunca casaria.
  it 'tem como opções da mensagem exatamente o que a mensagem pode valer', :aggregate_failures do
    lido = lambda do |caminho, message_type, privada|
      mensagem = build(:message, conversation: conversa, account: account, message_type: message_type, private: privada)
      described_class.new(alvo: conversa, mensagem: mensagem).ler(caminho)
    end
    formas = [[:incoming, false], [:outgoing, false], [:outgoing, true], [:template, false]]

    expect(described_class::FECHADOS.keys).to match_array(described_class::MENSAGEM.keys)
    described_class::FECHADOS.each do |caminho, fechado|
      expect(formas.map { |forma| lido.call(caminho, *forma) }.uniq).to match_array(fechado['opcoes'])
    end
  end

  it 'lê atributo personalizado pela chave, mesmo com ponto' do
    expect(valores.ler('conversa.atributos.origem')).to eq('anuncio')
    expect(valores.ler('contato.atributos.apolice.numero')).to eq('991')
    expect(valores.ler('contato.atributos.ausente')).to be_nil
  end

  it 'só aceita caminho da lista' do
    expect(described_class.caminho_valido?('contato.atributos.placa')).to be(true)
    expect(described_class.caminho_valido?('contato.atributos.')).to be(false)
    expect(described_class.caminho_valido?('contato.senha')).to be(false)
    expect { valores.ler('contato.senha') }.to raise_error(ArgumentError)
  end

  describe 'alvo card e contato (#2499)' do
    let(:funil) { create_crm_pipeline(account: account, user: create(:user, account: account, role: :administrator)) }
    let(:card) do
      novo_card(primary_conversation: conversa, title: 'Seguro auto', value_cents: 180_050, custom_attributes: { 'vencimento' => '2026-12-01' })
    end

    def novo_card(**atributos)
      Crm::Card.create!(account: account, pipeline: funil.first, stage: funil.last, title: 'Pedido', currency: 'BRL', contact: contato, **atributos)
    end

    it 'lê o card e, pelas pontes, a conversa principal e o contato', :aggregate_failures do
      valores = described_class.new(alvo: card)

      expect(valores.ler('card.titulo')).to eq('Seguro auto')
      expect(valores.ler('card.valor')).to eq(BigDecimal('1800.50'))
      expect(valores.ler('card.etapa_id')).to eq(card.stage_id)
      expect(valores.ler('card.atributos.vencimento')).to eq('2026-12-01')
      expect(valores.ler('conversa.id')).to eq(conversa.display_id)
      expect(valores.ler('contato.nome')).to eq('Maria')
    end

    it 'lê vazio quando a ponte falta: card sem conversa, contato sem card' do
      sem_conversa = novo_card(primary_conversation: nil)

      expect(described_class.new(alvo: sem_conversa).ler('conversa.status')).to be_nil
      expect(described_class.new(alvo: contato).ler('card.titulo')).to be_nil
      expect(described_class.new(alvo: contato).ler('contato.atributos.apolice.numero')).to eq('991')
    end

    it 'diz o que cada alvo alcança' do
      expect(described_class.no_alvo?('card.valor', 'Conversation')).to be(false)
      expect(described_class.no_alvo?('contato.nome', 'Crm::Card')).to be(true)
      expect(described_class.no_alvo?('conversa.status', 'Contact')).to be(false)
      expect(described_class.no_alvo?('mensagem.tipo', 'Conversation')).to be(true)
    end
  end
end
