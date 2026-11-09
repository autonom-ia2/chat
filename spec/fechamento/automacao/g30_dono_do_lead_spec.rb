require 'rails_helper'

# Fechamento do épico #2414 (#2570), lacuna G30 (#2702): o card do lead do formulário nasce com o dono que a Atribuição
# do funil daria. Provado nos passos 4 e 7 do exemplo 2 ("Lead do anúncio atendido em 5 minutos"): o lead entra pelo
# importador de verdade, o card nasce com a corretora que cuida do funil, o retorno "ligar ainda hoje" vai para ela e o
# link da agenda é o dela. A mensagem do passo 7 sai pelo WhatsApp, que é de outras lacunas (o lead não tem conversa);
# aqui o link vai para a nota do contato, que prova o valor. O exemplo 2 inteiro fica no pendentes_spec até as outras
# lacunas fecharem.
RSpec.describe 'Fechamento #2414 · G30: o card do lead nasce com dono', :automacao_motor, :fechamento_automacao, type: :request do
  include ActiveJob::TestHelper

  around { |exemplo| with_modified_env(CRM_KANBAN_ENABLED: 'true', CRM_CALENDAR_MEETINGS_ENABLED: 'true') { exemplo.run } }

  let(:account) { create(:account, locale: 'pt_BR') }
  let(:marcio) { create(:user, account: account, role: :administrator, name: 'Márcio Imóveis') }
  let(:ana) { create(:user, account: account, role: :agent, name: 'Ana Corretora') }
  let(:funil_e_etapa) { create_crm_pipeline(account: account, user: marcio, name: 'Lançamentos') }
  let(:funil) { funil_e_etapa.first }
  let(:etapa) { funil_e_etapa.last }
  let(:caixa) { create_crm_whatsapp_api_inbox(account: account, members: [ana]) }
  let(:agenda_da_ana) { create_booking_profile(account: account, host: ana, pipeline: funil, stage: etapa, title: 'Visita') }

  let(:receita) do
    {
      gatilho: { tipo: 'card.criado', funil_id: funil.id },
      passos: [
        { id: 'ligar', tipo: 'retorno', titulo: ['Ligar para ', { '$valor' => 'contato.nome' }], daqui: { valor: 2, unidade: 'horas' } },
        { id: 'agenda', tipo: 'acao', acao: 'POST contacts/:contact_id/notes', descricao: 'Anotar o link da agenda',
          caminho: { contact_id: { '$valor' => 'contato.id' } },
          corpo: { content: { '$texto' => ['Agenda do corretor: ', { '$valor' => 'card.link_da_agenda' }] } } }
      ]
    }
  end

  before do
    flags_do_piloto(account)
    account.enable_features!('automacao_gatilhos', 'crm_booking_v2')
    account.crm_pipeline_inboxes.create!(pipeline: funil, inbox: caixa)
    funil.update!(metadata: { 'ai' => { 'handoff' => { 'enabled' => true } } })
    agenda_da_ana
    allow(OnlineStatusTracker).to receive(:get_available_users).and_return({})
    clear_enqueued_jobs
  end

  after { Current.reset }

  def drenar
    drenados = [EventDispatcherJob, Autonomia::Automacao::EventoDoCardJob, Autonomia::Automacao::AvancarJob]
    FechamentoAutomacao::LIMITE_DE_JOBS.times do
      job = enqueued_jobs.find { |item| drenados.include?(item[:job]) }
      return unless job

      enqueued_jobs.delete(job)
      job[:job].perform_now(*ActiveJob::Arguments.deserialize(job[:args]))
    end
    raise "a fila não esvaziou em #{FechamentoAutomacao::LIMITE_DE_JOBS} jobs"
  end

  def lead
    { 'id' => 'L2730', 'created_time' => '2026-11-08T12:00:00+0000', 'form_id' => '9001', 'ad_name' => 'Apartamento Jardim',
      'field_data' => [{ 'name' => 'full_name', 'values' => ['Ana Souza'] }, { 'name' => 'phone_number', 'values' => ['+5511987652730'] }] }
  end

  it 'passos 4 e 7: o retorno vai para a corretora dona do card e o link da agenda é o dela', :aggregate_failures do
    automacao = montar_automacao(marcio, account, nome: 'Lead do anúncio atendido em 5 minutos', receita: receita)
    ligar_automacao(marcio, account, automacao)

    freeze_time do
      Crm::MetaAds::LeadForms::Importer.new(account: account, pipeline: funil, stage: etapa, form_name: 'Visitas').import(lead)
      drenar

      card = account.crm_cards.sole
      expect(card.owner).to eq(ana)
      expect(historico_de(automacao)).to eq([['ligar', 'ok', nil], ['agenda', 'ok', nil]])
      expect(Crm::FollowUp.sole).to have_attributes(card_id: card.id, title: 'Ligar para Ana Souza', recipient_mode: 'card_owner',
                                                    due_at: 2.hours.from_now)
      expect(card.contact.notes.sole.content).to eq("Agenda do corretor: #{Crm::BookingV2::ShortLink.url_for(agenda_da_ana)}")
    end
  end
end
