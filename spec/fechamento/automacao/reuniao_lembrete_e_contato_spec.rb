require 'rails_helper'

# Fechamento do épico #2414 (#2570), lacunas da reunião achadas nos exemplos 18 e 20 (auditoria de 07/11):
# - #2709, exemplo 18, passo 8: "1 dia antes da entrevista, lembra o endereço pelo modelo" — o gatilho de tempo
#   card.antes_da_reuniao, na varredura de 15 minutos;
# - #2710, exemplo 20, passo 6: "Reunião marcada: move para Implantação" — com o card já ganho, a página de agendamento
#   põe a reunião num card novo do contato (Crm::BookingV2::Booker#book!, intocado); quem espera no card ganho lê
#   contato.tem_reuniao_marcada e acorda com a reunião do card novo.
# A reunião nasce pelo serviço real (Crm::Meetings::InternalCreator, o mesmo da página), e o evento chega ao motor pelo
# emissor do CRM; o modelo aprovado para no receptor do WhatsApp oficial.
RSpec.describe 'Fechamento #2414 · reunião: lembrete antes e reunião do contato', :fechamento_automacao, type: :request do
  include ActiveJob::TestHelper

  around do |exemplo|
    with_modified_env(CRM_KANBAN_ENABLED: 'true', CRM_CALENDAR_MEETINGS_ENABLED: 'true') { exemplo.run }
  end

  let(:canal) { create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false) }
  let(:account) { canal.account }
  let(:inbox) { canal.inbox }
  let(:doutora) { create(:user, account: account, role: :administrator, name: 'Doutora Ana') }
  let(:recepcao) { create(:user, account: account, role: :agent, name: 'Recepção') }
  let(:cliente) { create(:contact, account: account, name: 'Júlia', phone_number: '+5511900002709') }
  let(:conversa) do
    contact_inbox = create(:contact_inbox, inbox: inbox, contact: cliente, source_id: '5511900002709')
    create(:conversation, account: account, inbox: inbox, contact: cliente, contact_inbox: contact_inbox, status: :open)
  end
  let(:funil) { create_crm_pipeline(account: account, user: doutora, name: 'Clientes').first }
  let(:entrada) { create_crm_stage(account: account, pipeline: funil, name: 'Entrada', position: 1) }
  let(:implantacao) { create_crm_stage(account: account, pipeline: funil, name: 'Implantação', position: 2) }
  let(:entrevistas) { create_booking_profile(account: account, host: recepcao, title: 'Entrevistas') }
  let(:outra_pagina) { create_booking_profile(account: account, host: doutora, title: 'Avaliação') }

  def fuso = ActiveSupport::TimeZone['America/Sao_Paulo']
  def inicio = fuso.parse('2026-11-10 08:00')
  def entrevista = fuso.parse('2026-11-13 09:00')

  def ligada(nome, receita)
    automacao = montar_automacao(doutora, account, nome: nome, receita: receita)
    ligar_automacao(doutora, account, automacao)
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

  def novo_card(titulo)
    Crm::Cards::Creator.new(account: account, user: doutora, params: {
                              pipeline_id: funil.id, stage_id: entrada.id, contact_id: cliente.id, owner_id: doutora.id,
                              conversation_id: conversa.id, inbox_id: inbox.id, title: titulo, currency: 'BRL'
                            }).perform
    drenar
    account.crm_cards.find_by!(title: titulo)
  end

  def marca(card, pagina:, quando: entrevista)
    params = { title: 'Entrevista', starts_at: quando, ends_at: quando + 30.minutes, timezone: fuso.name, extra_guests: [],
               location_type: 'whatsapp_video', booking_profile_id: pagina.id }
    Crm::Meetings::InternalCreator.new(account: account, card: card, inbox: nil, scheduled_by: pagina.default_assignee,
                                       params: params).perform
    drenar
    account.crm_meetings.where(card_id: card.id).order(:id).last
  end

  # A varredura dos gatilhos de tempo naquele instante e os jobs que ela abre.
  def varre(instante)
    travel_to(instante) do
      Autonomia::Automacao::TempoJob.perform_now
      perform_enqueued_jobs(only: Autonomia::Automacao::TempoDaAutomacaoJob)
      drenar
    end
  end

  def modelos_enviados = chamadas_para('graph.facebook.com').filter_map { |chamada| chamada.corpo.dig('template', 'name') }

  before do
    travel_to(inicio)
    account.update!(locale: 'pt_BR', reporting_timezone: fuso.name)
    flags_do_piloto(account)
    account.enable_features!('automacao_gatilhos', 'crm_booking_v2')
    [doutora, recepcao].each { |pessoa| create(:inbox_member, user: pessoa, inbox: inbox) }
    canal.update!(message_templates: [{ 'name' => 'endereco_entrevista', 'language' => 'pt_BR', 'status' => 'APPROVED',
                                        'category' => 'UTILITY',
                                        'components' => [{ 'type' => 'BODY', 'text' => 'Oi {{1}}, sua entrevista é {{2}}.' }] }])
    receptor_whatsapp_cloud
    [entrada, implantacao, entrevistas, outra_pagina]
    create(:message, conversation: conversa, account: account, inbox: inbox, message_type: :incoming, sender: cliente, content: 'Oi')
    clear_enqueued_jobs
  end

  after { Current.reset }

  describe 'exemplo 18, passo 8: 1 dia antes da entrevista, lembra pelo modelo (#2709)' do
    def lembrete
      { id: 'lembra', tipo: 'mensagem', texto: ['Lembrete'],
        modelo: { nome: 'endereco_entrevista', idioma: 'pt_BR',
                  variaveis: [[{ '$valor' => 'contato.nome' }], [{ '$valor' => 'reuniao.inicio' }]] } }
    end
    let!(:automacao) do
      ligada('Lembrete da entrevista', { gatilho: { tipo: 'card.antes_da_reuniao', antes: { valor: 1, unidade: 'dias' },
                                                    pagina_id: entrevistas.id }, passos: [lembrete] })
    end
    let!(:card) { novo_card('Seleção da Júlia') }

    def corpo_do_modelo = chamadas_para('graph.facebook.com').last.corpo.dig('template', 'components', 0, 'parameters')

    it 'lembra 1 dia antes, uma vez, com o horário da entrevista; antes disso, não', :aggregate_failures do
      marca(card, pagina: entrevistas)

      varre(entrevista - 1.day - 20.minutes)
      expect(modelos_enviados).to be_empty

      varre(entrevista - 1.day + 5.minutes)
      expect(modelos_enviados).to eq(['endereco_entrevista'])
      expect(corpo_do_modelo.pluck('text')).to eq(['Júlia', '13/11/2026 às 09:00'])
      expect(Autonomia::Automacao::Execucao.sole).to have_attributes(alvo: card, estado: 'concluida')

      varre(entrevista - 1.day + 35.minutes)
      varre(entrevista - 2.hours)
      expect(modelos_enviados).to eq(['endereco_entrevista'])
    end

    it 'remarcada: lembra no horário novo, e não no antigo', :aggregate_failures do
      reuniao = marca(card, pagina: entrevistas)
      nova = entrevista + 2.days
      Crm::Meetings::RescheduleService.new(meeting: reuniao, params: { starts_at: nova, ends_at: nova + 30.minutes }).perform
      drenar

      varre(entrevista - 1.day + 5.minutes)
      expect(modelos_enviados).to be_empty

      varre(nova - 1.day + 5.minutes)
      expect(modelos_enviados).to eq(['endereco_entrevista'])
      expect(corpo_do_modelo.pluck('text').last).to eq('15/11/2026 às 09:00')
    end

    it 'já lembrou e foi remarcada: lembra de novo no horário novo', :aggregate_failures do
      reuniao = marca(card, pagina: entrevistas)
      varre(entrevista - 1.day + 5.minutes)
      nova = entrevista + 2.days
      travel_to(entrevista - 1.day + 10.minutes) do
        Crm::Meetings::RescheduleService.new(meeting: reuniao, params: { starts_at: nova, ends_at: nova + 30.minutes }).perform
        drenar
      end

      varre(nova - 1.day + 5.minutes)
      expect(modelos_enviados).to eq(%w[endereco_entrevista endereco_entrevista])
    end

    it 'cancelada, ou marcada por outra página: não lembra', :aggregate_failures do
      Crm::Meetings::CancelService.new(meeting: marca(card, pagina: entrevistas)).perform
      marca(card, pagina: outra_pagina, quando: entrevista + 1.hour)

      varre(entrevista - 1.day + 5.minutes)
      varre(entrevista - 1.day + 1.hour + 5.minutes)
      expect(modelos_enviados).to be_empty
      expect(Autonomia::Automacao::Execucao.where(automacao_id: automacao['id'])).to be_empty
    end

    it 'card perdido: não lembra' do
      marca(card, pagina: entrevistas)
      Crm::Cards::Closer.new(card: card, actor: doutora, result: 'lost').perform
      drenar

      varre(entrevista - 1.day + 5.minutes)
      expect(Autonomia::Automacao::Execucao.where(automacao_id: automacao['id'])).to be_empty
    end

    it 'marcada com menos de 1 dia de antecedência: lembra na varredura seguinte, uma vez', :aggregate_failures do
      em_cima = inicio + 6.hours
      marca(card, pagina: entrevistas, quando: em_cima)

      varre(inicio + 10.minutes)
      varre(inicio + 25.minutes)
      # A conversa ainda está na janela de 24 h: o passo manda o texto, sem o modelo.
      expect(historico_de(automacao)).to eq([['lembra', 'ok', nil]])
      expect(Autonomia::Automacao::Execucao.sole.evento).to eq("card.antes_da_reuniao:#{Crm::Meeting.sole.id}:#{em_cima.utc.iso8601(6)}")
    end

    it 'ligar não age no passado: o lembrete cujo momento já tinha passado ao ligar não roda, nem com a reunião tocada' do
      outra = novo_card('Seleção antiga')
      travel_to(inicio - 2.days) { marca(outra, pagina: entrevistas, quando: inicio + 12.hours) }
      Autonomia::Automacao::Definicao.find(automacao['id']).update!(ligada_em: inicio + 1.hour)
      # A confirmação do cliente grava na reunião depois de ligar: não vira lembrete.
      travel_to(inicio + 1.hour + 2.minutes) { Crm::Meeting.sole.update!(title: 'Entrevista confirmada') }

      varre(inicio + 1.hour + 5.minutes)
      expect(Autonomia::Automacao::Execucao.where(automacao_id: automacao['id'])).to be_empty
    end
  end

  describe 'o valor contato.tem_reuniao_marcada' do
    def tem_reuniao?(card) = Autonomia::Automacao::Valores.new(alvo: card.reload, quem: doutora).ler('contato.tem_reuniao_marcada')

    it 'conta a reunião por vir em qualquer card do contato; cancelada ou já passada, não', :aggregate_failures do
      ganho = novo_card('Contrato da Júlia')
      expect(tem_reuniao?(ganho)).to be(false)

      reuniao = marca(novo_card('Júlia - Entrevistas'), pagina: entrevistas)
      expect(tem_reuniao?(ganho)).to be(true)

      travel_to(entrevista + 1.hour) { expect(tem_reuniao?(ganho)).to be(false) }

      Crm::Meetings::CancelService.new(meeting: reuniao).perform
      expect(tem_reuniao?(ganho)).to be(false)
    end
  end

  describe 'exemplo 20, passo 6: a reunião marcada depois do ganho move o card ganho (#2710)' do
    let!(:automacao) do
      ligada('Cliente novo', { gatilho: { tipo: 'card.ganho', funil_id: funil.id }, passos: [
               { id: 'marcou', tipo: 'esperar_ate',
                 condicao: { campo: { '$valor' => 'contato.tem_reuniao_marcada' }, op: 'igual', valor: true },
                 prazo: { valor: 30, unidade: 'dias' }, se_vencer: [] },
               { id: 'implantacao', tipo: 'acao', acao: 'POST crm/cards/:id/move', descricao: 'Mover o card',
                 caminho: { id: { '$valor' => 'card.id' } }, corpo: { stage_id: implantacao.id } }
             ] })
    end
    let!(:ganho) { novo_card('Contrato da Júlia') }

    def execucao = Autonomia::Automacao::Execucao.find_by!(automacao_id: automacao['id'], alvo: ganho)

    before do
      Crm::Cards::Closer.new(card: ganho, actor: doutora, result: 'won').perform
      drenar
    end

    it 'a reunião cai num card novo do contato: o card ganho acorda na hora e vai para Implantação', :aggregate_failures do
      expect(execucao.estado).to eq('esperando')

      # O que o Booker faz com o card ganho: abre outro card do contato no funil da página.
      travel_to(inicio + 2.days) { marca(novo_card('Júlia - Entrevistas'), pagina: entrevistas) }

      expect(execucao.estado).to eq('concluida')
      expect(ganho.reload).to have_attributes(stage_id: implantacao.id, status: 'won')
      expect(account.crm_cards.find_by!(title: 'Júlia - Entrevistas').stage_id).to eq(entrada.id)
    end

    it 'a espera pela resposta do cliente, no mesmo card, não é acordada pela reunião' do
      resposta = ligada('Respondeu', { gatilho: { tipo: 'card.ganho', funil_id: funil.id }, passos: [
                          { id: 'respondeu', tipo: 'esperar_ate', prazo: { valor: 2, unidade: 'dias' }, se_vencer: [],
                            condicao: { campo: { '$valor' => 'conversa.cliente_respondeu' }, op: 'igual', valor: true } }
                        ] })
      outro_ganho = novo_card('Outro contrato')
      Crm::Cards::Closer.new(card: outro_ganho, actor: doutora, result: 'won').perform
      drenar
      esperando = Autonomia::Automacao::Execucao.find_by!(automacao_id: resposta['id'], alvo: outro_ganho)
      allow(Autonomia::Automacao::Escuta).to receive(:reservar).and_call_original

      marca(novo_card('Júlia - Entrevistas'), pagina: entrevistas)

      expect(Autonomia::Automacao::Escuta).not_to have_received(:reservar).with(have_attributes(id: esperando.id))
      expect(execucao.reload.estado).to eq('concluida')
    end

    it 'a reunião de outro contato não acorda nem conta' do
      outro = create(:contact, account: account, name: 'Pedro', phone_number: '+5511900002710')
      card_do_outro = Crm::Cards::Creator.new(account: account, user: doutora, params: {
                                                pipeline_id: funil.id, stage_id: entrada.id, contact_id: outro.id,
                                                owner_id: doutora.id, title: 'Pedro', currency: 'BRL'
                                              }).perform
      drenar
      marca(card_do_outro, pagina: entrevistas)

      expect(execucao.estado).to eq('esperando')
      expect(ganho.reload.stage_id).to eq(entrada.id)
    end
  end
end
