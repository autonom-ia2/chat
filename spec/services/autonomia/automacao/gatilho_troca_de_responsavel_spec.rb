require 'rails_helper'

# G9 (#2707): os gatilhos "quando muda quem cuida do card" e "quando muda o time do card". A troca vem do próprio card
# (Crm::CardAvisaAutomacao, o gancho único), seja qual for o caminho que grava o `owner_id` ou o `team_id`; a marca da
# execução leva quem era antes. O ponta a ponta, pela Lista do CRM, está em
# spec/fechamento/automacao/g9_troca_de_responsavel_spec.rb.
RSpec.describe 'Automação livre: gatilho troca de responsável do card', :automacao_motor do # rubocop:disable RSpec/DescribeClass
  include ActiveJob::TestHelper

  around { |example| with_modified_env(CRM_KANBAN_ENABLED: 'true') { example.run } }

  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator, name: 'Paula') }
  let(:julia) { create(:user, account: account, role: :agent, name: 'Júlia') }
  let(:renata) { create(:user, account: account, role: :agent, name: 'Renata') }
  let(:funil) { create_crm_pipeline(account: account, user: admin) }
  let(:card) { account.crm_cards.create!(pipeline: funil.first, stage: funil.last, title: 'Proposta', currency: 'BRL', owner: julia) }
  let(:execucoes) { Autonomia::Automacao::Execucao }

  before do
    ligar_motor(account)
    account.enable_features!('automacao_gatilhos')
    card
    clear_enqueued_jobs
  end

  after { Current.reset }

  def da_troca(tipo = 'card.responsavel_mudou', **parametros)
    automacao_ligada(account, admin, [esperar_passo('p1')], gatilho: { 'tipo' => tipo, **parametros.transform_keys(&:to_s) })
  end

  def anterior(execucao, tipo = Autonomia::Automacao::TrocaNoCard::RESPONSAVEL)
    Autonomia::Automacao::TrocaNoCard.anterior_da_marca(execucao.evento, tipo)
  end

  def drenar
    5.times do
      job = enqueued_jobs.find { |item| item[:job] == Autonomia::Automacao::EventoDoCardJob }
      return unless job

      enqueued_jobs.delete(job)
      job[:job].perform_now(*ActiveJob::Arguments.deserialize(job[:args]))
    end
  end

  def valores_da(execucao)
    Autonomia::Automacao::Valores.new(alvo: Autonomia::Automacao::Contexto.de(card, execucao: execucao), quem: admin)
  end

  it 'a troca feita na tela do card começa a automação, com quem cuidava antes e quem cuida agora', :aggregate_failures do
    da_troca(funil_id: funil.first.id)
    card.update!(owner: renata)
    drenar

    execucao = execucoes.sole
    expect(execucao.evento).to start_with("card.responsavel_mudou:#{card.id}:#{julia.id}:")
    expect(valores_da(execucao).ler('gatilho.responsavel_anterior_id')).to eq(julia.id)
    expect(valores_da(execucao).ler('gatilho.responsavel_anterior_nome')).to eq('Júlia')
    expect(valores_da(execucao).ler('card.responsavel_nome')).to eq('Renata')
  end

  it 'card que não tinha ninguém: a troca começa, e quem cuidava antes vem vazio' do
    card.update!(owner: nil)
    da_troca
    clear_enqueued_jobs
    card.update!(owner: renata)
    drenar

    expect(valores_da(execucoes.sole).ler('gatilho.responsavel_anterior_id')).to be_nil
  end

  it 'duas trocas na mesma transação: quem cuidava antes é o do começo, não o do meio' do
    paula = create(:user, account: account, role: :agent, name: 'Paula')
    da_troca
    ActiveRecord::Base.transaction do
      card.update!(owner: renata)
      card.update!(owner: paula)
    end
    drenar

    expect(anterior(execucoes.sole)).to eq(julia.id)
  end

  it 'troca desfeita na mesma transação não começa nada' do
    da_troca
    ActiveRecord::Base.transaction do
      card.update!(owner: renata)
      card.update!(owner: julia)
    end
    drenar

    expect(execucoes.count).to eq(0)
  end

  it 'o mesmo evento entregue duas vezes abre uma execução só' do
    da_troca
    card.update!(owner: renata)
    job = enqueued_jobs.find { |item| item[:job] == Autonomia::Automacao::EventoDoCardJob }
    2.times { Autonomia::Automacao::EventoDoCardJob.perform_now(*ActiveJob::Arguments.deserialize(job[:args])) }

    expect(execucoes.count).to eq(1)
  end

  it 'sem automação da troca ligada, a troca não enfileira nada' do
    card.update!(owner: renata)

    expect(enqueued_jobs.map { |item| item[:job] }).not_to include(Autonomia::Automacao::EventoDoCardJob)
  end

  it 'fora do gatilho da troca, o salvar recusa o responsável anterior' do
    receita = { 'gatilho' => { 'tipo' => 'card.ganho' },
                'passos' => [{ 'id' => 's1', 'tipo' => 'se', 'entao' => [esperar_passo('p2')],
                               'condicao' => { 'campo' => { '$valor' => 'gatilho.responsavel_anterior_id' }, 'op' => 'preenchido' } }] }
    problemas = I18n.with_locale(:pt_BR) { Autonomia::Automacao::Receita.new(receita, conta: account, account_user: nil).problemas }

    expect(problemas.join).to include('só existe no gatilho da troca que ele descreve')
  end

  it 'o time de antes só existe na troca de time, não na de dono' do
    receita = { 'gatilho' => { 'tipo' => 'card.responsavel_mudou' },
                'passos' => [{ 'id' => 's1', 'tipo' => 'se', 'entao' => [esperar_passo('p2')],
                               'condicao' => { 'campo' => { '$valor' => 'gatilho.time_anterior_nome' }, 'op' => 'preenchido' } }] }
    problemas = I18n.with_locale(:pt_BR) { Autonomia::Automacao::Receita.new(receita, conta: account, account_user: nil).problemas }

    expect(problemas.join).to include('gatilho.time_anterior_nome só existe no gatilho da troca')
  end

  it 'fora de gatilho de card, o salvar recusa avisar quem cuida do card' do
    receita = { 'gatilho' => { 'tipo' => 'conversa.criada' },
                'passos' => [{ 'id' => 'a1', 'tipo' => 'avisar', 'para' => { 'responsavel_do_card' => true }, 'texto' => ['Oi'] }] }
    problemas = I18n.with_locale(:pt_BR) { Autonomia::Automacao::Receita.new(receita, conta: account, account_user: nil).problemas }

    expect(problemas.join).to include('"quem cuida do card" só vale quando o gatilho é de card')
  end

  it 'o card que já nasce com dono não é troca' do
    da_troca
    account.crm_cards.create!(pipeline: funil.first, stage: funil.last, title: 'Novo', currency: 'BRL', owner: renata)
    drenar

    expect(execucoes.count).to eq(0)
  end

  # #2832, revisão: a criação não é troca, mas a troca feita depois dela, na mesma transação, é.
  it 'card criado e trocado na mesma transação: a troca depois da criação começa', :aggregate_failures do
    da_troca
    novo = ActiveRecord::Base.transaction do
      criado = account.crm_cards.create!(pipeline: funil.first, stage: funil.last, title: 'Novo', currency: 'BRL', owner: julia)
      criado.update!(owner: renata)
      criado
    end
    drenar

    expect(execucoes.sole.alvo).to eq(novo)
    expect(anterior(execucoes.sole)).to eq(julia.id)
  end

  it 'a troca sem atividade (a saída da triagem grava o card direto) também começa' do
    da_troca
    card.update!(owner_id: nil)
    drenar

    expect(anterior(execucoes.sole)).to eq(julia.id)
  end

  it 'quem cuidava antes e saiu da conta lê vazio: a pessoa é achada na conta, nunca só pelo id da marca', :aggregate_failures do
    da_troca
    card.update!(owner: renata)
    drenar
    AccountUser.find_by!(account: account, user: julia).destroy!

    expect(valores_da(execucoes.sole).ler('gatilho.responsavel_anterior_nome')).to be_nil
    expect(valores_da(execucoes.sole).ler('gatilho.responsavel_anterior_ausente')).to be(false)
  end

  context 'with o filtro "quem cuidava antes está ausente" (exemplo 17)' do
    before do
      automacao_ligada(account, admin, [esperar_passo('p1')], gatilho: {
                         'tipo' => 'card.responsavel_mudou',
                         'filtros' => [{ 'campo' => { '$valor' => 'gatilho.responsavel_anterior_ausente' }, 'op' => 'igual', 'valor' => true }]
                       })
    end

    it 'a Júlia de férias: começa, e o valor lê true também nos passos', :aggregate_failures do
      AccountUser.find_by!(account: account, user: julia).update!(ausente_ate: 2.days.from_now)
      card.update!(owner: renata)
      drenar

      expect(execucoes.count).to eq(1)
      expect(valores_da(execucoes.sole).ler('gatilho.responsavel_anterior_ausente')).to be(true)
    end

    it 'a Júlia presente: não começa' do
      card.update!(owner: renata)
      drenar

      expect(execucoes.count).to eq(0)
    end

    it 'o "ausente até" que já passou: não começa' do
      AccountUser.find_by!(account: account, user: julia).update!(ausente_ate: 1.day.ago)
      card.update!(owner: renata)
      drenar

      expect(execucoes.count).to eq(0)
    end

    # A execução aberta não registra a repetição (repetiu_em): o filtro barrou antes, com a Renata presente.
    it 'devolver o card à Júlia, com a Renata presente como anterior, para no filtro (sem laço)', :aggregate_failures do
      AccountUser.find_by!(account: account, user: julia).update!(ausente_ate: 2.days.from_now)
      card.update!(owner: renata)
      drenar
      card.update!(owner: julia)
      drenar

      expect(execucoes.count).to eq(1)
      expect(execucoes.sole.repetiu_em).to be_nil
    end
  end

  context 'with a troca de time' do
    let(:vendas) { create(:team, account: account, name: 'Vendas') }
    let(:pos_venda) { create(:team, account: account, name: 'Pós-venda') }

    before do
      card.update!(team: vendas)
      clear_enqueued_jobs
    end

    it 'começa a automação da troca de time, com o time de antes', :aggregate_failures do
      da_troca('card.time_mudou', funil_id: funil.first.id)
      card.update!(team: pos_venda)
      drenar

      execucao = execucoes.sole
      expect(anterior(execucao, Autonomia::Automacao::TrocaNoCard::TIME)).to eq(vendas.id)
      expect(valores_da(execucao).ler('gatilho.time_anterior_id')).to eq(vendas.id)
      expect(valores_da(execucao).ler('gatilho.time_anterior_nome')).to eq(vendas.name)
    end

    it 'trocar o dono não começa a automação de time, e trocar o time não começa a de dono' do
      da_troca('card.time_mudou')
      da_troca('card.responsavel_mudou')
      card.update!(owner: renata)
      drenar

      expect(execucoes.pluck(:evento)).to contain_exactly(start_with('card.responsavel_mudou:'))
    end
  end

  it 'no ensaio, sem execução, o responsável anterior lê vazio' do
    valores = Autonomia::Automacao::Valores.new(alvo: card, quem: admin)

    expect(valores.ler('gatilho.responsavel_anterior_nome')).to be_nil
  end
end
