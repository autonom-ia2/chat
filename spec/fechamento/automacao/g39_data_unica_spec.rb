require 'rails_helper'

# Fechamento do épico #2414, lacuna G39 (#2753): o gatilho que roda uma vez, numa data. Exemplo 7 dos termos de aceite
# ("Black Friday para os clientes antigos primeiro"), passo 1: "Quinta-feira antes da Black Friday, às 9h, monta a
# campanha de WhatsApp para quem tem a etiqueta 'já comprou' e manda o modelo aprovado 'Pré-Black'".
#
# Montado e ligado pela API da tela, como a dona montaria, no fuso da conta; o relógio anda até a data e a varredura do
# motor dispara. O que sai para o cliente para no receptor de teste (F9.7). Só o passo 1: o "todos os outros" (G37) e a
# resposta à campanha (G38) seguem pendentes, e o exemplo 7 inteiro fica no pendentes_spec.rb até os três estarem na main.
RSpec.describe 'Fechamento #2414 · G39: campanha numa data única', :fechamento_automacao, type: :request do
  include ActiveJob::TestHelper

  around { |exemplo| with_modified_env(CRM_KANBAN_ENABLED: 'true') { exemplo.run } }

  let(:fuso) { ActiveSupport::TimeZone['America/Sao_Paulo'] }
  let(:canal) { create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false) }
  let(:account) { canal.account }
  let(:inbox) { canal.inbox }
  let(:vanessa) { create(:user, account: account, role: :administrator, name: 'Vanessa Dona') }
  let!(:ja_comprou) { create(:label, account: account, title: 'ja_comprou', description: 'Já comprou com a loja') }
  let(:pre_black) do
    { 'name' => 'pre_black', 'language' => 'pt_BR', 'status' => 'APPROVED', 'category' => 'MARKETING',
      'components' => [{ 'type' => 'BODY', 'text' => 'Oi! A Black começa {{1}}.' }] }
  end
  let(:receita) do
    { gatilho: { tipo: 'conta.recorrente', frequencia: 'uma_vez', data: '2026-11-26', hora: 9 }, passos: [
      { id: 'pre_black', tipo: 'campanha', faz: 'disparar', titulo: 'Pré-Black', caixa_id: inbox.id,
        modelo: { nome: 'pre_black', idioma: 'pt_BR', variaveis: [['amanhã']] }, etiquetas: [ja_comprou.id] }
    ] }
  end

  def cliente(nome, telefone, etiquetas: [])
    create(:contact, account: account, name: nome, phone_number: telefone).tap { |contato| contato.update!(label_list: etiquetas) }
  end

  def varrer_em(momento)
    travel_to(momento) do
      Autonomia::Automacao::TempoJob.perform_now
      perform_enqueued_jobs(only: Autonomia::Automacao::TempoDaAutomacaoJob)
      perform_enqueued_jobs(only: Autonomia::Automacao::RecorrenteLoteJob)
      rodar_jobs
      perform_enqueued_jobs(only: Campaigns::TriggerOneoffCampaignJob)
    end
  end

  def enviados = chamadas_para('graph.facebook.com').map(&:corpo)

  before do
    account.update!(locale: 'pt_BR', reporting_timezone: fuso.name, custom_attributes: { 'timezone' => fuso.name })
    flags_do_piloto(account)
    account.enable_features!('automacao_gatilhos', 'whatsapp_campaign')
    canal.update!(message_templates: [pre_black])
    receptor_whatsapp_cloud
    # A trava do disparo pergunta à Meta o estado do modelo na hora (#1329): a Meta de teste responde aprovado.
    stub_request(:get, ->(uri) { uri.host == 'graph.facebook.com' && uri.path.end_with?('/message_templates') })
      .to_return(status: 200, body: { data: [pre_black.merge('id' => '9001')] }.to_json, headers: { 'Content-Type' => 'application/json' })
    cliente('Bia', '+5511900000031', etiquetas: ['ja_comprou'])
    cliente('Duda', '+5511900000032')
    travel_to(fuso.parse('2026-11-01 10:00')) do
      ligar_automacao(vanessa, account, montar_automacao(vanessa, account, nome: 'Pré-Black', receita: receita))
      clear_enqueued_jobs
    end
  end

  after { Current.reset }

  it 'na quinta às 9h a campanha sai, com o modelo, só para quem tem a etiqueta; antes, nada; e não repete', :aggregate_failures do
    varrer_em(fuso.parse('2026-11-25 09:05')) # véspera
    varrer_em(fuso.parse('2026-11-26 08:50')) # o dia, antes da hora
    expect(enviados).to be_empty
    expect(account.campaigns.count).to eq(0)

    varrer_em(fuso.parse('2026-11-26 09:05'))
    expect(account.campaigns.sole).to have_attributes(title: 'Pré-Black', campaign_status: 'completed')
    expect(enviados.pluck('to')).to eq(['+5511900000031'])
    expect(enviados.first['template']).to include('name' => 'pre_black')
    expect(enviados.first.dig('template', 'components', 0, 'parameters', 0, 'text')).to eq('amanhã')

    varrer_em(fuso.parse('2026-11-26 09:20'))
    varrer_em(fuso.parse('2026-11-27 09:05'))
    expect(account.campaigns.count).to eq(1)
    expect(enviados.size).to eq(1)
  end
end
