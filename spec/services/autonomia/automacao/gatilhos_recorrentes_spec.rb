require 'rails_helper'

# #2635 (G7): o gatilho recorrente. Na ocorrência (todo dia, toda semana, todo mês, numa hora), cada card ou contato da
# seleção abre uma execução, uma vez por ocorrência. A varredura enfileira os alvos em lotes (RecorrenteLoteJob).
RSpec.describe 'Automação livre: gatilho recorrente', :automacao_motor do # rubocop:disable RSpec/DescribeClass
  include ActiveJob::TestHelper

  around { |example| with_modified_env(CRM_KANBAN_ENABLED: 'true') { example.run } }

  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:execucoes) { Autonomia::Automacao::Execucao }
  let(:fuso) { ActiveSupport::TimeZone['America/New_York'] }
  let(:clientes) { create_list(:contact, 2, account: account) }

  before do
    ligar_motor(account)
    account.enable_features!('automacao_gatilhos')
    account.update!(reporting_timezone: fuso.name)
    create(:label, account: account, title: 'newsletter')
    clientes.each { |contato| contato.update!(label_list: ['newsletter']) }
    create(:contact, account: account)
  end

  def recorrente(tipo: 'contato.recorrente', ligada: fuso.local(2026, 9, 1, 0), selecao: { 'etiqueta' => 'newsletter' }, **parametros)
    gatilho = { 'tipo' => tipo, 'frequencia' => 'diaria', 'hora' => 8, 'selecao' => selecao, **parametros.transform_keys(&:to_s) }
    travel_to(ligada) { automacao_ligada(account, admin, [esperar_passo('p1')], gatilho: gatilho) }
  end

  # Uma varredura completa às `momento`: o TempoJob, o job da automação e os lotes.
  def varrer_em(momento)
    travel_to(momento) do
      Autonomia::Automacao::TempoJob.perform_now
      perform_enqueued_jobs(only: Autonomia::Automacao::TempoDaAutomacaoJob)
      perform_enqueued_jobs(only: Autonomia::Automacao::RecorrenteLoteJob)
    end
  end

  def alvos = execucoes.order(:alvo_id).pluck(:alvo_id)

  describe 'a ocorrência' do
    it 'diária: roda na hora, uma vez por contato da seleção, mesmo em 10 varreduras', :aggregate_failures do
      recorrente
      10.times { |vez| varrer_em(fuso.local(2026, 10, 5, 8, 5) + (15.minutes * vez)) }

      expect(alvos).to eq(clientes.map(&:id).sort)
      expect(execucoes.pluck(:evento).uniq.size).to eq(2)
      expect(execucoes.first.evento).to start_with('recorrente:2026-10-05T12:00:00Z:contato.recorrente:')
    end

    # Ligada à 0h: a ocorrência de ontem às 8h é anterior a ligar e não roda.
    it 'antes da hora, nada; no dia seguinte, a nova ocorrência roda de novo', :aggregate_failures do
      recorrente(ligada: fuso.local(2026, 10, 5, 0))
      varrer_em(fuso.local(2026, 10, 5, 7, 50))
      expect(execucoes.count).to eq(0)

      varrer_em(fuso.local(2026, 10, 5, 8, 10))
      execucoes.update_all(estado: 'concluida', travada_em: nil, due_at: nil, finalizada_em: Time.current) # rubocop:disable Rails/SkipsModelValidations
      varrer_em(fuso.local(2026, 10, 6, 8, 10))
      expect(execucoes.count).to eq(4)
    end

    it 'semanal: só no dia da semana; a ocorrência de mais de 1 dia atrás não roda', :aggregate_failures do
      recorrente(frequencia: 'semanal', dia_da_semana: 1)
      varrer_em(fuso.local(2026, 10, 7, 9)) # quarta: a segunda passou há mais de 1 dia
      expect(execucoes.count).to eq(0)

      varrer_em(fuso.local(2026, 10, 12, 8, 1)) # segunda
      expect(execucoes.count).to eq(2)
    end

    it 'mensal no dia 31: em abril, no dia 30' do
      recorrente(frequencia: 'mensal', dia_do_mes: 31, ligada: fuso.local(2026, 3, 1))
      varrer_em(fuso.local(2026, 4, 30, 8, 20))

      expect(execucoes.count).to eq(2)
    end

    it 'ligar não age no passado: ligada às 8h30, a das 8h fica de fora; a de amanhã roda', :aggregate_failures do
      recorrente(ligada: fuso.local(2026, 10, 5, 8, 30))
      varrer_em(fuso.local(2026, 10, 5, 8, 45))
      expect(execucoes.count).to eq(0)

      varrer_em(fuso.local(2026, 10, 6, 8, 5))
      expect(execucoes.count).to eq(2)
    end

    it 'horário de verão: na volta da hora (1h acontece duas vezes), roda uma vez' do
      recorrente(hora: 1)
      momento = fuso.local(2026, 11, 1, 0, 50)
      12.times { |vez| varrer_em(momento + (15.minutes * vez)) }

      expect(execucoes.count).to eq(2)
    end

    it 'horário de verão: no pulo da hora (2h não existe), roda uma vez' do
      recorrente(hora: 2, ligada: fuso.local(2026, 2, 1))
      momento = Time.utc(2026, 3, 8, 6, 30)
      12.times { |vez| varrer_em(momento + (15.minutes * vez)) }

      expect(execucoes.count).to eq(2)
    end
  end

  describe 'a seleção' do
    it 'card: o funil, perdido e fechado entre 330 e 360 dias atrás; o ganho, o recente e o de outra conta ficam de fora' do
      funil, etapa = create_crm_pipeline(account: account, user: admin)
      varredura = fuso.local(2026, 10, 5, 8, 5)
      # O closed_at é gravado pelo próprio card ao fechar: a data do fechamento vem depois, direto na coluna.
      card = lambda do |status, dias|
        account.crm_cards.create!(pipeline: funil, stage: etapa, title: 'C', currency: 'BRL', status: status)
               .tap { |item| item.update_columns(closed_at: varredura - dias.days) } # rubocop:disable Rails/SkipsModelValidations
      end
      perdido = card.call(:lost, 340)
      card.call(:won, 340)
      card.call(:lost, 20)
      outra = create(:account)
      outro_funil, outra_etapa = create_crm_pipeline(account: outra, user: create(:user, account: outra, role: :administrator))
      outra.crm_cards.create!(pipeline: outro_funil, stage: outra_etapa, title: 'X', currency: 'BRL', status: :lost)
           .update_columns(closed_at: varredura - 340.days) # rubocop:disable Rails/SkipsModelValidations
      selecao = { 'funil_id' => funil.id, 'situacao' => 'perdido', 'fechado_entre_dias' => { 'de' => 330, 'ate' => 360 } }

      recorrente(tipo: 'card.recorrente', selecao: selecao)
      varrer_em(varredura)

      expect(execucoes.pluck(:alvo_type, :alvo_id)).to eq([['Crm::Card', perdido.id]])
    end

    # Ex. 17 (vendedora de férias): os cards abertos de uma pessoa; o fechado dela e o aberto de outra ficam de fora.
    it 'card: aberto e do responsável' do
      funil, etapa = create_crm_pipeline(account: account, user: admin)
      vendedora = create(:user, account: account, role: :agent)
      card = ->(dono, status) { account.crm_cards.create!(pipeline: funil, stage: etapa, title: 'C', currency: 'BRL', owner: dono, status: status) }
      dela = card.call(vendedora, :open)
      card.call(vendedora, :won)
      card.call(admin, :open)

      recorrente(tipo: 'card.recorrente', selecao: { 'situacao' => 'aberto', 'responsavel_id' => vendedora.id })
      varrer_em(fuso.local(2026, 10, 5, 8, 5))

      expect(execucoes.pluck(:alvo_type, :alvo_id)).to eq([['Crm::Card', dela.id]])
    end

    it 'contato: atributo igual e sem a etiqueta' do
      create(:custom_attribute_definition, account: account, attribute_key: 'plano', attribute_model: 'contact_attribute')
      alvo = create(:contact, account: account, custom_attributes: { 'plano' => 'ouro' })
      clientes.first.update!(custom_attributes: { 'plano' => 'ouro' })

      recorrente(selecao: { 'atributo' => { 'chave' => 'plano', 'valor' => 'ouro' }, 'sem_etiqueta' => 'newsletter' })
      varrer_em(fuso.local(2026, 10, 5, 8, 5))

      expect(alvos).to eq([alvo.id])
    end

    it 'a seleção sai uma vez por ocorrência: as rodadas seguintes da janela não reenfileiram os lotes' do
      recorrente
      lotes = 0
      [fuso.local(2026, 10, 5, 8, 5), fuso.local(2026, 10, 5, 8, 20)].each do |momento|
        travel_to(momento) do
          Autonomia::Automacao::TempoJob.perform_now
          perform_enqueued_jobs(only: Autonomia::Automacao::TempoDaAutomacaoJob)
          lotes += enqueued_jobs.count { |job| job[:job] == Autonomia::Automacao::RecorrenteLoteJob }
          perform_enqueued_jobs(only: Autonomia::Automacao::RecorrenteLoteJob)
        end
      end

      expect(lotes).to eq(1)
    end

    it 'sem condição nenhuma, a seleção não pega ninguém' do
      gatilho = { 'tipo' => 'contato.recorrente', 'selecao' => {} }
      expect(Autonomia::Automacao::Tempo::Selecao.new(account, gatilho).escopo.count).to eq(0)
    end

    it 'sai em lotes, e cada lote relê a seleção: quem saiu dela no meio fica de fora', :aggregate_failures do
      stub_const('Autonomia::Automacao::Tempo::Recorrente::LOTE', 1)
      recorrente
      travel_to(fuso.local(2026, 10, 5, 8, 5)) do
        Autonomia::Automacao::TempoJob.perform_now
        perform_enqueued_jobs(only: Autonomia::Automacao::TempoDaAutomacaoJob)
        expect(enqueued_jobs.count { |job| job[:job] == Autonomia::Automacao::RecorrenteLoteJob }).to eq(2)

        clientes.first.update!(label_list: [])
        perform_enqueued_jobs(only: Autonomia::Automacao::RecorrenteLoteJob)
      end

      expect(alvos).to eq([clientes.last.id])
    end

    # Parecer do Funções: cada registro passa pela Partida, que confere se quem ligou alcança o alvo.
    it 'quem ligou numa função com 1 caixa: só o card dessa caixa abre; o da outra fica de fora' do
      agente = create(:user, account: account, role: :agent)
      funcao = create(:custom_role, account: account,
                                    permissions: %w[automation_manage conversation_manage crm_view crm_manage_cards crm_manage_pipelines])
      account.account_users.find_by(user: agente).update!(custom_role: funcao)
      caixa = create(:inbox, account: account)
      create(:inbox_member, user: agente, inbox: caixa)
      funil, etapa = create_crm_pipeline(account: account, user: admin)
      card = ->(inbox) { account.crm_cards.create!(pipeline: funil, stage: etapa, title: 'C', currency: 'BRL', inbox: inbox) }
      dele = card.call(caixa)
      card.call(create(:inbox, account: account))

      definicao = recorrente(tipo: 'card.recorrente', selecao: { 'funil_id' => funil.id })
      definicao.update!(ligada_por: agente)
      varrer_em(fuso.local(2026, 10, 5, 8, 5))

      expect(execucoes.pluck(:alvo_id)).to eq([dele.id])
      # O card que ele não vê fica fora da seleção: a automação segue ligada, sem pausar no primeiro.
      expect(definicao.reload.ativa).to be(true)
      # O ensaio conta pelo mesmo SQL: para quem ligou, o número é o que a execução pegou.
      contexto = Autonomia::Automacao::Acesso.new(definicao).contexto
      gatilho = definicao.versao_ativa.receita['gatilho']
      expect(Autonomia::Automacao::Tempo::Selecao.new(account, gatilho).quantos_para(contexto)).to eq(execucoes.count)
    end

    # Qualidade: chave e valor do atributo vão como parâmetro, nunca no texto do SQL.
    it 'chave e valor maliciosos no atributo não pegam ninguém nem mexem no banco', :aggregate_failures do
      create(:contact, account: account, custom_attributes: { 'plano' => 'ouro' })
      maliciosos = ["plano' OR 1=1 --", "'; DROP TABLE contacts; --", "') OR ('1'='1"]
      contar = lambda do |atributo|
        gatilho = { 'tipo' => 'contato.recorrente', 'selecao' => { 'atributo' => atributo } }
        Autonomia::Automacao::Tempo::Selecao.new(account, gatilho).escopo.count
      end

      maliciosos.each do |texto|
        expect(contar.call({ 'chave' => texto, 'valor' => 'ouro' })).to eq(0)
        expect(contar.call({ 'chave' => 'plano', 'valor' => texto })).to eq(0)
      end
      expect(account.contacts.count).to eq(4)
    end

    it 'automação desligada antes do lote: o lote não age' do
      definicao = recorrente
      travel_to(fuso.local(2026, 10, 5, 8, 5)) do
        Autonomia::Automacao::TempoJob.perform_now
        perform_enqueued_jobs(only: Autonomia::Automacao::TempoDaAutomacaoJob)
        definicao.update!(ativa: false)
        perform_enqueued_jobs(only: Autonomia::Automacao::RecorrenteLoteJob)
      end

      expect(execucoes.count).to eq(0)
    end
  end

  # Decisão (a) da Automação com a G14: conta.recorrente roda sem seleção, uma vez por ocorrência, na própria conta.
  describe 'conta.recorrente' do
    def da_conta(passos = [esperar_passo('p1')])
      gatilho = { 'tipo' => 'conta.recorrente', 'frequencia' => 'diaria', 'hora' => 8 }
      travel_to(fuso.local(2026, 9, 1, 0)) { automacao_ligada(account, admin, passos, gatilho: gatilho) }
    end

    it 'uma execução por ocorrência, na conta, mesmo em 10 varreduras; amanhã, outra', :aggregate_failures do
      da_conta
      10.times { |vez| varrer_em(fuso.local(2026, 10, 5, 8, 5) + (15.minutes * vez)) }

      expect(execucoes.pluck(:alvo_type, :alvo_id, :evento))
        .to eq([['Account', account.id, 'recorrente:2026-10-05T12:00:00Z:conta.recorrente']])

      execucoes.update_all(estado: 'concluida', travada_em: nil, due_at: nil, finalizada_em: Time.current) # rubocop:disable Rails/SkipsModelValidations
      varrer_em(fuso.local(2026, 10, 6, 8, 5))
      expect(execucoes.count).to eq(2)
    end

    it 'o executor anda com a conta como alvo, sem quebrar, até o fim', :aggregate_failures do
      definicao = da_conta([esperar_passo('p1', 1, 'minutos')])
      travel_to(fuso.local(2026, 10, 5, 8, 5)) do
        Autonomia::Automacao::TempoJob.perform_now
        perform_enqueued_jobs(only: Autonomia::Automacao::TempoDaAutomacaoJob)
        perform_enqueued_jobs(only: Autonomia::Automacao::RecorrenteLoteJob)
        perform_enqueued_jobs(only: Autonomia::Automacao::AvancarJob)
      end
      execucao = execucoes.sole
      expect(execucao.reload.estado).to eq('esperando')

      travel_to(fuso.local(2026, 10, 5, 8, 10)) { varrer }

      expect(execucao.reload.estado).to eq('concluida')
      expect(definicao.reload.ativa).to be(true)
    end

    it 'a execução só aceita como alvo a própria conta, nunca outra', :aggregate_failures do
      definicao = da_conta
      nova = lambda do |alvo|
        execucoes.new(account: account, automacao: definicao, versao: definicao.versao_ativa, alvo: alvo, chave_gatilho: 'conta.recorrente',
                      estado: 'andando')
      end

      expect(nova.call(account)).to be_valid
      expect(nova.call(create(:account)).tap(&:valid?).errors[:alvo]).to be_present
    end

    it 'o Contexto, o Acesso e o Valores aguentam a conta como alvo', :aggregate_failures do
      contexto = Autonomia::Automacao::Contexto.de(account)
      acesso = Autonomia::Automacao::Acesso.new(da_conta)

      expect([contexto.base, contexto.conta_id, contexto.conversa, contexto.card, contexto.contato]).to eq(['conta', account.id, nil, nil, nil])
      expect([contexto.no_spam?, contexto.visivel_para?(admin), contexto.link]).to eq([false, true, "accounts/#{account.id}/automacoes"])
      expect(contexto.rotulo).to eq(I18n.t('autonomia.automacao.alvo.conta'))
      expect([acesso.alcanca?(account), acesso.alcanca?(create(:account))]).to eq([true, false])
      expect(Autonomia::Automacao::Valores.new(alvo: account, quem: admin).ler('contato.nome')).to be_nil
    end

    # Revisor: a execução da conta mostra o que a automação fez; só quem vê as automações.
    it 'a execução da conta só fica visível para quem vê as automações', :aggregate_failures do
      agente = create(:user, account: account, role: :agent)
      contexto = Autonomia::Automacao::Contexto.de(account)

      expect(contexto.visivel_para?(admin)).to be(true)
      expect(contexto.visivel_para?(agente)).to be(false)
      expect(contexto.visivel_para?(create(:user))).to be(false)
    end

    it 'o salvar recusa o passo que pede alvo e a seleção; aceita o esperar', :aggregate_failures do
      receita = lambda do |passos, **extra|
        { 'gatilho' => { 'tipo' => 'conta.recorrente', 'frequencia' => 'diaria', 'hora' => 8, **extra }, 'passos' => passos }
      end
      problemas = ->(passos) { Autonomia::Automacao::Receita.new(receita.call(passos), conta: account, account_user: nil).problemas }
      etiquetar = { 'id' => 'p2', 'tipo' => 'acao', 'acao' => 'contato.etiquetar', 'corpo' => { 'labels' => ['newsletter'] } }

      expect(problemas.call([esperar_passo('p1')])).to be_empty
      expect(problemas.call([esperar_passo('p1'), etiquetar])).to eq([I18n.t('autonomia.automacao.receita.passo_pede_alvo', passo: 'p2')])
      expect(Autonomia::Automacao::Receita.esquema_valido?(receita.call([esperar_passo('p1')], 'selecao' => { 'etiqueta' => 'x' }))).to be(false)
    end
  end

  describe 'o salvar' do
    def problemas(selecao, tipo: 'contato.recorrente')
      receita = { 'gatilho' => { 'tipo' => tipo, 'frequencia' => 'diaria', 'hora' => 8, 'selecao' => selecao }, 'passos' => [esperar_passo('p1')] }
      Autonomia::Automacao::Receita.new(receita, conta: account, account_user: nil).problemas
    end

    # No contato, a condição do card não conta: sem nenhuma do contato, a seleção é vazia.
    it 'recusa a seleção sem nenhuma condição do alvo' do
      expect(problemas({ 'funil_id' => 1 })).to eq([I18n.t('autonomia.automacao.receita.selecao_vazia')])
    end

    it 'recusa condição do outro alvo, etiqueta e atributo que não são da conta, e etapa de outra conta', :aggregate_failures do
      expect(problemas({ 'etiqueta' => 'newsletter', 'funil_id' => 1 }))
        .to eq([I18n.t('autonomia.automacao.receita.selecao_de_outro_alvo', condicoes: 'funil_id')])
      expect(problemas({ 'etiqueta' => 'vip' })).to eq([I18n.t('autonomia.automacao.receita.etiqueta_de_fora', etiqueta: 'vip')])
      expect(problemas({ 'atributo' => { 'chave' => 'cpf', 'valor' => '123' } }))
        .to eq([I18n.t('autonomia.automacao.receita.atributo_de_fora', campo: 'cpf')])

      outra = create(:account)
      _, etapa_alheia = create_crm_pipeline(account: outra, user: create(:user, account: outra, role: :administrator))
      expect(problemas({ 'etapa_id' => etapa_alheia.id }, tipo: 'card.recorrente'))
        .to eq([I18n.t('autonomia.automacao.receita.etapa_de_fora', id: etapa_alheia.id)])
    end

    it 'recusa o responsável que não é da conta' do
      de_fora = create(:user, account: create(:account))
      expect(problemas({ 'responsavel_id' => de_fora.id }, tipo: 'card.recorrente'))
        .to eq([I18n.t('autonomia.automacao.receita.responsavel_de_fora')])
    end

    it 'recusa "fechado entre" com as pontas trocadas' do
      expect(problemas({ 'fechado_entre_dias' => { 'de' => 360, 'ate' => 330 } }, tipo: 'card.recorrente'))
        .to eq([I18n.t('autonomia.automacao.receita.faixa_invertida', de: 360, ate: 330)])
    end

    it 'aceita a seleção certa do card e do contato', :aggregate_failures do
      expect(problemas({ 'etiqueta' => 'newsletter' })).to be_empty
      expect(problemas({ 'situacao' => 'perdido', 'fechado_entre_dias' => { 'de' => 330, 'ate' => 360 } }, tipo: 'card.recorrente')).to be_empty
    end
  end
end
