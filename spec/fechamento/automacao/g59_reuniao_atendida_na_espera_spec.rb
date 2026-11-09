require 'rails_helper'

# Fechamento do épico #2414 (#2570), lacunas G59, G60 e G61. Exemplo 6 numa automação só, a do aniversário (gatilho
# `contato.data`, no contato), com os passos que já rodam à risca:
# - passo 2: manda pelo modelo aprovado "Aniversário", com o link da agenda (G60: `conversa.link_da_agenda`, a página de
#   quem atende a conversa do contato na caixa escolhida, pela ponte da conversa nova do #2680; sem ninguém atendendo,
#   a página de reserva escolhida no gatilho, decisão 10 do Rodrigo);
# - passo 3: cria o card no quadro "Aniversário";
# - passo 6: "Marcou: avisa a profissional" (G61: quem atende a próxima reunião marcada do contato); o "grava no card"
#   é a G49;
# - passo 7: "Não marcou em 10 dias: lembra uma vez, pelo modelo aprovado" (`contato.tem_reuniao_marcada`, #2710);
# - passo 8: "Atendida: no dia seguinte pede, pelo modelo aprovado, uma foto do resultado e autorização para postar"
#   (`contato.reuniao_atendida`, G59, acordado pelo resultado da reunião, G56);
# - passo 9: "A IA extrai se ela autorizou. Autorizou: põe a etiqueta 'pode postar' e avisa a Jéssica."
# Os passos 1, 4, 5 e 10 e o "grava no card" do 6 ficam fora: são as lacunas que seguram o exemplo inteiro no
# pendentes_spec. A reunião nasce pelo serviço real da agenda, o resultado pela rota da tela, o evento pelo emissor
# do CRM; o modelo aprovado para no receptor do WhatsApp oficial e a IA é o dublê.
RSpec.describe 'Fechamento #2414 · G59: esperar a reunião acontecer', :fechamento_automacao, type: :request do
  include ActiveJob::TestHelper

  around do |exemplo|
    with_modified_env(CRM_KANBAN_ENABLED: 'true', CRM_CALENDAR_MEETINGS_ENABLED: 'true') { exemplo.run }
  end

  let(:canal) { create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false) }
  let(:account) { canal.account }
  let(:inbox) { canal.inbox }
  let(:jessica) { create(:user, account: account, role: :administrator, name: 'Jéssica') }
  let(:carol) { create(:user, account: account, role: :agent, name: 'Carol Profissional') }
  let(:pagina) { create_booking_profile(account: account, host: carol, title: 'Hidratação') }
  let(:salao) { create_booking_profile(account: account, host: jessica, title: 'Agenda do salão') }
  let(:conversa) do
    contact_inbox = create(:contact_inbox, inbox: inbox, contact: bia, source_id: '5511900000059')
    create(:conversation, account: account, inbox: inbox, contact: bia, contact_inbox: contact_inbox, assignee: carol, status: :open)
  end
  let(:bia) { create(:contact, account: account, name: 'Bia', phone_number: '+5511900000059') }
  let(:aniversario) { create_crm_pipeline(account: account, user: jessica, name: 'Aniversário') }
  let(:roteiro) { { 'automacao_extrair' => { 'autorizou' => 'sim' } } }

  def fuso = ActiveSupport::TimeZone['America/Sao_Paulo']
  def as(hora, &) = travel_to(fuso.parse(hora), &)
  def modelo(nome, *variaveis) = { nome: nome, idioma: 'pt_BR', variaveis: [[{ '$valor' => 'contato.nome' }], *variaveis] }
  def link = { '$valor' => 'conversa.link_da_agenda' }
  def condicao(valor) = { campo: { '$valor' => valor }, op: 'igual', valor: true }

  def receita
    { gatilho: { tipo: 'contato.data', campo: 'nascimento', dias: 0, quando: 'antes', hora: 9, repete: 'todo_ano',
                 conversa_nova: { caixa_id: inbox.id }, agenda_de_reserva: { pagina_id: salao.id } },
      passos: passos_do_aniversario + passos_da_foto }
  end

  # Passos 2, 3, o aviso do 6, o 7 e a espera do passo 8.
  def passos_do_aniversario
    [
      { id: 'parabens', tipo: 'mensagem', texto: ['Feliz aniversário! Hidratação grátis este mês: ', link],
        modelo: modelo('aniversario', [link]) },
      { id: 'card', tipo: 'card', etapa_id: aniversario.last.id },
      { id: 'marcou', tipo: 'esperar_ate', condicao: condicao('contato.tem_reuniao_marcada'), prazo: { valor: 10, unidade: 'dias' },
        se_vencer: [{ id: 'lembra', tipo: 'mensagem', texto: ['O presente ainda vale!'], modelo: modelo('aniversario_lembrete') }] },
      { id: 'avisa_profissional', tipo: 'avisar', para: { da_reuniao: true },
        texto: ['Hidratação de presente para ', { '$valor' => 'contato.nome' }, '.'] },
      { id: 'atendida', tipo: 'esperar_ate', condicao: condicao('contato.reuniao_atendida'), prazo: { valor: 40, unidade: 'dias' } }
    ]
  end

  # Passos 8 ("no dia seguinte pede a foto") e 9.
  def passos_da_foto
    [
      { id: 'dia_seguinte', tipo: 'esperar', duracao: { valor: 1, unidade: 'dias' } },
      { id: 'pede_foto', tipo: 'mensagem', texto: ['Manda uma foto do resultado?'], modelo: modelo('foto_do_resultado') },
      { id: 'resposta', tipo: 'esperar_ate', condicao: condicao('conversa.cliente_respondeu'), prazo: { valor: 3, unidade: 'dias' } },
      { id: 'autorizou', tipo: 'extrair', le: %w[mensagens_recentes],
        campos: [{ chave: 'autorizou', descricao: 'sim se ela autorizou postar a foto no Instagram, não se não autorizou',
                   destino: 'contato.atributos.autorizou' }] },
      { id: 'se_autorizou', tipo: 'se', condicao: { campo: { '$valor' => 'contato.atributos.autorizou' }, op: 'igual', valor: 'sim' },
        entao: [
          { id: 'pode_postar', tipo: 'acao', acao: 'PATCH contacts/:contact_id/labels/alterar', descricao: 'Pôr a etiqueta pode postar',
            caminho: { contact_id: { '$valor' => 'contato.id' } }, corpo: { por: ['pode-postar'] } },
          { id: 'avisa_jessica', tipo: 'avisar', para: { pessoas: [jessica.id] },
            texto: [{ '$valor' => 'contato.nome' }, ' autorizou postar a foto do resultado.'] }
        ] }
    ]
  end

  def modelos_aprovados
    { 'aniversario' => 'Feliz aniversário, {{1}}! Hidratação grátis este mês: {{2}}', 'aniversario_lembrete' => 'Oi {{1}}, o presente vale.',
      'foto_do_resultado' => 'Oi {{1}}, manda uma foto do resultado?' }.map do |nome, texto|
      { 'name' => nome, 'language' => 'pt_BR', 'status' => 'APPROVED', 'category' => 'UTILITY',
        'components' => [{ 'type' => 'BODY', 'text' => texto }] }
    end
  end

  # Um job por vez, como no Sidekiq, com o do evento do card e os da varredura no meio.
  def drenar
    drenados = [*FechamentoAutomacao::JOBS, Autonomia::Automacao::EventoDoCardJob, Autonomia::Automacao::TempoDaAutomacaoJob]
    FechamentoAutomacao::LIMITE_DE_JOBS.times do
      job = enqueued_jobs.find { |item| drenados.include?(item[:job]) }
      return unless job

      enqueued_jobs.delete(job)
      job[:job].perform_now(*ActiveJob::Arguments.deserialize(job[:args]))
    end
    raise "a fila não esvaziou em #{FechamentoAutomacao::LIMITE_DE_JOBS} jobs"
  end

  def varredura_as(hora)
    as(hora) do
      Autonomia::Automacao::TempoJob.perform_now
      perform_enqueued_jobs(only: Autonomia::Automacao::AvancarJob) { Autonomia::Automacao::VarreduraJob.perform_now }
      drenar
    end
  end

  def card = account.crm_cards.find_by!(contact_id: bia.id, pipeline_id: aniversario.first.id)

  # A reunião marcada pela agenda, no dia 12 das 14h às 15h.
  def marca(no_card, hora: '2026-11-11 10:00')
    params = { title: 'Hidratação de presente', starts_at: fuso.parse('2026-11-12 14:00'), ends_at: fuso.parse('2026-11-12 15:00'),
               timezone: fuso.name, extra_guests: [], location_type: 'whatsapp_video' }
    as(hora) do
      reuniao = Crm::Meetings::InternalCreator.new(account: account, card: no_card, inbox: nil, scheduled_by: carol, params: params).perform
      drenar
      reuniao
    end
  end

  # O botão da Agenda ("Aconteceu" / "Não compareceu"), pela rota da tela.
  def resultado(reuniao, outcome, hora: '2026-11-12 16:00')
    as(hora) do
      post "/api/v1/accounts/#{account.id}/crm/meetings/#{reuniao.id}/record_outcome",
           params: { meeting: { outcome: outcome } }, headers: jessica.create_new_auth_token, as: :json
      expect(response).to have_http_status(:ok), -> { "o resultado não gravou: #{response.body}" }
      drenar
    end
  end

  def execucao = Autonomia::Automacao::Execucao.find_by!(automacao_id: Autonomia::Automacao::Definicao.find_by!(account: account).id, alvo: bia)
  def modelos_enviados = chamadas_para('graph.facebook.com').filter_map { |chamada| chamada.corpo.dig('template', 'name') }
  def mencoes_para(pessoa) = Notification.where(user: pessoa, notification_type: 'conversation_mention')
  def cursor = Autonomia::Automacao::Roteiro.new(execucao.versao.receita).passo(execucao.cursor)&.fetch('id', nil)

  before do
    receptor_whatsapp_cloud
    ia_responde(account, roteiro)
    as('2026-11-01 10:00') do
      account.update!(locale: 'pt_BR', reporting_timezone: fuso.name, custom_attributes: { 'timezone' => fuso.name })
      flags_do_piloto(account)
      account.enable_features!('automacao_gatilhos', 'crm_booking_v2')
      [jessica, carol].each { |pessoa| create(:inbox_member, user: pessoa, inbox: inbox) }
      pagina
      salao
      create(:message, conversation: conversa, account: account, inbox: inbox, message_type: :incoming, sender: bia,
                       content: 'Amei a escova de setembro!', created_at: 2.months.ago)
      { 'nascimento' => 'date', 'autorizou' => 'text' }.each do |chave, tipo|
        create(:custom_attribute_definition, account: account, attribute_key: chave, attribute_display_name: chave,
                                             attribute_model: 'contact_attribute', attribute_display_type: tipo)
      end
      create(:label, account: account, title: 'pode-postar', description: 'Pode postar a foto do resultado')
      canal.update!(message_templates: modelos_aprovados)
      bia.update!(custom_attributes: { 'nascimento' => '1995-11-10' })
      aniversario
      ligar_automacao(jessica, account, montar_automacao(jessica, account, nome: 'Aniversário', receita: receita))
      clear_enqueued_jobs
    end
    varredura_as('2026-11-10 09:30')
  end

  after { Current.reset }

  it 'no dia do aniversário: o parabéns pelo modelo com o link da agenda e o card no quadro; espera a reunião', :aggregate_failures do
    expect(modelos_enviados).to eq(['aniversario'])
    parametros = chamadas_para('graph.facebook.com').sole.corpo.dig('template', 'components', 0, 'parameters').pluck('text')
    expect(parametros).to eq(['Bia', Crm::BookingV2::ShortLink.url_for(pagina)])
    expect(card.stage_id).to eq(aniversario.last.id)
    expect([execucao.estado, cursor]).to eq(%w[esperando marcou])
  end

  it 'marcou, aconteceu: no dia seguinte pede a foto; ela autoriza: etiqueta e aviso à Jéssica', :aggregate_failures do
    reuniao = marca(card)
    expect([execucao.estado, cursor]).to eq(%w[esperando atendida])
    expect(conversa.messages.where(private: true).last.content).to include('Hidratação de presente para Bia.')
    expect(mencoes_para(carol).count).to eq(1)

    resultado(reuniao, 'held')
    expect([execucao.estado, cursor]).to eq(%w[esperando dia_seguinte])
    expect(modelos_enviados).to eq(['aniversario'])

    varredura_as('2026-11-13 16:30')
    expect(modelos_enviados).to eq(%w[aniversario foto_do_resultado])

    as('2026-11-13 17:00') { cliente_escreve(conversa, 'Pode postar sim! Segue a foto.') }
    drenar

    expect(bia.reload.label_list).to include('pode-postar')
    expect(mencoes_para(jessica).count).to eq(1)
    expect(execucao.estado).to eq('concluida')
  end

  it 'não marcou em 10 dias: lembra uma vez, ninguém é avisado, e continua esperando a reunião acontecer', :aggregate_failures do
    varredura_as('2026-11-20 10:00')

    expect(modelos_enviados).to eq(%w[aniversario aniversario_lembrete])
    expect(mencoes_para(carol)).to be_empty
    expect([execucao.estado, cursor]).to eq(%w[esperando atendida])
  end

  # O "Aconteceu" depois de um "Não compareceu" corrigido é o primeiro da reunião (first_held, G56): aí ela segue.
  it '"Não compareceu" acorda a espera, mas ela continua: só o "Aconteceu" conta', :aggregate_failures do
    reuniao = marca(card)
    resultado(reuniao, 'no_show')

    expect([execucao.estado, cursor]).to eq(%w[esperando atendida])

    resultado(reuniao, 'held', hora: '2026-11-12 17:00')
    expect([execucao.estado, cursor]).to eq(%w[esperando dia_seguinte])
  end

  # A G47 não segura o passo 8: a página que põe a reunião em outro card do contato (o card do serviço já ganho) não
  # muda nada, porque a espera lê as reuniões de todos os cards do contato que quem ligou vê.
  it 'a reunião em outro card do mesmo contato também conta' do
    servicos = create_crm_pipeline(account: account, user: jessica, name: 'Serviços')
    outro = Crm::Cards::Creator.new(account: account, user: jessica, params: {
                                      pipeline_id: servicos.first.id, stage_id: servicos.last.id, contact_id: bia.id,
                                      title: 'Hidratação da Bia', currency: 'BRL'
                                    }).perform
    reuniao = marca(outro)

    resultado(reuniao, 'held')

    expect(cursor).to eq('dia_seguinte')
  end

  # G60: o link é o de quem atende a conversa do contato na caixa da conversa nova. Sem ninguém atendendo, vale a página
  # de reserva escolhida no gatilho (decisão 10 do Rodrigo); nunca o link de outra pessoa (parecer do Funções, G12).
  def leitura_da_agenda(com: execucao)
    Autonomia::Automacao::Valores.new(alvo: Autonomia::Automacao::Contexto.de(bia, execucao: com), quem: jessica)
  end

  it 'o link da agenda: com quem atenda, a página dela; sem ninguém, a página de reserva do gatilho', :aggregate_failures do
    expect(leitura_da_agenda.ler('conversa.link_da_agenda')).to eq(Crm::BookingV2::ShortLink.url_for(pagina))

    conversa.update!(assignee: nil)
    expect(leitura_da_agenda.ler('conversa.link_da_agenda')).to eq(Crm::BookingV2::ShortLink.url_for(salao))

    conversa.destroy!
    expect(leitura_da_agenda.ler('conversa.link_da_agenda')).to eq(Crm::BookingV2::ShortLink.url_for(salao))
  end

  it 'sem ninguém atendendo e sem página de reserva no gatilho: vazio, e o passo pula com sem_responsavel', :aggregate_failures do
    conversa.update!(assignee: nil)
    receita = execucao.versao.receita.deep_dup.tap { |copia| copia['gatilho'].delete('agenda_de_reserva') }
    sem_reserva = Autonomia::Automacao::Execucao.new(account: account, automacao: execucao.automacao, alvo: bia,
                                                     versao: Autonomia::Automacao::Versao.new(receita: receita))
    leitura = leitura_da_agenda(com: sem_reserva)

    expect(leitura.ler('conversa.link_da_agenda')).to be_nil
    expect(leitura.falta_da_agenda).to eq('sem_responsavel')
  end

  # A página de reserva desligada ou apagada depois de ligar a automação: vazio com o motivo próprio, nunca outro link.
  it 'a página de reserva desligada ou apagada depois: vazio com o motivo próprio', :aggregate_failures do
    conversa.update!(assignee: nil)
    salao.update!(enabled: false)
    leitura = leitura_da_agenda
    expect(leitura.ler('conversa.link_da_agenda')).to be_nil
    expect(leitura.falta_da_agenda).to eq('agenda_de_reserva_indisponivel')

    salao.destroy!
    leitura = leitura_da_agenda
    expect(leitura.ler('conversa.link_da_agenda')).to be_nil
    expect(leitura.falta_da_agenda).to eq('agenda_de_reserva_indisponivel')
  end

  # Acesso (G59 e G61): a reunião em card de funil que quem ligou não vê não decide a espera (parecer do Funções, #2703).
  it 'só conta a reunião de card que quem ligou vê', :aggregate_failures do
    recepcao = create(:user, account: account, role: :agent, name: 'Recepção')
    corte = create_crm_pipeline(account: account, user: jessica, name: 'Corte')
    [aniversario.first, corte.first].each { |pipeline| Crm::PipelineInbox.create!(account: account, inbox: inbox, pipeline: pipeline) }
    acesso = Crm::InboxAgentAccess.create!(account: account, inbox: inbox, user: recepcao, all_pipelines: false, triage: false,
                                           only_own: false)
    acesso.agent_pipelines.create!(account: account, pipeline: aniversario.first)
    create(:inbox_member, user: recepcao, inbox: inbox)
    no_corte = Crm::Cards::Creator.new(account: account, user: jessica, params: {
                                         pipeline_id: corte.first.id, stage_id: corte.last.id, contact_id: bia.id, inbox_id: inbox.id,
                                         title: 'Corte da Bia', currency: 'BRL'
                                       }).perform
    reuniao = marca(no_corte)
    as('2026-11-11 11:00') do
      expect(Autonomia::Automacao::ValoresDaReuniao.proxima_do_contato(bia, recepcao)).to be_nil
      expect(Autonomia::Automacao::ValoresDaReuniao.proxima_do_contato(bia, jessica)).to eq(reuniao)
    end
    resultado(reuniao, 'held')

    janela = (fuso.parse('2026-11-12 00:00')..)
    leitura = ->(quem) { Autonomia::Automacao::Valores.new(alvo: bia.reload, quem: quem, espera: janela).ler('contato.reuniao_atendida') }
    as('2026-11-12 18:00') do
      expect(leitura.call(recepcao)).to be(false)
      expect(leitura.call(jessica)).to be(true)
      expect(leitura.call(nil)).to be(false)
    end
  end
end
