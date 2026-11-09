require 'rails_helper'

# Fechamento do épico #2414, lacuna G55 (exemplo 16, "Reconquistar quem foi para o concorrente", passo 2): "Todo dia 1º
# do mês, para cada card perdido há 11 meses" põe a etiqueta "reconquista" no contato e "monta a campanha com o modelo
# aprovado 'Seu seguro está vencendo' para todos com essa etiqueta". É a prova que a sonda da G55 lê.
#
# O card.recorrente abre uma execução por card. A campanha é da vez, não do card: uma só, para todos com a etiqueta,
# saindo quando o último card da vez passa pelo passo (CampanhaDaOcorrencia). Montado e ligado pela API da tela, como a
# corretora faria; o que sai para o cliente para no receptor de teste (F9.7).
#
# Fica de fora daqui: o "Só se" do motivo da perda (`card.motivo_da_perda`, G18, no #2675) e os passos 3 a 8 (G38 e os
# outros do exemplo, em pendentes_spec.rb).
RSpec.describe 'Fechamento #2414 · G55: a campanha da vez num gatilho de card', :fechamento_automacao, type: :request do
  include ActiveJob::TestHelper

  around { |exemplo| with_modified_env(CRM_KANBAN_ENABLED: 'true') { exemplo.run } }

  let(:fuso) { ActiveSupport::TimeZone['America/Sao_Paulo'] }
  let(:canal) { create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false) }
  let(:account) { canal.account }
  let(:juliana) { create(:user, account: account, role: :administrator, name: 'Juliana Corretora') }
  let(:funil) { account.crm_pipelines.create!(name: 'Comercial', created_by: juliana, status: :active) }
  let(:etapa) { account.crm_pipeline_stages.create!(pipeline: funil, name: 'Proposta', position: 0) }
  let!(:reconquista) { create(:label, account: account, title: 'reconquista') }
  let(:vencendo) do
    { 'name' => 'seguro_vencendo', 'language' => 'pt_BR', 'status' => 'APPROVED', 'category' => 'MARKETING',
      'components' => [{ 'type' => 'BODY', 'text' => 'Seu seguro está vencendo. {{1}}' }] }
  end
  let(:dia_primeiro) { fuso.local(2026, 11, 1, 9) }

  def receita
    { gatilho: { tipo: 'card.recorrente', frequencia: 'mensal', dia_do_mes: 1, hora: 9,
                 selecao: { funil_id: funil.id, situacao: 'perdido', fechado_entre_dias: { de: 330, ate: 345 } } },
      passos: [
        { id: 'etiqueta', tipo: 'acao', acao: 'PATCH contacts/:contact_id/labels/alterar', descricao: 'Pôr a etiqueta reconquista',
          caminho: { contact_id: { '$valor' => 'contato.id' } }, corpo: { por: ['reconquista'] } },
        { id: 'campanha', tipo: 'campanha', faz: 'disparar', titulo: 'Seu seguro está vencendo', caixa_id: canal.inbox.id,
          modelo: { nome: 'seguro_vencendo', idioma: 'pt_BR', variaveis: [['Este ano consigo melhor.']] },
          etiquetas: [reconquista.id] }
      ] }
  end

  def perdido(nome, telefone, dias)
    contato = create(:contact, account: account, name: nome, phone_number: telefone)
    account.crm_cards.create!(pipeline: funil, stage: etapa, title: "Seguro de #{nome}", currency: 'BRL', contact: contato, status: :lost)
           .tap { |card| card.update_columns(closed_at: dia_primeiro - dias.days) } # rubocop:disable Rails/SkipsModelValidations
    contato
  end

  # A varredura do dia 1º: o TempoJob, o job da automação, os lotes e cada execução, um job por vez.
  def chega_o_dia_primeiro
    travel_to(dia_primeiro + 5.minutes) do
      Autonomia::Automacao::TempoJob.perform_now
      perform_enqueued_jobs(only: Autonomia::Automacao::TempoDaAutomacaoJob)
      perform_enqueued_jobs(only: Autonomia::Automacao::RecorrenteLoteJob)
      rodar_jobs
    end
  end

  before do
    account.update!(locale: 'pt_BR', reporting_timezone: fuso.name)
    flags_do_piloto(account)
    account.enable_features!('automacao_gatilhos', 'whatsapp_campaign')
    canal.update!(message_templates: [vencendo])
    receptor_whatsapp_cloud
    # A trava do disparo pergunta à Meta o estado do modelo na hora (#1329): a Meta de teste responde aprovado.
    stub_request(:get, ->(uri) { uri.host == 'graph.facebook.com' && uri.path.end_with?('/message_templates') })
      .to_return(status: 200, body: { data: [vencendo.merge('id' => '9016')] }.to_json, headers: { 'Content-Type' => 'application/json' })
  end

  after { Current.reset }

  it 'cada card perdido ganha a etiqueta, e uma campanha só sai para todos com ela', :aggregate_failures do
    ana = perdido('Ana', '+5511900001601', 335)
    bruno = perdido('Bruno', '+5511900001602', 340)
    perdido('Caio', '+5511900001603', 20) # perdido há 20 dias: fora da seleção
    # Quem já tinha a etiqueta de outra vez também está em "todos com essa etiqueta".
    create(:contact, account: account, name: 'Duda', phone_number: '+5511900001604').update!(label_list: ['reconquista'])
    travel_to(fuso.local(2026, 10, 15, 10)) do
      automacao = montar_automacao(juliana, account, nome: 'Reconquista', receita: receita)
      ligar_automacao(juliana, account, automacao)
    end

    chega_o_dia_primeiro

    expect([ana, bruno].map { |contato| contato.reload.label_list }).to all(eq(['reconquista']))
    expect(account.campaigns.count).to eq(1)
    campanha = account.campaigns.last
    expect(campanha).to have_attributes(title: 'Seu seguro está vencendo', sender: juliana,
                                        audience: [{ 'type' => 'Label', 'id' => reconquista.id }])
    # O primeiro card entra e espera a vez; o segundo, o último da vez, a fecha e a campanha sai.
    registros = Autonomia::Automacao::Registro.where(passo: 'campanha').order(:id).pluck(:resultado, :motivo)
    expect(registros).to eq([%w[ok campanha_da_vez_aguardando], %w[ok campanha_da_vez_saiu]])

    travel_to(dia_primeiro + 6.minutes) { perform_enqueued_jobs(only: Campaigns::TriggerOneoffCampaignJob) }

    expect(campanha.reload.campaign_status).to eq('completed')
    enviados = chamadas_para('graph.facebook.com').map(&:corpo)
    expect(enviados.pluck('to')).to contain_exactly('+5511900001601', '+5511900001602', '+5511900001604')
    expect(enviados.map { |corpo| corpo.dig('template', 'name') }.uniq).to eq(['seguro_vencendo'])
  end
end
