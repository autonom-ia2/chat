require 'rails_helper'

# #2414 G55 com a G39 (#2681): no recorrente uma_vez a vez é a DATA, como a marca de cada card (marca_do_recorrente).
# A vez que a varredura abre é a mesma em que as execuções dos cards chegam; mudar só a hora depois do disparo
# reaproveita a vez e não manda a campanha de novo.
RSpec.describe Autonomia::Automacao::CampanhaDaOcorrencia, :automacao_motor do
  include ActiveJob::TestHelper

  around { |example| with_modified_env(CRM_KANBAN_ENABLED: 'true') { example.run } }

  let(:fuso) { ActiveSupport::TimeZone['America/Sao_Paulo'] }
  let(:canal) { create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false) }
  let(:account) { canal.account }
  let(:dona) { create(:user, account: account, role: :administrator) }
  let(:etiqueta) { create(:label, account: account, title: 'black') }
  let(:modelo) do
    { 'name' => 'black', 'language' => 'pt_BR', 'status' => 'APPROVED', 'category' => 'MARKETING',
      'components' => [{ 'type' => 'BODY', 'text' => 'A Black chegou. {{1}}' }] }
  end
  let(:disparar) do
    { 'id' => 'c1', 'tipo' => 'campanha', 'faz' => 'disparar', 'titulo' => 'Black', 'caixa_id' => canal.inbox.id,
      'modelo' => { 'nome' => 'black', 'idioma' => 'pt_BR', 'variaveis' => [['Só hoje.']] }, 'etiquetas' => [etiqueta.id] }
  end

  let(:definicao) { travel_to(fuso.local(2026, 11, 1)) { automacao_ligada(account, dona, [disparar], gatilho: gatilho) } }

  def gatilho(hora: 9)
    { 'tipo' => 'card.recorrente', 'frequencia' => 'uma_vez', 'data' => '2026-11-26', 'hora' => hora,
      'selecao' => { 'situacao' => 'perdido' } }
  end

  before do
    account.update!(reporting_timezone: fuso.name)
    ligar_motor(account)
    ligar_mensagens(account)
    account.enable_features!('whatsapp_campaign', 'automacao_gatilhos')
    canal.update!(message_templates: [modelo])
    funil, etapa = create_crm_pipeline(account: account, user: dona)
    create_list(:contact, 2, account: account).each do |contato|
      account.crm_cards.create!(pipeline: funil, stage: etapa, title: 'C', currency: 'BRL', contact: contato, status: :lost)
    end
  end

  after { Current.reset }

  # A varredura de verdade: o TempoJob, o job da automação (abre a vez e enfileira os lotes) e os lotes (as execuções).
  def varrer_em(momento)
    travel_to(momento) do
      Autonomia::Automacao::TempoJob.perform_now
      perform_enqueued_jobs(only: Autonomia::Automacao::TempoDaAutomacaoJob)
      perform_enqueued_jobs(only: Autonomia::Automacao::RecorrenteLoteJob)
    end
  end

  # O passo campanha na execução, com o registro e a conferência da vez, como no Executor.
  def chega(execucao)
    resultado = Autonomia::Automacao::PassoDeCampanha.new(execucao: execucao, passo: disparar, alvo: execucao.alvo).executar
    Autonomia::Automacao::Registro.create!(account: account, automacao: definicao, execucao: execucao, passo: 'c1',
                                           resultado: 'ok', motivo: resultado.motivo, dados: resultado.dados)
    described_class.conferir_execucao(execucao)
    resultado
  end

  def execucoes = Autonomia::Automacao::Execucao.where(automacao: definicao).order(:id)

  it 'a vez aberta pela varredura recebe as chegadas, e a campanha sai uma vez', :aggregate_failures do
    definicao
    varrer_em(fuso.local(2026, 11, 26, 9, 5))

    linha = Autonomia::Automacao::CampanhaDaVez.sole
    expect(linha.ocorrencia).to eq('recorrente:2026-11-26:card.recorrente')
    expect(linha.lotes_feitos).to eq([0])
    expect(execucoes.size).to eq(2)
    expect(execucoes.map { |execucao| described_class.vez_da(execucao) }.uniq).to eq([linha.ocorrencia])

    motivos = execucoes.map { |execucao| chega(execucao).motivo }

    expect(motivos).to eq(%w[campanha_da_vez_aguardando campanha_da_vez_aguardando])
    expect(Autonomia::Automacao::CampanhaDaVez.sole.id).to eq(linha.id)
    expect(linha.reload.fechada_em).to be_present
    expect(account.campaigns.count).to eq(1)
    expect(linha.campanha_display_id).to eq(account.campaigns.last.display_id)
  end

  it 'mudar só a hora depois do disparo reaproveita a vez: nem vez nova, nem execução, nem campanha', :aggregate_failures do
    definicao
    varrer_em(fuso.local(2026, 11, 26, 9, 5))
    execucoes.each { |execucao| chega(execucao) }
    linha = Autonomia::Automacao::CampanhaDaVez.sole

    travel_to(fuso.local(2026, 11, 26, 10)) do
      definicao.salvar_versao!(receita: { 'gatilho' => gatilho(hora: 15), 'passos' => [disparar] }, autor: dona)
    end
    varrer_em(fuso.local(2026, 11, 26, 15, 5))

    expect(Autonomia::Automacao::CampanhaDaVez.sole.id).to eq(linha.id)
    expect(execucoes.size).to eq(2)
    expect(account.campaigns.count).to eq(1)
  end

  # B6 do lote 3: a marca da janela no Redis é gravada antes de abrir a vez. Se abrir falhar, a marca sai e o erro sobe:
  # a rodada seguinte da janela abre a vez e enfileira os lotes, em vez de achar a marca e nunca rodar.
  it 'abrir a vez que falha apaga a marca da janela, e a rodada seguinte roda', :aggregate_failures do
    definicao
    allow(described_class).to receive(:abrir).and_raise(ActiveRecord::ConnectionTimeoutError, 'banco ocupado')
    travel_to(fuso.local(2026, 11, 26, 9, 5)) do
      Autonomia::Automacao::TempoJob.perform_now
      expect { perform_enqueued_jobs(only: Autonomia::Automacao::TempoDaAutomacaoJob) }.to raise_error(ActiveRecord::ConnectionTimeoutError)
    end
    expect(execucoes).to be_empty

    allow(described_class).to receive(:abrir).and_call_original
    varrer_em(fuso.local(2026, 11, 26, 9, 20))

    expect(Autonomia::Automacao::CampanhaDaVez.sole.lotes_feitos).to eq([0])
    expect(execucoes.size).to eq(2)
  end
end
