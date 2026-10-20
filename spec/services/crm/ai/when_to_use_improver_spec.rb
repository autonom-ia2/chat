require 'rails_helper'

# #1920: "Melhorar com IA" do "quando usar" vê os outros funis e os cards que uma pessoa mudou de funil.
RSpec.describe Crm::Ai::WhenToUseImprover do
  let(:account_and_admin) { create_account_and_user }
  let(:account) { account_and_admin.first }
  let(:admin) { account_and_admin.last }
  let(:venda_e_etapa) { create_crm_pipeline(account: account, user: admin, name: 'Vendas') }
  let(:venda) { venda_e_etapa.first }
  let(:atendimento_e_etapa) { create_crm_pipeline(account: account, user: admin, name: 'Atendimento') }
  let(:atendimento) { atendimento_e_etapa.first }
  let(:client) { instance_double(Crm::Ai::ResponsesClient) }
  let(:resposta) { { 'when_to_use' => 'Pedidos de quem já é cliente.', 'note' => '' } }

  before do
    venda.update!(when_to_use: 'Quem quer comprar.')
    atendimento.update!(counts_as_sale: false)
    allow(Crm::Ai::CredentialResolver).to receive(:new).and_return(instance_double(Crm::Ai::CredentialResolver, resolve: { api_key: 'x' }))
    allow(Crm::Ai::ResponsesClient).to receive(:new).and_return(client)
  end

  def pedido(funil: {})
    enviado = nil
    allow(client).to receive(:create) do |request|
      enviado = request
      { text: resposta.to_json }
    end
    resultado = described_class.new(pipeline: atendimento, language: 'pt_BR', funil: funil).perform
    [resultado, enviado]
  end

  it 'vê o funil da tela, os outros funis e o card que uma pessoa trouxe de outro funil' do
    contact = create(:contact, account: account, name: 'Cliente Sintético')
    conversation = create_crm_conversation(account: account, inbox: create_crm_inbox(account: account), contact: contact)
    conversation.messages.create!(account_id: account.id, inbox_id: conversation.inbox_id, message_type: :incoming,
                                  content: 'Quero cancelar meu plano', sender: contact, created_at: 2.hours.ago)
    card = account.crm_cards.create!(pipeline: atendimento, stage: atendimento_e_etapa.last, title: 'Pedido', conversation_id: conversation.id)
    Crm::Activity.create!(account: account, card: card, actor_type: 'user', actor_id: admin.id, event_type: 'move', created_at: 1.hour.ago,
                          payload: { from_pipeline_id: venda.id, to_pipeline_id: atendimento.id,
                                     from_stage_id: venda_e_etapa.last.id, to_stage_id: atendimento_e_etapa.last.id })

    resultado, enviado = pedido(funil: { 'when_to_use' => 'Suporte' })
    entrada = JSON.parse(enviado[:input])

    expect(resultado).to eq(resposta)
    expect(entrada['target']).to eq('name' => 'Atendimento', 'kind' => 'serve', 'when_to_use' => 'Suporte', 'stages' => ['Novo Lead'])
    expect(entrada['other_pipelines']).to eq([{ 'name' => 'Vendas', 'kind' => 'sell', 'when_to_use' => 'Quem quer comprar.' }])
    expect(entrada['evidence']).to eq([{ 'signal' => 'pessoa_trouxe_para_este_funil', 'other_pipeline' => 'Vendas',
                                         'messages' => [{ 'role' => 'customer', 'content' => 'Quero cancelar meu plano' }] }])
    expect(enviado[:input]).not_to include('Cliente Sintético')
    expect(enviado[:instructions]).to include('cancellation, renewal')
  end

  it 'não conta movimento dentro do mesmo funil e corta a resposta no tamanho do campo' do
    card = account.crm_cards.create!(pipeline: atendimento, stage: atendimento_e_etapa.last, title: 'Pedido')
    Crm::Activity.create!(account: account, card: card, actor_type: 'user', event_type: 'move', created_at: 1.hour.ago,
                          payload: { from_pipeline_id: atendimento.id, to_pipeline_id: atendimento.id })
    resposta['when_to_use'] = 'a' * (Crm::Pipeline::MAX_WHEN_TO_USE + 50)

    resultado, enviado = pedido

    expect(JSON.parse(enviado[:input])).not_to have_key('evidence')
    expect(resultado['when_to_use'].length).to eq(Crm::Pipeline::MAX_WHEN_TO_USE)
  end
end
