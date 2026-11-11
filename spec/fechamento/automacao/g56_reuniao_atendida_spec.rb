require 'rails_helper'

# Fechamento do épico #2414 (#2570), lacuna G56: o gatilho "reunião atendida". Exemplo 6, passos 8 e 9:
# "Atendida: no dia seguinte pede, pelo modelo aprovado, uma foto do resultado e autorização para postar." / "A IA extrai
# se ela autorizou. Autorizou: põe a etiqueta 'pode postar' e avisa a Jéssica."
#
# Montado pela API da tela. O "Aconteceu" é o da Agenda (POST record_outcome, Crm::Meetings::RecordOutcomeService), o
# evento sai pelo emissor do CRM e chega ao motor pelo despacho; o modelo aprovado para no receptor do WhatsApp oficial e
# a IA é o dublê. Só o primeiro "Aconteceu" dispara (first_held na atividade). O exemplo 6 inteiro segue no
# pendentes_spec (G6, G47 e as outras lacunas dele).
RSpec.describe 'Fechamento #2414 · G56: reunião atendida', :fechamento_automacao, type: :request do
  include ActiveJob::TestHelper

  around do |exemplo|
    with_modified_env(CRM_KANBAN_ENABLED: 'true', CRM_CALENDAR_MEETINGS_ENABLED: 'true') { exemplo.run }
  end

  let(:canal) { create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false) }
  let(:account) { canal.account }
  let(:inbox) { canal.inbox }
  let(:jessica) { create(:user, account: account, role: :administrator, name: 'Jéssica') }
  let(:profissional) { create(:user, account: account, role: :administrator, name: 'Carol Profissional') }
  let(:bia) { create(:contact, account: account, name: 'Bia', phone_number: '+5511900000056') }
  let(:conversa) do
    contact_inbox = create(:contact_inbox, inbox: inbox, contact: bia, source_id: '5511900000056')
    create(:conversation, account: account, inbox: inbox, contact: bia, contact_inbox: contact_inbox, status: :open)
  end
  let(:aniversario) { create_crm_pipeline(account: account, user: jessica, name: 'Aniversário').first }
  let(:marcou) { create_crm_stage(account: account, pipeline: aniversario, name: 'Marcou', position: 1) }
  let(:roteiro) { { 'automacao_extrair' => { 'autorizou' => 'sim' } } }

  def fuso = ActiveSupport::TimeZone['America/Sao_Paulo']
  def as(hora, &) = travel_to(fuso.parse(hora), &)
  def conversa_id = { '$valor' => 'conversa.id' }

  def receita(funil: aniversario)
    autorizou = { campo: { '$valor' => 'conversa.atributos.autorizou' }, op: 'igual', valor: 'sim' }
    { gatilho: { tipo: 'card.reuniao_atendida', funil_id: funil.id }, passos: [
      { id: 'dia_seguinte', tipo: 'esperar', duracao: { valor: 1, unidade: 'dias' } },
      { id: 'pede_foto', tipo: 'mensagem', texto: ['Oi ', { '$valor' => 'contato.nome' }, ', manda uma foto do resultado?'],
        modelo: { nome: 'foto_do_resultado', idioma: 'pt_BR', variaveis: [[{ '$valor' => 'contato.nome' }]] } },
      { id: 'resposta', tipo: 'esperar_ate', condicao: { campo: { '$valor' => 'conversa.cliente_respondeu' }, op: 'igual', valor: true },
        prazo: { valor: 3, unidade: 'dias' } },
      { id: 'autorizou', tipo: 'extrair', le: %w[mensagens_recentes],
        campos: [{ chave: 'autorizou', descricao: 'sim se ela autorizou postar a foto no Instagram, não se não autorizou',
                   destino: 'conversa.atributos.autorizou' }] },
      { id: 'se_autorizou', tipo: 'se', condicao: autorizou, entao: [
        { id: 'pode_postar', tipo: 'acao', acao: 'PATCH conversations/:conversation_id/labels/alterar',
          descricao: 'Pôr a etiqueta pode postar', caminho: { conversation_id: conversa_id }, corpo: { por: ['pode-postar'] } },
        { id: 'avisa_jessica', tipo: 'avisar', para: { pessoas: [jessica.id] },
          texto: [{ '$valor' => 'contato.nome' }, ' autorizou postar a foto do resultado.'] }
      ] }
    ] }
  end

  def ligada(nome, receita)
    automacao = montar_automacao(jessica, account, nome: nome, receita: receita)
    ligar_automacao(jessica, account, automacao)
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

  def card_no_funil(funil, etapa, titulo)
    Crm::Cards::Creator.new(account: account, user: jessica, params: {
                              pipeline_id: funil.id, stage_id: etapa.id, contact_id: bia.id, owner_id: profissional.id,
                              conversation_id: conversa.id, inbox_id: inbox.id, title: titulo, currency: 'BRL'
                            }).perform
    drenar
    account.crm_cards.find_by!(title: titulo)
  end

  # A reunião interna do card, das 14h às 15h do dia 10, marcada pela agenda.
  def reuniao_de(card)
    params = { title: 'Hidratação de presente', starts_at: fuso.parse('2026-11-10 14:00'), ends_at: fuso.parse('2026-11-10 15:00'),
               timezone: fuso.name, extra_guests: [], location_type: 'whatsapp_video' }
    reuniao = Crm::Meetings::InternalCreator.new(account: account, card: card, inbox: nil, scheduled_by: profissional, params: params).perform
    drenar
    reuniao
  end

  # O botão da Agenda ("Aconteceu" / "Não compareceu"), pela rota da tela.
  def resultado(reuniao, outcome, notes: nil)
    post "/api/v1/accounts/#{account.id}/crm/meetings/#{reuniao.id}/record_outcome",
         params: { meeting: { outcome: outcome, notes: notes }.compact }, headers: profissional.create_new_auth_token, as: :json
    expect(response).to have_http_status(:ok), -> { "o resultado não gravou: #{response.body}" }
    drenar
  end

  def varredura_as(hora)
    as(hora) do
      perform_enqueued_jobs(only: Autonomia::Automacao::AvancarJob) { Autonomia::Automacao::VarreduraJob.perform_now }
      drenar
    end
  end

  def execucoes_de(automacao) = Autonomia::Automacao::Execucao.where(automacao_id: automacao['id'])
  def atendida = Crm::Activity.where(event_type: 'meeting_outcome_recorded').order(:id).first
  def modelos_enviados = chamadas_para('graph.facebook.com').filter_map { |chamada| chamada.corpo.dig('template', 'name') }
  def mencoes_para(pessoa) = Notification.where(user: pessoa, notification_type: 'conversation_mention')

  before do
    receptor_whatsapp_cloud
    ia_responde(account, roteiro)
    as('2026-11-10 10:00') do
      account.update!(locale: 'pt_BR', reporting_timezone: fuso.name, custom_attributes: { 'timezone' => fuso.name })
      flags_do_piloto(account)
      account.enable_features!('automacao_gatilhos', 'crm_booking_v2')
      [jessica, profissional].each { |pessoa| create(:inbox_member, user: pessoa, inbox: inbox) }
      create(:custom_attribute_definition, account: account, attribute_key: 'autorizou', attribute_display_name: 'autorizou',
                                           attribute_model: 'conversation_attribute', attribute_display_type: 'text')
      create(:label, account: account, title: 'pode-postar', description: 'Pode postar a foto do resultado')
      canal.update!(message_templates: [{ 'name' => 'foto_do_resultado', 'language' => 'pt_BR', 'status' => 'APPROVED',
                                          'category' => 'UTILITY',
                                          'components' => [{ 'type' => 'BODY', 'text' => 'Oi {{1}}, manda uma foto do resultado?' }] }])
      create(:message, conversation: conversa, account: account, inbox: inbox, message_type: :incoming, sender: bia, content: 'Oi')
      marcou
      clear_enqueued_jobs
    end
  end

  after { Current.reset }

  describe 'exemplo 6, passos 8 e 9' do
    let!(:automacao) { as('2026-11-10 10:00') { ligada('Foto do resultado', receita) } }
    let!(:card) { as('2026-11-10 10:00') { card_no_funil(aniversario, marcou, 'Aniversário da Bia') } }
    let!(:reuniao) { as('2026-11-10 10:00') { reuniao_de(card) } }

    it 'o "Aconteceu" abre uma execução só; no dia seguinte vai o modelo; ela autoriza: etiqueta e aviso', :aggregate_failures do
      as('2026-11-10 16:00') { resultado(reuniao, 'held') }

      execucao = execucoes_de(automacao).sole
      expect([execucao.estado, execucao.alvo, execucao.evento]).to eq(['esperando', card, "card.reuniao_atendida:atividade:#{atendida.id}"])
      expect(modelos_enviados).to be_empty

      as('2026-11-10 16:10') do
        resultado(reuniao, 'held', notes: 'Hidratação feita')
        resultado(reuniao, 'no_show')
        resultado(reuniao, 'held')
      end
      expect(execucoes_de(automacao).count).to eq(1)
      expect(Crm::Activity.where(event_type: 'meeting_outcome_recorded').count).to eq(4)

      varredura_as('2026-11-11 16:30')
      expect(modelos_enviados).to eq(['foto_do_resultado'])

      as('2026-11-11 17:00') { cliente_escreve(conversa, 'Pode postar sim! Segue a foto.') }
      drenar

      expect(conversa.reload.label_list).to include('pode-postar')
      expect(mencoes_para(jessica).count).to eq(1)
      expect(execucao.reload.estado).to eq('concluida')
      # O "esperar até" registra ao começar a espera e ao cumprir.
      passos = %w[dia_seguinte pede_foto resposta resposta autorizou se_autorizou pode_postar avisa_jessica]
      expect(historico_de(automacao)).to eq(passos.map { |passo| [passo, 'ok', nil] })
    end

    it 'ela não autoriza: sem etiqueta e sem aviso', :aggregate_failures do
      roteiro['automacao_extrair'] = { 'autorizou' => 'não' }
      as('2026-11-10 16:00') { resultado(reuniao, 'held') }
      varredura_as('2026-11-11 16:30')
      as('2026-11-11 17:00') { cliente_escreve(conversa, 'Prefiro que não poste.') }
      drenar

      expect(conversa.reload.label_list).not_to include('pode-postar')
      expect(mencoes_para(jessica)).to be_empty
    end

    it '"Não compareceu" não abre execução' do
      as('2026-11-10 16:00') { resultado(reuniao, 'no_show') }

      expect(execucoes_de(automacao)).to be_empty
    end

    # Efeito do gatilho estar em Gatilhos::DE_REUNIAO (crítica da G56): todo resultado da reunião, também o "Não
    # compareceu", acorda quem espera no card (Escuta#acordar_o_card), e o gate do emissor (EsperaDaReuniao.no_card?)
    # assina o evento quando há execução esperando no card. A espera só relê a condição.
    it 'o resultado da reunião acorda quem espera no card, e o gate do emissor assina o evento', :aggregate_failures do
      evento = Events::Types::CRM_MEETING_OUTCOME_RECORDED
      tipos = Autonomia::Automacao::Gatilhos::DO_EVENTO_DO_CARD.fetch(evento)
      espera = { id: 'p1', tipo: 'esperar', duracao: { valor: 1, unidade: 'dias' } }
      outra = ligada('Espera a reunião', { gatilho: { tipo: 'card.ganho' }, passos: [espera] })
      Autonomia::Automacao::Execucao.create!(account: account, automacao_id: outra['id'], versao_id: outra.dig('versao', 'id'), alvo: card,
                                             chave_gatilho: 'card.ganho', evento: 'card.ganho:atividade:0', estado: 'esperando',
                                             due_at: 1.day.from_now)
      expect(Autonomia::Automacao::EsperaDaReuniao.no_card?(account, tipos, card.id)).to be(true)
      allow(Autonomia::Automacao::Escuta).to receive(:acordar_o_card).and_call_original

      as('2026-11-10 16:00') { resultado(reuniao, 'no_show') }

      expect(Autonomia::Automacao::Escuta).to have_received(:acordar_o_card).with(card)
      expect(execucoes_de(automacao)).to be_empty
    end
  end

  it 'a reunião num card de outro funil não abre' do
    outro, outra_etapa = create_crm_pipeline(account: account, user: jessica, name: 'Corte')
    automacao = as('2026-11-10 10:00') { ligada('Foto do resultado', receita) }
    card = as('2026-11-10 10:00') { card_no_funil(outro, outra_etapa, 'Corte da Bia') }
    reuniao = as('2026-11-10 10:00') { reuniao_de(card) }

    as('2026-11-10 16:00') { resultado(reuniao, 'held') }

    expect(execucoes_de(automacao)).to be_empty
  end
end
