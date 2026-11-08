require 'rails_helper'

# Fechamento do épico #2414 (#2570), lacuna G29 (#2702): de onde o card veio e o anúncio do formulário, como valores da
# receita. Provado no começo e no passo 1 do exemplo 2 ("Lead do anúncio atendido em 5 minutos"): o lead chega pelo
# importador de verdade do formulário da Meta, o card nasce e sai pelo emissor do CRM, o filtro "veio de um formulário de
# anúncio" deixa passar e o contato ganha a etiqueta com o nome do anúncio. O card que nasce de uma conversa não passa.
# O exemplo 2 inteiro fica no pendentes_spec até as outras lacunas dele fecharem.
RSpec.describe 'Fechamento #2414 · G29: origem do card e anúncio do formulário', :automacao_motor, :fechamento_automacao,
               type: :request do
  include ActiveJob::TestHelper

  around { |exemplo| with_modified_env(CRM_KANBAN_ENABLED: 'true') { exemplo.run } }

  let(:account) { create(:account, locale: 'pt_BR') }
  let(:marina) { create(:user, account: account, role: :administrator, name: 'Marina Imóveis') }
  let(:funil_e_etapa) { create_crm_pipeline(account: account, user: marina) }
  let(:funil) { funil_e_etapa.first }
  let(:etapa) { funil_e_etapa.last }

  let(:receita) do
    {
      gatilho: { tipo: 'card.criado', funil_id: funil.id,
                 filtros: [{ campo: { '$valor' => 'card.origem' }, op: 'igual', valor: 'formulario_de_anuncio' }] },
      passos: [{ id: 'etiqueta', tipo: 'acao', acao: 'PATCH contacts/:contact_id/labels/alterar', descricao: 'Pôr o nome do anúncio',
                 caminho: { contact_id: { '$valor' => 'contato.id' } }, corpo: { por: [{ '$valor' => 'card.anuncio' }] } }]
    }
  end

  before do
    flags_do_piloto(account)
    account.enable_features!('automacao_gatilhos')
    funil_e_etapa
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

  def ligada
    automacao = montar_automacao(marina, account, nome: 'Lead do anúncio atendido em 5 minutos', receita: receita)
    ligar_automacao(marina, account, automacao)
    automacao
  end

  # O lead como a Graph da Meta o entrega ao webhook e ao "trazer os antigos".
  def lead_do_formulario
    { 'id' => 'L2702', 'created_time' => '2026-11-08T12:00:00+0000', 'form_id' => '9001', 'ad_id' => '77',
      'ad_name' => 'Apartamento Jardim', 'campaign_name' => 'Lançamento',
      'field_data' => [{ 'name' => 'full_name', 'values' => ['Ana Souza'] }, { 'name' => 'phone_number', 'values' => ['+5511987652702'] }] }
  end

  it 'lead do formulário: a automação passa no filtro e põe no contato a etiqueta com o nome do anúncio', :aggregate_failures do
    automacao = ligada

    resultado = Crm::MetaAds::LeadForms::Importer.new(account: account, pipeline: funil, stage: etapa, form_name: 'Quero visitar')
                                                 .import(lead_do_formulario)
    drenar

    card = account.crm_cards.sole
    expect(resultado).to eq(:created)
    expect(historico_de(automacao)).to eq([['etiqueta', 'ok', nil]])
    expect(card.contact.reload.label_list).to eq(['apartamento jardim'])
  end

  def controle_passo
    { id: 'novo', tipo: 'acao', acao: 'PATCH contacts/:contact_id/labels/alterar', descricao: 'Pôr novo',
      caminho: { contact_id: { '$valor' => 'contato.id' } }, corpo: { por: ['novo'] } }
  end

  # A de controle, sem filtro, prova que o card criado chegou ao motor: só o filtro barrou a outra.
  it 'card que nasce de uma conversa não passa no filtro', :aggregate_failures do
    automacao = ligada
    controle = montar_automacao(marina, account, nome: 'Todo card novo',
                                                 receita: { gatilho: { tipo: 'card.criado', funil_id: funil.id }, passos: [controle_passo] })
    ligar_automacao(marina, account, controle)
    contato = account.contacts.create!(name: 'Bruno', phone_number: '+5511987652703')
    inbox = create_crm_whatsapp_api_inbox(account: account, members: [marina])
    conversa = create_crm_conversation(account: account, inbox: inbox, contact: contato)

    Crm::Cards::Creator.new(account: account, user: marina,
                            params: { pipeline_id: funil.id, stage_id: etapa.id, title: 'Conversa', currency: 'BRL',
                                      conversation_id: conversa.id }).perform
    drenar

    expect(historico_de(automacao)).to be_empty
    expect(historico_de(controle)).to eq([['novo', 'ok', nil]])
    expect(contato.reload.label_list).to eq(['novo'])
  end
end
