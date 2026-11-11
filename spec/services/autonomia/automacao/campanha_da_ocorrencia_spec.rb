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
    travel_to(Time.current + described_class::REDE + 1.minute) { Autonomia::Automacao::FecharVezJob.perform_now(linha.id, linha.account_id) }
  end

  # A conferência marcada da vez, na hora dela.
  def na_hora_marcada(linha)
    travel_to(linha.reload.conferir_em + 1.second) { Autonomia::Automacao::FecharVezJob.perform_now(linha.id, linha.account_id) }
  end

  def fecha_vez_na_fila = enqueued_jobs.count { |job| job[:job] == Autonomia::Automacao::FecharVezJob }

  # A conferência dá erro no meio (o banco), depois de a vez ser lida: EstadoDaVez#pronta? levanta.
  def falhar_a_conferencia
    allow(Autonomia::Automacao::EstadoDaVez).to receive(:new).and_wrap_original do |original, *args, **opcoes|
      original.call(*args, **opcoes).tap { |estado| allow(estado).to receive(:pronta?).and_raise(ActiveRecord::ConnectionTimeoutError) }
    end
  end

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

    expect { rede_passa(linha) }.to have_enqueued_job(Autonomia::Automacao::FecharVezJob).with(linha.id, linha.account_id)

    expect(account.campaigns).to be_empty
    expect(linha.reload.fechada_em).to be_nil
  end

  it 'a execução travada sai da conta pela rede, com o registro de quem ficou de fora', :aggregate_failures do
    linha = varredura
    execucoes.first(2).each { |execucao| chega(execucao) }
    execucoes.last.update_columns(estado: 'andando', due_at: nil, updated_at: 3.hours.ago) # rubocop:disable Rails/SkipsModelValidations
    described_class.conferir(linha.id, linha.account_id)
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

    expect { execucoes.each { |execucao| chega(execucao) } }.to have_enqueued_job(Autonomia::Automacao::FecharVezJob).with(linha.id, linha.account_id)
    expect(account.campaigns).to be_empty
    expect(linha.reload.fechada_em).to be_nil
    expect(registro_da_vez('campanha_da_vez_falhou').dados).to include('erro' => 'ActiveRecord::ConnectionTimeoutError')

    falhar = false
    Autonomia::Automacao::FecharVezJob.perform_now(linha.id, linha.account_id) # antes da hora marcada: nada
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
    Autonomia::Automacao::FecharVezJob.perform_now(linha.id, linha.account_id)
    expect(Autonomia::Automacao::EstadoDaVez).not_to have_received(:new)
    expect(fecha_vez_na_fila).to eq(1)

    na_hora_marcada(linha)
    expect(Autonomia::Automacao::EstadoDaVez).to have_received(:new)
    expect(fecha_vez_na_fila).to eq(2)
  end

  it 'na rede, quem ainda espera depois de ESPERA_MAXIMA fica de fora, e o registro diz quantos', :aggregate_failures do
    linha = varredura
    execucoes.first(2).each { |execucao| chega(execucao) }
    execucoes.last.update_columns(estado: 'esperando', due_at: 1.day.from_now) # rubocop:disable Rails/SkipsModelValidations

    travel_to(Time.current + described_class::ESPERA_MAXIMA + 1.hour) do
      execucoes.last.update_columns(due_at: 1.day.from_now, updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
      Autonomia::Automacao::FecharVezJob.perform_now(linha.id, linha.account_id)
    end

    expect(account.campaigns.count).to eq(1)
    resumo = registro_da_vez('campanha_da_vez_saiu_pela_rede')
    expect(resumo.dados).to include('chegaram' => 2, 'esperaram' => 1, 'dias' => 30)
    historico = Autonomia::Automacao::Historico.new(automacao: definicao, usuario: dona)
    texto = I18n.with_locale(:pt_BR) { historico.send(:passo, resumo, visivel: true)[:motivo] }
    expect(texto).to include('1 ficaram de fora por ainda estarem esperando depois de 30 dias')
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

  # O banco de teste usa a collation C, onde o índice comum também serve ao LIKE com prefixo; em produção não. Por isso,
  # dentro da transação do exemplo, saem todos os outros índices da tabela (menos a chave primária, que é restrição), e
  # o plano tem de usar o da vez com o começo da marca na condição do índice. Tirar só os que começam por automacao_id
  # não basta (#2914): a consulta também filtra por account_id, e com poucas linhas e sem ANALYZE o índice de account_id
  # empata no custo e às vezes ganha, com a marca no Filter.
  it 'as execuções da vez saem do índice pelo começo da marca (text_pattern_ops)', :aggregate_failures do
    linha = varredura
    conexao = ActiveRecord::Base.connection
    definicao_do_indice = conexao.select_value("SELECT indexdef FROM pg_indexes WHERE indexname = 'idx_autonomia_automacao_execucoes_vez'")
    expect(definicao_do_indice).to include('text_pattern_ops')

    outros = conexao.select_values(<<~SQL.squish)
      SELECT indexname FROM pg_indexes
      WHERE schemaname = current_schema() AND tablename = 'autonomia_automacao_execucoes'
        AND indexname NOT IN ('idx_autonomia_automacao_execucoes_vez', 'autonomia_automacao_execucoes_pkey')
    SQL
    expect(outros).to include('index_autonomia_automacao_execucoes_on_account_id')
    conexao.execute("DROP INDEX #{outros.map { |nome| conexao.quote_column_name(nome) }.join(', ')}")
    conexao.execute('SET LOCAL enable_seqscan = off')
    relacao = Autonomia::Automacao::EstadoDaVez.new(linha).send(:execucoes)
    plano = conexao.select_values("EXPLAIN #{relacao.to_sql}").join("\n")

    expect(plano).to include('idx_autonomia_automacao_execucoes_vez').and include('Index Cond').and include('~>=~')
  end

  it 'quem chega depois: "já saiu" só se a campanha saiu; senão, "fechou sem mandar"', :aggregate_failures do
    linha = varredura
    execucoes.first(2).each { |execucao| chega(execucao) }
    termina(execucoes.last)
    expect(passo_em(execucoes.last)).to have_attributes(tipo: :pulado, motivo: 'campanha_da_vez_ja_saiu')

    linha.reload.update!(campanha_display_id: nil) # a vez que fechou sem mandar (desligada, motor desligado)
    expect(passo_em(execucoes.last)).to have_attributes(tipo: :pulado, motivo: 'campanha_da_vez_fechou_sem_enviar')
  end

  it 'a conferência que roda sem erro zera as tentativas: erros isolados não somam até desistir', :aggregate_failures do
    linha = varredura
    falhar_a_conferencia
    described_class.conferir(linha.id, linha.account_id)
    expect(linha.reload.tentativas).to eq(1)

    allow(Autonomia::Automacao::EstadoDaVez).to receive(:new).and_call_original
    described_class.conferir(linha.id, linha.account_id)

    expect(linha.reload).to have_attributes(tentativas: 0, fechada_em: nil)
  end

  it 'o registro de erro da vez na primeira execução não a conta como chegada: a vez espera ela chegar', :aggregate_failures do
    linha = varredura
    falhar_a_conferencia
    described_class.conferir(linha.id, linha.account_id)
    expect(registro_da_vez('campanha_da_vez_falhou')).to be_present

    allow(Autonomia::Automacao::EstadoDaVez).to receive(:new).and_call_original
    execucoes.last(2).each { |execucao| termina(execucao) }
    expect(linha.reload.fechada_em).to be_nil

    chega(execucoes[0])

    expect(account.campaigns.count).to eq(1)
    expect(registro_da_vez('campanha_da_vez_saiu').dados).to include('chegaram' => 1, 'sairam' => 2)
  end

  it 'o erro grava a marca da nova tentativa sob a mesma trava que conta a tentativa', :aggregate_failures do
    linha = varredura
    falhar_ao_montar
    allow(described_class).to receive(:marcar).and_call_original

    execucoes.each { |execucao| chega(execucao) }

    expect(described_class).not_to have_received(:marcar)
    expect(linha.reload.conferir_em).to be_within(1.second).of(Time.current + described_class::TENTAR_DE_NOVO)
    expect(Autonomia::Automacao::FecharVezJob).to have_been_enqueued.with(linha.id, linha.account_id).at_least(:once)
  end

  it 'a rede que não consegue marcar a próxima põe o job de novo na fila e levanta o erro', :aggregate_failures do
    linha = varredura
    allow(described_class).to receive(:marcar).and_raise(ActiveRecord::ConnectionTimeoutError, 'banco ocupado')
    clear_enqueued_jobs
    marca = linha.reload.conferir_em

    expect { na_hora_marcada(linha) }.to raise_error(ActiveRecord::ConnectionTimeoutError)
    expect(fecha_vez_na_fila).to eq(1)
    expect(linha.reload.conferir_em).to eq(marca)
  end

  # B1 e B2 do lote 3: o público "desta execução" (G58) no recorrente de card mandaria uma campanha por card, fora da vez.
  # A execução pula, e a vez que chega a fechar com ele (a receita mudou depois das chegadas) não sai, com o porquê.
  it 'público "desta execução" no recorrente de card: nada sai por card, e a vez fecha sem mandar com o motivo', :aggregate_failures do
    linha = varredura
    desta = disparar.except('etiquetas').merge('publico' => 'desta_execucao')
    expect(Autonomia::Automacao::PassoDeCampanha.new(execucao: execucoes[0], passo: desta, alvo: execucoes[0].alvo).executar)
      .to have_attributes(tipo: :pulado, motivo: 'campanha_desta_execucao_so_na_conta')

    execucoes.first(2).each { |execucao| chega(execucao) }
    Autonomia::Automacao::Versao.where(id: definicao.versao_ativa_id).update_all(receita: { 'gatilho' => gatilho, 'passos' => [desta] }) # rubocop:disable Rails/SkipsModelValidations
    chega(execucoes[2])

    expect(linha.reload.fechada_em).to be_present
    expect(account.campaigns).to be_empty
    expect(disparos).to eq(0)
    resumo = registro_da_vez('campanha_da_vez_nao_saiu')
    expect(resumo.dados).to include('por' => 'campanha_desta_execucao_so_na_conta')
    historico = Autonomia::Automacao::Historico.new(automacao: definicao, usuario: dona)
    texto = I18n.with_locale(:pt_BR) { historico.send(:passo, resumo, visivel: true)[:motivo] }
    expect(texto).to include('A campanha desta vez não saiu.').and include('só vale na automação que roda uma vez para a conta inteira')
  end

  it 'o histórico da vez que não saiu sem motivo escrito mostra o texto, sem levantar' do
    varredura
    resumo = Autonomia::Automacao::Registro.create!(account: account, automacao: definicao, execucao: execucoes[0], passo: 'c1',
                                                    resultado: 'pulado', motivo: 'campanha_da_vez_nao_saiu', dados: { 'por' => nil })
    historico = Autonomia::Automacao::Historico.new(automacao: definicao, usuario: dona)

    expect(I18n.with_locale(:pt_BR) { historico.send(:passo, resumo, visivel: true)[:motivo] }).to eq('A campanha desta vez não saiu. ')
  end

  # B4 do lote 3: a vez é lida sempre na conta dela.
  it 'a conferência com a conta errada não lê nem fecha a vez', :aggregate_failures do
    linha = varredura
    outra = create(:account)

    expect(described_class.conferir(linha.id, outra.id)).to eq(:falhou)
    expect(Autonomia::Automacao::FecharVezJob.perform_now(linha.id, outra.id)).to be_nil
    expect(linha.reload).to have_attributes(fechada_em: nil, tentativas: 0)
  end
end
