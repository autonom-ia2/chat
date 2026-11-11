require 'rails_helper'

# Fechamento do épico #2414 (#2570), lacuna G50 (#2682, item 2): o card entra de novo na etapa do gatilho enquanto uma
# execução da mesma automação ainda espera por ele. É o contador de faltas do exemplo 4 ("A automação usa a própria
# etiqueta como contador"): a 2ª falta do aluno cai durante os 30 dias do passo 1 e precisa chegar ao passo 2; e o
# passo 10 ("Espera 30 dias. Se nesse tempo não entrou de novo em 'Faltou'...") precisa saber da nova entrada.
#
# Montado pela API da tela, como o Rogério montaria, com os passos 1, 2 e 10 do exemplo 4; os passos 3 a 9 (IA, Clara,
# decidir, retorno) e o card de Retenção ficam no spec à risca do exemplo (exemplo_04_aluno_que_falta_spec.rb). O card
# anda pelo Crm::Cards::Mover, e o evento chega ao motor pelo emissor do CRM e pelo despacho, um job por vez.
RSpec.describe 'Fechamento #2414 · G50: o card entra de novo na etapa durante a espera', :fechamento_automacao, type: :request do
  include ActiveJob::TestHelper

  around do |exemplo|
    with_modified_env(CRM_KANBAN_ENABLED: 'true') { exemplo.run }
  end

  let(:account) { create(:account) }
  let(:rogerio) { create(:user, account: account, role: :administrator, name: 'Rogério Coordenador') }
  let(:recepcao) { create(:user, account: account, role: :agent, name: 'Bianca Recepção') }
  let(:aluno) { create(:contact, account: account, name: 'Lucas') }
  let(:alunos_e_ativo) { create_crm_pipeline(account: account, user: rogerio, name: 'Alunos') }
  let(:faltou) { create_crm_stage(account: account, pipeline: alunos_e_ativo.first, name: 'Faltou', position: 1) }
  let(:card) do
    account.crm_cards.create!(pipeline: ativo.pipeline, stage: ativo, contact: aluno, owner: recepcao, title: 'Lucas - inglês',
                              currency: 'BRL')
  end
  let(:se_repetir) { 'comeca_outra' }

  def fuso = ActiveSupport::TimeZone['America/Sao_Paulo']
  def ativo = alunos_e_ativo.last
  def sem_faltou_1x = { campo: { '$valor' => 'contato.etiquetas' }, op: 'nao_contem', valor: 'faltou-1x' }

  def etiquetas(id, por: [], tirar: [])
    { id: id, tipo: 'acao', acao: 'PATCH contacts/:contact_id/labels/alterar', descricao: 'Etiquetas do aluno',
      caminho: { contact_id: { '$valor' => 'contato.id' } }, corpo: { por: por, tirar: tirar }.compact_blank }
  end

  def gatilho = { tipo: 'card.entrou_na_etapa', etapa_id: faltou.id, se_repetir: se_repetir }.compact

  # Passos 1, 2 e 10 do exemplo 4.
  def receita
    { gatilho: gatilho, passos: [
      { id: 'primeira_falta', tipo: 'se', condicao: sem_faltou_1x, entao: [
        etiquetas('faltou_1x', por: ['faltou-1x']),
        { id: 'trinta_dias', tipo: 'esperar', duracao: { valor: 30, unidade: 'dias' } },
        etiquetas('tira_faltou_1x', tirar: ['faltou-1x']),
        { id: 'fim_da_primeira', tipo: 'parar' }
      ] },
      etiquetas('risco', por: ['risco-de-sair'], tirar: ['faltou-1x']),
      { id: 'nao_entrou_de_novo', tipo: 'esperar_ate', condicao: { campo: { '$valor' => 'card.entrou_de_novo' }, op: 'igual', valor: true },
        prazo: { valor: 30, unidade: 'dias' }, se_vencer: [etiquetas('tira_risco', tirar: ['risco-de-sair'])] }
    ] }
  end

  def drenar
    drenados = [*FechamentoAutomacao::JOBS, Autonomia::Automacao::EventoDoCardJob]
    FechamentoAutomacao::LIMITE_DE_JOBS.times do
      job = enqueued_jobs.find { |item| drenados.include?(item[:job]) }
      return unless job

      enqueued_jobs.delete(job)
      job[:job].perform_now(*ActiveJob::Arguments.deserialize(job[:args]))
    end
    raise "a fila não esvaziou em #{FechamentoAutomacao::LIMITE_DE_JOBS} jobs"
  end

  def as(hora, &) = travel_to(fuso.parse(hora), &)

  def recepcao_move_as(hora, etapa)
    as(hora) do
      Crm::Cards::Mover.new(card: card.reload, actor: recepcao, target_stage: etapa).perform
      drenar
    end
  end

  def falta_as(dia)
    recepcao_move_as("#{dia} 08:00", ativo)
    recepcao_move_as("#{dia} 19:00", faltou)
  end

  def varredura_as(hora)
    as(hora) do
      perform_enqueued_jobs(only: Autonomia::Automacao::AvancarJob) { Autonomia::Automacao::VarreduraJob.perform_now }
      drenar
    end
  end

  def automacao = Autonomia::Automacao::Definicao.find_by!(account: account, nome: 'Aluno que começa a faltar')
  def execucoes = Autonomia::Automacao::Execucao.where(automacao: automacao).order(:id)
  def etiquetas_do_aluno = account.contacts.find(aluno.id).label_list.sort
  def historico_da(execucao) = Autonomia::Automacao::Registro.where(execucao: execucao).order(:id).pluck(:passo, :resultado, :motivo)
  def ja_aberta = Autonomia::Automacao::Registro.where(automacao: automacao, motivo: 'ja_aberta')

  # Todas as frases da resposta da API, onde quer que estejam no JSON.
  def textos(corpo)
    case corpo
    when Hash then corpo.values.flat_map { |item| textos(item) }
    when Array then corpo.flat_map { |item| textos(item) }
    else [corpo.to_s]
    end
  end

  # Só o despacho, até o evento do card ficar na fila; devolve o job dele (fora da fila).
  def evento_do_card_na_fila
    while (despacho = enqueued_jobs.find { |item| item[:job] == EventDispatcherJob })
      enqueued_jobs.delete(despacho)
      despacho[:job].perform_now(*ActiveJob::Arguments.deserialize(despacho[:args]))
    end
    enqueued_jobs.find { |item| item[:job] == Autonomia::Automacao::EventoDoCardJob }.tap { |job| enqueued_jobs.delete(job) }
  end

  before do
    as('2026-11-10 08:00') do
      account.update!(locale: 'pt_BR', reporting_timezone: fuso.name, custom_attributes: { 'timezone' => fuso.name })
      flags_do_piloto(account)
      account.enable_features!('automacao_gatilhos')
      %w[faltou-1x risco-de-sair].each { |nome| create(:label, account: account, title: nome) }
      [faltou, card, recepcao]
      ligar_automacao(rogerio, account, montar_automacao(rogerio, account, nome: 'Aluno que começa a faltar', receita: receita))
      clear_enqueued_jobs
    end
  end

  after { Current.reset }

  context 'with "começa outra vez" no gatilho' do
    before do
      recepcao_move_as('2026-11-10 19:00', faltou)
      falta_as('2026-11-20')
    end

    it 'a 1ª falta põe faltou-1x e espera os 30 dias; a 2ª abre outra execução, paralela, sem "já estava rodando"', :aggregate_failures do
      primeira, segunda = execucoes.to_a

      expect(execucoes.count).to eq(2)
      expect(primeira).to have_attributes(estado: 'esperando', cursor: 'trinta_dias', alvo: card, paralela: true)
      expect(segunda).to have_attributes(estado: 'esperando', cursor: 'nao_entrou_de_novo', alvo: card, paralela: true)
      expect(ja_aberta).to be_empty
    end

    it 'passo 2: a 2ª execução acha faltou-1x e troca para risco-de-sair' do
      expect(etiquetas_do_aluno).to eq(['risco-de-sair'])
    end

    it 'passo 10, não voltou: vencidos os 30 dias, a 2ª tira risco-de-sair; a 1ª conclui, e o tirar faltou-1x não quebra',
       :aggregate_failures do
      primeira, segunda = execucoes.to_a

      varredura_as('2026-12-10 19:05')
      varredura_as('2026-12-20 19:05')

      expect(etiquetas_do_aluno).to be_empty
      expect([primeira.reload.estado, segunda.reload.estado]).to eq(%w[concluida concluida])
      expect(historico_da(segunda).last(2)).to eq([%w[nao_entrou_de_novo pulado prazo_vencido], ['tira_risco', 'ok', nil]])
      expect(historico_da(primeira).map(&:second)).not_to include('falhou')
    end

    it 'passo 10, voltou: a 3ª falta acorda a espera na hora; ela para e o risco fica', :aggregate_failures do
      segunda = execucoes.second

      falta_as('2026-11-25')

      expect(segunda.reload.estado).to eq('concluida')
      expect(historico_da(segunda).last).to eq(['nao_entrou_de_novo', 'ok', nil])
      expect(etiquetas_do_aluno).to include('risco-de-sair')
    end

    # A leitura literal do termo (crítica do desenho): a 3ª execução não vê faltou-1x, que o passo 2 trocou, e volta ao
    # passo 1.
    it 'a 3ª falta abre a 3ª execução, que volta ao passo 1 e põe faltou-1x de novo', :aggregate_failures do
      falta_as('2026-11-25')

      expect(execucoes.count).to eq(3)
      expect(execucoes.last).to have_attributes(estado: 'esperando', cursor: 'trinta_dias')
      expect(etiquetas_do_aluno).to eq(%w[faltou-1x risco-de-sair])
    end

    it 'a varredura no fim do prazo não desfaz o que a nova entrada já decidiu', :aggregate_failures do
      falta_as('2026-11-25')
      recepcao_move_as('2026-11-26 08:00', ativo)

      varredura_as('2026-12-20 19:05')

      expect(etiquetas_do_aluno).to include('risco-de-sair')
      expect(historico_da(execucoes.second).map(&:first)).not_to include('tira_risco')
    end
  end

  it 'o mesmo evento entregue duas vezes abre uma execução só', :aggregate_failures do
    recepcao_move_as('2026-11-10 19:00', faltou)
    as('2026-11-20 19:00') do
      Crm::Cards::Mover.new(card: card.reload, actor: recepcao, target_stage: ativo).perform
      drenar
      Crm::Cards::Mover.new(card: card.reload, actor: recepcao, target_stage: faltou).perform
      job = evento_do_card_na_fila
      2.times { Autonomia::Automacao::EventoDoCardJob.perform_now(*ActiveJob::Arguments.deserialize(job[:args])) }
      drenar
    end

    expect(execucoes.count).to eq(2)
  end

  context 'without "começa outra vez" (como era)' do
    let(:se_repetir) { nil }

    it 'a 2ª falta não abre outra, e o histórico da aberta diz que o gatilho se repetiu', :aggregate_failures do
      recepcao_move_as('2026-11-10 19:00', faltou)
      falta_as('2026-11-20')

      expect(execucoes.count).to eq(1)
      expect(ja_aberta.sole.execucao).to eq(execucoes.sole)
      expect(etiquetas_do_aluno).to eq(['faltou-1x'])
    end
  end

  describe 'o salvar' do
    def salvar(receita_nova)
      post api_automacoes(account), params: { nome: 'Outra', receita: receita_nova }, headers: rogerio.create_new_auth_token, as: :json
    end

    it 'recusa "começa outra vez" na mensagem nova', :aggregate_failures do
      salvar(gatilho: { tipo: 'mensagem.criada', se_repetir: 'comeca_outra' }, passos: [{ id: 'p1', tipo: 'parar' }])

      expect(response).to have_http_status(:unprocessable_entity)
      expect(textos(response.parsed_body)).to include(a_string_including(I18n.t('autonomia.automacao.receita.se_repetir_fora', locale: :pt_BR)))
    end

    it 'recusa "entrou de novo" fora da condição do "esperar até"', :aggregate_failures do
      se = { id: 'p1', tipo: 'se', condicao: { campo: { '$valor' => 'card.entrou_de_novo' }, op: 'igual', valor: true },
             entao: [{ id: 'p2', tipo: 'parar' }] }
      salvar(gatilho: gatilho, passos: [se])

      expect(response).to have_http_status(:unprocessable_entity)
      fora = I18n.t('autonomia.automacao.receita.entrada_so_na_espera', passo: 'p1', caminho: 'card.entrou_de_novo', locale: :pt_BR)
      expect(textos(response.parsed_body)).to include(a_string_including(fora))
    end
  end
end
