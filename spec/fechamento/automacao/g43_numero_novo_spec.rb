require 'rails_helper'

# Fechamento do épico #2414, G43 (#2700): o exemplo 19, "Cliente que sumiu do WhatsApp", passos 4 e 7.
#
# > 4. A IA escreve o recado que tinha falhado e manda ao número novo dentro do modelo aprovado "Retomar contato".
# > 7. Falhou de novo no número novo: avisa a Fernanda com um **resumo** de tudo o que foi tentado.
#
# O gatilho é o do termo: o WhatsApp recusa a mensagem ao Bruno (G8). O telefone dele já foi atualizado (passo 3; o
# ramo do e-mail e a resposta estão no lote 3, #2680). A conversa do WhatsApp oficial nasceu no número antigo, que
# acabou de falhar, e a mensagem sai na do número novo, na mesma caixa: conversa nova no número oficial só sai com
# modelo, e a Graph recebe o número novo. A espera do envio (G34) lê a mensagem que saiu lá; a recusa de novo não
# começa outra execução da mesma automação (a cadeia segue a de quem mandou).
# O resumo do passo 7 é o "resumir" da G42 (EnviosDaExecucao): lê o e-mail que a execução mandou (passo 2, em conversa
# própria) e o modelo recusado no número novo. O e-mail aqui só pergunta pelo número: "o mesmo conteúdo" é a G53.
# A dona monta e liga pela API da tela; a IA é o dublê. O exemplo inteiro segue no pendentes_spec até a G53 fechar.
RSpec.describe 'Fechamento #2414 · G43: mandar ao número novo', :automacao_motor, :fechamento_automacao, type: :request do
  include ActiveJob::TestHelper

  # O e-mail do passo 2 sai de verdade pelo ActionMailer, como no exemplo 1.
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
  let(:fernanda) { create(:user, account: account, role: :administrator, name: 'Fernanda Gerente') }
  let(:bruno) { create(:contact, account: account, name: 'Bruno', phone_number: '+5511900000019', email: 'bruno@exemplo.test') }
  let(:numero_antigo) { create(:contact_inbox, inbox: canal.inbox, contact: bruno, source_id: '5511900000019') }
  let(:conversa) { create(:conversation, account: account, inbox: canal.inbox, contact: bruno, contact_inbox: numero_antigo) }
  let(:caixa_de_email) { create(:channel_email, account: account).inbox }
  let(:resumo) { 'Tentamos o e-mail "Você trocou de WhatsApp?" e o modelo "Retomar contato" no número novo; os dois sem resposta.' }
  let(:roteiro) do
    { 'automacao_escrever' => { 'texto' => 'sua apólice vence em 30 dias' }, 'automacao_resumir' => { 'resumo' => resumo } }
  end

  before do
    account.update!(locale: 'pt_BR')
    flags_do_piloto(account)
    create(:inbox_member, user: fernanda, inbox: canal.inbox)
    canal.update!(message_templates: [{ 'name' => 'retomar_contato', 'language' => 'pt_BR', 'status' => 'APPROVED',
                                        'category' => 'UTILITY',
                                        'components' => [{ 'type' => 'BODY', 'text' => 'Oi {{1}}, {{2}}.' }] }])
    receptor_whatsapp_cloud
    ia_responde(account, roteiro)
    create(:message, conversation: conversa, account: account, inbox: canal.inbox, message_type: :incoming, sender: bruno,
                     content: 'Oi', created_at: 2.days.ago)
    clear_enqueued_jobs
  end

  after { Current.reset }

  def receita
    { gatilho: { tipo: 'mensagem.falhou' }, passos: [pergunta_por_email, *retomar_no_numero_novo] }
  end

  # Passo 2: tem e-mail, pergunta pelo número novo.
  def pergunta_por_email
    email = { id: 'por_email', tipo: 'email', caixa_id: caixa_de_email.id, assunto: ['Você trocou de WhatsApp?'],
              texto: ['Me responde com o número novo.'] }
    { id: 'tem_email', tipo: 'se', condicao: { campo: { '$valor' => 'contato.email' }, op: 'preenchido' }, entao: [email], senao: [] }
  end

  # Passos 4 e 7.
  def retomar_no_numero_novo
    recado = { id: 'recado', tipo: 'escrever', destino: 'guardar', instrucao: 'Reescreva o recado da renovação que não chegou.' }
    retomar = { id: 'retomar', tipo: 'mensagem', texto: ['Oi, Bruno.'],
                modelo: { nome: 'retomar_contato', idioma: 'pt_BR',
                          variaveis: [[{ '$valor' => 'contato.nome' }], [{ '$valor' => 'ia.recado' }]] } }
    chegou = { id: 'chegou', tipo: 'esperar_ate', prazo: { valor: 1, unidade: 'horas' },
               condicao: { campo: { '$valor' => 'envio.situacao' }, op: 'diferente', valor: 'saiu' } }
    falhou = { id: 'falhou', tipo: 'se', condicao: { campo: { '$valor' => 'envio.situacao' }, op: 'igual', valor: 'falhou' },
               entao: [{ id: 'tudo_que_tentou', tipo: 'resumir', le: %w[mensagens_com_respostas], linhas: 4,
                         destino: { avisar: { pessoas: [fernanda.id] } } }],
               senao: [] }
    [recado, retomar, chegou, falhou]
  end

  def no_numero_novo = Conversation.joins(:contact_inbox).find_by!(contact_inboxes: { source_id: '5511988880019' })

  def comeca
    automacao = montar_automacao(fernanda, account, nome: 'Cliente que sumiu', receita: receita)
    ligar_automacao(fernanda, account, automacao)
    recado = create(:message, conversation: conversa, account: account, inbox: canal.inbox, message_type: :outgoing,
                              content: 'Sua apólice vence em 30 dias.')
    bruno.update!(phone_number: '+5511988880019')
    clear_enqueued_jobs
    recado.update!(status: :failed)
    rodar_jobs
    automacao
  end

  it 'passo 4: o recado sai no modelo "Retomar contato", na conversa do número novo, e a Graph recebe o número novo',
     :aggregate_failures do
    automacao = comeca
    nova = no_numero_novo

    expect(nova).to have_attributes(inbox_id: canal.inbox.id, contact_id: bruno.id)
    expect(nova.messages.outgoing.sole.content).to eq('Oi Bruno, sua apólice vence em 30 dias.')
    expect(conversa.messages.outgoing.pluck(:status)).to eq(['failed'])
    expect(ActionMailer::Base.deliveries.last).to have_attributes(to: ['bruno@exemplo.test'], subject: 'Você trocou de WhatsApp?')
    pedido = chamadas_para('graph.facebook.com').last.corpo
    expect(pedido).to include('to' => '5511988880019', 'type' => 'template')
    expect(pedido.dig('template', 'name')).to eq('retomar_contato')
    expect(historico_de(automacao)).to eq([['tem_email', 'ok', nil], ['por_email', 'ok', nil], ['recado', 'ok', nil], ['retomar', 'ok', nil],
                                           ['chegou', 'ok', nil]])
  end

  def pedidos_da_ia(schema) = ia_recebeu.select { |corpo| corpo.dig('text', 'format', 'name') == schema }

  it 'passo 7: a recusa no número novo acorda a espera, e a Fernanda recebe, na conversa do número novo, o resumo do e-mail ' \
     'e do modelo tentados', :aggregate_failures do
    automacao = comeca
    nova = no_numero_novo

    travel(5.minutes) do
      nova.messages.outgoing.sole.update!(status: :failed)
      rodar_jobs
    end

    expect(historico_de(automacao).map(&:first)).to eq(%w[tem_email por_email recado retomar chegou chegou falhou tudo_que_tentou])
    expect(Autonomia::Automacao::Execucao.where(automacao_id: automacao['id']).count).to eq(1)
    expect(historico_de(automacao).last).to eq(['tudo_que_tentou', 'ok', nil])
    # A IA é o dublê, mas o que ela recebe é o de verdade: tudo o que a execução tentou.
    entrada = JSON.parse(pedidos_da_ia('automacao_resumir').sole['input'].first['content'].first['text'])['conversa']
    expect(entrada['automation_sends']).to eq([
                                                { 'channel' => 'email', 'subject' => 'Você trocou de WhatsApp?',
                                                  'text' => 'Me responde com o número novo.' },
                                                { 'channel' => 'whatsapp', 'text' => 'Oi Bruno, sua apólice vence em 30 dias.',
                                                  'not_delivered' => true }
                                              ])
    expect(nova.messages.where(private: true).last.content).to include(resumo)
    expect(Notification.where(user: fernanda, notification_type: 'conversation_mention')).to exist
  end
end
