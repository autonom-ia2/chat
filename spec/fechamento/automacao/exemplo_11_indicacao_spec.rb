require 'rails_helper'

# Fechamento do épico #2414 (F9.6), exemplo 11 dos termos de aceite: "Indicação que vira presente".
#
# > "Quando um cliente me indica alguém, quero dar um desconto pro amigo. E se o amigo virar cliente, quero mandar um
# > banho grátis pro cachorro de quem indicou." — Lu, dona do pet shop
#
# Montado como a Lu montaria, pela API da tela, em quatro automações: a da indicação (toda mensagem de cliente, passos 1
# a 5), a da reunião marcada no quadro "Indicações" (passo 6) e as do card do João ganho e perdido (passos 7 a 9).
#
# - Passo 3 (G17, G4, G49): o `POST contacts` cria o João; o "criar card" abre o card dele no quadro "Indicações"
#   (`contato: criado.<passo>`); e a ação grava no card que o passo criou quem indicou: o id da Maria (`indicado_por`,
#   que os passos 7 a 9 usam para chegar a ela) e o nome dela.
# - Passo 5 (G18 × G49, G1, G12, G33): o "em outro registro" no card que o passo 3 criou manda ao João, que ainda não
#   tem conversa: ela abre na caixa da conversa nova, pelo modelo aprovado, com o link da agenda do dono do card.
# - Passo 6 (G12): o João marca pela página de agendamento da Lu (Crm::BookingV2::Booker), que põe a reunião no card
#   aberto dele no funil.
# - Passos 7 a 9 (G5, G18): o card do João ganho ou perdido age na conversa da Maria, pelo `indicado_por`. O nome do
#   amigo vem do que a IA extraiu na conversa dela (passo 2), e o do pet da Maria, do cadastro dela. O link da agenda é
#   o da pessoa que atende a conversa da Maria.
#
# Mensagem ao cliente fora da janela de 24 h vai pelo modelo aprovado e para no receptor do WhatsApp oficial; a IA é o
# dublê. Desenho e lacunas: docs/automacao/F9-fechamento-20-exemplos.md.
RSpec.describe 'Fechamento #2414 · exemplo 11: indicação que vira presente', :fechamento_automacao, type: :request do
  include ActiveJob::TestHelper

  around do |exemplo|
    with_modified_env(CRM_KANBAN_ENABLED: 'true', CRM_CALENDAR_MEETINGS_ENABLED: 'true') { exemplo.run }
  end

  let(:fuso) { ActiveSupport::TimeZone['America/Sao_Paulo'] }
  let(:canal) { create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false) }
  let(:account) { canal.account }
  let(:inbox) { canal.inbox }
  let(:lu) { create(:user, account: account, role: :administrator, name: 'Lu Dona') }
  let(:maria) do
    create(:contact, account: account, name: 'Maria', phone_number: '+5511900000011', custom_attributes: { 'pet' => 'Thor' })
  end
  let(:contact_inbox) { create(:contact_inbox, inbox: inbox, contact: maria, source_id: '5511900000011') }
  let(:conversa_da_maria) do
    create(:conversation, account: account, inbox: inbox, contact: maria, contact_inbox: contact_inbox, assignee: lu, status: :open)
  end
  let(:funil_e_entrada) { create_crm_pipeline(account: account, user: lu, name: 'Indicações') }
  let(:agendado) { create_crm_stage(account: account, pipeline: funil, name: 'Agendado', position: 1) }
  let(:agenda) { create_booking_profile(account: account, host: lu, pipeline: funil, stage: funil_e_entrada.last, title: 'Banho') }
  let(:roteiro) do
    { 'automacao_decidir' => { 'caminho' => 'indicacao', 'motivo' => 'a Maria passou o nome e o telefone do João' },
      'automacao_extrair' => { 'amigo_nome' => 'João', 'amigo_telefone' => '+5511900000012', 'pet' => 'Rex' } }
  end

  def funil = funil_e_entrada.first
  def valor(caminho) = { '$valor' => caminho }
  def amigo = valor('conversa.atributos.amigo_nome')
  def modelo(nome, *variaveis) = { nome: nome, idioma: 'pt_BR', variaveis: variaveis.zip }
  def acao(id, acao, descricao, caminho, corpo) = { id: id, tipo: 'acao', acao: acao, descricao: descricao, caminho: caminho, corpo: corpo }

  # Passos 1 a 5, a cada mensagem de cliente.
  def receita_da_indicacao
    { gatilho: { tipo: 'mensagem.criada', filtros: [{ campo: valor('mensagem.tipo'), op: 'igual', valor: 'recebida' }],
                 conversa_nova: { caixa_id: inbox.id } },
      passos: [
        { id: 'e_indicacao', tipo: 'decidir', le: %w[mensagens_recentes], pergunta: 'A cliente está indicando alguém, com nome e telefone?',
          caminhos: [
            { nome: 'É indicação', chave: 'indicacao', descricao: 'passou o nome e o telefone de um amigo', passos: indicacao },
            { nome: 'Outra coisa', chave: 'outra_coisa', descricao: 'qualquer outra mensagem', passos: [{ id: 'nao_e', tipo: 'parar' }] }
          ],
          nenhum: [] }
      ] }
  end

  def indicacao
    [{ id: 'dados_do_amigo', tipo: 'extrair', le: %w[mensagens_recentes], campos: [
      { chave: 'amigo_nome', descricao: 'o nome do amigo indicado', destino: 'conversa.atributos.amigo_nome' },
      { chave: 'amigo_telefone', descricao: 'o telefone do amigo, com +55 e DDD', destino: 'conversa.atributos.amigo_telefone' },
      { chave: 'pet', descricao: 'o nome do pet do amigo, se vier', destino: 'conversa.atributos.pet' }
    ] },
     acao('contato_do_amigo', 'POST contacts', 'Criar o contato do amigo', {},
          { name: amigo, phone_number: valor('conversa.atributos.amigo_telefone') }),
     { id: 'card_do_amigo', tipo: 'card', etapa_id: funil_e_entrada.last.id, contato: valor('criado.contato_do_amigo') },
     acao('quem_indicou', 'PATCH crm/cards/:id', 'Gravar quem indicou', { id: valor('criado.card_do_amigo') },
          { card: { custom_attributes: { indicado_por: valor('contato.id'), quem_indicou: valor('contato.nome') } } }),
     { id: 'agradece', tipo: 'mensagem', texto: ['Obrigada! Vou falar com o ', amigo, ' com todo carinho'] },
     { id: 'no_card_do_amigo', tipo: 'em_outro_registro', registro: { de: 'criado_no_passo', passo: 'card_do_amigo' }, passos: [
       { id: 'desconto', tipo: 'mensagem',
         texto: ['Oi, ', valor('contato.nome'), '! A ', valor('card.atributos.quem_indicou'),
                 ' indicou a gente. O primeiro banho do seu pet tem 20% de desconto: ', valor('card.link_da_agenda')],
         modelo: modelo('indicacao_desconto', valor('contato.nome'), valor('card.atributos.quem_indicou'), valor('card.link_da_agenda')) }
     ] }]
  end

  # Passo 6.
  def receita_da_reuniao
    { gatilho: { tipo: 'card.reuniao_marcada', funil_id: funil.id },
      passos: [acao('agendado', 'POST crm/cards/:id/move', 'Levar para Agendado', { id: valor('card.id') }, { stage_id: agendado.id })] }
  end

  def na_maria(*passos)
    { id: 'na_maria', tipo: 'em_outro_registro', registro: { de: 'contato_do_campo', campo: valor('card.atributos.indicado_por'), usar: 'conversa' },
      passos: passos }
  end

  # Passos 7 e 8.
  def receita_do_ganho
    { gatilho: { tipo: 'card.ganho', funil_id: funil.id }, passos: [na_maria(
      { id: 'presente', tipo: 'mensagem',
        texto: ['O ', amigo, ' virou cliente! O próximo banho do ', valor('contato.atributos.pet'), ' é por nossa conta: ',
                valor('conversa.link_da_agenda')],
        modelo: modelo('indicacao_presente', amigo, valor('contato.atributos.pet'), valor('conversa.link_da_agenda')) },
      acao('etiqueta', 'PATCH contacts/:contact_id/labels/alterar', 'Indicou e fechou', { contact_id: valor('contato.id') },
           { por: ['indicou_e_fechou'] }),
      { id: 'avisa_a_lu', tipo: 'avisar', para: { pessoas: [lu.id] }, texto: [valor('contato.nome'), ' indicou e o amigo fechou.'] }
    )] }
  end

  # Passo 9.
  def receita_da_perda
    { gatilho: { tipo: 'card.perdido', funil_id: funil.id }, passos: [na_maria(
      { id: 'obrigada', tipo: 'mensagem', texto: ['Obrigada por indicar o ', amigo, '! Conte sempre com a gente.'],
        modelo: modelo('indicacao_obrigada', amigo) }
    )] }
  end

  def modelos_aprovados
    { 'indicacao_desconto' => 'Oi, {{1}}! A {{2}} indicou a gente. O primeiro banho do seu pet tem 20% de desconto: {{3}}',
      'indicacao_presente' => 'O {{1}} virou cliente! O próximo banho do {{2}} é por nossa conta: {{3}}',
      'indicacao_obrigada' => 'Obrigada por indicar o {{1}}! Conte sempre com a gente.' }.map do |nome, texto|
      { 'name' => nome, 'language' => 'pt_BR', 'status' => 'APPROVED', 'category' => 'UTILITY',
        'components' => [{ 'type' => 'BODY', 'text' => texto }] }
    end
  end

  def atributo(chave, modelo_do_atributo, tipo)
    create(:custom_attribute_definition, account: account, attribute_key: chave, attribute_display_name: chave,
                                         attribute_model: modelo_do_atributo, attribute_display_type: tipo)
  end

  # Onde o extrair grava (a conversa da Maria), o pet da Maria e quem indicou, no card do amigo.
  def criar_campos
    %w[amigo_nome amigo_telefone pet].each { |chave| atributo(chave, 'conversation_attribute', 'text') }
    atributo('pet', 'contact_attribute', 'text')
    atributo('indicado_por', 'card_attribute', 'number')
    atributo('quem_indicou', 'card_attribute', 'text')
  end

  def preparar_conta
    account.update!(locale: 'pt_BR', reporting_timezone: fuso.name, custom_attributes: { 'timezone' => fuso.name })
    flags_do_piloto(account)
    account.enable_features!('automacao_gatilhos', 'crm_booking_v2')
    create(:inbox_member, user: lu, inbox: inbox)
    criar_campos
    create(:label, account: account, title: 'indicou_e_fechou', description: 'Indicou e o amigo fechou')
    canal.update!(message_templates: modelos_aprovados)
    [agendado, agenda, conversa_da_maria]
  end

  def ligar_tudo
    { indicacao: receita_da_indicacao, reuniao: receita_da_reuniao, ganho: receita_do_ganho, perda: receita_da_perda }.each do |nome, receita|
      ligar_automacao(lu, account, montar_automacao(lu, account, nome: "Indicação: #{nome}", receita: receita))
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

  def maria_escreve_as(hora, texto)
    as(hora) do
      create(:message, conversation: conversa_da_maria, account: account, inbox: inbox, message_type: :incoming, sender: maria, content: texto)
      drenar
    end
  end

  def joao_marca_as(hora, horario)
    as(hora) do
      Crm::BookingV2::Booker.new(profile: agenda, name: 'João', phone: '(11) 90000-0012', starts_at: fuso.parse(horario).iso8601,
                                 source: 'public_link').perform
      drenar
    end
  end

  def fechar_as(hora, resultado, **extra)
    as(hora) do
      Crm::Cards::Closer.new(card: card_do_joao, actor: lu, result: resultado, **extra).perform
      drenar
    end
  end

  def joao = account.contacts.find_by!(phone_number: '+5511900000012')
  def card_do_joao = funil.cards.find_by!(contact: joao)
  def link = Crm::BookingV2::ShortLink.url_for(agenda)
  def whatsapp = chamadas_para('graph.facebook.com')
  def modelos_para(numero) = whatsapp.select { |chamada| chamada.corpo['to'] == numero }.map { |chamada| chamada.corpo.dig('template', 'name') }
  def parametros(chamada) = chamada.corpo.dig('template', 'components', 0, 'parameters').pluck('text')
  def saidas(conversa) = conversa.messages.outgoing.where(private: false).order(:id).pluck(:content)
  def historico(nome) = Autonomia::Automacao::Registro.where(automacao_id: automacao(nome).id).order(:id).pluck(:passo, :resultado, :motivo)
  def automacao(nome) = Autonomia::Automacao::Definicao.find_by!(account: account, nome: "Indicação: #{nome}")

  before do
    receptor_whatsapp_cloud
    ia_responde(account, roteiro)
    as('2026-11-10 09:00') do
      preparar_conta
      ligar_tudo
      clear_enqueued_jobs
    end
    maria_escreve_as('2026-11-10 10:00', 'Oi Lu! Indiquei meu amigo João, o telefone dele é 11 90000-0012. O cachorro dele é o Rex.')
  end

  after { Current.reset }

  it 'passos 1 a 3: a IA vê a indicação e cria o contato e o card do João, com quem indicou gravado', :aggregate_failures do
    expect(joao).to have_attributes(name: 'João')
    # O card nasce só do contato; a conversa que o passo 5 abre para o João fica ligada a ele, nunca a da Maria.
    conversa_do_joao = Conversation.find_by!(account: account, inbox: inbox, contact: joao)
    expect(card_do_joao).to have_attributes(stage_id: funil_e_entrada.last.id, conversation_id: conversa_do_joao.id, owner_id: lu.id)
    expect(card_do_joao.custom_attributes).to include('indicado_por' => maria.id, 'quem_indicou' => 'Maria')
    expect(conversa_da_maria.reload.custom_attributes).to include('amigo_nome' => 'João', 'pet' => 'Rex')
    expect(historico(:indicacao).first(5)).to eq([['e_indicacao', 'ok', nil], ['dados_do_amigo', 'ok', nil], ['contato_do_amigo', 'ok', nil],
                                                  ['card_do_amigo', 'ok', nil], ['quem_indicou', 'ok', nil]])
  end

  it 'passos 4 e 5: agradece a Maria na conversa dela e manda ao João, pelo modelo, o desconto com o link da agenda', :aggregate_failures do
    expect(saidas(conversa_da_maria)).to eq(['Obrigada! Vou falar com o João com todo carinho'])
    conversa_do_joao = Conversation.find_by!(account: account, inbox: inbox, contact: joao)
    expect(saidas(conversa_do_joao)).to eq(["Oi, João! A Maria indicou a gente. O primeiro banho do seu pet tem 20% de desconto: #{link}"])
    chamada = whatsapp.find { |item| item.corpo['to'] == '5511900000012' }
    expect(chamada.corpo.dig('template', 'name')).to eq('indicacao_desconto')
    expect(parametros(chamada)).to eq(['João', 'Maria', link])
    expect(historico(:indicacao)).to include(['agradece', 'ok', nil], ['no_card_do_amigo', 'ok', nil], ['desconto', 'ok', nil])
  end

  it 'mensagem que não é indicação para no passo 1, sem criar ninguém', :aggregate_failures do
    roteiro['automacao_decidir'] = { 'caminho' => 'outra_coisa', 'motivo' => 'perguntou o horário' }
    maria_escreve_as('2026-11-10 11:00', 'Que horas vocês abrem amanhã?')

    expect(account.contacts.where(phone_number: '+5511900000012').count).to eq(1)
    expect(funil.cards.count).to eq(1)
    expect(Autonomia::Automacao::Registro.where(automacao_id: automacao(:indicacao).id, passo: 'nao_e').count).to eq(1)
  end

  it 'passo 6: o João marca pela agenda e o card dele vai para "Agendado"' do
    joao_marca_as('2026-11-11 10:00', '2026-11-13 10:00')

    expect(card_do_joao.reload.stage_id).to eq(agendado.id)
  end

  it 'passos 7 e 8: card ganho, a Maria ganha o presente com o link, a etiqueta, e a Lu é avisada', :aggregate_failures do
    fechar_as('2026-11-10 15:00', 'won')

    expect(saidas(conversa_da_maria).last).to eq("O João virou cliente! O próximo banho do Thor é por nossa conta: #{link}")
    expect(maria.reload.label_list).to eq(['indicou_e_fechou'])
    expect(Notification.where(user: lu, notification_type: 'conversation_mention').count).to eq(1)
    expect(conversa_da_maria.messages.where(private: true).pluck(:content).last).to include('Maria indicou e o amigo fechou.')
    expect(historico(:ganho)).to eq([['na_maria', 'ok', nil], %w[inicio ok em_outro_registro], ['presente', 'ok', nil],
                                     ['etiqueta', 'ok', nil], ['avisa_a_lu', 'ok', nil]])
  end

  it 'passo 9: card perdido, agradece a Maria do mesmo jeito, sem presente', :aggregate_failures do
    fechar_as('2026-11-10 15:00', 'lost', lost_reason: 'mudou de cidade')

    expect(saidas(conversa_da_maria).last).to eq('Obrigada por indicar o João! Conte sempre com a gente.')
    expect(maria.reload.label_list).to be_empty
    expect(historico(:ganho)).to be_empty
  end
end
