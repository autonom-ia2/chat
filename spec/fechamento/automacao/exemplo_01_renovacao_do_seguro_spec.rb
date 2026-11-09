require 'rails_helper'

# Fechamento do épico #2414 (F9.6), exemplo 1 dos termos de aceite: "Renovação do seguro sem esquecer ninguém".
#
# > "Quando faltar um mês pro seguro do cliente vencer, o sistema chama ele. Se ele trocou de carro, me avisa. Se não
# > responder, manda ele marcar um horário comigo." — Marcos, corretor
#
# Começa quando: faltam 30 dias para o vencimento da apólice, gravado no card.
#   1. Move o card para "Renovação" e põe a etiqueta "renovação".
#   2. Manda a mensagem de renovação pelo modelo aprovado do WhatsApp, com o nome do cliente e o carro.
#   3. Se o WhatsApp recusar e o cliente tiver e-mail, manda por e-mail.
#   4. Espera a resposta, por até 7 dias.
#   5. A IA extrai da resposta se mudou carro, endereço ou condutor, e atualiza o card.
#   6. A IA decide: "mudou algo", "quer renovar igual", "quer cancelar" ou "nenhum desses".
#   7. Mudou algo: cria o retorno "recotar" para o Marcos, para hoje.
#   8. Quer renovar igual: move para "Renovar igual" e avisa o Marcos.
#   9. Quer cancelar: avisa o Marcos com um resumo da conversa e cria retorno para ligar.
#  10. Sem resposta em 7 dias: manda, pelo modelo aprovado, o link da agenda do Marcos para 15 minutos de conversa.
#  11. Reunião marcada: move para "Reunião marcada". Reunião cancelada: manda o link de novo.
#  12. Faltando 5 dias e ainda sem resposta: avisa o Marcos com um resumo de tudo o que foi tentado.
# Resultado: toda manhã a coluna "Renovação" já está separada, e os 5 dias finais chegam com o resumo pronto.
#
# Montado como o Marcos montaria, pela API da tela, em três automações: a do vencimento (passos 1 a 10 e 12, G6, G1,
# G34, G2, G11, G3, G12, G42), a da reunião marcada e a da reunião cancelada (passo 11, G12). Os passos 1 a 10 e o 12
# são uma execução só: o resumo do passo 12 conta o que ela tentou, e por isso o e-mail sai dela (o ramo da G34) e não
# de outra automação pelo gatilho de falha (G8). O cliente marca pela página de agendamento do Marcos, pelo serviço
# real (Crm::BookingV2::Booker), que põe a reunião no card aberto do funil. Mensagem fora da janela de 24 h vai pelo
# modelo aprovado e para no receptor do WhatsApp oficial, que entrega ou recusa como a Graph; a IA é o dublê.
# Desenho e lacunas: docs/automacao/F9-fechamento-20-exemplos.md.
#
# - Passo 3: o WhatsApp recusa na hora (a Graph responde com erro, e o SendReplyJob marca a mensagem); a espera curta
#   lê `envio.situacao` e, recusada, o e-mail leva o mesmo texto (`envio.texto`). Entregue, a espera vence e segue. O
#   e-mail sai pelo envio de sempre da caixa (SendReplyJob, ConversationReplyMailer) e para no
#   `ActionMailer::Base.deliveries`. Sem o SMTP_ADDRESS o mailer não manda e a mensagem fica recusada; e o ambiente de
#   teste entrega por sendmail (config/initializers/mailer.rb), por isso o spec troca a entrega por :test e devolve.
# - Passo 5, "atualiza o card": o extrair grava na conversa, e uma ação por campo copia para o card ($valor, G16), como
#   no exemplo 13. Uma por campo porque valor vazio pula a ação inteira, e o cliente costuma mudar só uma coisa.
# - Passo 12, "faltando 5 dias": o gatilho é 30 dias antes; 7 dias da 1ª espera e 18 da 2ª chegam aos 5 do vencimento.
# - A etiqueta "renovação" se escreve `renovação`: nome de etiqueta na plataforma é minúsculo e sem espaço.
RSpec.describe 'Fechamento #2414 · exemplo 1: renovação do seguro sem esquecer ninguém', :fechamento_automacao, type: :request do
  include ActiveJob::TestHelper

  around do |exemplo|
    metodo = ActionMailer::Base.delivery_method
    ActionMailer::Base.delivery_method = :test
    ActionMailer::Base.deliveries.clear
    with_modified_env(CRM_KANBAN_ENABLED: 'true', CRM_CALENDAR_MEETINGS_ENABLED: 'true', SMTP_ADDRESS: 'smtp.fechamento.test') do
      exemplo.run
    end
  ensure
    ActionMailer::Base.delivery_method = metodo
  end

  let(:canal) { create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false) }
  let(:account) { canal.account }
  let(:caixa_de_email) { create(:channel_email, account: account).inbox }
  let(:marcos) { create(:user, account: account, role: :administrator, name: 'Marcos') }
  let(:cliente) { create(:contact, account: account, name: 'Daniel', phone_number: '+5511900000001', email: 'daniel@exemplo.test') }
  let(:contact_inbox) { create(:contact_inbox, inbox: canal.inbox, contact: cliente, source_id: '5511900000001') }
  let(:conversa) { create(:conversation, account: account, inbox: canal.inbox, contact: cliente, contact_inbox: contact_inbox) }
  let(:funil_e_entrada) { create_crm_pipeline(account: account, user: marcos, name: 'Apólices') }
  let(:renovacao) { create_crm_stage(account: account, pipeline: funil, name: 'Renovação', position: 1) }
  let(:renovar_igual) { create_crm_stage(account: account, pipeline: funil, name: 'Renovar igual', position: 2) }
  let(:reuniao_marcada) { create_crm_stage(account: account, pipeline: funil, name: 'Reunião marcada', position: 3) }
  let(:agenda) do
    create_booking_profile(account: account, host: marcos, pipeline: funil, stage: renovacao, title: 'Renovação do seguro',
                           duration_minutes: 15)
  end
  let(:card) do
    account.crm_cards.create!(pipeline: funil, stage: funil_e_entrada.last, inbox: canal.inbox, contact: cliente, primary_conversation: conversa,
                              owner: marcos, title: 'Seguro do Corolla', currency: 'BRL',
                              custom_attributes: { 'vencimento' => '2026-12-20', 'carro' => 'Corolla 2022',
                                                   'endereco' => 'Rua das Flores, 10', 'condutor' => 'Daniel' })
  end
  let(:roteiro) do
    { 'automacao_extrair' => { 'carro' => nil, 'endereco' => nil, 'condutor' => nil },
      'automacao_resumir' => { 'resumo' => 'Tentamos o WhatsApp, que recusou, o e-mail "Renovação do seu seguro" e o link da agenda. ' \
                                           'O Daniel não respondeu.' } }
  end

  def fuso = ActiveSupport::TimeZone['America/Sao_Paulo']
  def funil = funil_e_entrada.first
  def nome = { '$valor' => 'contato.nome' }
  def carro = { '$valor' => 'card.atributos.carro' }
  def link_da_agenda = { '$valor' => 'card.link_da_agenda' }
  def card_id = { '$valor' => 'card.id' }
  def para_o_marcos = { pessoas: [marcos.id] }
  def respondeu = { campo: { '$valor' => 'conversa.cliente_respondeu' }, op: 'igual', valor: true }
  def modelo(nome_do_modelo, *variaveis) = { nome: nome_do_modelo, idioma: 'pt_BR', variaveis: [[nome], *variaveis] }

  def mensagem(id, nome_do_modelo, texto, *variaveis)
    { id: id, tipo: 'mensagem', texto: texto, modelo: modelo(nome_do_modelo, *variaveis) }
  end

  def mover(id, etapa)
    { id: id, tipo: 'acao', acao: 'POST crm/cards/:id/move', descricao: "Levar para #{etapa.name}", caminho: { id: card_id },
      corpo: { stage_id: etapa.id } }
  end

  def link_por_modelo(id)
    mensagem(id, 'renovacao_agenda', ['Oi ', nome, ', vamos conversar 15 minutos sobre a renovação? Marque aqui: ', link_da_agenda],
             [link_da_agenda])
  end

  # Passos 1 a 10 e 12, a partir de 30 dias antes do vencimento.
  def receita_do_vencimento
    { gatilho: { tipo: 'card.data', campo: 'vencimento', dias: 30, quando: 'antes', hora: 9 }, passos: [
      mover('renovacao', renovacao),
      { id: 'etiqueta', tipo: 'acao', acao: 'PATCH conversations/:conversation_id/labels/alterar', descricao: 'Pôr a etiqueta renovação',
        caminho: { conversation_id: { '$valor' => 'conversa.id' } }, corpo: { por: ['renovação'] } },
      mensagem('aviso', 'renovacao', ['Oi ', nome, ', o seguro do seu ', carro, ' vence em 30 dias. Vamos renovar?'], [carro]),
      *se_o_whatsapp_recusar,
      { id: 'resposta', tipo: 'esperar_ate', condicao: respondeu, prazo: { valor: 7, unidade: 'dias' }, se_vencer: sem_resposta },
      { id: 'mudancas', tipo: 'extrair', le: %w[mensagens_recentes], campos: [
        { chave: 'carro', descricao: 'o carro novo, se o cliente trocou de carro', destino: 'conversa.atributos.carro' },
        { chave: 'endereco', descricao: 'o endereço novo, se o cliente mudou de endereço', destino: 'conversa.atributos.endereco' },
        { chave: 'condutor', descricao: 'o condutor novo, se mudou quem dirige o carro', destino: 'conversa.atributos.condutor' }
      ] },
      *%w[carro endereco condutor].map { |chave| para_o_card(chave) },
      decidir_a_resposta
    ] }
  end

  # Passo 3: a espera curta acorda quando o canal confirma ou recusa; recusou e o cliente tem e-mail, vai o mesmo texto.
  def se_o_whatsapp_recusar
    situacao = { '$valor' => 'envio.situacao' }
    tem_email = { campo: { '$valor' => 'contato.email' }, op: 'preenchido' }
    email = { id: 'por_email', tipo: 'email', caixa_id: caixa_de_email.id, assunto: ['Renovação do seu seguro'],
              texto: [{ '$valor' => 'envio.texto' }] }
    [{ id: 'chegou', tipo: 'esperar_ate', condicao: { campo: situacao, op: 'diferente', valor: 'saiu' }, prazo: { valor: 1, unidade: 'horas' } },
     { id: 'recusou', tipo: 'se', condicao: { todas: [{ campo: situacao, op: 'igual', valor: 'falhou' }, tem_email] }, entao: [email],
       senao: [] }]
  end

  # Passos 10 e 12: sem resposta em 7 dias, o link da agenda; faltando 5 dias e ainda sem resposta, o resumo ao Marcos.
  def sem_resposta
    [link_por_modelo('agenda'),
     { id: 'ainda', tipo: 'esperar_ate', condicao: respondeu, prazo: { valor: 18, unidade: 'dias' }, se_vencer: [
       { id: 'tudo_que_tentou', tipo: 'resumir', le: %w[mensagens_com_respostas], linhas: 4, destino: { avisar: para_o_marcos } },
       { id: 'fim', tipo: 'parar' }
     ] }]
  end

  def para_o_card(chave)
    { id: "#{chave}_no_card", tipo: 'acao', acao: 'PATCH crm/cards/:id', descricao: "Gravar #{chave} no card", caminho: { id: card_id },
      corpo: { card: { custom_attributes: { chave => { '$valor' => "conversa.atributos.#{chave}" } } } } }
  end

  # Passos 6 a 9.
  def decidir_a_resposta
    { id: 'o_que_quer', tipo: 'decidir', le: %w[mensagens_recentes], pergunta: 'O que o cliente respondeu sobre a renovação do seguro?',
      caminhos: [
        { nome: 'Mudou algo', chave: 'mudou_algo', descricao: 'trocou de carro, de endereço ou de condutor', passos: [
          { id: 'recotar', tipo: 'retorno', titulo: ['Recotar o seguro de ', nome], daqui: { valor: 1, unidade: 'horas' },
            para: { quem: 'pessoas', pessoas: [marcos.id] } }
        ] },
        { nome: 'Quer renovar igual', chave: 'renovar_igual', descricao: 'quer renovar sem mudar nada', passos: [
          mover('para_renovar_igual', renovar_igual),
          { id: 'avisa_renovar', tipo: 'avisar', para: para_o_marcos, texto: [nome, ' quer renovar o seguro igual.'] }
        ] },
        { nome: 'Quer cancelar', chave: 'cancelar', descricao: 'não quer renovar ou quer cancelar o seguro', passos: [
          { id: 'resumo_cancelar', tipo: 'resumir', le: %w[mensagens_com_respostas], linhas: 3, destino: { avisar: para_o_marcos } },
          { id: 'ligar', tipo: 'retorno', titulo: ['Ligar para ', nome, ' sobre o cancelamento'], daqui: { valor: 1, unidade: 'horas' },
            para: { quem: 'pessoas', pessoas: [marcos.id] } }
        ] }
      ],
      nenhum: [] }
  end

  # Passo 11, nas duas pontas da reunião.
  def receita_da_reuniao_marcada
    { gatilho: { tipo: 'card.reuniao_marcada', funil_id: funil.id }, passos: [mover('para_reuniao_marcada', reuniao_marcada)] }
  end

  def receita_da_reuniao_cancelada = { gatilho: { tipo: 'card.reuniao_cancelada', funil_id: funil.id }, passos: [link_por_modelo('de_novo')] }

  def atributo(chave, modelo_do_atributo, tipo)
    create(:custom_attribute_definition, account: account, attribute_key: chave, attribute_display_name: chave,
                                         attribute_model: modelo_do_atributo, attribute_display_type: tipo)
  end

  def modelos_aprovados
    { 'renovacao' => 'Oi {{1}}, o seguro do seu {{2}} vence em 30 dias. Vamos renovar?',
      'renovacao_agenda' => 'Oi {{1}}, vamos conversar 15 minutos sobre a renovação? Marque aqui: {{2}}' }.map do |nome_do_modelo, texto|
      { 'name' => nome_do_modelo, 'language' => 'pt_BR', 'status' => 'APPROVED', 'category' => 'UTILITY',
        'components' => [{ 'type' => 'BODY', 'text' => texto }] }
    end
  end

  def preparar_conta
    account.update!(locale: 'pt_BR', reporting_timezone: fuso.name, custom_attributes: { 'timezone' => fuso.name })
    flags_do_piloto(account)
    account.enable_features!('automacao_gatilhos', 'crm_booking_v2')
    create(:inbox_member, user: marcos, inbox: canal.inbox)
    criar_campos
    create(:label, account: account, title: 'renovação', description: 'Apólice em renovação')
    canal.update!(message_templates: modelos_aprovados)
    [renovar_igual, reuniao_marcada, agenda, caixa_de_email, card]
  end

  # Os campos do card que o Marcos criou, e os da conversa onde o extrair grava antes de copiar para o card.
  def criar_campos
    atributo('vencimento', 'card_attribute', 'date')
    %w[carro endereco condutor].each do |chave|
      atributo(chave, 'card_attribute', 'text')
      atributo(chave, 'conversation_attribute', 'text')
    end
  end

  def ligar_tudo
    { vencimento: receita_do_vencimento, reuniao_marcada: receita_da_reuniao_marcada,
      reuniao_cancelada: receita_da_reuniao_cancelada }.each do |nome_da, receita|
      ligar_automacao(marcos, account, montar_automacao(marcos, account, nome: "Renovação: #{nome_da}", receita: receita))
    end
  end

  # O WhatsApp que recusa: a Graph responde com erro, como para um número sem WhatsApp, e o receptor grava o pedido.
  def whatsapp_recusa
    stub_request(:post, ->(uri) { uri.host == 'graph.facebook.com' }).to_return do |pedido|
      receptor << FechamentoAutomacao::Chamada.new(metodo: 'POST', host: pedido.uri.host, caminho: pedido.uri.path, corpo: JSON.parse(pedido.body))
      { status: 400, body: { error: { message: '(#131026) Message undeliverable', code: 131_026 } }.to_json,
        headers: { 'Content-Type' => 'application/json' } }
    end
  end

  # Um job por vez, como no Sidekiq, com o do evento do card no meio.
  def drenar
    drenados = [*FechamentoAutomacao::JOBS, Autonomia::Automacao::EventoDoCardJob]
    FechamentoAutomacao::LIMITE_DE_JOBS.times do
      job = enqueued_jobs.find { |item| drenados.include?(item[:job]) }
      return unless job

      enqueued_jobs.delete(job)
      job[:job].perform_now(*ActiveJob::Arguments.deserialize(job[:args]))
    end
    raise "a fila não esvaziou em #{FechamentoAutomacao::LIMITE_DE_JOBS} jobs"
  end

  def as(hora, &) = travel_to(fuso.parse(hora), &)

  # A varredura acha os gatilhos de data e acorda as esperas vencidas; os jobs que ela abre rodam um por vez.
  def varredura_as(hora)
    as(hora) do
      Autonomia::Automacao::TempoJob.perform_now
      perform_enqueued_jobs(only: Autonomia::Automacao::TempoDaAutomacaoJob)
      perform_enqueued_jobs(only: Autonomia::Automacao::AvancarJob) { Autonomia::Automacao::VarreduraJob.perform_now }
      drenar
    end
  end

  def cliente_responde_as(hora, texto)
    as(hora) do
      create(:message, conversation: conversa, account: account, inbox: canal.inbox, message_type: :incoming, sender: cliente, content: texto)
      drenar
      perform_enqueued_jobs(only: Autonomia::Automacao::AvancarJob) { Autonomia::Automacao::VarreduraJob.perform_now }
      drenar
    end
  end

  # O Daniel marca pela página do link que recebeu, como qualquer cliente: nome, WhatsApp e horário.
  def daniel_marca_as(hora, horario)
    as(hora) do
      Crm::BookingV2::Booker.new(profile: agenda, name: 'Daniel', phone: '(11) 90000-0001', starts_at: fuso.parse(horario).iso8601,
                                 source: 'public_link').perform
      drenar
    end
  end

  def link = Crm::BookingV2::ShortLink.url_for(agenda)
  def whatsapp = chamadas_para('graph.facebook.com')
  def modelos_enviados = whatsapp.filter_map { |chamada| chamada.corpo.dig('template', 'name') }
  def parametros(chamada) = chamada.corpo.dig('template', 'components', 0, 'parameters').pluck('text')
  def pedidos_da_ia(schema) = ia_recebeu.select { |corpo| corpo.dig('text', 'format', 'name') == schema }
  def mencoes_para(pessoa) = Notification.where(user: pessoa, notification_type: 'conversation_mention')
  def notas = conversa.messages.where(private: true).pluck(:content)
  def conversa_do_email = Conversation.find_by!(inbox: caixa_de_email, contact: cliente)
  def historico(nome_da) = Autonomia::Automacao::Registro.where(automacao_id: automacao_id(nome_da)).order(:id).pluck(:passo, :resultado, :motivo)
  def automacao_id(nome_da) = Autonomia::Automacao::Definicao.find_by!(account: account, nome: "Renovação: #{nome_da}").id
  def texto_do_aviso = 'Oi Daniel, o seguro do seu Corolla 2022 vence em 30 dias. Vamos renovar?'
  def texto_do_link = "Oi Daniel, vamos conversar 15 minutos sobre a renovação? Marque aqui: #{link}"

  before do
    receptor_whatsapp_cloud
    ia_responde(account, roteiro)
    as('2026-11-10 10:00') do
      preparar_conta
      ligar_tudo
      clear_enqueued_jobs
    end
  end

  after { Current.reset }

  context 'with o WhatsApp entregando (passos 1, 2 e 4 a 11)' do
    before do
      varredura_as('2026-11-20 09:30')
      varredura_as('2026-11-20 10:45')
    end

    it 'passos 1 e 2: 30 dias antes, o card vai para "Renovação", ganha a etiqueta e o modelo leva o nome e o carro',
       :aggregate_failures do
      expect(card.reload.stage_id).to eq(renovacao.id)
      expect(conversa.reload.label_list).to include('renovação')
      expect(modelos_enviados).to eq(%w[renovacao])
      expect(parametros(whatsapp.sole)).to eq(['Daniel', 'Corolla 2022'])
      expect(Conversation.where(inbox: caixa_de_email)).to be_empty
      expect(historico(:vencimento)).to eq([['renovacao', 'ok', nil], ['etiqueta', 'ok', nil], ['aviso', 'ok', nil], ['chegou', 'ok', nil],
                                            %w[chegou pulado prazo_vencido], ['recusou', 'ok', nil], ['resposta', 'ok', nil]])
    end

    it 'passos 4, 5, 6 e 7: trocou de carro; a IA grava a mudança no card e o Marcos ganha o retorno "recotar" para hoje',
       :aggregate_failures do
      roteiro['automacao_extrair'] = { 'carro' => 'Compass 2024', 'endereco' => nil, 'condutor' => nil }
      roteiro['automacao_decidir'] = { 'caminho' => 'mudou_algo', 'motivo' => 'trocou o Corolla por um Compass' }

      cliente_responde_as('2026-11-22 14:00', 'Oi Marcos! Troquei o Corolla por um Compass 2024 mês passado.')

      lido = pedidos_da_ia('automacao_extrair').sole['input'].to_json
      expect(lido).to include('Troquei o Corolla por um Compass 2024')
      expect(card.reload.custom_attributes).to include('carro' => 'Compass 2024', 'endereco' => 'Rua das Flores, 10',
                                                       'condutor' => 'Daniel', 'vencimento' => '2026-12-20')
      expect(Crm::FollowUp.sole).to have_attributes(card_id: card.id, title: 'Recotar o seguro de Daniel', recipient_mode: 'users',
                                                    recipient_user_ids: [marcos.id], due_at: fuso.parse('2026-11-22 15:00'))
      expect(historico(:vencimento).last(6)).to eq([['mudancas', 'ok', nil], ['carro_no_card', 'ok', nil],
                                                    %w[endereco_no_card pulado faltou_valor], %w[condutor_no_card pulado faltou_valor],
                                                    ['o_que_quer', 'ok', nil], ['recotar', 'ok', nil]])
    end

    it 'passo 8: quer renovar igual; o card vai para "Renovar igual" e o Marcos é avisado', :aggregate_failures do
      roteiro['automacao_decidir'] = { 'caminho' => 'renovar_igual', 'motivo' => 'quer manter tudo' }

      cliente_responde_as('2026-11-22 14:00', 'Pode renovar igual, não mudou nada.')

      expect(card.reload.stage_id).to eq(renovar_igual.id)
      expect(mencoes_para(marcos).count).to eq(1)
      expect(notas.find { |nota| nota.include?('quer renovar o seguro igual') }).to include('Daniel quer renovar o seguro igual.')
      expect(Crm::FollowUp.where(card_id: card.id)).to be_empty
    end

    it 'passo 9: quer cancelar; o Marcos recebe o resumo da conversa e o retorno para ligar', :aggregate_failures do
      roteiro['automacao_decidir'] = { 'caminho' => 'cancelar', 'motivo' => 'vai cancelar' }
      roteiro['automacao_resumir'] = { 'resumo' => 'O Daniel vendeu o carro e quer cancelar o seguro.' }

      cliente_responde_as('2026-11-22 14:00', 'Vendi o carro, quero cancelar o seguro.')

      expect(pedidos_da_ia('automacao_resumir').sole['input'].to_json).to include('Vendi o carro, quero cancelar o seguro.')
      expect(mencoes_para(marcos).count).to eq(1)
      expect(notas.find { |nota| nota.include?('quer cancelar o seguro') }).to include('O Daniel vendeu o carro e quer cancelar o seguro.')
      expect(Crm::FollowUp.sole).to have_attributes(card_id: card.id, title: 'Ligar para Daniel sobre o cancelamento',
                                                    recipient_user_ids: [marcos.id])
      expect(card.reload.stage_id).to eq(renovacao.id)
    end

    it 'passo 10: sem resposta em 7 dias, o link da agenda do Marcos vai pelo modelo aprovado', :aggregate_failures do
      varredura_as('2026-11-27 10:50')

      expect(modelos_enviados).to eq(%w[renovacao renovacao_agenda])
      expect(parametros(whatsapp.last)).to eq(['Daniel', link])
      expect(agenda.duration_minutes).to eq(15)
      expect(pedidos_da_ia('automacao_decidir')).to be_empty
    end

    it 'passo 11: marcou pela página, o card vai para "Reunião marcada"; cancelou, o link vai de novo', :aggregate_failures do
      varredura_as('2026-11-27 10:50')

      daniel_marca_as('2026-11-28 10:00', '2026-12-01 10:00')
      expect(account.crm_meetings.sole.card).to eq(card)
      expect(card.reload.stage_id).to eq(reuniao_marcada.id)

      as('2026-11-29 08:00') do
        Crm::Meetings::CancelService.new(meeting: account.crm_meetings.sole).perform
        drenar
      end
      expect(modelos_enviados).to eq(%w[renovacao renovacao_agenda renovacao_agenda])
      expect(parametros(whatsapp.last)).to eq(['Daniel', link])
      expect(historico(:reuniao_cancelada)).to eq([['de_novo', 'ok', nil]])
    end
  end

  context 'with o WhatsApp recusando (passos 3, 10 e 12)' do
    before do
      whatsapp_recusa
      varredura_as('2026-11-20 09:30')
    end

    it 'passo 3: o WhatsApp recusou e o Daniel tem e-mail; o mesmo texto sai por e-mail, numa conversa própria', :aggregate_failures do
      expect(conversa.messages.outgoing.sole).to have_attributes(status: 'failed', content: texto_do_aviso)
      expect(conversa_do_email.additional_attributes['mail_subject']).to eq('Renovação do seu seguro')
      expect(conversa_do_email.messages.outgoing.sole).to have_attributes(content: texto_do_aviso, status: 'sent', external_error: nil)
      expect(ActionMailer::Base.deliveries.last).to have_attributes(to: ['daniel@exemplo.test'], subject: 'Renovação do seu seguro')
      expect(historico(:vencimento).map(&:first)).to eq(%w[renovacao etiqueta aviso chegou chegou recusou por_email resposta])
    end

    it 'passo 12: faltando 5 dias, o Marcos recebe o resumo que leu o WhatsApp recusado, o e-mail e o link', :aggregate_failures do
      varredura_as('2026-11-27 09:45')
      varredura_as('2026-12-15 10:00')

      # Só o Marcos na conta, administrador: ele vê as duas conversas, e a do e-mail entra no resumo (G42).
      expect(account.users).to eq([marcos])
      entrada = JSON.parse(pedidos_da_ia('automacao_resumir').sole['input'].first['content'].first['text'])['conversa']
      expect(entrada['automation_sends']).to eq([
                                                  { 'channel' => 'whatsapp', 'text' => texto_do_aviso, 'not_delivered' => true },
                                                  { 'channel' => 'email', 'subject' => 'Renovação do seu seguro', 'text' => texto_do_aviso },
                                                  { 'channel' => 'whatsapp', 'text' => texto_do_link, 'not_delivered' => true }
                                                ])
      expect(entrada['other_conversations']).to eq([{ 'channel' => 'email', 'subject' => 'Renovação do seu seguro',
                                                      'messages' => ["Team: #{texto_do_aviso}"] }])
      expect(mencoes_para(marcos).count).to eq(1)
      expect(notas.find { |nota| nota.include?('Tentamos o WhatsApp') }).to include('o e-mail "Renovação do seu seguro"')
      expect(historico(:vencimento).last(3)).to eq([%w[ainda pulado prazo_vencido], ['tudo_que_tentou', 'ok', nil], ['fim', 'ok', nil]])
    end
  end

  context 'without e-mail do Daniel (passo 3)' do
    before do
      cliente.update!(email: nil)
      whatsapp_recusa
      varredura_as('2026-11-20 09:30')
    end

    it 'o WhatsApp recusou e nada sai por e-mail', :aggregate_failures do
      expect(conversa.messages.outgoing.sole.status).to eq('failed')
      expect(Conversation.where(inbox: caixa_de_email)).to be_empty
      expect(historico(:vencimento).map(&:first)).to eq(%w[renovacao etiqueta aviso chegou chegou recusou resposta])
    end
  end
end
