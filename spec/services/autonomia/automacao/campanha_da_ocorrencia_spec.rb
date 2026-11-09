require 'rails_helper'

# #2414 G55 (exemplo 16, passo 2): no card.recorrente, uma execução por card, e a campanha é da vez. Ela sai uma vez,
# quando todos os cards que a vez esperava chegaram ao passo campanha, saíram por outro caminho ou nem abriram execução;
# a vez que não fecha sai pela rede de segurança, com o registro de quantos ficaram de fora.
RSpec.describe Autonomia::Automacao::CampanhaDaOcorrencia, :automacao_motor do
  include ActiveJob::TestHelper

  around { |example| with_modified_env(CRM_KANBAN_ENABLED: 'true') { example.run } }

  let(:canal) { create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false) }
  let(:account) { canal.account }
  let(:dona) { create(:user, account: account, role: :administrator) }
  let(:etiqueta) { create(:label, account: account, title: 'reconquista') }
  let(:modelo) do
    { 'name' => 'vencendo', 'language' => 'pt_BR', 'status' => 'APPROVED', 'category' => 'MARKETING',
      'components' => [{ 'type' => 'BODY', 'text' => 'Seu seguro está vencendo. {{1}}' }] }
  end
  let(:disparar) do
    { 'id' => 'c1', 'tipo' => 'campanha', 'faz' => 'disparar', 'titulo' => 'Vencendo', 'caixa_id' => canal.inbox.id,
      'modelo' => { 'nome' => 'vencendo', 'idioma' => 'pt_BR', 'variaveis' => [['Consigo melhor.']] }, 'etiquetas' => [etiqueta.id] }
  end
  let(:gatilho) do
    { 'tipo' => 'card.recorrente', 'frequencia' => 'mensal', 'dia_do_mes' => 1, 'hora' => 9, 'selecao' => { 'situacao' => 'perdido' } }
  end
  let(:definicao) { automacao_ligada(account, dona, [disparar], gatilho: gatilho) }
  let(:vez) { Time.zone.parse('2026-11-01 12:00:00 UTC') }
  let(:cards) do
    funil, etapa = create_crm_pipeline(account: account, user: dona)
    create_list(:contact, 3, account: account).map do |contato|
      account.crm_cards.create!(pipeline: funil, stage: etapa, title: 'C', currency: 'BRL', contact: contato, status: :lost)
    end
  end
  let(:execucoes) do
    cards.map do |card|
      Autonomia::Automacao::Execucao.create!(automacao: definicao, account: account, versao: definicao.versao_ativa, alvo: card,
                                             chave_gatilho: 'card.recorrente',
                                             evento: Autonomia::Automacao::Gatilhos.marca_do_recorrente('card.recorrente', card.id, vez))
    end
  end

  before do
    ligar_motor(account)
    ligar_mensagens(account)
    account.enable_features!('whatsapp_campaign', 'automacao_gatilhos')
    canal.update!(message_templates: [modelo])
  end

  after { Current.reset }

  # A varredura: abre a vez e grava os esperados.
  def varredura(esperados = cards.size)
    linhas = described_class.abrir(definicao, vez)
    described_class.esperar(linhas, esperados)
    linhas.first.reload
  end

  # O passo campanha na execução, com o registro que o Executor grava depois dele.
  def chega(execucao)
    resultado = Autonomia::Automacao::PassoDeCampanha.new(execucao: execucao, passo: disparar, alvo: execucao.alvo).executar
    Autonomia::Automacao::Registro.create!(account: account, automacao: definicao, execucao: execucao, passo: 'c1',
                                           resultado: resultado.tipo == :ok ? 'ok' : 'pulado', motivo: resultado.motivo,
                                           dados: resultado.dados)
    resultado
  end

  def disparos = enqueued_jobs.count { |job| job[:job] == Campaigns::TriggerOneoffCampaignJob }

  it 'a vez com N cards sai uma vez, depois do N-ésimo', :aggregate_failures do
    varredura
    primeiros = execucoes.first(2).map { |execucao| chega(execucao) }

    expect(primeiros.map(&:motivo)).to eq(%w[campanha_da_vez_aguardando campanha_da_vez_aguardando])
    expect(account.campaigns).to be_empty

    ultimo = chega(execucoes.last)

    expect([ultimo.tipo, ultimo.motivo]).to eq([:ok, 'campanha_da_vez_saiu'])
    expect(account.campaigns.count).to eq(1)
    expect(account.campaigns.last).to have_attributes(sender: dona, audience: [{ 'type' => 'Label', 'id' => etiqueta.id }])
    expect(ultimo.dados).to include('campanha_id' => account.campaigns.last.display_id, 'esperados' => 3, 'chegaram' => 3, 'faltaram' => 0)
    expect(disparos).to eq(1)
  end

  it 'o card que para antes não segura a vez: a saída dele completa a conta, e o registro vai para a primeira', :aggregate_failures do
    varredura
    chega(execucoes[0])
    chega(execucoes[2])
    expect(account.campaigns).to be_empty

    described_class.saiu(execucoes[1]) # o "se" mandou o card 2 para outro caminho, e a execução fechou

    expect(account.campaigns.count).to eq(1)
    resumo = Autonomia::Automacao::Registro.where(execucao: execucoes[0], motivo: 'campanha_da_vez_saiu').sole
    expect(resumo.dados).to include('chegaram' => 2, 'sairam' => 1, 'faltaram' => 0)
    expect(disparos).to eq(1)
  end

  it 'quem chegou e depois fecha não conta como saída' do
    linha = varredura
    chega(execucoes[0])
    described_class.saiu(execucoes[0])

    expect(linha.reload).to have_attributes(chegadas: 1, saidas: 0, fechada_em: nil)
  end

  it 'os ids do lote que não abriram execução contam como fora da vez' do
    varredura(4)
    outro = create(:contact, account: account)
    execucoes.each { |execucao| chega(execucao) }
    expect(account.campaigns).to be_empty

    described_class.lote_feito(definicao, 'card.recorrente', vez, [*cards.map(&:id), outro.id])

    expect(account.campaigns.count).to eq(1)
  end

  it 'a vez travada sai pela rede de segurança, com quem chegou e quantos ficaram de fora', :aggregate_failures do
    linha = nil
    expect { linha = varredura }.to have_enqueued_job(Autonomia::Automacao::FecharVezJob).with(kind_of(Integer))
    expect(described_class::REDE).to eq(2.hours)
    chega(execucoes[0])

    travel_to(vez + described_class::REDE + 1.minute) { Autonomia::Automacao::FecharVezJob.perform_now(linha.id) }

    expect(account.campaigns.count).to eq(1)
    resumo = Autonomia::Automacao::Registro.where(execucao: execucoes[0], motivo: 'campanha_da_vez_saiu_pela_rede').sole
    expect(resumo.dados).to include('esperados' => 3, 'chegaram' => 1, 'faltaram' => 2, 'horas' => 2)
    historico = Autonomia::Automacao::Historico.new(automacao: definicao, usuario: dona)
    texto = I18n.with_locale(:pt_BR) { historico.send(:passo, resumo, visivel: true)[:motivo] }
    expect(texto).to include('2 ficaram de fora')
    expect(disparos).to eq(1)
  end

  it 'o card que chega depois de a vez sair pula, sem outra campanha', :aggregate_failures do
    linha = varredura
    chega(execucoes[0])
    described_class.fechar_pela_rede(linha.id)

    tarde = chega(execucoes[1])

    expect([tarde.tipo, tarde.motivo]).to eq([:pulado, 'campanha_da_vez_ja_saiu'])
    expect(tarde.dados['campanha_id']).to eq(account.campaigns.last.display_id)
    expect(account.campaigns.count).to eq(1)
  end

  it 'a rede numa vez já fechada não faz nada' do
    linha = varredura
    execucoes.each { |execucao| chega(execucao) }

    expect { described_class.fechar_pela_rede(linha.id) }.not_to(change { account.campaigns.count })
  end
end
