require 'rails_helper'

# Ponta a ponta do modelo fora da janela (#2468, G1 do fechamento #2570): o dono monta e liga a automação pela API da
# tela; a equipe resolve uma conversa em que o cliente não escreve há 30 h; os jobs rodam um por vez, como no Sidekiq;
# e o pedido do modelo chega ao receptor da Graph, que o grava.
RSpec.describe 'Automação: modelo aprovado fora da janela', type: :request do
  include ActiveJob::TestHelper

  let(:canal) { create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false) }
  let(:account) { canal.account }
  let(:dono) { create(:user, account: account, role: :administrator) }
  let(:contato) { create(:contact, account: account, name: 'Ana', phone_number: '+5511937016094') }
  let(:contact_inbox) { create(:contact_inbox, inbox: canal.inbox, contact: contato, source_id: '5511937016094') }
  let(:conversa) { create(:conversation, inbox: canal.inbox, contact: contato, contact_inbox: contact_inbox, account: account) }
  let(:pedidos) { [] }
  let(:jobs_do_caminho) { [EventDispatcherJob, Autonomia::Automacao::AvancarJob, SendReplyJob] }
  let(:base) { "/api/v1/accounts/#{account.id}/autonomia/automacoes" }
  let(:receita) do
    { gatilho: { tipo: 'conversa.resolvida' },
      passos: [{ id: 'p1', tipo: 'mensagem', texto: ['Obrigado pelo contato!'],
                 modelo: { nome: 'atendimento_encerrado', idioma: 'pt_BR', variaveis: [[{ '$valor': 'contato.nome' }]] } }] }
  end

  let(:modelo_aprovado) do
    { 'name' => 'atendimento_encerrado', 'language' => 'pt_BR', 'status' => 'APPROVED', 'category' => 'UTILITY',
      'components' => [{ 'type' => 'BODY', 'text' => 'Oi {{1}}, seu atendimento foi encerrado.' }] }
  end

  before do
    account.enable_features!('automacao_fundacao', 'automacao_motor', 'automacao_mensagens', 'automacao_editor')
    create(:inbox_member, user: dono, inbox: canal.inbox)
    canal.update!(message_templates: [modelo_aprovado])
    stub_request(:post, ->(uri) { uri.host == 'graph.facebook.com' }).to_return do |pedido|
      pedidos << JSON.parse(pedido.body)
      { status: 200, body: { messages: [{ id: "wamid.G1#{pedidos.size}" }] }.to_json, headers: { 'Content-Type' => 'application/json' } }
    end
  end

  # Um job do caminho por vez; o enfileirado dentro de outro roda depois dele.
  def rodar_jobs
    40.times do
      job = enqueued_jobs.find { |item| jobs_do_caminho.include?(item[:job]) }
      return unless job

      enqueued_jobs.delete(job)
      job[:job].perform_now(*ActiveJob::Arguments.deserialize(job[:args]))
    end
    raise 'a fila não esvaziou'
  end

  it 'monta, liga e, com a janela fechada, o modelo sai até a Graph com o nome do contato', :aggregate_failures do
    post base, params: { nome: 'Encerrou', receita: receita }, headers: dono.create_new_auth_token, as: :json
    expect(response).to have_http_status(:created), -> { response.body }
    automacao = response.parsed_body
    post "#{base}/#{automacao['id']}/ligar", params: { versao_id: automacao.dig('versao', 'id') },
                                             headers: dono.create_new_auth_token, as: :json
    expect(response).to have_http_status(:ok), -> { response.body }

    create(:message, conversation: conversa, account: account, inbox: canal.inbox, message_type: :incoming, sender: contato,
                     content: 'oi', created_at: 30.hours.ago)
    clear_enqueued_jobs
    conversa.update!(status: :resolved)
    rodar_jobs

    expect(pedidos.size).to eq(1)
    expect(pedidos.last['type']).to eq('template')
    expect(pedidos.last.dig('template', 'name')).to eq('atendimento_encerrado')
    corpo = pedidos.last.dig('template', 'components').find { |parte| parte['type'] == 'body' }
    expect(corpo['parameters'].pluck('text')).to eq(['Ana'])
    expect(conversa.messages.outgoing.last.content).to eq('Oi Ana, seu atendimento foi encerrado.')
  end
end
