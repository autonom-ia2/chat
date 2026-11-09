require 'rails_helper'

# #2414 G55 (exemplo 16, passo 2): no card.recorrente, uma execução por card, e a campanha é da vez. Ela sai uma vez,
# quando a vez fecha pelo estado do banco: os lotes rodaram e nenhuma execução da vez está aberta antes do passo. Nada
# sai com a automação desligada ou o motor desligado; a rede de segurança só tira da conta quem está travado.
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

  # A varredura de um lote só, que rodou. O lote abre as execuções antes de marcar que rodou, como no RecorrenteLoteJob.
  def varredura(lotes: 1, rodaram: [0])
    execucoes
    linhas = described_class.abrir(definicao, vez)
    described_class.lotes(linhas, lotes)
    rodaram.each { |indice| described_class.lote_feito(definicao, 'card.recorrente', vez, indice) }
    linhas.first.reload
  end

  # O passo campanha na execução, sem o registro (o que o Executor faz antes de gravar).
  def passo_em(execucao) = Autonomia::Automacao::PassoDeCampanha.new(execucao: execucao, passo: disparar, alvo: execucao.alvo).executar

  # O passo inteiro, como no Executor: o passo, o registro e a conferência da vez.
  def chega(execucao)
    resultado = passo_em(execucao)
    Autonomia::Automacao::Registro.create!(account: account, automacao: definicao, execucao: execucao, passo: 'c1',
                                           resultado: resultado.tipo == :ok ? 'ok' : 'pulado', motivo: resultado.motivo,
                                           dados: resultado.dados)
    described_class.conferir_execucao(execucao)
    resultado
  end

  # A execução fecha por outro caminho (o "se", parar, erro), como no Executor#finalizar.
  def termina(execucao)
    execucao.update_columns(estado: 'concluida', travada_em: nil, due_at: nil, finalizada_em: Time.current) # rubocop:disable Rails/SkipsModelValidations
    described_class.conferir_execucao(execucao)
  end

  def disparos = enqueued_jobs.count { |job| job[:job] == Campaigns::TriggerOneoffCampaignJob }

  def registro_da_vez(motivo) = Autonomia::Automacao::Registro.where(execucao: execucoes[0], motivo: motivo).sole

  def rede_passa(linha)
    travel_to(Time.current + described_class::REDE + 1.minute) { Autonomia::Automacao::FecharVezJob.perform_now(linha.id) }
  end

  # A conferência marcada da vez, na hora dela.
  def na_hora_marcada(linha)
    travel_to(linha.reload.conferir_em + 1.second) { Autonomia::Automacao::FecharVezJob.perform_now(linha.id) }
  end

  def fecha_vez_na_fila = enqueued_jobs.count { |job| job[:job] == Autonomia::Automacao::FecharVezJob }

  def falhar_ao_montar
    allow_any_instance_of(Autonomia::Automacao::PassoDeCampanha).to receive(:montar) # rubocop:disable RSpec/AnyInstance
      .and_raise(ActiveRecord::ConnectionTimeoutError, 'banco ocupado')
  end

  it 'a vez com N cards sai uma vez, depois do N-ésimo', :aggregate_failures do
    expect { varredura }.to have_enqueued_job(Autonomia::Automacao::FecharVezJob)
    primeiros = execucoes.first(2).map { |execucao| chega(execucao) }

    expect(primeiros.map(&:motivo)).to eq(%w[campanha_da_vez_aguardando campanha_da_vez_aguardando])
    expect(account.campaigns).to be_empty

    chega(execucoes.last)

    expect(account.campaigns.count).to eq(1)
    expect(account.campaigns.last).to have_attributes(sender: dona, audience: [{ 'type' => 'Label', 'id' => etiqueta.id }])
    expect(registro_da_vez('campanha_da_vez_saiu').dados).to include('campanha_id' => account.campaigns.last.display_id, 'chegaram' => 3)
    expect(disparos).to eq(1)
  end

  it 'o card que termina antes não segura a vez', :aggregate_failures do
    varredura
    chega(execucoes[0])
    chega(execucoes[2])
    expect(account.campaigns).to be_empty

    termina(execucoes[1])

    expect(account.campaigns.count).to eq(1)
    expect(registro_da_vez('campanha_da_vez_saiu').dados).to include('chegaram' => 2, 'sairam' => 1)
    expect(disparos).to eq(1)
  end

  it 'desligar no meio da vez: nada sai, e o registro diz por quê', :aggregate_failures do
    linha = varredura
    chega(execucoes[0])

    definicao.desligar!

    expect(account.campaigns).to be_empty
    expect(linha.reload.fechada_em).to be_present
    expect(registro_da_vez('campanha_da_vez_nao_saiu').dados).to include('por' => 'desligada')
    expect(disparos).to eq(0)
  end

  it 'motor desligado: nada sai', :aggregate_failures do
    varredura
    execucoes.first(2).each { |execucao| chega(execucao) }
    account.disable_features!('automacao_motor')

    chega(execucoes.last)

    expect(account.campaigns).to be_empty
    expect(registro_da_vez('campanha_da_vez_nao_saiu').dados).to include('por' => 'motor_desligado')
  end

  it 'quem espera antes da campanha segura a vez, mesmo na rede', :aggregate_failures do
    linha = varredura
    execucoes.first(2).each { |execucao| chega(execucao) }
    execucoes.last.update_columns(estado: 'esperando', due_at: 3.days.from_now, updated_at: 1.day.ago) # rubocop:disable Rails/SkipsModelValidations

    expect { rede_passa(linha) }.to have_enqueued_job(Autonomia::Automacao::FecharVezJob).with(linha.id)

    expect(account.campaigns).to be_empty
    expect(linha.reload.fechada_em).to be_nil
  end

  it 'a execução travada sai da conta pela rede, com o registro de quem ficou de fora', :aggregate_failures do
    linha = varredura
    execucoes.first(2).each { |execucao| chega(execucao) }
    execucoes.last.update_columns(estado: 'andando', due_at: nil, updated_at: 3.hours.ago) # rubocop:disable Rails/SkipsModelValidations
    described_class.conferir(linha.id)
    expect(account.campaigns).to be_empty

    rede_passa(linha)

    expect(account.campaigns.count).to eq(1)
    resumo = registro_da_vez('campanha_da_vez_saiu_pela_rede')
    expect(resumo.dados).to include('chegaram' => 2, 'fora' => 1, 'lotes_fora' => 0, 'horas' => 2)
    historico = Autonomia::Automacao::Historico.new(automacao: definicao, usuario: dona)
    texto = I18n.with_locale(:pt_BR) { historico.send(:passo, resumo, visivel: true)[:motivo] }
    expect(texto).to include('1 ficaram de fora por estarem travados')
  end

  it 'o lote repetido não fecha a vez antes do outro lote rodar', :aggregate_failures do
    linha = varredura(lotes: 2, rodaram: [0, 0])
    execucoes.each { |execucao| chega(execucao) }

    expect(account.campaigns).to be_empty
    expect(linha.reload.fechada_em).to be_nil

    described_class.lote_feito(definicao, 'card.recorrente', vez, 1)

    expect(account.campaigns.count).to eq(1)
  end

  it 'a execução que morreu entre o passo e o registro segura a vez' do
    varredura
    passo_em(execucoes.last) # chegou, mas o registro não foi gravado
    execucoes.first(2).each { |execucao| chega(execucao) }

    expect(account.campaigns).to be_empty
  end

  it 'o disparo que falha deixa a vez aberta, registra o erro e tenta de novo', :aggregate_failures do
    linha = varredura
    falhar = true
    allow_any_instance_of(Autonomia::Automacao::PassoDeCampanha).to receive(:montar).and_wrap_original do |original| # rubocop:disable RSpec/AnyInstance
      raise ActiveRecord::ConnectionTimeoutError, 'banco ocupado' if falhar

      original.call
    end

    expect { execucoes.each { |execucao| chega(execucao) } }.to have_enqueued_job(Autonomia::Automacao::FecharVezJob).with(linha.id)
    expect(account.campaigns).to be_empty
    expect(linha.reload.fechada_em).to be_nil
    expect(registro_da_vez('campanha_da_vez_falhou').dados).to include('erro' => 'ActiveRecord::ConnectionTimeoutError')

    falhar = false
    Autonomia::Automacao::FecharVezJob.perform_now(linha.id) # antes da hora marcada: nada
    expect(account.campaigns).to be_empty

    na_hora_marcada(linha)

    expect(account.campaigns.count).to eq(1)
    expect(linha.reload.campanha_display_id).to eq(account.campaigns.last.display_id)
  end

  it 'sem chegada nenhuma, a vez fecha sem mandar, com o motivo no registro da primeira execução', :aggregate_failures do
    linha = varredura
    execucoes.each { |execucao| termina(execucao) }

    expect(account.campaigns).to be_empty
    expect(linha.reload.fechada_em).to be_present
    expect(registro_da_vez('campanha_da_vez_nao_saiu').dados).to include('por' => 'sem_chegada', 'chegaram' => 0, 'sairam' => 3)
    expect(linha.conferir_em).to be_nil
  end

  it 'o erro que se repete: uma tentativa por vez marcada, até TENTATIVAS, e a vez desiste com o registro final', :aggregate_failures do
    linha = varredura
    falhar_ao_montar
    execucoes.each { |execucao| chega(execucao) }
    5.times { described_class.conferir_execucao(execucoes[0]) } # cada card que termina confere de novo: mesma tentativa

    expect(Autonomia::Automacao::Registro.where(motivo: 'campanha_da_vez_falhou').count).to eq(1)
    expect(linha.reload.tentativas).to eq(1)

    (described_class::TENTATIVAS - 1).times { na_hora_marcada(linha) }

    expect(linha.reload).to have_attributes(tentativas: described_class::TENTATIVAS, conferir_em: nil)
    expect(linha.fechada_em).to be_present
    expect(Autonomia::Automacao::Registro.where(motivo: 'campanha_da_vez_falhou').count).to eq(described_class::TENTATIVAS - 1)
    expect(registro_da_vez('campanha_da_vez_desistiu').dados).to include('tentativas' => described_class::TENTATIVAS)
    expect { described_class.conferir_execucao(execucoes[0]) }.not_to change(Autonomia::Automacao::Registro, :count)
    expect(account.campaigns).to be_empty
  end

  it 'uma conferência marcada por vez: a vez que já existe não marca outra, e o job fora da hora não confere', :aggregate_failures do
    linha = varredura
    expect(fecha_vez_na_fila).to eq(1)

    described_class.abrir(definicao, vez)
    expect(fecha_vez_na_fila).to eq(1)

    allow(Autonomia::Automacao::EstadoDaVez).to receive(:new).and_call_original
    Autonomia::Automacao::FecharVezJob.perform_now(linha.id)
    expect(Autonomia::Automacao::EstadoDaVez).not_to have_received(:new)
    expect(fecha_vez_na_fila).to eq(1)

    na_hora_marcada(linha)
    expect(Autonomia::Automacao::EstadoDaVez).to have_received(:new)
    expect(fecha_vez_na_fila).to eq(2)
  end

  it 'a vez sem a contagem dos lotes (varredura antes da atualização) sai pela rede com o texto disso', :aggregate_failures do
    linha = described_class.send(:garantir, definicao, Autonomia::Automacao::Gatilhos.marca_da_vez('card.recorrente', vez), 'c1')
    execucoes.each { |execucao| chega(execucao) }
    expect(account.campaigns).to be_empty

    rede_passa(linha)

    expect(account.campaigns.count).to eq(1)
    resumo = registro_da_vez('campanha_da_vez_saiu_sem_contar_lotes')
    historico = Autonomia::Automacao::Historico.new(automacao: definicao, usuario: dona)
    texto = I18n.with_locale(:pt_BR) { historico.send(:passo, resumo, visivel: true)[:motivo] }
    expect(texto).to include('não registrou quantos lotes tinha')
  end

  it 'as execuções da vez saem do índice pelo começo da marca' do
    linha = varredura
    execucoes
    relacao = Autonomia::Automacao::EstadoDaVez.new(linha).send(:execucoes)
    ActiveRecord::Base.connection.execute('SET LOCAL enable_seqscan = off')
    plano = ActiveRecord::Base.connection.select_values("EXPLAIN #{relacao.to_sql}").join("\n")

    expect(plano).to include('idx_autonomia_automacao_execucoes_vez')
  end

  it 'quem chega depois: "já saiu" só se a campanha saiu; senão, "fechou sem mandar"', :aggregate_failures do
    linha = varredura
    execucoes.first(2).each { |execucao| chega(execucao) }
    termina(execucoes.last)
    expect(passo_em(execucoes.last)).to have_attributes(tipo: :pulado, motivo: 'campanha_da_vez_ja_saiu')

    linha.reload.update!(campanha_display_id: nil) # a vez que fechou sem mandar (desligada, motor desligado)
    expect(passo_em(execucoes.last)).to have_attributes(tipo: :pulado, motivo: 'campanha_da_vez_fechou_sem_enviar')
  end
end
