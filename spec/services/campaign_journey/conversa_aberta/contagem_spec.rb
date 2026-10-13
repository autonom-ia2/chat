require 'rails_helper'

# #1335: quantas pessoas do público falaram com a caixa nas últimas 24 h, com o preço do modelo, o da mensagem escrita e
# as grátis do mês do número. Não depende da tela de Modelos.
RSpec.describe CampaignJourney::ConversaAberta::Contagem, :aggregate_failures do
  let(:account_and_user) { create_account_and_user }
  let(:account) { account_and_user.first }
  let(:user) { account_and_user.last }
  let(:channel) { journey_cloud_channel(account) }
  let(:inbox) { channel.inbox }
  let(:content) { "Nome,Celular\nAna Souza,11987654321\nBia Lima,21987654321\nCaio Reis,31987654321\n" }
  let(:audience) { saved_audience(account: account, user: user, content: content) }
  let(:now) { Time.zone.parse('2026-10-13 12:00') }

  def contato(nome)
    audience.campaign_import_rows.includes(:contact).map(&:contact).find { |contact| contact.name == nome }
  end

  def falou(contact, at:)
    conversation = create(:conversation, account: account, inbox: inbox, contact: contact)
    create(:message, account: account, inbox: inbox, conversation: conversation, sender: contact, message_type: :incoming, created_at: at)
  end

  def contar(categoria = 'MARKETING')
    described_class.new(account: account, campaign_import: audience, inbox: inbox, categoria: categoria, now: now).perform
  end

  it 'separa quem falou nas últimas 24 h de quem não falou, e quantos fecham logo' do
    falou(contato('Ana Souza'), at: now - 23.hours)
    falou(contato('Bia Lima'), at: now - 1.hour)
    falou(contato('Caio Reis'), at: now - 30.hours)

    resultado = contar

    expect(resultado.slice(:dentro, :fora, :fecham_logo)).to eq(dentro: 2, fora: 1, fecham_logo: 1)
    expect(resultado[:conferido_em]).to eq(now.iso8601)
  end

  it 'deixa de fora quem pediu para parar' do
    falou(contato('Ana Souza'), at: now - 1.hour)
    contato('Ana Souza').opt_out!(source: 'manual')

    expect(contar.slice(:dentro, :fora)).to eq(dentro: 0, fora: 2)
  end

  it 'traz o preço do modelo pela categoria, o da mensagem escrita e a franquia do número' do
    resultado = contar('MARKETING')

    expect(resultado[:precos]).to eq(modelo: { valor: '0.3217', moeda: 'BRL' }, escrita: { valor: '0.035', moeda: 'BRL' })
    expect(resultado[:franquia]).to eq(limite: 1000, usadas: 0)
    expect(contar('UTILITY')[:precos][:modelo]).to eq(valor: '0.035', moeda: 'BRL')
  end

  it 'conta as respostas livres do mês do número na franquia' do
    conversation = create(:conversation, account: account, inbox: inbox)
    create_list(:message, 2, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing, created_at: now - 1.day)

    expect(contar[:franquia]).to eq(limite: 1000, usadas: 2)
  end

  it 'sem categoria conhecida, não inventa preço de modelo' do
    expect(contar('')[:precos][:modelo]).to be_nil
  end
end
