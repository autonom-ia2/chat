require 'rails_helper'

# Fechamento do épico #2414, exemplo 19 dos termos de aceite, "Cliente que sumiu do WhatsApp", à risca:
#
# > "Às vezes a mensagem não chega porque o cliente trocou de número. Quero que o sistema tente achar ele de outro
# > jeito." — Fernanda, gerente de atendimento
#
# Começa quando: O WhatsApp recusa uma mensagem para o cliente.
#   1. Põe a etiqueta "número com problema" no contato.
#   2. Tem e-mail: manda por e-mail o mesmo conteúdo e pergunta "Você trocou de WhatsApp? Me responde com o número novo".
#   3. Respondeu: a IA extrai o número novo e atualiza o contato.
#   4. A IA escreve o recado que tinha falhado e manda ao número novo dentro do modelo aprovado "Retomar contato".
#   5. Chegou: tira a etiqueta e grava uma nota no contato: "número trocado em 03/11".
#   6. Sem e-mail, ou sem resposta em 3 dias: cria um retorno para alguém ligar e avisa o responsável.
#   7. Falhou de novo no número novo: avisa a Fernanda com um resumo de tudo o que foi tentado.
#
# A Fernanda monta e liga pela API da tela, numa automação só (G8, G53, G34, G28, G43, G19, G3, G11, G42). O cliente
# escreve pela Cloud; a Paula, responsável pela conversa, responde pela API; a Graph é o receptor, e a recusa e a
# entrega voltam pelo webhook de status, como a Meta manda. A IA é o dublê, mas o que ela recebe é o de verdade.
#
# - A etiqueta se escreve `número-com-problema`: nome de etiqueta na plataforma é minúsculo e sem espaço.
# - Passo 3, "atualiza o contato": o extrair grava no atributo do contato (telefone não é destino do extrair, D4 A), e a
#   ação "editar contato" copia o valor para o telefone.
# - Passo 5, "número trocado em 03/11": a data é a do dia em que o recado chegou, no fuso da conta.
# - Passo 3, "respondeu" (G68): o extrair lê a resposta na conversa do e-mail, como o resumir (G42). A Paula atende o
#   Bruno nas duas caixas: a outra conversa só vai à IA se todos que veem a conversa do WhatsApp também a veem.
RSpec.describe 'Fechamento #2414 · exemplo 19: cliente que sumiu do WhatsApp', :automacao_motor, :fechamento_automacao,
               type: :request do
  include ActiveJob::TestHelper

  around do |exemplo|
    metodo = ActionMailer::Base.delivery_method
    ActionMailer::Base.delivery_method = :test
    ActionMailer::Base.deliveries.clear
    with_modified_env(CRM_KANBAN_ENABLED: 'true', SMTP_ADDRESS: 'smtp.fechamento.test') { exemplo.run }
  ensure
    ActionMailer::Base.delivery_method = metodo
  end

  let(:fuso) { ActiveSupport::TimeZone['America/Sao_Paulo'] }
  let(:canal) { create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false) }
  let(:account) { canal.account }
  let(:whatsapp) { canal.inbox }
  let(:caixa_de_email) { create(:channel_email, account: account).inbox }
  let(:fernanda) { create(:user, account: account, role: :administrator, name: 'Fernanda Gerente') }
  let(:paula) { create(:user, account: account, role: :agent, name: 'Paula Atendente') }
  let(:boleto) { 'Seu boleto vence sexta, segue o código 123' }
  let(:pergunta) { "\n\nVocê trocou de WhatsApp? Me responde com o número novo" }
  let(:resposta) { 'Troquei sim! Meu número novo é (11) 98888-0019' }
  let(:resumo) { 'Tentamos o e-mail e o modelo "Retomar contato" no número novo; os dois sem resposta.' }
  let(:automacao) { montar_automacao(fernanda, account, nome: 'Cliente que sumiu do WhatsApp', receita: receita) }
  let(:roteiro) do
    { 'automacao_extrair' => { 'numero_novo' => '+5511988880019' },
      'automacao_escrever' => { 'texto' => 'seu boleto vence sexta, segue o código 123' },
      'automacao_resumir' => { 'resumo' => resumo } }
  end

  def para_a_fernanda = { pessoas: [fernanda.id] }
  def situacao = { '$valor' => 'envio.situacao' }

  def receita
    { gatilho: { tipo: 'mensagem.falhou' },
      passos: [etiqueta('etiqueta', por: ['número-com-problema']), pergunta_por_email, *atualizar_o_contato, *retomar, *chegou] }
  end

  def etiqueta(id, **corpo)
    { id: id, tipo: 'acao', acao: 'PATCH contacts/:contact_id/labels/alterar', descricao: 'Número com problema',
      caminho: { contact_id: { '$valor' => 'contato.id' } }, corpo: corpo }
  end

  # Passos 2, 3 (a espera) e 6.
  def pergunta_por_email
    email = { id: 'email', tipo: 'email', caixa_id: caixa_de_email.id, assunto: ['Você trocou de WhatsApp?'],
              texto: [{ '$valor' => 'falhou.texto' }, pergunta] }
    respondeu = { id: 'respondeu', tipo: 'esperar_ate', prazo: { valor: 3, unidade: 'dias' }, se_vencer: sem_jeito('sem_resposta'),
                  condicao: { campo: { '$valor' => 'conversa.cliente_respondeu' }, op: 'igual', valor: true } }
    { id: 'tem_email', tipo: 'se', condicao: { campo: { '$valor' => 'contato.email' }, op: 'preenchido' },
      entao: [email, respondeu], senao: sem_jeito('sem_email') }
  end

  # Passo 6.
  def sem_jeito(prefixo)
    [{ id: "#{prefixo}_ligar", tipo: 'retorno', titulo: ['Ligar para ', { '$valor' => 'contato.nome' }, ': o WhatsApp recusou'],
       daqui: { valor: 1, unidade: 'horas' }, para: { quem: 'responsavel' } },
     { id: "#{prefixo}_avisa", tipo: 'avisar', para: { responsavel: true },
       texto: ['O WhatsApp recusou a mensagem para ', { '$valor' => 'contato.nome' }, '. Ligue para ele.'] },
     { id: "#{prefixo}_fim", tipo: 'parar' }]
  end

  # Passo 3.
  def atualizar_o_contato
    [{ id: 'numero_novo', tipo: 'extrair', le: %w[mensagens_recentes],
       campos: [{ chave: 'numero_novo', descricao: 'o número novo de WhatsApp que o cliente mandou, com DDI e DDD',
                  destino: 'contato.atributos.numero_novo' }] },
     { id: 'telefone', tipo: 'acao', acao: 'PATCH contacts/:id', descricao: 'Trocar o telefone',
       caminho: { id: { '$valor' => 'contato.id' } }, corpo: { phone_number: { '$valor' => 'contato.atributos.numero_novo' } } }]
  end

  # Passo 4.
  def retomar
    [{ id: 'recado', tipo: 'escrever', destino: 'guardar', instrucao: 'Reescreva o recado que não chegou ao cliente.' },
     { id: 'retomar', tipo: 'mensagem', texto: ['Oi, ', { '$valor' => 'contato.nome' }, '.'],
       modelo: { nome: 'retomar_contato', idioma: 'pt_BR',
                 variaveis: [[{ '$valor' => 'contato.nome' }], [{ '$valor' => 'ia.recado' }]] } }]
  end

  # Passos 5 e 7.
  def chegou
    nota = { id: 'nota', tipo: 'acao', acao: 'POST contacts/:contact_id/notes', descricao: 'Anotar a troca de número',
             caminho: { contact_id: { '$valor' => 'contato.id' } }, corpo: { content: 'número trocado em 03/11' } }
    { id: 'chegou', tipo: 'esperar_ate', prazo: { valor: 1, unidade: 'dias' },
      condicao: { campo: situacao, op: 'diferente', valor: 'saiu' },
      se_vencer: [] }.then do |espera|
      [espera,
       { id: 'entregue', tipo: 'se', condicao: { campo: situacao, op: 'igual', valor: 'entregue' },
         entao: [etiqueta('tira_etiqueta', tirar: ['número-com-problema']), nota], senao: [] },
       { id: 'falhou_de_novo', tipo: 'se', condicao: { campo: situacao, op: 'igual', valor: 'falhou' },
         entao: [{ id: 'tudo_que_tentou', tipo: 'resumir', le: %w[mensagens_com_respostas], linhas: 4,
                   destino: { avisar: para_a_fernanda } }], senao: [] }]
    end
  end

  def contato = whatsapp.contact_inboxes.order(:id).first.contact
  def conversa = whatsapp.conversations.order(:id).first
  def conversa_do_email = Conversation.find_by!(inbox: caixa_de_email, contact: contato)
  def no_numero_novo = Conversation.joins(:contact_inbox).find_by!(contact_inboxes: { source_id: '5511988880019' })
  def historico = historico_de(automacao)
  def pedidos_da_ia(schema) = ia_recebeu.select { |corpo| corpo.dig('text', 'format', 'name') == schema }

  # A Paula responde pela API da tela; o SendReplyJob manda pela Graph, que devolve o wamid.
  def paula_manda(texto)
    post "/api/v1/accounts/#{account.id}/conversations/#{conversa.display_id}/messages",
         params: { private: false, content: texto }, headers: paula.create_new_auth_token
    expect(response).to have_http_status(:ok), -> { "a mensagem não foi criada: #{response.body}" }
    rodar_jobs
    conversa.messages.outgoing.order(:id).last
  end

  # O status da Cloud para a mensagem, como a Meta manda: `failed` com o erro, ou `delivered`.
  def cloud_avisa(mensagem, status, recipient)
    estado = { id: mensagem.source_id, status: status, timestamp: Time.current.to_i.to_s, recipient_id: recipient }
    estado[:errors] = [{ code: 131_026, title: 'Message undeliverable' }] if status == 'failed'
    valor = { messaging_product: 'whatsapp', statuses: [estado],
              metadata: { display_phone_number: canal.phone_number.delete('+'), phone_number_id: canal.provider_config['phone_number_id'] } }
    corpo = { object: 'whatsapp_business_account', entry: [{ id: 'waba-fechamento', changes: [{ field: 'messages', value: valor }] }] }
    webhook_da_meta("/webhooks/whatsapp/#{canal.phone_number}", corpo, :WHATSAPP_APP_SECRET)
    rodar_jobs
  end

  def comeca
    ligar_automacao(fernanda, account, automacao)
    recusada = paula_manda(boleto)
    cloud_avisa(recusada, 'failed', '5511900000019')
    recusada
  end

  # O Bruno responde ao e-mail: a mensagem chega na conversa do e-mail, como o recebimento da caixa grava.
  def bruno_responde_o_email
    travel_to(fuso.parse('2026-11-03 14:00'))
    create(:message, conversation: conversa_do_email, account: account, inbox: caixa_de_email, message_type: :incoming,
                     sender: contato, content: resposta)
    rodar_jobs
    perform_enqueued_jobs(only: Autonomia::Automacao::AvancarJob) { Autonomia::Automacao::VarreduraJob.perform_now }
    rodar_jobs
  end

  def varredura_em(instante)
    travel_to(instante)
    perform_enqueued_jobs(only: Autonomia::Automacao::AvancarJob) { Autonomia::Automacao::VarreduraJob.perform_now }
    rodar_jobs
  end

  before do
    travel_to(fuso.parse('2026-11-03 10:00'))
    account.update!(locale: 'pt_BR', reporting_timezone: fuso.name, custom_attributes: { 'timezone' => fuso.name })
    flags_do_piloto(account)
    account.enable_features!('automacao_gatilhos')
    whatsapp.update!(enable_auto_assignment: false)
    [fernanda, paula].each { |pessoa| create(:inbox_member, user: pessoa, inbox: whatsapp) }
    create(:inbox_member, user: paula, inbox: caixa_de_email)
    create(:label, account: account, title: 'número-com-problema')
    create(:custom_attribute_definition, account: account, attribute_key: 'numero_novo', attribute_display_name: 'Número novo',
                                         attribute_model: 'contact_attribute', attribute_display_type: 'text')
    canal.update!(message_templates: [{ 'name' => 'retomar_contato', 'language' => 'pt_BR', 'status' => 'APPROVED',
                                        'category' => 'UTILITY', 'components' => [{ 'type' => 'BODY', 'text' => 'Oi {{1}}, {{2}}.' }] }])
    receptor_whatsapp_cloud
    ia_responde(account, roteiro)
    clear_enqueued_jobs
    cliente_escreve_pela_cloud(canal, remetente: '5511900000019', nome: 'Bruno', texto: 'Oi, quero a segunda via do boleto')
    contato.update!(email: 'bruno@exemplo.com.br')
    conversa.update!(assignee: paula)
  end

  after do
    Current.reset
  end

  it 'passos 1 e 2: a recusa põe a etiqueta no contato e manda por e-mail o mesmo conteúdo, com a pergunta', :aggregate_failures do
    recusada = comeca

    expect(recusada.reload.status).to eq('failed')
    expect(contato.reload.label_list).to eq(['número-com-problema'])
    expect(conversa_do_email.messages.outgoing.sole).to have_attributes(content: "#{boleto}#{pergunta}", status: 'sent')
    expect(ActionMailer::Base.deliveries.last).to have_attributes(to: ['bruno@exemplo.com.br'], subject: 'Você trocou de WhatsApp?')
    expect(historico).to eq([['etiqueta', 'ok', nil], ['tem_email', 'ok', nil], ['email', 'ok', nil], ['respondeu', 'ok', nil]])
  end

  it 'passos 3 e 4: o Bruno responde o e-mail; a IA lê a resposta, o contato ganha o número novo e o recado sai nele ' \
     'pelo modelo "Retomar contato"', :aggregate_failures do
    comeca
    bruno_responde_o_email

    expect(pedidos_da_ia('automacao_extrair').sole['input'].to_json).to include('Meu número novo é (11) 98888-0019')
    expect(contato.reload.phone_number).to eq('+5511988880019')
    expect(no_numero_novo.messages.outgoing.sole.content).to eq('Oi Bruno, seu boleto vence sexta, segue o código 123.')
    pedido = chamadas_para('graph.facebook.com').last.corpo
    expect(pedido).to include('to' => '5511988880019', 'type' => 'template')
    expect(pedido.dig('template', 'name')).to eq('retomar_contato')
    expect(historico.map(&:first)).to eq(%w[etiqueta tem_email email respondeu respondeu numero_novo telefone recado retomar chegou])
  end

  it 'passo 3: a resposta do e-mail que a Paula não vê fica fora da IA, e o histórico diz qual conversa', :aggregate_failures do
    InboxMember.where(user: paula, inbox: caixa_de_email).delete_all
    comeca
    bruno_responde_o_email

    expect(pedidos_da_ia('automacao_extrair').sole['input'].to_json).not_to include('Meu número novo é')
    registro = Autonomia::Automacao::Registro.find_by!(automacao_id: automacao['id'], passo: 'numero_novo')
    expect(registro.dados['conversas_fora']).to eq([conversa_do_email.display_id])
  end

  it 'passo 5: o recado chega no número novo; a etiqueta sai e o contato ganha a nota "número trocado em 03/11"',
     :aggregate_failures do
    comeca
    bruno_responde_o_email
    cloud_avisa(no_numero_novo.messages.outgoing.sole, 'delivered', '5511988880019')

    expect(contato.reload.label_list).to be_empty
    expect(contato.notes.pluck(:content)).to eq(['número trocado em 03/11'])
    expect(historico.last(5)).to eq([['chegou', 'ok', nil], ['entregue', 'ok', nil], ['tira_etiqueta', 'ok', nil], ['nota', 'ok', nil],
                                     ['falhou_de_novo', 'ok', nil]])
  end

  it 'passo 6: sem resposta em 3 dias, a Paula ganha o retorno para ligar e o aviso', :aggregate_failures do
    comeca
    varredura_em(fuso.parse('2026-11-06 10:05'))

    expect(Crm::FollowUp.sole).to have_attributes(title: 'Ligar para Bruno: o WhatsApp recusou', recipient_user_ids: [paula.id])
    expect(Notification.where(user: paula, notification_type: 'conversation_mention')).to exist
    expect(historico.last(4).map(&:first)).to eq(%w[respondeu sem_resposta_ligar sem_resposta_avisa sem_resposta_fim])
  end

  it 'passo 6: sem e-mail, o retorno e o aviso saem na hora, e nada vai por e-mail', :aggregate_failures do
    contato.update!(email: nil)
    comeca

    expect(Conversation.where(inbox: caixa_de_email)).to be_empty
    expect(Crm::FollowUp.sole).to have_attributes(title: 'Ligar para Bruno: o WhatsApp recusou', recipient_user_ids: [paula.id])
    expect(historico.map(&:first)).to eq(%w[etiqueta tem_email sem_email_ligar sem_email_avisa sem_email_fim])
  end

  it 'passo 7: falhou de novo no número novo; a Fernanda recebe o resumo do e-mail e do modelo tentados', :aggregate_failures do
    comeca
    bruno_responde_o_email
    cloud_avisa(no_numero_novo.messages.outgoing.sole, 'failed', '5511988880019')

    entrada = JSON.parse(pedidos_da_ia('automacao_resumir').sole['input'].first['content'].first['text'])['conversa']
    expect(entrada['automation_sends'].pluck('channel')).to eq(%w[email whatsapp])
    expect(Notification.where(user: fernanda, notification_type: 'conversation_mention')).to exist
    expect(historico.last(3)).to eq([['entregue', 'ok', nil], ['falhou_de_novo', 'ok', nil], ['tudo_que_tentou', 'ok', nil]])
  end
end
