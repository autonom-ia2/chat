require 'rails_helper'

# Fechamento do épico #2414 (F9.6), exemplo 6 dos termos de aceite ("Aniversário que vira horário marcado"), só a parte
# da data dos passos 5 e 10 (#2705). O exemplo inteiro segue pendente pelas outras lacunas (pendentes_spec.rb).
#
# - Passo 5, "não pode: estende o presente e grava a nova data no card": a cliente que não pode agora ganha o presente
#   até o fim do mês que vem. A automação grava no card a data calculada (G16) hoje + 1 mês, no fim do mês.
# - Passo 10, "fim do mês sem marcar": no dia gravado, o gatilho de data do card (G6) dispara.
#
# Montado como a dona montaria, pela API da tela, no fuso da conta; o relógio anda até o dia e a varredura dispara.
RSpec.describe 'Fechamento #2414 · exemplo 6: o presente vale até o fim do mês', :fechamento_automacao, type: :request do
  include ActiveJob::TestHelper

  around { |exemplo| with_modified_env(CRM_KANBAN_ENABLED: 'true') { exemplo.run } }

  let(:fuso) { ActiveSupport::TimeZone['America/Sao_Paulo'] }
  let(:canal) { create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false) }
  let(:account) { canal.account }
  let(:jessica) { create(:user, account: account, role: :administrator, name: 'Jéssica Dona') }
  let(:cliente) { create(:contact, account: account, name: 'Bia', phone_number: '+5511900000006') }
  let(:contact_inbox) { create(:contact_inbox, inbox: canal.inbox, contact: cliente, source_id: '5511900000006') }
  let(:conversa) { create(:conversation, account: account, inbox: canal.inbox, contact: cliente, contact_inbox: contact_inbox) }
  let(:funil) { account.crm_pipelines.create!(name: 'Aniversário', created_by: jessica, status: :active) }
  let(:presente) { account.crm_pipeline_stages.create!(pipeline: funil, name: 'Presente oferecido', position: 0) }
  let(:nao_pode) { account.crm_pipeline_stages.create!(pipeline: funil, name: 'Não pode agora', position: 1) }
  let(:card) do
    account.crm_cards.create!(pipeline: funil, stage: presente, title: 'Aniversário da Bia', currency: 'BRL', contact: cliente,
                              primary_conversation: conversa)
  end

  def estende_o_presente
    { gatilho: { tipo: 'card.entrou_na_etapa', etapa_id: nao_pode.id }, passos: [
      { id: 'nova_data', tipo: 'acao', acao: 'PATCH crm/cards/:id', descricao: 'Estender o presente até o fim do mês que vem',
        caminho: { id: { '$valor' => 'card.id' } },
        corpo: { card: { custom_attributes: { presente_ate: {
          '$data' => { de: 'hoje', mais: { valor: 1, unidade: 'meses' }, fim_do: 'mes' }
        } } } } }
    ] }
  end

  def fim_do_presente
    { gatilho: { tipo: 'card.data', campo: 'presente_ate', dias: 0, quando: 'antes', hora: 9 }, passos: [
      { id: 'saudade', tipo: 'acao', acao: 'PATCH conversations/:conversation_id/labels/alterar', descricao: 'Pôr a etiqueta saudade',
        caminho: { conversation_id: { '$valor' => 'conversa.id' } }, corpo: { por: ['saudade'] } }
    ] }
  end

  def historico(nome)
    definicao = Autonomia::Automacao::Definicao.find_by!(account: account, nome: "Aniversário: #{nome}")
    Autonomia::Automacao::Registro.where(automacao_id: definicao.id).order(:id).pluck(:passo, :resultado)
  end

  def mover_para_nao_pode
    travel_to(fuso.parse('2026-11-20 22:30')) do # 01h30 do dia 21 em UTC: no fuso da conta ainda é novembro
      Crm::Cards::Mover.new(card: card, actor: jessica, target_stage: nao_pode).perform
      rodar_jobs
      perform_enqueued_jobs(only: Autonomia::Automacao::EventoDoCardJob)
      rodar_jobs
    end
  end

  def chega_o_dia(dia)
    travel_to(fuso.parse("#{dia} 09:30")) do
      Autonomia::Automacao::TempoJob.perform_now
      perform_enqueued_jobs(only: Autonomia::Automacao::TempoDaAutomacaoJob)
      rodar_jobs
    end
  end

  before do
    account.update!(locale: 'pt_BR', reporting_timezone: fuso.name, custom_attributes: { 'timezone' => fuso.name })
    flags_do_piloto(account)
    account.enable_features!('automacao_gatilhos')
    create(:custom_attribute_definition, account: account, attribute_key: 'presente_ate', attribute_display_name: 'Presente até',
                                         attribute_model: 'card_attribute', attribute_display_type: 'date')
    create(:label, account: account, title: 'saudade', description: 'Campanha Saudade')
    travel_to(fuso.parse('2026-11-01 10:00')) do
      card
      { estende: estende_o_presente, fim: fim_do_presente }.each do |nome, receita|
        ligar_automacao(jessica, account, montar_automacao(jessica, account, nome: "Aniversário: #{nome}", receita: receita))
      end
      clear_enqueued_jobs
    end
  end

  after { Current.reset }

  it 'passo 5: "não pode agora" grava no card o fim do mês que vem, contado no fuso da conta', :aggregate_failures do
    mover_para_nao_pode

    expect(card.reload.custom_attributes).to include('presente_ate' => '2026-12-31')
    expect(historico(:estende)).to eq([%w[nova_data ok]])
  end

  it 'passo 10: no último dia do mês gravado, o gatilho de data do card dispara; antes dele, não', :aggregate_failures do
    mover_para_nao_pode

    chega_o_dia('2026-12-30')
    expect(historico(:fim)).to be_empty

    chega_o_dia('2026-12-31')
    expect(historico(:fim)).to eq([%w[saudade ok]])
    expect(conversa.reload.label_list).to include('saudade')
  end
end
