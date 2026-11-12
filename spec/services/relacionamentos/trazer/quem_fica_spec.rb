require 'rails_helper'

# #2896 (fatia 3) — das pessoas que uma lista criou, quais o "Desfazer" não apaga: aquelas em quem alguém já tocou.
RSpec.describe Relacionamentos::Trazer::QuemFica, :aggregate_failures do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: :administrator) }
  let(:importacao) { lista }

  def lista(conta: account)
    conta.campaign_imports.create!(user: create(:user, account: conta, role: :administrator), status: :completed, mode: 'single_label',
                                   options: { 'flow' => CampaignImport::CONTACTS_FLOW, 'trazer' => {} })
  end

  # Uma pessoa que a lista criou.
  def criada(nome, **dados)
    quem = create(:contact, account: account, name: nome, **dados)
    importacao.campaign_import_rows.create!(row_number: importacao.campaign_import_rows.count + 2, status: :imported, contact_id: quem.id)
    quem
  end

  # Linha mínima numa tabela, sem passar pelo modelo: aqui só importa a linha existir.
  def linha!(tabela, atributos)
    modelo = Class.new(ApplicationRecord) { self.table_name = tabela }
    agora = Time.current
    carimbos = { created_at: agora, updated_at: agora }.slice(*modelo.column_names.map(&:to_sym))
    modelo.insert!(atributos.merge(carimbos), returning: :id).rows.first.first # rubocop:disable Rails/SkipsModelValidations
  end

  def ficam(*pessoas)
    described_class.new(importacao).entre(pessoas.map(&:id))
  end

  it 'deixa sair a pessoa em quem ninguém tocou' do
    intocada = criada('Pessoa Intocada', phone_number: '+5511987650020')

    expect(ficam(intocada)).to be_empty
    expect(described_class.new(importacao).entre([])).to be_empty
  end

  it 'fica quem tem conversa' do
    com_conversa = criada('Pessoa Conversa')
    sem = criada('Pessoa Sem')
    create(:conversation, account: account, contact: com_conversa)

    expect(ficam(com_conversa, sem)).to contain_exactly(com_conversa.id)
  end

  it 'fica quem tem card, como a pessoa do card ou como quem pediu' do
    do_card = criada('Pessoa Card')
    pediu = criada('Pessoa Pediu')
    sem = criada('Pessoa Sem')
    funil, etapa = create_crm_pipeline(account: account, user: user)
    account.crm_cards.create!(pipeline: funil, stage: etapa, contact: do_card, title: 'Pedido')
    account.crm_cards.create!(pipeline: funil, stage: etapa, solicitante: pediu, title: 'Pedido do RH')

    expect(ficam(do_card, pediu, sem)).to contain_exactly(do_card.id, pediu.id)
  end

  it 'fica quem tem nota na ficha ou retorno marcado' do
    com_nota = criada('Pessoa Nota')
    com_retorno = criada('Pessoa Retorno')
    com_serie = criada('Pessoa Serie')
    sem = criada('Pessoa Sem')
    Note.create!(account: account, contact: com_nota, user: user, content: 'Ligar na segunda')
    linha!('crm_follow_ups', account_id: account.id, contact_id: com_retorno.id, title: 'Retorno', due_at: 1.day.from_now)
    linha!('crm_follow_up_series', account_id: account.id, contact_id: com_serie.id, title: 'Toda segunda', frequency: 0, starts_at: 1.day.from_now)

    expect(ficam(com_nota, com_retorno, com_serie, sem)).to contain_exactly(com_nota.id, com_retorno.id, com_serie.id)
  end

  it 'fica quem recebeu ou está na fila de uma campanha de WhatsApp Oficial ou de e-mail' do
    do_whatsapp = criada('Pessoa WhatsApp')
    do_email = criada('Pessoa Email')
    sem = criada('Pessoa Sem')
    campanha = linha!('whatsapp_api_campaigns', account_id: account.id, created_by_id: user.id, title: 'Aviso')
    linha!('whatsapp_api_campaign_recipients', account_id: account.id, whatsapp_api_campaign_id: campanha, contact_id: do_whatsapp.id)
    remetente = linha!('email_sender_identities', account_id: account.id, domain: 'exemplo.invalid')
    de_email = linha!('email_campaigns', account_id: account.id, name: 'Novidades', sender_identity_id: remetente)
    linha!('email_campaign_recipients', email_campaign_id: de_email, email: 'pessoa.email@exemplo.invalid', contact_id: do_email.id)

    expect(ficam(do_whatsapp, do_email, sem)).to contain_exactly(do_whatsapp.id, do_email.id)
  end

  it 'fica quem está numa campanha da caixa (WhatsApp ou SMS)' do
    da_campanha = criada('Pessoa Campanha')
    sem = criada('Pessoa Sem')
    account.enable_features!(:whatsapp_campaign)
    canal = create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false)
    campanha = create(:campaign, account: account, inbox: canal.inbox, campaign_type: :one_off, scheduled_at: 1.hour.ago)
    CampaignRecipient.create!(account: account, campaign: campanha, inbox: canal.inbox, contact: da_campanha, status: :failed)

    expect(ficam(da_campanha, sem)).to contain_exactly(da_campanha.id)
  end

  it 'fica quem está em outra importação: outra lista, um Público ou uma base de campanha' do
    em_outra = criada('Pessoa Outra Lista')
    so_nesta = criada('Pessoa Só Nesta')
    lista.campaign_import_rows.create!(row_number: 2, status: :imported, contact_id: em_outra.id, was_existing_contact: true)

    expect(ficam(em_outra, so_nesta)).to contain_exactly(em_outra.id)
  end

  it 'fica quem entrou num Público montado pelas conversas' do
    no_publico = criada('Pessoa Público')
    sem = criada('Pessoa Sem')
    conversa = create(:conversation, account: account)
    busca = linha!('conversation_audience_searches', account_id: account.id, request: 'quem pediu orçamento', period: '30d')
    linha!('conversation_audience_people', search_id: busca, contact_id: no_publico.id, conversation_id: conversa.id, group: 'sure')

    expect(ficam(no_publico, sem)).to contain_exactly(no_publico.id)
  end

  it 'fica quem recusou mensagens ou está bloqueada, para a recusa não sumir com a pessoa' do
    recusou = criada('Pessoa Recusou', phone_number: '+5511987650021')
    bloqueada = criada('Pessoa Bloqueada', phone_number: '+5511987650022')
    sem = criada('Pessoa Sem', phone_number: '+5511987650023')
    recusou.opt_out!(source: 'manual')
    bloqueada.update!(blocked: true)

    expect(ficam(recusou, bloqueada, sem)).to contain_exactly(recusou.id, bloqueada.id)
  end

  it 'separa em blocos quem sai e quem fica, só entre as pessoas que a lista criou e que ainda existem' do
    stub_const("#{described_class}::BLOCO", 2)
    saem = Array.new(3) { |vez| criada("Pessoa Sai #{vez}") }
    fica = criada('Pessoa Fica')
    create(:conversation, account: account, contact: fica)
    apagada = criada('Pessoa Apagada')
    apagada.destroy!
    ja_existia = create(:contact, account: account, name: 'Pessoa Antiga')
    importacao.campaign_import_rows.create!(row_number: 99, status: :imported, contact_id: ja_existia.id, was_existing_contact: true)
    importacao.campaign_import_rows.create!(row_number: 100, status: :import_failed)

    blocos = []
    described_class.new(importacao).em_blocos { |sairam, ficaram| blocos << [sairam, ficaram] }

    expect(blocos.size).to eq(3)
    expect(blocos.flat_map(&:first)).to match_array(saem.map(&:id))
    expect(blocos.flat_map(&:last)).to eq([fica.id])
  end

  it 'não olha a conversa, o card nem a recusa de outra conta' do
    outra = create(:account)
    de_fora = create(:contact, account: outra, name: 'Pessoa de Fora', blocked: true)
    create(:conversation, account: outra, contact: de_fora)
    intocada = criada('Pessoa Intocada')

    expect(ficam(intocada, de_fora)).to be_empty
  end
end
