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

  # Uma pessoa que a lista criou, com o resumo dela anotado, como a gravação de "Trazer minha lista" deixa.
  def criada(nome, **dados)
    anotada(sem_anotacao(nome, **dados))
  end

  # Uma pessoa que a lista criou e não anotou: a lista veio pela tela antiga, que nunca anota.
  def sem_anotacao(nome, **dados)
    quem = create(:contact, account: account, name: nome, **dados)
    importacao.campaign_import_rows.create!(row_number: importacao.campaign_import_rows.count + 2, status: :imported, contact_id: quem.id)
    quem
  end

  # O que a gravação anota de quem ela cria: o resumo da pessoa como está agora.
  def anotada(quem)
    campo = Relacionamentos::CampoPreenchido
    linha = importacao.campaign_import_rows.find_by!(contact_id: quem.id)
    como_esta = Relacionamentos::Trazer::PessoaCriada.new(importacao).conteudo(quem.id)
    campo.create!(account_id: account.id, campaign_import_row_id: linha.id, contact_id: quem.id, campo: campo::PESSOA_CRIADA,
                  valor_posto_hash: campo.resumo(linha.id, campo::PESSOA_CRIADA, como_esta))
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

  it 'fica quem teve a ficha editada depois da lista, por qualquer campo dela' do
    intocada = criada('Pessoa Intocada', phone_number: '+5511987650030', email: 'pessoa.intocada@exemplo.com.br',
                                         additional_attributes: { 'city' => 'Campinas' }, custom_attributes: { 'plano' => 'Ouro' })
    mudancas = {
      'Pessoa Nome' => { name: 'Pessoa Renomeada' },
      'Pessoa Telefone' => { phone_number: '+5511987650039' },
      'Pessoa Email' => { email: 'pessoa.nova@exemplo.com.br' },
      'Pessoa Nome do Meio' => { middle_name: 'Maria' },
      'Pessoa Sobrenome' => { last_name: 'Silveirino' },
      'Pessoa Identificador' => { identifier: 'cliente-0042' },
      'Pessoa Cidade' => { additional_attributes: { 'city' => 'Recife' } },
      'Pessoa Biografia' => { additional_attributes: { 'description' => 'Prefere ligação à tarde' } },
      'Pessoa Rede Social' => { additional_attributes: { 'social_profiles' => { 'instagram' => 'pessoa.rede' } } },
      # Sem empresa ligada, o nome da empresa é texto que alguém escreve na ficha.
      'Pessoa Empresa em Texto' => { additional_attributes: { 'company_name' => 'Oficina do Bairro' } },
      'Pessoa Informacao' => { custom_attributes: { 'plano' => 'Diamante' } },
      'Pessoa Empresa' => { company: account.companies.create!(name: 'Oficina Central') },
      'Pessoa Cliente' => { contact_type: :customer, customer_since: Time.current }
    }
    editadas = mudancas.map do |nome, mudanca|
      quem = criada(nome)
      quem.update!(mudanca)
      quem
    end
    # O que muda sozinho não é edição: a última atividade não segura ninguém.
    intocada.update!(last_activity_at: Time.current)

    expect(ficam(intocada, *editadas)).to match_array(editadas.map(&:id))
  end

  # A tela de edição manda os campos em branco e as redes sociais vazias mesmo quando ninguém escreveu nada neles.
  it 'salvar a ficha sem mudar nada não segura: o que chega em branco é o mesmo que ausente, em qualquer nível' do
    salva = criada('Pessoa Salva', phone_number: '+5511987650040', additional_attributes: { 'city' => 'Campinas' })
    em_branco = { 'description' => '', 'company_name' => nil, 'social_profiles' => { 'facebook' => '', 'instagram' => '' } }

    salva.update!(additional_attributes: salva.additional_attributes.merge(em_branco), custom_attributes: { 'plano' => '' })

    expect(ficam(salva)).to be_empty
  end

  # Sem a anotação não há com o que comparar: o Desfazer não apaga quem não dá para provar que ninguém editou.
  it 'fica a pessoa sem anotação (lista da tela antiga, que nunca anota), editada ou não' do
    intocada = sem_anotacao('Pessoa Sem Anotação')
    renomeada = sem_anotacao('Pessoa Sem Anotação Dois')
    renomeada.update!(name: 'Pessoa Renomeada')
    anotada = criada('Pessoa Anotada')

    expect(ficam(intocada, renomeada, anotada)).to contain_exactly(intocada.id, renomeada.id)
  end

  it 'fica quem tem seguro na carteira' do
    com_seguro = criada('Pessoa Segurada')
    sem = criada('Pessoa Sem')
    create(:carteira_apolice, account: account, contact: com_seguro)

    expect(ficam(com_seguro, sem)).to contain_exactly(com_seguro.id)
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

  it 'fica quem ganhou etiqueta' do
    com_etiqueta = criada('Pessoa Etiqueta')
    sem = criada('Pessoa Sem')
    com_etiqueta.update!(label_list: ['quente'])

    expect(ficam(com_etiqueta, sem)).to contain_exactly(com_etiqueta.id)
  end

  it 'fica quem recusou os avisos de agendamento e quem veio também da prospecção ou de um anúncio' do
    sem_aviso = criada('Pessoa Sem Aviso')
    prospectada = criada('Pessoa Prospectada')
    do_anuncio = criada('Pessoa Anúncio')
    sem = criada('Pessoa Sem')
    linha!('crm_booking_notice_stops', account_id: account.id, contact_id: sem_aviso.id)
    linha!('autonomia_prospecting_leads', account_id: account.id, contact_id: prospectada.id, name: 'Padaria Exemplo', dedupe_key: 'padaria-exemplo')
    linha!('crm_meta_ads_leads', account_id: account.id, contact_id: do_anuncio.id, leadgen_id: 'lead-inventado-1', received_at: Time.current)

    expect(ficam(sem_aviso, prospectada, do_anuncio, sem)).to contain_exactly(sem_aviso.id, prospectada.id, do_anuncio.id)
    expect(described_class.new(importacao).fica?(sem.id)).to be(false)
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

  it 'a lista que já foi desfeita não segura ninguém' do
    em_lista_desfeita = criada('Pessoa Lista Desfeita')
    desfeita = lista
    desfeita.update!(undo_status: :completed)
    desfeita.campaign_import_rows.create!(row_number: 2, status: :imported, contact_id: em_lista_desfeita.id, was_existing_contact: true)

    expect(ficam(em_lista_desfeita)).to be_empty
  end

  it 'a lista que quebrou no meio e foi desfeita também não segura ninguém' do
    em_lista_desfeita = criada('Pessoa Lista Quebrada')
    desfeita = lista
    desfeita.update!(status: :failed, import_started_at: 1.hour.ago, undo_status: :completed)
    desfeita.campaign_import_rows.create!(row_number: 2, status: :imported, contact_id: em_lista_desfeita.id, was_existing_contact: true)

    expect(ficam(em_lista_desfeita)).to be_empty
  end

  # CampaignImports::UndoLabels também grava `undo_status: completed`, mas só tirou as etiquetas: a pessoa segue na base.
  it 'a base de campanha que só teve as etiquetas desfeitas continua segurando a pessoa' do
    na_base = criada('Pessoa Na Base')
    so_nesta = criada('Pessoa Só Nesta')
    base = account.campaign_imports.create!(user: user, status: :labels_undone, undo_status: :completed, mode: 'single_label')
    base.campaign_import_rows.create!(row_number: 2, status: :labels_undone, contact_id: na_base.id, was_existing_contact: true)

    expect(ficam(na_base, so_nesta)).to contain_exactly(na_base.id)
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

  it 'não olha a importação, a campanha de e-mail nem o Público de outra conta' do
    outra = create(:account)
    intocada = criada('Pessoa Intocada')
    lista(conta: outra).campaign_import_rows.create!(row_number: 2, status: :imported, contact_id: intocada.id, was_existing_contact: true)
    remetente = linha!('email_sender_identities', account_id: outra.id, domain: 'exemplo.invalid')
    de_email = linha!('email_campaigns', account_id: outra.id, name: 'Novidades', sender_identity_id: remetente)
    linha!('email_campaign_recipients', email_campaign_id: de_email, email: 'pessoa.email@exemplo.invalid', contact_id: intocada.id)
    conversa = create(:conversation, account: outra)
    busca = linha!('conversation_audience_searches', account_id: outra.id, request: 'quem pediu orçamento', period: '30d')
    linha!('conversation_audience_people', search_id: busca, contact_id: intocada.id, conversation_id: conversa.id, group: 'sure')

    expect(ficam(intocada)).to be_empty
  end
end
