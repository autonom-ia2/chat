require 'rails_helper'

# Fechamento do épico #2414 (#2702), lacuna G30: o card do lead do formulário nasce com dono (opção A do Rodrigo, 07/11).
# Provado nos passos 4 e 7 do exemplo 2 ("4. Sem resposta: retorno ao corretor responsável pelo anúncio. 7. Quer
# visitar: link da agenda do corretor do anúncio"), com o corretor fixo na Atribuição do funil ("A mesma pessoa"). O
# lead chega pelo importador de verdade, o card criado sai pelo emissor do CRM, e o motor cria o retorno para o dono e
# lê o link da agenda dele. O exemplo 2 inteiro fica no pendentes_spec até as lacunas G31 e G32 fecharem.
RSpec.describe 'Fechamento #2414 · G30: o card do lead com o dono da Atribuição', :automacao_motor, :fechamento_automacao,
               type: :request do
  include ActiveJob::TestHelper

  around { |exemplo| with_modified_env(CRM_KANBAN_ENABLED: 'true', CRM_CALENDAR_MEETINGS_ENABLED: 'true') { exemplo.run } }

  let(:account) { create(:account, locale: 'pt_BR') }
  let(:dono) { create(:user, account: account, role: :administrator, name: 'Paula Imobiliária') }
  let(:corretor) { create(:user, account: account, role: :agent, name: 'Rafael Corretor') }
  let(:funil) { create_crm_pipeline(account: account, user: dono).first }
  let(:importador) do
    Crm::MetaAds::LeadForms::Importer.new(account: account, pipeline: funil, stage: funil.stages.first, form_name: 'Quero visitar')
  end

  let(:retorno_ao_corretor) do
    { id: 'retorno_ao_corretor', tipo: 'retorno', titulo: ['Ligar para ', { '$valor' => 'contato.nome' }],
      daqui: { valor: 1, unidade: 'horas' } }
  end

  before do
    flags_do_piloto(account)
    account.enable_features!('automacao_gatilhos', 'crm_booking_v2')
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

  def corretor_fixo_no_funil
    regra = { 'enabled' => true, 'pool_type' => 'user', 'pool_id' => corretor.id }
    funil.update!(metadata: (funil.metadata || {}).merge('ai' => { 'handoff' => regra }))
  end

  def ligada(*passos)
    receita = { gatilho: { tipo: 'card.criado', funil_id: funil.id,
                           filtros: [{ campo: { '$valor' => 'card.origem' }, op: 'igual', valor: 'formulario_do_anuncio' }] },
                passos: passos }
    automacao = montar_automacao(dono, account, nome: 'Lead do anúncio', receita: receita)
    ligar_automacao(dono, account, automacao)
    automacao
  end

  def chega_o_lead
    importador.import('id' => 'L1', 'created_time' => '2026-11-07T12:00:00+0000', 'form_id' => '9001', 'ad_id' => '120001',
                      'ad_name' => 'Apartamento Jardins', 'field_data' => [{ 'name' => 'full_name', 'values' => ['Marcos Lima'] },
                                                                           { 'name' => 'phone_number', 'values' => ['+5511987650002'] }])
    drenar
    account.crm_cards.find_by!(source: Crm::MetaAds::LeadForms::Importer::SOURCE)
  end

  it 'passo 4: o retorno vai para o corretor fixo do funil, dono do card do lead', :aggregate_failures do
    corretor_fixo_no_funil
    automacao = ligada(retorno_ao_corretor)

    card = chega_o_lead

    expect(card.owner).to eq(corretor)
    expect(historico_de(automacao)).to eq([['retorno_ao_corretor', 'ok', nil]])
    expect(Crm::FollowUp.sole).to have_attributes(card_id: card.id, title: 'Ligar para Marcos Lima', recipient_mode: 'card_owner')
  end

  it 'passo 7: o link da agenda do card é a página do corretor' do
    corretor_fixo_no_funil
    pagina = create_booking_profile(account: account, host: corretor)

    card = chega_o_lead

    expect(Autonomia::Automacao::Valores.new(alvo: card, quem: dono).ler('card.link_da_agenda'))
      .to eq(Crm::BookingV2::ShortLink.url_for(pagina))
  end

  it 'funil com rodízio: o card fica sem dono e o retorno pula com o motivo', :aggregate_failures do
    funil.update!(metadata: (funil.metadata || {}).merge('ai' => { 'handoff' => { 'enabled' => true, 'pool_type' => 'inbox' } }))
    automacao = ligada(retorno_ao_corretor)

    card = chega_o_lead

    expect(card.owner_id).to be_nil
    expect(historico_de(automacao)).to eq([%w[retorno_ao_corretor pulado retorno_sem_responsavel]])
  end
end
