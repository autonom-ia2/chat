require 'rails_helper'

# Fechamento do épico #2414 (F9.6), exemplo 3 dos termos de aceite: "Pós-procedimento da clínica".
#
# > "Depois que a cliente faz o procedimento, eu queria mandar os cuidados, saber se ficou tudo bem e lembrar ela da
# > manutenção. Se der alguma reação, eu tenho que saber na hora." — Dra. Patrícia, dona da clínica
#
# Montado como a Dra. Patrícia montaria, pela API da tela, em três automações: a do card que entra em "Atendida" (G5),
# a do 25º dia (data da manutenção que a 1ª grava no card, G16 e G6) e a da reunião marcada (G12). O relógio anda e a
# varredura do motor acorda as esperas. Mensagem fora da janela de 24 h vai pelo modelo aprovado (G1); a resposta da
# cliente, com a foto, vai inteira à IA (G20); o retorno é da recepção (G3); a campanha "Manutenção" é o e-mail pela caixa
# da clínica (G2). A IA é o dublê. Desenho e lacunas: docs/automacao/F9-fechamento-20-exemplos.md.
#
# Passo 2 ("manda pelo modelo aprovado 'Cuidados'"): o "escrever" manda dentro da janela; com ela fechada, para sem gastar.
# Mandar pelo modelo é a lacuna G28 (#2674), pendente no fim do arquivo.
RSpec.describe 'Fechamento #2414 · exemplo 3: pós-procedimento da clínica', :fechamento_automacao, type: :request do
  include ActiveJob::TestHelper

  around do |exemplo|
    with_modified_env(CRM_KANBAN_ENABLED: 'true', CRM_CALENDAR_MEETINGS_ENABLED: 'true') { exemplo.run }
  end

  let(:fuso) { ActiveSupport::TimeZone['America/Sao_Paulo'] }
  let(:canal) { create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false) }
  let(:account) { canal.account }
  let(:caixa_de_email) { create(:channel_email, account: account).inbox }
  let(:patricia) { create(:user, account: account, role: :administrator, name: 'Dra. Patrícia') }
  let(:recepcao) { create(:team, account: account, name: 'Recepção') }
  let(:mundo) { build_booking_world(account: account, host_name: 'Dra. Patrícia Agenda') }
  let(:cliente) { mundo.contact.tap { |contato| contato.update!(name: 'Luana', email: 'luana@exemplo.com') } }
  let(:contact_inbox) { create(:contact_inbox, inbox: canal.inbox, contact: cliente, source_id: '5511912345678') }
  let(:conversa) { create(:conversation, account: account, inbox: canal.inbox, contact: cliente, contact_inbox: contact_inbox) }
  let(:atendida) { create_crm_stage(account: account, pipeline: mundo.pipeline, name: 'Atendida', position: 1) }
  let(:retorno_marcado) { create_crm_stage(account: account, pipeline: mundo.pipeline, name: 'Retorno marcado', position: 2) }
  let(:card) { mundo.card }
  let(:roteiro) do
    { 'automacao_extrair' => { 'procedimento' => 'botox' },
      'automacao_escrever' => { 'texto' => 'Cuidados do botox: não deite nas próximas 4 horas e não massageie o local.' } }
  end

  def modelo(nome, *variaveis) = { nome: nome, idioma: 'pt_BR', variaveis: [[{ '$valor' => 'contato.nome' }], *variaveis] }
  def card_id = { '$valor' => 'card.id' }
  def conversa_id = { '$valor' => 'conversa.id' }

  def etiqueta(id, nome)
    { id: id, tipo: 'acao', acao: 'PATCH conversations/:conversation_id/labels/alterar', descricao: "Pôr a etiqueta #{nome}",
      caminho: { conversation_id: conversa_id }, corpo: { por: [nome] } }
  end

  # Passos 1 a 7, a partir do card que entra em "Atendida".
  def receita_do_atendimento
    { gatilho: { tipo: 'card.entrou_na_etapa', etapa_id: atendida.id }, passos: [
      { id: 'procedimento', tipo: 'extrair', le: %w[mensagens_recentes],
        campos: [{ chave: 'procedimento', descricao: 'o procedimento feito: botox, limpeza ou preenchimento',
                   destino: 'conversa.atributos.procedimento' }] },
      { id: 'no_card', tipo: 'acao', acao: 'PATCH crm/cards/:id', descricao: 'Gravar o procedimento e a manutenção no card',
        caminho: { id: card_id }, corpo: { card: { custom_attributes: {
          procedimento: { '$valor' => 'conversa.atributos.procedimento' },
          manutencao: { '$data' => { de: 'hoje', mais: { valor: 25, unidade: 'dias' } } }
        } } } },
      { id: 'dia_seguinte', tipo: 'esperar', duracao: { valor: 1, unidade: 'dias' } },
      { id: 'cuidados', tipo: 'escrever', le: %w[mensagens_recentes conversa], destino: 'mensagem',
        instrucao: 'Escreva os cuidados de depois do procedimento que está no campo procedimento da conversa.' },
      { id: 'terceiro_dia', tipo: 'esperar', duracao: { valor: 2, unidade: 'dias' } },
      { id: 'como_esta', tipo: 'mensagem', texto: ['Como você está? Pode mandar uma foto se quiser'], modelo: modelo('pos_como_esta') },
      { id: 'resposta', tipo: 'esperar_ate', condicao: { campo: { '$valor' => 'conversa.cliente_respondeu' }, op: 'igual', valor: true },
        prazo: { valor: 2, unidade: 'dias' } },
      decidir_a_resposta
    ] }
  end

  def decidir_a_resposta
    { id: 'como_ficou', tipo: 'decidir', le: %w[mensagens_recentes anexos], pergunta: 'Como a cliente está depois do procedimento?',
      caminhos: [
        { nome: 'Vermelhidão ou dor', chave: 'reacao', descricao: 'fala de vermelhidão, inchaço, dor ou mostra isso na foto', passos: [
          etiqueta('etiqueta_atencao', 'atencao'),
          { id: 'prioridade', tipo: 'acao', acao: 'POST conversations/:id/toggle_priority', descricao: 'Marcar como prioridade',
            caminho: { id: conversa_id }, corpo: { priority: 'urgent' } },
          { id: 'avisar_doutora', tipo: 'avisar', para: { pessoas: [patricia.id] },
            texto: ['A cliente ', { '$valor' => 'contato.nome' }, ' relatou reação depois do procedimento. Veja agora.'] }
        ] },
        { nome: 'Dúvida', chave: 'duvida', descricao: 'pergunta algo sobre os cuidados ou o procedimento', passos: [
          { id: 'retorno_recepcao', tipo: 'retorno', titulo: ['Responder a dúvida de ', { '$valor' => 'contato.nome' }],
            daqui: { valor: 2, unidade: 'horas' }, para: { quem: 'time', time: recepcao.id } }
        ] },
        { nome: 'Tudo bem', chave: 'tudo_bem', descricao: 'diz que está tudo bem', passos: [etiqueta('etiqueta_satisfeita', 'satisfeita')] }
      ],
      nenhum: [] }
  end

  # Passos 8 e 9, no 25º dia. O "agendou" do passo 10 é a etapa "Retorno marcado".
  def receita_da_manutencao
    agendou = { campo: { '$valor' => 'card.etapa_id' }, op: 'igual', valor: retorno_marcado.id }
    { gatilho: { tipo: 'card.data', campo: 'manutencao', dias: 0, quando: 'antes', hora: 9 }, passos: [
      { id: 'link', tipo: 'mensagem', texto: ['Hora da manutenção! Marque aqui: ', { '$valor' => 'card.link_da_agenda' }],
        modelo: modelo('pos_manutencao', [{ '$valor' => 'card.link_da_agenda' }]) },
      { id: 'agendou', tipo: 'esperar_ate', condicao: agendou, prazo: { valor: 7, unidade: 'dias' }, se_vencer: [
        { id: 'campanha', tipo: 'email', caixa_id: caixa_de_email.id, assunto: ['Sua manutenção na clínica'],
          texto: ['Oi ', { '$valor' => 'contato.nome' }, ', está na hora da manutenção. Marque pelo link: ',
                  { '$valor' => 'card.link_da_agenda' }] }
      ] }
    ] }
  end

  # Passo 10: reunião marcada leva o card para "Retorno marcado".
  def receita_do_agendamento
    { gatilho: { tipo: 'card.reuniao_marcada' }, passos: [
      { id: 'mover', tipo: 'acao', acao: 'POST crm/cards/:id/move', descricao: 'Levar para Retorno marcado',
        caminho: { id: card_id }, corpo: { stage_id: retorno_marcado.id } }
    ] }
  end

  def atributo(chave, modelo, tipo)
    create(:custom_attribute_definition, account: account, attribute_key: chave, attribute_display_name: chave,
                                         attribute_model: modelo, attribute_display_type: tipo)
  end

  def modelos_aprovados
    { 'pos_como_esta' => 'Oi {{1}}, como você está? Pode mandar uma foto se quiser.',
      'pos_manutencao' => 'Oi {{1}}, está na hora da manutenção. Marque aqui: {{2}}' }.map do |nome, texto|
      { 'name' => nome, 'language' => 'pt_BR', 'status' => 'APPROVED', 'category' => 'UTILITY',
        'components' => [{ 'type' => 'BODY', 'text' => texto }] }
    end
  end

  def preparar_conta
    ligar_conta
    [patricia, mundo.host].each { |pessoa| create(:inbox_member, user: pessoa, inbox: canal.inbox) }
    criar_campos_e_etiquetas
    canal.update!(message_templates: modelos_aprovados)
    card.update!(primary_conversation: conversa, title: 'Luana - botox')
    [atendida, retorno_marcado]
  end

  def ligar_conta
    account.update!(locale: 'pt_BR', reporting_timezone: fuso.name, custom_attributes: { 'timezone' => fuso.name })
    flags_do_piloto(account)
    account.enable_features!('automacao_gatilhos', 'crm_booking_v2')
  end

  def criar_campos_e_etiquetas
    atributo('procedimento', 'conversation_attribute', 'text')
    atributo('procedimento', 'card_attribute', 'text')
    atributo('manutencao', 'card_attribute', 'date')
    %w[atencao satisfeita].each { |nome| create(:label, account: account, title: nome, description: "Pós: #{nome}") }
  end

  def ligar_tudo
    { atendimento: receita_do_atendimento, manutencao: receita_da_manutencao, agendamento: receita_do_agendamento }.each do |nome, receita|
      ligar_automacao(patricia, account, montar_automacao(patricia, account, nome: "Pós: #{nome}", receita: receita))
    end
  end

  def drenar
    drenados = [EventDispatcherJob, Autonomia::Automacao::EventoDoCardJob, Autonomia::Automacao::AvancarJob, SendReplyJob]
    FechamentoAutomacao::LIMITE_DE_JOBS.times do
      job = enqueued_jobs.find { |item| drenados.include?(item[:job]) }
      return unless job

      enqueued_jobs.delete(job)
      job[:job].perform_now(*ActiveJob::Arguments.deserialize(job[:args]))
    end
    raise "a fila não esvaziou em #{FechamentoAutomacao::LIMITE_DE_JOBS} jobs"
  end

  def as(hora, &) = travel_to(fuso.parse(hora), &)

  def cliente_escreve_as(hora, texto)
    as(hora) do
      create(:message, conversation: conversa, account: account, inbox: canal.inbox, message_type: :incoming, sender: cliente, content: texto)
      drenar
    end
  end

  # A varredura acorda as esperas vencidas e os gatilhos de data; os jobs que ela abre rodam um por vez.
  def varredura_as(hora)
    as(hora) do
      Autonomia::Automacao::TempoJob.perform_now
      perform_enqueued_jobs(only: Autonomia::Automacao::TempoDaAutomacaoJob)
      perform_enqueued_jobs(only: Autonomia::Automacao::AvancarJob) { Autonomia::Automacao::VarreduraJob.perform_now }
      drenar
    end
  end

  def card_entra_em_atendida
    as('2026-11-10 18:30') do
      Crm::Cards::Mover.new(card: card, actor: patricia, target_stage: atendida).perform
      drenar
    end
  end

  # A resposta do 3º dia, com a foto do local.
  def cliente_responde_com_foto(texto)
    as('2026-11-13 20:00') do
      mensagem = conversa.messages.new(account: account, inbox: canal.inbox, message_type: :incoming, sender: cliente, content: texto)
      anexo = mensagem.attachments.new(account_id: account.id, file_type: :image)
      anexo.file.attach(io: Rails.root.join('spec/assets/avatar.png').open, filename: 'foto-do-local.png', content_type: 'image/png')
      mensagem.save!
      drenar
      perform_enqueued_jobs(only: Autonomia::Automacao::AvancarJob) { Autonomia::Automacao::VarreduraJob.perform_now }
      drenar
    end
  end

  # A reunião marcada pelo serviço real da agenda, como na página da clínica.
  def cliente_marca_a_manutencao
    reuniao = { title: 'Manutenção do botox', starts_at: fuso.parse('2026-12-09 14:00'), ends_at: fuso.parse('2026-12-09 14:30'),
                timezone: fuso.name, extra_guests: [], location_type: 'whatsapp_video' }
    as('2026-12-06 10:00') do
      Crm::Meetings::InternalCreator.new(account: account, card: card, inbox: nil, scheduled_by: mundo.host, params: reuniao).perform
      drenar
    end
  end

  def link = Crm::BookingV2::ShortLink.url_for(mundo.profile)
  def whatsapp = chamadas_para('graph.facebook.com')
  def modelos_enviados = whatsapp.filter_map { |chamada| chamada.corpo.dig('template', 'name') }
  def textos_enviados = whatsapp.filter_map { |chamada| chamada.corpo.dig('text', 'body') }
  def pedidos_da_ia(schema) = ia_recebeu.select { |corpo| corpo.dig('text', 'format', 'name') == schema }
  def historico(nome) = Autonomia::Automacao::Registro.where(automacao_id: automacao_id(nome)).order(:id).pluck(:passo, :resultado, :motivo)
  def automacao_id(nome) = Autonomia::Automacao::Definicao.find_by!(account: account, nome: "Pós: #{nome}").id
  def mencoes_para(pessoa) = Notification.where(user: pessoa, notification_type: 'conversation_mention')

  before do
    receptor_whatsapp_cloud
    ia_responde(account, roteiro)
    as('2026-11-10 10:00') do
      preparar_conta
      create(:message, conversation: conversa, account: account, inbox: canal.inbox, message_type: :incoming, sender: cliente,
                       content: 'Oi, marquei o botox para hoje às 17h.')
      ligar_tudo
      clear_enqueued_jobs
    end
  end

  after { Current.reset }

  it 'passo 1: o card entra em "Atendida", e o procedimento e a data da manutenção vão para o card', :aggregate_failures do
    card_entra_em_atendida

    expect(card.reload.custom_attributes).to include('procedimento' => 'botox', 'manutencao' => '2026-12-05')
    expect(historico(:atendimento).first(2)).to eq([['procedimento', 'ok', nil], ['no_card', 'ok', nil]])
  end

  it 'passo 2: no dia seguinte, com a cliente na janela, a IA escreve os cuidados do procedimento e manda', :aggregate_failures do
    card_entra_em_atendida
    cliente_escreve_as('2026-11-10 22:00', 'Fiz o botox, obrigada!')

    varredura_as('2026-11-11 19:00')

    expect(textos_enviados).to eq(['Cuidados do botox: não deite nas próximas 4 horas e não massageie o local.'])
    expect(historico(:atendimento).map(&:first)).to include('cuidados')
  end

  it 'passo 2: com a janela fechada, o "escrever" para sem gastar, e nada sai à cliente', :aggregate_failures do
    card_entra_em_atendida

    varredura_as('2026-11-11 19:00')

    expect(pedidos_da_ia('automacao_escrever')).to be_empty
    expect(whatsapp).to be_empty
    # A execução para ali (#2573): os passos seguintes não rodam nesta cliente.
    expect(historico(:atendimento).last).to eq(%w[cuidados falhou fora_da_janela])
  end

  context 'with o 3º dia (passos 3 a 7)' do
    before do
      card_entra_em_atendida
      cliente_escreve_as('2026-11-10 22:00', 'Fiz o botox, obrigada!')
      varredura_as('2026-11-11 19:00')
      varredura_as('2026-11-13 19:00')
    end

    it 'passo 3: pergunta pelo modelo aprovado como a cliente está' do
      expect(modelos_enviados).to eq(%w[pos_como_esta])
    end

    it 'passos 4 e 5: a IA vê a foto e reconhece a reação; etiqueta, prioridade e a doutora avisada na hora', :aggregate_failures do
      roteiro['automacao_decidir'] = { 'caminho' => 'reacao', 'motivo' => 'vermelhidão na foto' }

      cliente_responde_com_foto('Ficou vermelho, olha a foto')

      partes = pedidos_da_ia('automacao_decidir').sole['input'].first['content']
      expect(partes.pluck('type')).to eq(%w[input_text input_image])
      conversa.reload
      expect(conversa.label_list).to include('atencao')
      expect(conversa.priority).to eq('urgent')
      expect(mencoes_para(patricia).count).to eq(1)
    end

    it 'passo 6: dúvida vira retorno para a recepção responder ainda hoje', :aggregate_failures do
      roteiro['automacao_decidir'] = { 'caminho' => 'duvida', 'motivo' => 'pergunta se pode malhar' }

      cliente_responde_com_foto('Posso malhar amanhã?')

      expect(Crm::FollowUp.sole).to have_attributes(card_id: card.id, title: 'Responder a dúvida de Luana', recipient_mode: 'team',
                                                    recipient_team_id: recepcao.id, due_at: fuso.parse('2026-11-13 22:00'))
    end

    it 'passo 7: tudo bem põe a etiqueta satisfeita', :aggregate_failures do
      roteiro['automacao_decidir'] = { 'caminho' => 'tudo_bem', 'motivo' => 'diz que está ótimo' }

      cliente_responde_com_foto('Tudo ótimo, amei o resultado!')

      expect(conversa.reload.label_list).to include('satisfeita')
      expect(conversa.label_list).not_to include('atencao')
      expect(mencoes_para(patricia)).to be_empty
    end
  end

  context 'with o 25º dia (passos 8 a 10)' do
    before do
      card.update!(custom_attributes: { 'procedimento' => 'botox', 'manutencao' => '2026-12-05' })
      varredura_as('2026-12-05 09:30')
    end

    it 'passo 8: manda pelo modelo aprovado o link da agenda para a manutenção', :aggregate_failures do
      expect(modelos_enviados).to eq(%w[pos_manutencao])
      parametros = whatsapp.sole.corpo.dig('template', 'components', 0, 'parameters').pluck('text')
      expect(parametros).to eq(['Luana', link])
    end

    it 'passo 9: sem agendar em 7 dias, a cliente recebe o e-mail da manutenção', :aggregate_failures do
      varredura_as('2026-12-12 09:31')

      email = Conversation.where(inbox: caixa_de_email).sole
      expect(email.contact).to eq(cliente)
      expect(email.additional_attributes['mail_subject']).to eq('Sua manutenção na clínica')
      expect(email.messages.outgoing.sole.content).to include('Oi Luana', link)
    end

    it 'passo 10: agendou, o card vai para "Retorno marcado" e o e-mail não sai', :aggregate_failures do
      cliente_marca_a_manutencao
      varredura_as('2026-12-06 10:30')
      varredura_as('2026-12-12 09:31')

      expect(card.reload.stage).to eq(retorno_marcado)
      expect(Conversation.where(inbox: caixa_de_email)).to be_empty
      expect(historico(:manutencao).map(&:first)).not_to include('campanha')
    end
  end

  it 'passo 2, pelo modelo: com a janela fechada, os cuidados saem pelo modelo aprovado "Cuidados"' do
    abertas = FechamentoAutomacao::Lacunas.abertas(%w[G28])
    pending 'lacuna G28 (#2674): o "escrever" não manda pelo modelo aprovado; fora da janela, para sem gastar'
    expect(abertas).to be_empty
  end
end
