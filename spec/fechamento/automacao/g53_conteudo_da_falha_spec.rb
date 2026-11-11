require 'rails_helper'

# Fechamento do épico #2414, G53: o texto da mensagem que falhou vira valor da receita (`falhou.texto`). É o passo 2 do
# exemplo 19 ("Cliente que sumiu do WhatsApp"), à risca:
#
#   Começa quando: O WhatsApp recusa uma mensagem para o cliente.
#   1. Põe a etiqueta "número com problema" no contato.
#   2. Tem e-mail: manda por e-mail o mesmo conteúdo e pergunta "Você trocou de WhatsApp? Me responde com o número novo".
#
# A dona monta e liga pela API da tela. O cliente escreve pelo webhook da Cloud, a agente responde pela API, a resposta
# sai pela Graph (receptor), e a recusa volta pelo webhook de status da Cloud, como a Meta manda. O exemplo segue no
# pendentes_spec até o spec de ponta a ponta dele, que fica com a sessão do fechamento (#2570).
#
# - A etiqueta se escreve `número-com-problema`: nome de etiqueta na plataforma é minúsculo e sem espaço.
# - O e-mail pede assunto; o termo não diz qual, e vai a pergunta dele. Ele sai pelo envio de sempre da caixa
#   (SendReplyJob) e para no `ActionMailer::Base.deliveries`, com a entrega trocada por :test, como no exemplo 1.
RSpec.describe 'Fechamento #2414 · G53: o conteúdo da mensagem que falhou', :fechamento_automacao, type: :request do
  include ActiveJob::TestHelper

  around do |exemplo|
    metodo = ActionMailer::Base.delivery_method
    ActionMailer::Base.delivery_method = :test
    ActionMailer::Base.deliveries.clear
    with_modified_env(SMTP_ADDRESS: 'smtp.fechamento.test') { exemplo.run }
  ensure
    ActionMailer::Base.delivery_method = metodo
  end

  let(:canal) { create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false) }
  let(:account) { canal.account }
  let(:whatsapp) { canal.inbox }
  let(:caixa_de_email) { create(:channel_email, account: account).inbox }
  let(:dona) { create(:user, account: account, role: :administrator, name: 'Fernanda Gerente') }
  let(:agente) { create(:user, account: account, role: :agent, name: 'Paula Atendente') }
  let(:pergunta) { "\n\nVocê trocou de WhatsApp? Me responde com o número novo" }
  let(:boleto) { 'Seu boleto vence sexta, segue o código 123' }

  def receita(gatilho = 'mensagem.falhou')
    etiqueta = { id: 'etiqueta', tipo: 'acao', acao: 'PATCH contacts/:contact_id/labels/alterar', descricao: 'Número com problema',
                 caminho: { contact_id: { '$valor' => 'contato.id' } }, corpo: { por: ['número-com-problema'] } }
    email = { id: 'email', tipo: 'email', caixa_id: caixa_de_email.id, assunto: ['Você trocou de WhatsApp?'],
              texto: [{ '$valor' => 'falhou.texto' }, pergunta] }
    tem_email = { id: 'tem_email', tipo: 'se', condicao: { campo: { '$valor' => 'contato.email' }, op: 'preenchido' },
                  entao: [email], senao: [] }
    { gatilho: { tipo: gatilho }, passos: [etiqueta, tem_email] }
  end

  def contato = whatsapp.contact_inboxes.sole.contact
  def conversa = whatsapp.conversations.sole
  def conversa_do_email = Conversation.find_by(inbox: caixa_de_email, contact: contato)

  # A agente responde pela API da tela; o SendReplyJob manda pela Graph, que devolve o wamid.
  def agente_manda(**params)
    post "/api/v1/accounts/#{account.id}/conversations/#{conversa.display_id}/messages",
         params: { private: false, **params }, headers: agente.create_new_auth_token
    expect(response).to have_http_status(:ok), -> { "a mensagem não foi criada: #{response.body}" }
    rodar_jobs
    conversa.messages.outgoing.order(:id).last
  end

  # A Cloud avisa que não entregou: o webhook de status, como a Meta manda.
  def whatsapp_recusa(mensagem)
    expect(mensagem.source_id).to be_present
    valor = {
      messaging_product: 'whatsapp',
      metadata: { display_phone_number: canal.phone_number.delete('+'), phone_number_id: canal.provider_config['phone_number_id'] },
      statuses: [{ id: mensagem.source_id, status: 'failed', timestamp: Time.current.to_i.to_s, recipient_id: '5511900000019',
                   errors: [{ code: 131_026, title: 'Message undeliverable' }] }]
    }
    corpo = { object: 'whatsapp_business_account', entry: [{ id: 'waba-fechamento', changes: [{ field: 'messages', value: valor }] }] }
    webhook_da_meta("/webhooks/whatsapp/#{canal.phone_number}", corpo, :WHATSAPP_APP_SECRET)
    rodar_jobs
  end

  before do
    account.update!(locale: 'pt_BR')
    flags_do_piloto(account)
    account.enable_features!('automacao_gatilhos')
    whatsapp.update!(enable_auto_assignment: false)
    create(:inbox_member, user: agente, inbox: whatsapp)
    create(:label, account: account, title: 'número-com-problema')
    receptor_whatsapp_cloud
    clear_enqueued_jobs
    cliente_escreve_pela_cloud(canal, remetente: '5511900000019', nome: 'Bruno', texto: 'Oi, quero a segunda via do boleto')
    contato.update!(email: 'bruno@exemplo.com.br')
  end

  after { Current.reset }

  it 'a recusa do WhatsApp põe a etiqueta e manda por e-mail o mesmo conteúdo, com a pergunta do termo', :aggregate_failures do
    automacao = montar_automacao(dona, account, nome: 'Cliente que sumiu do WhatsApp', receita: receita)
    ligar_automacao(dona, account, automacao)

    recusada = agente_manda(content: boleto)
    whatsapp_recusa(recusada)

    expect(recusada.reload).to have_attributes(status: 'failed', external_error: '131026: Message undeliverable')
    expect(Autonomia::Automacao::Execucao.where(automacao_id: automacao['id']).sole.evento).to eq("mensagem.falhou:#{recusada.id}")
    expect(contato.reload.label_list).to eq(['número-com-problema'])
    email = conversa_do_email.messages.outgoing.sole
    expect(email.content).to eq("#{boleto}#{pergunta}")
    expect(email).to have_attributes(status: 'sent', external_error: nil)
    expect(conversa_do_email.additional_attributes['mail_subject']).to eq('Você trocou de WhatsApp?')
    expect(ActionMailer::Base.deliveries.last).to have_attributes(to: ['bruno@exemplo.com.br'], subject: 'Você trocou de WhatsApp?')
    expect(historico_de(automacao)).to eq([['etiqueta', 'ok', nil], ['tem_email', 'ok', nil], ['email', 'ok', nil]])
  end

  it 'a mensagem que falhou só com anexo deixa o texto vazio: o e-mail pula com faltou_valor e nada sai', :aggregate_failures do
    automacao = montar_automacao(dona, account, nome: 'Cliente que sumiu do WhatsApp', receita: receita)
    ligar_automacao(dona, account, automacao)

    # A Cloud recebe a imagem antes (upload de mídia) e devolve o id dela.
    stub_request(:post, ->(uri) { uri.host == 'graph.facebook.com' && uri.path.end_with?('/media') })
      .to_return(status: 200, body: { id: 'midia-1' }.to_json, headers: { 'Content-Type' => 'application/json' })
    recusada = agente_manda(attachments: [fixture_file_upload(Rails.root.join('spec/assets/avatar.png'), 'image/png')])
    whatsapp_recusa(recusada)

    expect(recusada.reload).to have_attributes(status: 'failed', content: nil)
    expect(contato.reload.label_list).to eq(['número-com-problema'])
    expect(conversa_do_email).to be_nil
    expect(historico_de(automacao).last).to eq(%w[email pulado faltou_valor])
  end

  it 'o salvar recusa o texto da mensagem que falhou fora do gatilho dela' do
    post api_automacoes(account), params: { nome: 'Fora do lugar', receita: receita('mensagem.criada') },
                                  headers: dona.create_new_auth_token, as: :json

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include('falhou.texto só existe no gatilho de mensagem que não chegou')
  end

  # A Partida confere o "Só se" antes de haver a execução de onde o texto é lido: ali ele leria sempre vazio.
  it 'o salvar recusa o texto da mensagem que falhou no "Só se" do próprio gatilho' do
    filtro = { campo: { '$valor' => 'falhou.texto' }, op: 'preenchido' }
    com_filtro = receita.merge(gatilho: { tipo: 'mensagem.falhou', filtros: [filtro] })
    post api_automacoes(account), params: { nome: 'No filtro', receita: com_filtro }, headers: dona.create_new_auth_token, as: :json

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include('falhou.texto só pode ser usado nos passos, não no \\"Só se\\" do gatilho')
  end
end
