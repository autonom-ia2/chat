require 'rails_helper'

# Fechamento do épico #2414 (#2570), lacuna G32 (#2703): a reunião marcada no meio da execução e a reunião certa.
# Provado nos pedaços dos exemplos que dependem dela, montados e ligados pela API da tela. A reunião nasce pelo serviço
# real (Crm::Meetings::InternalCreator, o mesmo da página de agendamento), o evento sai pelo emissor do CRM e chega ao
# motor pelo despacho; o modelo aprovado para no receptor do WhatsApp oficial.
# - exemplo 1, passo 11: "Reunião marcada: move" — só a reunião da renovação (a página de agendamento dela);
# - exemplo 5, passos 5 a 7: "Marcou: move para Revisão marcada"; "Não marcou em 5 dias: manda de novo"; "Não marcou de
#   novo em 5 dias: retorno para o Seu Zé";
# - exemplo 6, passos 6 e 7: "Marcou: avisa a profissional"; "Não marcou em 10 dias: lembra uma vez pelo modelo".
# Os exemplos inteiros ficam no pendentes_spec até as outras lacunas deles fecharem. A reunião que a página grava em
# outro card do mesmo contato é a #2704.
RSpec.describe 'Fechamento #2414 · G32: reunião marcada no meio da execução', :fechamento_automacao, type: :request do
  include ActiveJob::TestHelper

  around do |exemplo|
    with_modified_env(CRM_KANBAN_ENABLED: 'true', CRM_CALENDAR_MEETINGS_ENABLED: 'true') { exemplo.run }
  end

  let(:canal) { create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false) }
  let(:account) { canal.account }
  let(:inbox) { canal.inbox }
  let(:seu_ze) { create(:user, account: account, role: :administrator, name: 'Seu Zé') }
  let(:profissional) { create(:user, account: account, role: :agent, name: 'Bia Profissional') }
  let(:cliente) { create(:contact, account: account, name: 'Carla', phone_number: '+5511900000032') }
  let(:conversa) do
    contact_inbox = create(:contact_inbox, inbox: inbox, contact: cliente, source_id: '5511900000032')
    create(:conversation, account: account, inbox: inbox, contact: cliente, contact_inbox: contact_inbox, status: :open)
  end
  let(:funil) { create_crm_pipeline(account: account, user: seu_ze, name: 'Revisões').first }
  let(:revisao) { create_crm_stage(account: account, pipeline: funil, name: 'Revisão', position: 1) }
  let(:revisao_marcada) { create_crm_stage(account: account, pipeline: funil, name: 'Revisão marcada', position: 2) }
  let(:da_renovacao) { create_booking_profile(account: account, host: profissional, title: 'Renovação do seguro') }
  let(:da_vistoria) { create_booking_profile(account: account, host: seu_ze, title: 'Vistoria') }

  def fuso = ActiveSupport::TimeZone['America/Sao_Paulo']
  def inicio = fuso.parse('2026-11-10 10:00')
  def modelo(nome) = { nome: nome, idioma: 'pt_BR', variaveis: [[{ '$valor' => 'contato.nome' }]] }
  def lembrete(id, nome) = { id: id, tipo: 'mensagem', texto: ["Mensagem #{nome}"], modelo: modelo(nome) }

  def mover(id, etapa)
    { id: id, tipo: 'acao', acao: 'POST crm/cards/:id/move', descricao: 'Mover o card',
      caminho: { id: { '$valor' => 'card.id' } }, corpo: { stage_id: etapa.id } }
  end

  def ate_marcar(id, dias, se_vencer)
    { id: id, tipo: 'esperar_ate', condicao: { campo: { '$valor' => 'card.tem_reuniao_marcada' }, op: 'igual', valor: true },
      prazo: { valor: dias, unidade: 'dias' }, se_vencer: se_vencer }
  end

  def ligada(nome, receita)
    automacao = montar_automacao(seu_ze, account, nome: nome, receita: receita)
    ligar_automacao(seu_ze, account, automacao)
    clear_enqueued_jobs
    automacao
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

  # O card nasce em "Revisão" pela mesma criação da tela e do agendamento: conta como "entrou" nela.
  def card_na_revisao
    Crm::Cards::Creator.new(account: account, user: seu_ze, params: {
                              pipeline_id: funil.id, stage_id: revisao.id, contact_id: cliente.id, owner_id: seu_ze.id,
                              conversation_id: conversa.id, inbox_id: inbox.id, title: 'Revisão do Gol', currency: 'BRL'
                            }).perform
  end

  def card = account.crm_cards.find_by!(title: 'Revisão do Gol')

  # A cliente marca pela página (os metadados da página vão na reunião, como no Booker) ou a equipe marca na tela.
  def marca(pagina: nil, quando: inicio + 3.days)
    params = { title: 'Revisão', starts_at: quando, ends_at: quando + 30.minutes, timezone: fuso.name, extra_guests: [],
               location_type: 'whatsapp_video' }
    params[:booking_profile_id] = pagina.id if pagina
    Crm::Meetings::InternalCreator.new(account: account, card: card, inbox: nil, scheduled_by: pagina&.default_assignee || seu_ze,
                                       params: params).perform
    drenar
  end

  def no_dia(instante)
    travel_to(instante) do
      perform_enqueued_jobs(only: Autonomia::Automacao::AvancarJob) { Autonomia::Automacao::VarreduraJob.perform_now }
      drenar
    end
  end

  def modelos_enviados = chamadas_para('graph.facebook.com').filter_map { |chamada| chamada.corpo.dig('template', 'name') }
  def execucao_de(automacao) = Autonomia::Automacao::Execucao.find_by!(automacao_id: automacao['id'], alvo: card)

  before do
    travel_to(inicio)
    account.update!(locale: 'pt_BR', reporting_timezone: fuso.name)
    flags_do_piloto(account)
    account.enable_features!('automacao_gatilhos', 'crm_booking_v2')
    [seu_ze, profissional].each { |pessoa| create(:inbox_member, user: pessoa, inbox: inbox) }
    canal.update!(message_templates: %w[revisao_de_novo revisao_lavagem presente_lembrete].map do |nome|
      { 'name' => nome, 'language' => 'pt_BR', 'status' => 'APPROVED', 'category' => 'UTILITY',
        'components' => [{ 'type' => 'BODY', 'text' => "Oi {{1}}, mensagem #{nome}." }] }
    end)
    receptor_whatsapp_cloud
    [revisao, revisao_marcada, da_renovacao, da_vistoria]
    create(:message, conversation: conversa, account: account, inbox: inbox, message_type: :incoming, sender: cliente, content: 'Oi')
    clear_enqueued_jobs
  end

  after { Current.reset }

  describe 'exemplo 1, passo 11: a reunião da renovação move o card' do
    let!(:automacao) do
      ligada('Renovação marcada', { gatilho: { tipo: 'card.reuniao_marcada', pagina_id: da_renovacao.id },
                                    passos: [mover('marcada', revisao_marcada)] })
    end

    before do
      card_na_revisao
      drenar
    end

    it 'a reunião marcada pela página da renovação move; a de outra página e a marcada na tela não', :aggregate_failures do
      marca(pagina: da_vistoria)
      marca
      expect(card.reload.stage_id).to eq(revisao.id)
      expect(Autonomia::Automacao::Execucao.where(automacao_id: automacao['id'])).to be_empty

      marca(pagina: da_renovacao, quando: inicio + 4.days)
      expect(card.reload.stage_id).to eq(revisao_marcada.id)
      expect(historico_de(automacao)).to eq([['marcada', 'ok', nil]])
    end

    # A antiga (page_version 1) o editor não lista: também não salva.
    it 'salvar com a página de outra conta, ou com a página antiga, é recusado', :aggregate_failures do
      outra = create(:account)
      de_outra = create_booking_profile(account: outra, host: create(:user, account: outra))
      versao_antiga = Crm::AgentBookingProfile::LEGACY_PAGE
      antiga = create_booking_profile(account: account, host: seu_ze, title: 'Antiga', page_version: versao_antiga, inbox: inbox)

      [de_outra, antiga].each do |pagina|
        receita = { gatilho: { tipo: 'card.reuniao_marcada', pagina_id: pagina.id }, passos: [mover('marcada', revisao_marcada)] }
        post api_automacoes(account), params: { nome: 'Outra', receita: receita }, headers: seu_ze.create_new_auth_token, as: :json

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.body).to include("a página de agendamento #{pagina.id} não é desta conta")
      end
    end
  end

  describe 'exemplo 5, passos 5 a 7: esperar a revisão ser marcada' do
    let!(:automacao) do
      ligada('Revisão', { gatilho: { tipo: 'card.entrou_na_etapa', etapa_id: revisao.id }, passos: [
               ate_marcar('marcou', 5, [lembrete('de_novo', 'revisao_lavagem'),
                                        ate_marcar('marcou_de_novo', 5, [{ id: 'para_o_ze', tipo: 'retorno', titulo: ['Ligar para a Carla'],
                                                                           daqui: { valor: 1, unidade: 'dias' } }])]),
               mover('marcada', revisao_marcada)
             ] })
    end

    before do
      card_na_revisao
      drenar
    end

    it 'marcou no 2º dia: a espera acorda na hora, sem varredura, e o card vai para "Revisão marcada"', :aggregate_failures do
      expect(execucao_de(automacao).estado).to eq('esperando')

      travel_to(inicio + 2.days) { marca(pagina: da_vistoria) }

      expect(execucao_de(automacao).estado).to eq('concluida')
      expect(card.reload.stage_id).to eq(revisao_marcada.id)
      expect(modelos_enviados).to be_empty
      expect(Crm::FollowUp.where(card_id: card.id, title: 'Ligar para a Carla')).to be_empty
    end

    it 'não marcou em 5 dias: manda de novo; não marcou de novo: retorno para o Seu Zé, e o card fica', :aggregate_failures do
      no_dia(inicio + 5.days + 1.hour)
      expect(modelos_enviados).to eq(['revisao_lavagem'])
      expect(execucao_de(automacao).estado).to eq('esperando')

      no_dia(inicio + 10.days + 2.hours)
      expect(Crm::FollowUp.sole).to have_attributes(card_id: card.id, assignee_id: seu_ze.id, title: 'Ligar para a Carla')
      expect(card.reload.stage_id).to eq(revisao_marcada.id)
      expect(modelos_enviados).to eq(['revisao_lavagem'])
    end
  end

  describe 'o valor card.tem_reuniao_marcada' do
    before do
      card_na_revisao
      drenar
    end

    def tem_reuniao? = Autonomia::Automacao::Valores.new(alvo: card.reload, quem: seu_ze).ler('card.tem_reuniao_marcada')

    it 'a reunião marcada conta; cancelada ou já passada, não', :aggregate_failures do
      expect(tem_reuniao?).to be(false)

      marca(pagina: da_vistoria)
      expect(tem_reuniao?).to be(true)

      travel_to(inicio + 4.days) { expect(tem_reuniao?).to be(false) }

      Crm::Meetings::CancelService.new(meeting: account.crm_meetings.find_by!(card_id: card.id)).perform
      expect(tem_reuniao?).to be(false)
    end
  end

  describe 'exemplo 6, passos 6 e 7: avisa a profissional e lembra uma vez' do
    let(:aviso) do
      { id: 'avisa', tipo: 'avisar', para: { da_reuniao: true },
        texto: ['Hidratação de presente para ', { '$valor' => 'contato.nome' }, ' em ', { '$valor' => 'reuniao.inicio' }] }
    end
    let!(:lembra) do
      ligada('Presente', { gatilho: { tipo: 'card.entrou_na_etapa', etapa_id: revisao.id }, passos: [
               ate_marcar('marcou', 10, [lembrete('lembra', 'presente_lembrete')])
             ] })
    end

    before do
      ligada('Presente marcado', { gatilho: { tipo: 'card.reuniao_marcada' }, passos: [aviso] })
      card_na_revisao
      drenar
    end

    it 'marcou pela página: avisa quem atende, e não o dono do card; e não lembra', :aggregate_failures do
      travel_to(inicio + 1.day) { marca(pagina: da_renovacao) }

      nota = conversa.messages.where(private: true).sole
      expect(nota.content).to include('Hidratação de presente para Carla em 13/11/2026 às 10:00')
      expect(Notification.where(user: profissional, notification_type: 'conversation_mention').count).to eq(1)
      expect(Notification.where(user: seu_ze, notification_type: 'conversation_mention')).to be_empty

      no_dia(inicio + 10.days + 1.hour)
      expect(modelos_enviados).to be_empty
      expect(historico_de(lembra).last).to eq(['marcou', 'ok', nil])
    end

    it 'não marcou em 10 dias: lembra uma vez pelo modelo', :aggregate_failures do
      no_dia(inicio + 10.days + 1.hour)
      no_dia(inicio + 20.days)

      expect(modelos_enviados).to eq(['presente_lembrete'])
      expect(execucao_de(lembra).estado).to eq('concluida')
    end

    # G61: fora do gatilho de reunião, "quem atende a reunião" é a próxima reunião marcada do contato; o salvar aceita.
    # O reuniao.* segue só nos gatilhos de reunião.
    it '"quem atende a reunião" fora do gatilho de reunião salva; reuniao.* não', :aggregate_failures do
      sem_reuniao = { id: 'avisa', tipo: 'avisar', para: { da_reuniao: true }, texto: ['Hidratação de presente marcada'] }
      receita = { gatilho: { tipo: 'card.entrou_na_etapa', etapa_id: revisao.id }, passos: [sem_reuniao] }
      post api_automacoes(account), params: { nome: 'Certa', receita: receita }, headers: seu_ze.create_new_auth_token, as: :json
      expect(response).to have_http_status(:created)

      receita = { gatilho: { tipo: 'card.entrou_na_etapa', etapa_id: revisao.id }, passos: [aviso] }
      post api_automacoes(account), params: { nome: 'Errada', receita: receita }, headers: seu_ze.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include('só existe nos gatilhos de reunião')
    end
  end
end
