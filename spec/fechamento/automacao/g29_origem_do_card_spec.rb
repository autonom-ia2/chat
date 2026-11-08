require 'rails_helper'

# Fechamento do épico #2414 (#2702), lacuna G29: a origem do card como valor da receita. Provado no início e no passo 1
# do exemplo 2 ("Começa: card criado pelo formulário de um anúncio. 1. Põe no contato a etiqueta com o nome do
# anúncio"): o dono monta e liga pela API da tela, o lead chega pelo importador de verdade (o mesmo do webhook da Meta),
# o card criado sai pelo emissor do CRM e o motor põe a etiqueta. O exemplo 2 inteiro fica no pendentes_spec até as
# lacunas G30, G31 e G32 fecharem.
RSpec.describe 'Fechamento #2414 · G29: a origem do card na receita', :automacao_motor, :fechamento_automacao, type: :request do
  include ActiveJob::TestHelper

  around { |exemplo| with_modified_env(CRM_KANBAN_ENABLED: 'true') { exemplo.run } }

  let(:account) { create(:account, locale: 'pt_BR') }
  let(:dono) { create(:user, account: account, role: :administrator, name: 'Paula Imobiliária') }
  let(:funil) { create_crm_pipeline(account: account, user: dono).first }
  let(:importador) do
    Crm::MetaAds::LeadForms::Importer.new(account: account, pipeline: funil, stage: funil.stages.first, form_name: 'Quero visitar')
  end

  let(:etiqueta_do_anuncio) do
    { id: 'etiqueta_do_anuncio', tipo: 'acao', acao: 'PATCH contacts/:contact_id/labels/alterar', descricao: 'Pôr o nome do anúncio',
      caminho: { contact_id: { '$valor' => 'contato.id' } }, corpo: { por: [{ '$valor' => 'card.anuncio' }] } }
  end

  before do
    flags_do_piloto(account)
    account.enable_features!('automacao_gatilhos')
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

  def ligada(*passos)
    receita = { gatilho: { tipo: 'card.criado', funil_id: funil.id,
                           filtros: [{ campo: { '$valor' => 'card.origem' }, op: 'igual', valor: 'formulario_do_anuncio' }] },
                passos: passos }
    automacao = montar_automacao(dono, account, nome: 'Lead do anúncio', receita: receita)
    ligar_automacao(dono, account, automacao)
    automacao
  end

  def chega_o_lead(id: 'L1', anuncio: 'Apartamento Jardins')
    importador.import('id' => id, 'created_time' => '2026-11-07T12:00:00+0000', 'form_id' => '9001', 'ad_id' => '120001',
                      'ad_name' => anuncio, 'field_data' => [{ 'name' => 'full_name', 'values' => ['Marcos Lima'] },
                                                             { 'name' => 'phone_number', 'values' => ['+5511987650002'] }])
    drenar
    account.crm_cards.find_by!(source: Crm::MetaAds::LeadForms::Importer::SOURCE)
  end

  it 'card do formulário do anúncio: o contato ganha a etiqueta com o nome do anúncio', :aggregate_failures do
    automacao = ligada(etiqueta_do_anuncio)

    card = chega_o_lead

    expect(historico_de(automacao)).to eq([['etiqueta_do_anuncio', 'ok', nil]])
    # A etiqueta sai em minúsculas, como toda etiqueta da plataforma.
    expect(card.contact.reload.label_list).to eq(['apartamento jardins'])
  end

  it 'card que veio de outro caminho: o filtro da origem barra e nada roda', :aggregate_failures do
    automacao = ligada(etiqueta_do_anuncio)

    Crm::Cards::Creator.new(account: account, user: dono,
                            params: { pipeline_id: funil.id, stage_id: funil.stages.first.id, title: 'Cliente da vitrine' }).perform
    drenar

    expect(historico_de(automacao)).to be_empty
  end
end
