require 'rails_helper'

# #2499 (G12): os gatilhos de reunião e os valores da reunião e da agenda. A reunião marcada, remarcada ou cancelada
# pelos serviços reais grava a atividade do card; o emissor do CRM despacha só para a Automação livre (os webhooks da
# conta não recebem), e a escuta começa a automação no card, com a marca da atividade.
RSpec.describe 'Automação livre: gatilhos de reunião', :automacao_motor do # rubocop:disable RSpec/DescribeClass
  include ActiveJob::TestHelper

  around do |example|
    with_modified_env(CRM_KANBAN_ENABLED: 'true', CRM_CALENDAR_MEETINGS_ENABLED: 'true') { example.run }
  end

  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:world) { build_booking_world(account: account) }
  let(:card) { world.card }
  let(:inicio) { Time.utc(2026, 10, 20, 13, 0, 0) }
  let(:execucoes) { Autonomia::Automacao::Execucao }

  before do
    travel_to Time.utc(2026, 10, 12, 11, 0, 0)
    ligar_motor(account)
    account.enable_features!('automacao_gatilhos', 'crm_booking_v2')
    world
    clear_enqueued_jobs
  end

  after { Current.reset }

  def drenar
    drenados = [EventDispatcherJob, Autonomia::Automacao::EventoDoCardJob]
    40.times do
      job = enqueued_jobs.find { |item| drenados.include?(item[:job]) }
      return unless job

      enqueued_jobs.delete(job)
      job[:job].perform_now(*ActiveJob::Arguments.deserialize(job[:args]))
    end
    raise 'a fila não esvaziou em 40 jobs'
  end

  def de_reuniao(tipo, **parametros)
    automacao_ligada(account, admin, [esperar_passo('p1')], gatilho: { 'tipo' => tipo, **parametros.transform_keys(&:to_s) })
  end

  def marcar(comeca = inicio, **params)
    Crm::Meetings::InternalCreator.new(account: account, card: card, inbox: nil, scheduled_by: world.host, params: {
      title: 'Conversa', starts_at: comeca, ends_at: comeca + 30.minutes, timezone: 'America/Sao_Paulo', extra_guests: [],
      location_type: 'whatsapp_video'
    }.merge(params)).perform
  end

  def atividade(tipo) = Crm::Activity.where(card_id: card.id, event_type: tipo).last

  describe 'os três gatilhos, pelos serviços reais' do
    it 'reunião marcada começa no card, com a marca da atividade' do
      definicao = de_reuniao('card.reuniao_marcada')
      marcar
      drenar

      execucao = execucoes.sole
      expect([execucao.automacao_id, execucao.alvo, execucao.chave_gatilho]).to eq([definicao.id, card, 'card.reuniao_marcada'])
      expect(execucao.evento).to eq("card.reuniao_marcada:atividade:#{atividade('meeting_scheduled').id}")
    end

    it 'reunião remarcada e cancelada disparam cada uma o seu', :aggregate_failures do
      remarcada = de_reuniao('card.reuniao_remarcada')
      cancelada = de_reuniao('card.reuniao_cancelada')
      reuniao = marcar
      drenar
      expect(execucoes.count).to eq(0)

      Crm::Meetings::RescheduleService.new(meeting: reuniao, params: { starts_at: inicio + 1.day, ends_at: inicio + 1.day + 30.minutes })
                                      .perform
      drenar
      expect(execucoes.where(automacao: remarcada).pluck(:alvo_id)).to eq([card.id])

      Crm::Meetings::CancelService.new(meeting: reuniao.reload).perform
      drenar
      expect(execucoes.where(automacao: cancelada).pluck(:alvo_id)).to eq([card.id])
    end

    it 'o mesmo evento entregue duas vezes abre uma execução só' do
      de_reuniao('card.reuniao_marcada')
      marcar
      despacho = enqueued_jobs.find { |item| item[:job] == EventDispatcherJob }
      enqueued_jobs << despacho.dup
      drenar

      expect(execucoes.count).to eq(1)
    end

    # Qualidade, G12 (c): a reunião marcada dentro de uma cadeia em curso leva a cadeia ao EventoDoCardJob, pelo
    # despacho, como no card. Hoje nenhum passo marca reunião; o laço entra no spec se isso mudar.
    it 'reunião marcada dentro de uma cadeia leva a cadeia ao EventoDoCardJob' do
      de_reuniao('card.reuniao_marcada')
      Autonomia::Automacao::Cadeia.entrar('automacao:999', account) { marcar }
      despacho = enqueued_jobs.find { |item| item[:job] == EventDispatcherJob && item[:args].first == Events::Types::CRM_MEETING_SCHEDULED }
      enqueued_jobs.delete(despacho)
      EventDispatcherJob.perform_now(*ActiveJob::Arguments.deserialize(despacho[:args]))

      job = enqueued_jobs.find { |item| item[:job] == Autonomia::Automacao::EventoDoCardJob }
      dados = ActiveJob::Arguments.deserialize(job[:args]).first
      expect(dados.dig('autonomia_cadeia', 'origens')).to include('automacao:999')
    end

    it 'o funil escolhido filtra: reunião em card de outro funil não começa' do
      outro_funil, = create_crm_pipeline(account: account, user: admin)
      de_reuniao('card.reuniao_marcada', funil_id: outro_funil.id)
      marcar
      drenar

      expect(execucoes.count).to eq(0)
    end

    it 'sem as reuniões da instalação, o gatilho não vale' do
      de_reuniao('card.reuniao_marcada')
      with_modified_env(CRM_CALENDAR_MEETINGS_ENABLED: 'false') do
        marcar
        drenar
      end

      expect(execucoes.count).to eq(0)
    end
  end

  describe 'os webhooks da conta não mudam' do
    it 'sem automação de reunião, nada é despachado, mesmo com webhook que assina todos os eventos do card' do
      create(:webhook, account: account, webhook_type: :account_type,
                       subscriptions: Crm::Webhooks::Emitter::EVENT_MAP.values + ['conversation_created'])
      marcar

      expect(enqueued_jobs.map { |item| item[:job] }).not_to include(EventDispatcherJob)
    end

    it 'com automação de reunião, o despacho roda e o webhook que assina todos os eventos do card não recebe nada', :aggregate_failures do
      create(:webhook, account: account, webhook_type: :account_type,
                       subscriptions: Crm::Webhooks::Emitter::EVENT_MAP.values + ['conversation_created'])
      de_reuniao('card.reuniao_marcada')
      marcar
      drenar

      expect(execucoes.count).to eq(1)
      expect(enqueued_jobs.map { |item| item[:job] }).not_to include(WebhookJob)
    end
  end

  it 'reuniões da instalação desligadas: o salvar recusa o gatilho de reunião' do
    receita = { 'gatilho' => { 'tipo' => 'card.reuniao_marcada' }, 'passos' => [esperar_passo('p1')] }
    problemas = with_modified_env(CRM_CALENDAR_MEETINGS_ENABLED: 'false') do
      Autonomia::Automacao::Receita.new(receita, conta: account, account_user: nil).problemas
    end

    expect(problemas).to include(I18n.t('autonomia.automacao.receita.reunioes_desligadas'))
  end

  describe 'a reunião do gatilho nos valores' do
    def valores_da(execucao) = Autonomia::Automacao::Valores.new(alvo: Autonomia::Automacao::Contexto.de(card, execucao: execucao), quem: admin)

    before { account.update!(locale: 'pt_BR') }

    it 'lê o início no fuso e no idioma da conta, e o link da chamada', :aggregate_failures do
      de_reuniao('card.reuniao_marcada')
      marcar(location_type: 'custom_link', location_url: 'https://meet.example.com/abc')
      drenar
      valores = valores_da(execucoes.sole)

      expect(valores.ler('reuniao.inicio')).to eq('20/10/2026 às 10:00')
      expect(valores.ler('reuniao.link_da_reuniao')).to eq('https://meet.example.com/abc')
    end

    it 'conta em inglês: o formato em inglês' do
      account.update!(locale: 'en')
      de_reuniao('card.reuniao_marcada')
      marcar
      drenar

      expect(valores_da(execucoes.sole).ler('reuniao.inicio')).to eq('10/20/2026 at 10:00')
    end

    it 'remarcada de novo depois: o passo lê o horário novo' do
      de_reuniao('card.reuniao_marcada')
      reuniao = marcar
      drenar
      Crm::Meetings::RescheduleService.new(meeting: reuniao, params: { starts_at: inicio + 2.hours, ends_at: inicio + 150.minutes }).perform

      expect(valores_da(execucoes.sole).ler('reuniao.inicio')).to eq('20/10/2026 às 12:00')
    end

    # Parecer do Funções: a reunião é sempre a do card do alvo, nunca só pelo id que a atividade traz.
    it 'atividade apontando para a reunião de outro card: vazio' do
      de_reuniao('card.reuniao_marcada')
      marcar
      drenar
      outro_card = create_booking_card(account: account, pipeline: world.pipeline, stage: world.stage, contact: world.contact)
      alheia = create_internal_meeting(world: world, starts_at: inicio + 3.days, card: outro_card)
      atividade('meeting_scheduled').update_columns(payload: { 'meeting_id' => alheia.id }) # rubocop:disable Rails/SkipsModelValidations

      expect(valores_da(execucoes.sole).ler('reuniao.inicio')).to be_nil
    end

    it 'fora do gatilho de reunião não há reunião, e o salvar recusa reuniao.*', :aggregate_failures do
      definicao = de_reuniao('card.ganho')
      execucao = execucoes.create!(account: account, automacao: definicao, versao: definicao.versao_ativa, alvo: card,
                                   chave_gatilho: 'card.ganho', evento: 'card.ganho:atividade:1')
      expect(valores_da(execucao).ler('reuniao.inicio')).to be_nil

      receita = { 'gatilho' => { 'tipo' => 'card.ganho' },
                  'passos' => [{ 'id' => 's1', 'tipo' => 'se', 'condicao' => { 'campo' => { '$valor' => 'reuniao.inicio' }, 'op' => 'preenchido' },
                                 'entao' => [esperar_passo('p2')] }] }
      problemas = I18n.with_locale(:pt_BR) { Autonomia::Automacao::Receita.new(receita, conta: account, account_user: nil).problemas }
      expect(problemas.join).to include('só existe nos gatilhos de reunião')
    end
  end

  describe 'o link da agenda' do
    let(:link) { Autonomia::Automacao::LinkDaAgenda }

    it 'na página fixa em que o responsável do card atende, o endereço da página' do
      expect(link.de(account, card.owner)).to eq(Crm::BookingV2::ShortLink.url_for(world.profile))
    end

    it 'vale em gatilho de conversa e de card, pelo Valores', :aggregate_failures do
      conversa = create(:conversation, account: account, assignee: world.host)
      card.update!(primary_conversation: conversa)

      expect(Autonomia::Automacao::Valores.new(alvo: card, quem: admin).ler('card.link_da_agenda'))
        .to eq(Crm::BookingV2::ShortLink.url_for(world.profile))
      expect(Autonomia::Automacao::Valores.new(alvo: conversa, quem: admin).ler('conversa.link_da_agenda'))
        .to eq(Crm::BookingV2::ShortLink.url_for(world.profile))
    end

    it 'duas páginas sem pista: vazio por varias_paginas; com a página da reunião, a dela', :aggregate_failures do
      segunda = create_booking_profile(account: account, host: world.host, title: 'Revisão')

      expect(link.resultado(account, card.owner).to_h).to eq(url: nil, por: 'varias_paginas')
      expect(link.de(account, card.owner, pagina_id: segunda.id)).to eq(Crm::BookingV2::ShortLink.url_for(segunda))
    end

    it 'a página da reunião só desempata: se a pessoa não atende nela, vale a única em que atende', :aggregate_failures do
      colega = create(:user, account: account, role: :agent)
      alheia = create_booking_profile(account: account, host: colega, title: 'Da colega')

      expect(link.de(account, card.owner, pagina_id: alheia.id)).to eq(Crm::BookingV2::ShortLink.url_for(world.profile))
    end

    it 'página de link por pessoa: o link dela; link desligado não vale, e nunca o de outra pessoa', :aggregate_failures do
      colega = create(:user, account: account, role: :agent)
      world.profile.update!(assignment_mode: :per_agent)
      proprio = account.crm_agent_booking_links.create!(booking_profile: world.profile, agent: world.host, slug: SecureRandom.uuid)
      account.crm_agent_booking_links.create!(booking_profile: world.profile, agent: colega, slug: SecureRandom.uuid)

      expect(link.de(account, card.owner)).to eq(Crm::BookingV2::ShortLink.url_for(world.profile, link: proprio))

      proprio.update!(enabled: false)
      expect(link.de(account, card.owner)).to be_nil
    end

    it 'sem responsável (sem_responsavel), agendamento desligado ou quem saiu da conta (sem_pagina)', :aggregate_failures do
      expect(link.resultado(account, nil).to_h).to eq(url: nil, por: 'sem_responsavel')

      account.disable_features!('crm_booking_v2')
      expect(link.resultado(account, card.owner).to_h).to eq(url: nil, por: 'sem_pagina')
      account.enable_features!('crm_booking_v2')

      AccountUser.find_by(account: account, user: world.host).destroy!
      expect(link.resultado(account, world.host).to_h).to eq(url: nil, por: 'sem_pagina')
    end

    # Qualidade, G12 (b): o passo que fica sem o link pula com o motivo próprio e o porquê, nunca com a URL nos dados.
    it 'o passo de mensagem sem o link pula com faltou_link_da_agenda e o por', :aggregate_failures do
      ligar_mensagens(account)
      conversa = create(:conversation, account: account, contact: world.contact)
      card.update!(primary_conversation: conversa, owner: nil)
      passo = mensagem_passo('m1', 'Marque aqui: ', { '$valor' => 'card.link_da_agenda' })
      definicao = automacao_ligada(account, admin, [passo], gatilho: { 'tipo' => 'card.ganho' })
      execucao = execucoes.create!(account: account, automacao: definicao, versao: definicao.versao_ativa, alvo: card,
                                   chave_gatilho: 'card.ganho', evento: 'card.ganho:atividade:1')

      resultado = Autonomia::Automacao::PassoDeMensagem.new(execucao: execucao, passo: passo, alvo: card).executar

      expect([resultado.tipo, resultado.motivo, resultado.dados]).to eq([:pulado, 'faltou_link_da_agenda', { 'por' => 'sem_responsavel' }])
    end

    it 'o link vazio junto de outro valor vazio: o motivo geral, faltou_valor' do
      ligar_mensagens(account)
      conversa = create(:conversation, account: account, contact: world.contact)
      card.update!(primary_conversation: conversa, owner: nil)
      world.contact.update!(name: '')
      passo = mensagem_passo('m1', { '$valor' => 'contato.nome' }, ', marque aqui: ', { '$valor' => 'card.link_da_agenda' })
      definicao = automacao_ligada(account, admin, [passo], gatilho: { 'tipo' => 'card.ganho' })
      execucao = execucoes.create!(account: account, automacao: definicao, versao: definicao.versao_ativa, alvo: card,
                                   chave_gatilho: 'card.ganho', evento: 'card.ganho:atividade:1')

      resultado = Autonomia::Automacao::PassoDeMensagem.new(execucao: execucao, passo: passo, alvo: card).executar

      expect([resultado.motivo, resultado.dados]).to eq(['faltou_valor', {}])
    end

    it 'no modelo do WhatsApp (janela fechada) sem o link: o mesmo motivo próprio e o por, e a execução para' do
      ligar_mensagens(account)
      conversa = create(:conversation, account: account, contact: world.contact)
      card.update!(primary_conversation: conversa, owner: nil)
      definicao = automacao_ligada(account, admin, [esperar_passo('p1')], gatilho: { 'tipo' => 'card.ganho' })
      execucao = execucoes.create!(account: account, automacao: definicao, versao: definicao.versao_ativa, alvo: card,
                                   chave_gatilho: 'card.ganho', evento: 'card.ganho:atividade:1')
      passo = mensagem_passo('m1', 'Oi').merge('modelo' => { 'nome' => 'agenda' })
      allow(Conversations::MessageWindowService).to receive(:new).and_return(instance_double(Conversations::MessageWindowService, can_reply?: false))
      allow(Autonomia::Automacao::ModeloWhatsapp).to receive(:aplica?).and_return(true)
      allow(Autonomia::Automacao::ModeloWhatsapp).to receive(:new) do |_modelo, _conversa, valores|
        instance_double(Autonomia::Automacao::ModeloWhatsapp, preparar: valores.ler('card.link_da_agenda') || 'faltou_valor')
      end

      resultado = Autonomia::Automacao::PassoDeMensagem.new(execucao: execucao, passo: passo, alvo: card).executar

      expect([resultado.tipo, resultado.motivo, resultado.dados])
        .to eq([:pulado, 'faltou_link_da_agenda', { 'por' => 'sem_responsavel', 'janela' => 'fechada' }])
    end
  end
end
