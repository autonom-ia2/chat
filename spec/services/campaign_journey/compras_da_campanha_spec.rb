require 'rails_helper'

# #3098: "Quem recebeu e comprou". Compra = card fechado como venda (régua do ResultReplies) da pessoa, entre o envio e
# o envio + a janela; conta só na campanha mais recente antes da compra; separa quem respondeu; compara com o grupo de
# controle a partir do primeiro envio.
RSpec.describe CampaignJourney::ComprasDaCampanha, :aggregate_failures do
  let(:account_and_user) { create_account_and_user }
  let(:account) { account_and_user.first }
  let(:admin) { account_and_user.last }
  let(:account_user) { account.account_users.find_by(user: admin) }
  let(:reply_inbox) { create_crm_inbox(account: account, members: [admin]) }
  let(:whatsapp_inbox) { create(:channel_whatsapp, account: account, sync_templates: false, validate_provider_config: false).inbox }
  let(:campaign) { create(:campaign, account: account, inbox: whatsapp_inbox, title: 'Renovação', campaign_type: :one_off) }
  let(:outra) { create(:campaign, account: account, inbox: whatsapp_inbox, title: 'Outra', campaign_type: :one_off) }
  let(:audience) { saved_audience(account: account, user: admin, content: "Nome,Celular\nAna,11987654321\n") }
  let!(:link) { CampaignAudienceLink.create!(account: account, campaign: campaign, campaign_import: audience, janela_de_compra_dias: 7) }
  let(:sale) { create_crm_pipeline(account: account, user: admin) }
  let(:enviado_em) { 10.days.ago }

  around do |example|
    with_modified_env(CRM_KANBAN_ENABLED: 'true') { example.run }
  end

  def pessoa(nome)
    account.contacts.create!(name: nome, phone_number: "+55119#{rand(10_000_000..99_999_999)}")
  end

  def enviar(contato, para: campaign, quando: enviado_em)
    CampaignRecipient.create!(account: account, campaign: para, contact: contato, inbox: whatsapp_inbox, status: :sent, sent_at: quando)
  end

  def compra(contato, quando:, valor: 10_000, status: :won)
    pipeline, stage = sale
    card = account.crm_cards.create!(pipeline: pipeline, stage: stage, title: contato.name, contact: contato, status: status,
                                     value_cents: valor)
    card.update_columns(closed_at: quando) # rubocop:disable Rails/SkipsModelValidations
    card
  end

  def respondeu(contato)
    conversa = create_crm_conversation(account: account, inbox: reply_inbox, contact: contato)
    CampaignJourney::CampaignMarks.mark!(conversa, campaign)
  end

  def resultado
    described_class.new(account, campaign, CampaignJourney::CampaignMarks.source_id_for(campaign))
                   .payload(user: admin, account_user: account_user)
  end

  it 'conta quem comprou dentro da janela, separando quem respondeu de quem comprou sem responder' do
    ana = pessoa('Ana')
    bia = pessoa('Bia')
    caio = pessoa('Caio')
    [ana, bia, caio].each { |contato| enviar(contato) }
    respondeu(ana)
    compra(ana, quando: enviado_em + 2.days, valor: 50_000)
    compra(bia, quando: enviado_em + 6.days, valor: 30_000)
    compra(caio, quando: enviado_em + 8.days, valor: 99_000)
    compra(caio, quando: enviado_em - 1.day, valor: 77_000)

    vendas = resultado

    expect(vendas).to include(janela_dias: 7, contando_ate: nil, receberam: 3, controle: nil)
    expect(vendas[:compraram]).to eq(pessoas: 2, valor: [{ currency: 'BRL', cents: 80_000 }])
    expect(vendas[:responderam]).to eq(pessoas: 1, valor: [{ currency: 'BRL', cents: 50_000 }])
    expect(vendas[:sem_responder]).to eq(pessoas: 1, valor: [{ currency: 'BRL', cents: 30_000 }])
  end

  it 'a compra conta só na campanha mais recente antes dela' do
    ana = pessoa('Ana')
    enviar(ana)
    enviar(ana, para: outra, quando: enviado_em + 1.day)
    compra(ana, quando: enviado_em + 3.days)

    expect(resultado[:compraram][:pessoas]).to eq(0)
  end

  it 'diz até quando ainda conta enquanto a janela está aberta' do
    enviar(pessoa('Ana'), quando: 2.days.ago)

    expect(resultado[:contando_ate]).to be_within(5).of((2.days.ago + 7.days).to_i)
  end

  it 'compara com o grupo de controle a partir do primeiro envio' do
    link.update!(grupo_de_controle_pct: 10)
    enviar(pessoa('Ana'))
    fora = [pessoa('Bia'), pessoa('Caio')]
    fora.each { |contato| CampaignControlContact.create!(account: account, campaign_audience_link: link, contact: contato) }
    compra(fora.first, quando: enviado_em + 1.day)
    compra(fora.last, quando: enviado_em + 9.days)

    expect(resultado[:controle]).to eq(pessoas: 2, compraram: 1)
  end

  it 'esconde o valor de quem não vê valor de venda e não mede campanha sem público' do
    ana = pessoa('Ana')
    enviar(ana)
    compra(ana, quando: enviado_em + 1.day)
    allow(Crm::ValorDeVenda).to receive(:ve?).and_return(false)

    expect(resultado[:compraram]).to eq(pessoas: 1, valor: nil)
    expect(described_class.new(account, outra, 'x').payload(user: admin, account_user: account_user)).to be_nil
  end
end
