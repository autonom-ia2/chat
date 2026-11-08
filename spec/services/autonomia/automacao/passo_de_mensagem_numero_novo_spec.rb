require 'rails_helper'

# #2700 (ex. 19, passo 4): depois de o telefone do contato mudar, a mensagem vai ao número novo. No WhatsApp oficial,
# no SMS e no Twilio a conversa fica presa ao número com que nasceu (`ContactInbox.source_id`); o passo "mensagem" vai
# à conversa do número novo na mesma caixa, que ele abre se preciso.
RSpec.describe Autonomia::Automacao::PassoDeMensagem, :automacao_motor do
  include ActiveJob::TestHelper

  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator, name: 'Ana Souza') }
  let(:caixa) { create(:channel_sms, account: account).inbox.tap { |inbox| inbox.add_members([admin.id]) } }
  let(:contato) { account.contacts.create!(name: 'Bruno', phone_number: '+5511900000019') }
  let(:conversa) do
    contact_inbox = ContactInboxBuilder.new(contact: contato, inbox: caixa, source_id: nil).perform
    ConversationBuilder.new(params: ActionController::Parameters.new(status: 'open'), contact_inbox: contact_inbox).perform.reload
  end

  before do
    ligar_motor(account)
    ligar_mensagens(account)
  end

  after { Current.reset }

  def rodar(passos, alvo, gatilho: { 'tipo' => 'conversa.resolvida' })
    definicao = automacao_ligada(account, admin, passos, gatilho: gatilho)
    perform_enqueued_jobs(only: Autonomia::Automacao::AvancarJob) do
      Autonomia::Automacao::Partida.new(definicao: definicao, alvo: alvo, chave_gatilho: gatilho['tipo']).call
    end
    Autonomia::Automacao::Execucao.where(automacao: definicao).last
  end

  def registros(execucao)
    Autonomia::Automacao::Registro.where(execucao: execucao).order(:id).pluck(:passo, :resultado, :motivo)
  end

  def dados_do(execucao, passo) = Autonomia::Automacao::Registro.find_by!(execucao: execucao, passo: passo).dados

  def recado = mensagem_passo('recado', 'Oi ', { '$valor' => 'contato.nome' }, ', anotamos o seu número novo.')

  def numero_novo! = contato.update!(phone_number: '+5511988880000')

  it 'com o telefone trocado, a mensagem abre a conversa do número novo e não manda no antigo', :aggregate_failures do
    conversa
    numero_novo!

    execucao = rodar([recado], conversa)
    nova = Conversation.where(contact: contato).where.not(id: conversa.id).sole

    expect(registros(execucao)).to eq([['recado', 'ok', nil]])
    expect(nova.contact_inbox.source_id).to eq('+5511988880000')
    expect(nova.messages.outgoing.sole.content).to eq('Oi Bruno, anotamos o seu número novo.')
    expect(conversa.messages.outgoing).to be_empty
    expect(dados_do(execucao, 'recado')).to include('numero_novo' => true, 'conversa_aberta' => nova.display_id)
  end

  it 'a conversa aberta do número novo é reaproveitada' do
    conversa
    numero_novo!
    ja_aberta = Autonomia::Automacao::ConversaNova.abrir(caixa, contato)

    rodar([recado], conversa)

    expect(ja_aberta.messages.outgoing.sole.content).to eq('Oi Bruno, anotamos o seu número novo.')
  end

  it 'com o mesmo número, manda na conversa de sempre', :aggregate_failures do
    execucao = rodar([recado], conversa)

    expect(Conversation.where(contact: contato).count).to eq(1)
    expect(dados_do(execucao, 'recado').keys).not_to include('numero_novo')
  end

  it 'no card, a conversa do número novo vira a principal (registrado)', :aggregate_failures do
    account.enable_features!('automacao_gatilhos')
    funil, etapa = with_modified_env(CRM_KANBAN_ENABLED: 'true') { create_crm_pipeline(account: account, user: admin) }
    card = account.crm_cards.create!(pipeline: funil, stage: etapa, contact: contato, title: 'Bruno', conversation_id: conversa.id)
    numero_novo!

    execucao = with_modified_env(CRM_KANBAN_ENABLED: 'true') { rodar([recado], card, gatilho: { 'tipo' => 'card.criado' }) }
    nova = Conversation.where(contact: contato).where.not(id: conversa.id).sole

    expect(card.reload.conversation_id).to eq(nova.id)
    expect(dados_do(execucao, 'recado')).to include('numero_novo' => true, 'conversa_principal_do_card' => card.id)
  end

  it 'a mensagem que não sai no número novo desfaz a conversa aberta', :aggregate_failures do
    conversa
    numero_novo!

    execucao = rodar([mensagem_passo('recado', { '$valor' => 'contato.email' })], conversa)

    expect(registros(execucao)).to eq([%w[recado pulado faltou_valor]])
    expect(Conversation.where(contact: contato).count).to eq(1)
  end

  it 'na caixa de API (sem número na conversa), nada muda' do
    api = create_crm_whatsapp_api_inbox(account: account, members: [admin])
    da_api = create_crm_conversation(account: account, inbox: api, contact: contato)
    numero_novo!

    rodar([recado], da_api)

    expect(da_api.messages.outgoing.sole.content).to eq('Oi Bruno, anotamos o seu número novo.')
  end
end
