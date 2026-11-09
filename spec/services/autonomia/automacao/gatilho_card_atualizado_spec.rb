require 'rails_helper'

# G27 (#2661): o gatilho "card atualizado". Nasce do próprio card (Crm::CardAvisaAutomacao, o único caminho para "o card
# mudou"): cada gravação soma o par [antes, agora] do valor e dos campos, e o commit enfileira um evento só, quando há
# automação com o gatilho; a escuta confere a mudança escolhida (o campo e a condição) e a Partida abre a execução. Vale
# a tela, a API, o upsert, a IA, o lote e os passos da automação. Tudo pela plataforma: o PATCH de verdade, o
# EventoDoCardJob e o AvancarJob.
RSpec.describe 'Automação livre: card atualizado', :automacao_motor, type: :request do
  include ActiveJob::TestHelper

  around { |example| with_modified_env(CRM_KANBAN_ENABLED: 'true') { example.run } }

  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:funil_e_etapa) { create_crm_pipeline(account: account, user: admin) }
  let(:funil) { funil_e_etapa.first }
  let(:novo) { funil_e_etapa.last }
  let(:operadora) { create_crm_stage(account: account, pipeline: funil, name: 'Enviar à operadora', position: 1) }
  let(:conversa) { create(:conversation, account: account, status: :open) }
  let(:card) do
    account.crm_cards.create!(pipeline: funil, stage: novo, title: 'Plano empresa', currency: 'BRL', value_cents: 1_000_000,
                              primary_conversation: conversa, contact: conversa.contact)
  end
  let(:execucoes) { Autonomia::Automacao::Execucao }
  let(:cadeia) { Autonomia::Automacao::Cadeia }

  before do
    ligar_motor(account)
    account.enable_features!('automacao_gatilhos')
    %w[documentos plano].each do |chave|
      account.custom_attribute_definitions.create!(attribute_key: chave, attribute_display_name: chave.capitalize,
                                                   attribute_model: :card_attribute, attribute_display_type: :text)
    end
    card
    operadora
    clear_enqueued_jobs
  end

  after { Current.reset }

  # Um job de cada vez, na ordem da fila: o job enfileirado dentro de outro só roda depois dele.
  def drenar
    drenados = [EventDispatcherJob, Autonomia::Automacao::EventoDoCardJob, Autonomia::Automacao::AvancarJob]
    40.times do
      job = enqueued_jobs.find { |item| drenados.include?(item[:job]) }
      return unless job

      enqueued_jobs.delete(job)
      job[:job].perform_now(*ActiveJob::Arguments.deserialize(job[:args]))
    end
    raise 'a fila não esvaziou em 40 jobs'
  end

  # A edição pela porta da frente: o mesmo PATCH da gaveta do card.
  def editar(alvo, campos, quem = admin)
    patch "/api/v1/accounts/#{account.id}/crm/cards/#{alvo.id}", params: campos, headers: auth_headers(quem), as: :json
    expect(response).to have_http_status(:ok)
    drenar
  end

  def atualizado(mudanca, passos = [esperar_passo('p1')])
    automacao_ligada(account, admin, passos, gatilho: { 'tipo' => 'card.atualizado', 'mudanca' => mudanca })
  end

  def gravar_passo(id, corpo)
    { 'id' => id, 'tipo' => 'acao', 'acao' => 'PATCH crm/cards/:id', 'descricao' => 'Gravar no card',
      'caminho' => { 'id' => { '$valor' => 'card.id' } }, 'corpo' => corpo }
  end

  def mover_passo(id, etapa)
    { 'id' => id, 'tipo' => 'acao', 'acao' => 'POST crm/cards/:id/move', 'descricao' => 'Mover o card',
      'caminho' => { 'id' => { '$valor' => 'card.id' } }, 'corpo' => { 'stage_id' => etapa.id } }
  end

  def vezes(definicao) = execucoes.where(automacao: definicao).count

  # A execução aberta no card segura a próxima (ja_aberta): fecha as abertas, para a próxima edição contar sozinha.
  def concluir_abertas
    execucoes.where.not(estado: 'concluida').update_all(estado: 'concluida', travada_em: nil, due_at: nil, finalizada_em: Time.current) # rubocop:disable Rails/SkipsModelValidations
  end

  def recusas(motivo) = have_received(:registrar_recusa).with(having_attributes(motivo: motivo), any_args)

  describe 'a condição escolhida' do
    it '"passou de" dispara na subida, uma vez, e de novo só depois de voltar para baixo', :aggregate_failures do
      definicao = atualizado({ 'campo' => 'valor', 'condicao' => 'passou_de', 'valor' => '50000' })

      editar(card, value_cents: 6_000_000)
      expect(vezes(definicao)).to eq(1)
      concluir_abertas

      editar(card, value_cents: 7_000_000)
      editar(card, value_cents: 4_000_000)
      expect(vezes(definicao)).to eq(1)

      editar(card, value_cents: 5_500_000)
      expect(vezes(definicao)).to eq(2)
    end

    it '"igual" num campo do card: só quando ele passa a valer aquilo, e não por outro campo', :aggregate_failures do
      definicao = atualizado({ 'campo' => 'atributo', 'chave' => 'documentos', 'condicao' => 'igual', 'valor' => 'completos' })

      editar(card, custom_attributes: { plano: 'ouro' })
      editar(card, custom_attributes: { documentos: 'faltando' })
      expect(vezes(definicao)).to eq(0)

      editar(card, custom_attributes: { documentos: 'completos' })
      expect(vezes(definicao)).to eq(1)
    end

    it '"mudou" e "maior que"; salvar o mesmo valor não é mudança', :aggregate_failures do
      mudou = atualizado({ 'campo' => 'atributo', 'chave' => 'plano', 'condicao' => 'mudou' })
      maior = atualizado({ 'campo' => 'valor', 'condicao' => 'maior_que', 'valor' => '20000' })

      editar(card, custom_attributes: { plano: 'prata' })
      editar(card, custom_attributes: { plano: 'prata' })
      editar(card, value_cents: 1_500_000)
      expect([vezes(mudou), vezes(maior)]).to eq([1, 0])

      editar(card, value_cents: 3_000_000)
      concluir_abertas
      editar(card, value_cents: 3_500_000)
      expect(vezes(maior)).to eq(2)
    end

    # O card guarda centavos; "igual a 25000" é em reais e compara número, não o texto "25000.0".
    it '"igual" no valor de venda compara o número em reais' do
      definicao = atualizado({ 'campo' => 'valor', 'condicao' => 'igual', 'valor' => '25000' })

      editar(card, value_cents: 2_500_000)

      expect(vezes(definicao)).to eq(1)
    end
  end

  # Exemplo 15 ("Cliente grande"): "card criado ou atualizado com valor acima de R$ 50 mil".
  describe 'o card criado conta como tudo vindo do vazio' do
    it 'o card que nasce com R$ 80 mil "passou de 50000"; o de R$ 10 mil, não', :aggregate_failures do
      definicao = atualizado({ 'campo' => 'valor', 'condicao' => 'passou_de', 'valor' => '50000' })
      criar = lambda do |cents|
        Crm::Cards::Creator.new(account: account, user: admin,
                                params: { pipeline_id: funil.id, stage_id: novo.id, title: 'Novo', currency: 'BRL', value_cents: cents })
                           .perform
      end

      grande = criar.call(8_000_000)
      criar.call(1_000_000)
      drenar

      expect(execucoes.where(automacao: definicao).pluck(:alvo_id)).to eq([grande.id])
    end

    # Cada commit leva o par dele: a criação com R$ 10 mil não passa; a edição para R$ 80 mil passa, uma vez.
    it 'criado com R$ 10 mil e editado para R$ 80 mil antes do job dispara uma vez, pela edição', :aggregate_failures do
      definicao = atualizado({ 'campo' => 'valor', 'condicao' => 'passou_de', 'valor' => '50000' })
      novo_card = Crm::Cards::Creator.new(account: account, user: admin,
                                          params: { pipeline_id: funil.id, stage_id: novo.id, title: 'Novo', currency: 'BRL',
                                                    value_cents: 1_000_000 }).perform

      editar(novo_card, value_cents: 8_000_000)

      expect(execucoes.where(automacao: definicao).pluck(:evento))
        .to eq(["card.atualizado:#{novo_card.id}:#{novo_card.reload.updated_at.utc.iso8601(6)}"])
    end
  end

  # Exemplo 8: "card completo: move para Enviar à operadora", depois que a IA marca os documentos no card.
  describe 'a gravação da IA no card' do
    let(:decisor) do
      Autonomia::ContatoPeloEmail::Completar::Campos.new(id: 'decisor', account: account,
                                                         campos: [{ 'chave' => 'documentos', 'destino' => 'card.atributo:documentos' }])
    end

    def ia_grava(valor) = Autonomia::Decisores::Aplicador.new(decisor: decisor, conversation: conversa, card: card).aplicar({ 'documentos' => valor })

    it 'a IA marca os documentos e a automação move o card para "Enviar à operadora"', :aggregate_failures do
      definicao = atualizado({ 'campo' => 'atributo', 'chave' => 'documentos', 'condicao' => 'igual', 'valor' => 'completos' },
                             [mover_passo('a1', operadora)])

      ia_grava('completos')
      drenar

      expect(execucoes.where(automacao: definicao).sole).to have_attributes(estado: 'concluida', alvo: card)
      expect(card.reload.stage).to eq(operadora)
    end

    it 'a IA que não muda nada (o campo já tinha valor) não dispara', :aggregate_failures do
      card.update!(custom_attributes: { 'documentos' => 'completos' })
      definicao = atualizado({ 'campo' => 'atributo', 'chave' => 'documentos', 'condicao' => 'mudou' })

      expect(ia_grava('outro').recusados).to have_key('documentos')
      drenar
      expect(vezes(definicao)).to eq(0)
    end
  end

  # A IA do funil (Crm::Ai::AttributeExtractorApplier) grava o campo do card pela conversa, sem atividade de edição.
  describe 'o campo que a IA do funil extrai da conversa' do
    it 'dispara o gatilho' do
      definicao = atualizado({ 'campo' => 'atributo', 'chave' => 'documentos', 'condicao' => 'igual', 'valor' => 'completos' })
      extraido = { card: [{ key: 'documentos', value: 'completos', confidence: 0.9, evidence: 'mandei tudo' }] }

      Crm::Ai::AttributeExtractorApplier.new(card: Crm::Card.find(card.id), extracted_attributes: extraido, prefix: '').perform
      drenar

      expect(vezes(definicao)).to eq(1)
    end
  end

  describe 'laço' do
    before { allow(cadeia).to receive(:registrar_recusa).and_call_original }

    # Sem a cadeia (a trava), a gravação do próprio passo dispararia a automação de novo, sem fim.
    it 'a automação que grava o próprio campo do gatilho roda uma vez: a gravação dela é auto-disparo', :aggregate_failures do
      definicao = atualizado({ 'campo' => 'valor', 'condicao' => 'mudou' }, [gravar_passo('a1', { 'value_cents' => 9_900_000 })])

      editar(card, value_cents: 2_000_000)

      expect(execucoes.where(automacao: definicao).pluck(:estado)).to eq(['concluida'])
      expect(cadeia).to recusas(:auto_disparo)
      expect(card.reload.value_cents).to eq(9_900_000)
    end

    it 'duas automações que se gravam uma à outra param no laço', :aggregate_failures do
      a = atualizado({ 'campo' => 'valor', 'condicao' => 'mudou' }, [gravar_passo('a1', { 'custom_attributes' => { 'plano' => 'a' } })])
      b = atualizado({ 'campo' => 'atributo', 'chave' => 'plano', 'condicao' => 'mudou' }, [gravar_passo('b1', { 'value_cents' => 7_700 })])

      editar(card, value_cents: 2_000_000)

      expect([vezes(a), vezes(b)]).to eq([1, 1])
      expect(cadeia).to recusas(:laco)
    end
  end

  describe 'a permissão de quem ligou' do
    it 'card que quem ligou não enxerga não abre execução', :aggregate_failures do
      agente = create(:user, account: account, role: :agent)
      funcao = create(:custom_role, account: account,
                                    permissions: %w[automation_manage conversation_manage crm_view crm_manage_cards crm_manage_pipelines])
      account.account_users.find_by(user: agente).update!(custom_role: funcao)
      definicao = atualizado({ 'campo' => 'atributo', 'chave' => 'plano', 'condicao' => 'mudou' })
      definicao.update!(ligada_por: agente)

      editar(card, custom_attributes: { plano: 'ouro' })

      expect(vezes(definicao)).to eq(0)
      expect(definicao.reload.ativa).to be(true)
    end

    # O disparo diria a quem não vê os valores que o card passou do limite (#2597).
    it 'o gatilho no valor de venda não dispara para quem ligou sem ver os valores; no campo, dispara', :aggregate_failures do
      agente = create(:user, account: account, role: :agent)
      funcao = create(:custom_role, account: account,
                                    permissions: %w[automation_manage conversation_manage crm_view crm_manage_cards crm_manage_pipelines])
      account.account_users.find_by(user: agente).update!(custom_role: funcao)
      create(:inbox_member, user: agente, inbox: conversa.inbox)
      card.update!(inbox: conversa.inbox)
      no_valor = atualizado({ 'campo' => 'valor', 'condicao' => 'mudou' }).tap { |definicao| definicao.update!(ligada_por: agente) }
      no_campo = atualizado({ 'campo' => 'atributo', 'chave' => 'plano', 'condicao' => 'mudou' })
                 .tap { |definicao| definicao.update!(ligada_por: agente) }

      editar(card, value_cents: 2_000_000, custom_attributes: { plano: 'ouro' })

      expect([vezes(no_valor), vezes(no_campo)]).to eq([0, 1])
    end
  end

  describe 'o gate' do
    def jobs_da_automacao = enqueued_jobs.count { |job| job[:job] == Autonomia::Automacao::EventoDoCardJob }

    it 'sem automação de card atualizado, a edição não enfileira' do
      automacao_ligada(account, admin, [esperar_passo('p1')], gatilho: { 'tipo' => 'card.ganho' })

      patch "/api/v1/accounts/#{account.id}/crm/cards/#{card.id}", params: { value_cents: 2 }, headers: auth_headers(admin), as: :json

      expect(jobs_da_automacao).to eq(0)
    end

    it 'com a automação, enfileira direto do card, sem webhook, Meta nem Google', :aggregate_failures do
      atualizado({ 'campo' => 'valor', 'condicao' => 'mudou' })

      patch "/api/v1/accounts/#{account.id}/crm/cards/#{card.id}", params: { value_cents: 2 }, headers: auth_headers(admin), as: :json

      fora = [Webhooks::CrmDeliveryJob, WebhookJob, Crm::MetaCapi::DispatchJob, Crm::GoogleOffline::RecordJob]
      expect(enqueued_jobs.map { |job| job[:job] } & fora).to be_empty
      expect(jobs_da_automacao).to eq(1)
    end
  end

  # Um caminho só (o próprio card): toda gravação pelo modelo conta, tenha ou não atividade de edição.
  describe 'de onde vem a mudança' do
    def jobs_da_automacao = enqueued_jobs.count { |job| job[:job] == Autonomia::Automacao::EventoDoCardJob }

    it 'a gravação em lote, sem atividade de edição, dispara em cada card', :aggregate_failures do
      definicao = atualizado({ 'campo' => 'atributo', 'chave' => 'documentos', 'condicao' => 'igual', 'valor' => 'completos' })
      outro = account.crm_cards.create!(pipeline: funil, stage: novo, title: 'Outro', currency: 'BRL')

      Crm::Card.transaction do
        [card, outro].each { |alvo| alvo.update!(custom_attributes: alvo.custom_attributes.to_h.merge('documentos' => 'completos')) }
      end
      drenar

      expect(Crm::Activity.where(card: [card, outro], event_type: 'update')).to be_empty
      expect(execucoes.where(automacao: definicao).pluck(:alvo_id)).to contain_exactly(card.id, outro.id)
    end

    it 'o upsert por external_id dispara', :aggregate_failures do
      definicao = atualizado({ 'campo' => 'atributo', 'chave' => 'plano', 'condicao' => 'igual', 'valor' => 'ouro' })
      card.update!(external_id: 'erp-7')
      base = { pipeline_id: funil.id, stage_id: novo.id, title: 'Plano empresa', external_id: 'erp-7' }

      params = { card: base.merge(custom_attributes: { plano: 'ouro' }) }
      post "/api/v1/accounts/#{account.id}/crm/cards", params: params, headers: auth_headers(admin), as: :json
      expect(response).to have_http_status(:ok).or have_http_status(:created)
      drenar

      expect(execucoes.where(automacao: definicao).sole.alvo).to eq(card)
    end

    it 'o passo de outra automação que grava o campo dispara', :aggregate_failures do
      grava = atualizado({ 'campo' => 'atributo', 'chave' => 'plano', 'condicao' => 'mudou' },
                         [gravar_passo('a1', { 'custom_attributes' => { 'documentos' => 'completos' } })])
      escuta = atualizado({ 'campo' => 'atributo', 'chave' => 'documentos', 'condicao' => 'igual', 'valor' => 'completos' })

      editar(card, custom_attributes: { plano: 'ouro' })

      expect([vezes(grava), vezes(escuta)]).to eq([1, 1])
      expect(card.reload.custom_attributes['documentos']).to eq('completos')
    end

    it 'mudança fora do valor e dos campos (título, última atividade) não enfileira' do
      atualizado({ 'campo' => 'valor', 'condicao' => 'mudou' })

      card.update!(title: 'Outro', last_activity_at: Time.current)

      expect(jobs_da_automacao).to eq(0)
    end

    # O after_commit vê só a última gravação em saved_changes; a soma guarda o antes da primeira.
    it 'várias gravações no mesmo commit viram um evento só, com o antes da primeira', :aggregate_failures do
      definicao = atualizado({ 'campo' => 'valor', 'condicao' => 'passou_de', 'valor' => '50000' })

      Crm::Card.transaction do
        card.update!(value_cents: 3_000_000)
        card.update!(custom_attributes: { 'plano' => 'ouro' })
        card.update!(value_cents: 6_000_000)
      end

      expect(jobs_da_automacao).to eq(1)
      dados = ActiveJob::Arguments.deserialize(enqueued_jobs.find { |job| job[:job] == Autonomia::Automacao::EventoDoCardJob }[:args]).first
      expect(dados.dig('changed_attributes', 'mudancas')).to eq('valor' => ['passou_de:50000'], 'atributo:plano' => [nil, 'ouro'])
      drenar
      expect(vezes(definicao)).to eq(1)
    end

    it 'a gravação desfeita (rollback) não enfileira' do
      atualizado({ 'campo' => 'valor', 'condicao' => 'mudou' })

      Crm::Card.transaction do
        card.update!(value_cents: 3_000_000)
        raise ActiveRecord::Rollback
      end

      expect(jobs_da_automacao).to eq(0)
    end

    # #2750, revisão: o savepoint desfeito leva só as gravações dele; as da transação de fora seguem no evento.
    it 'o savepoint desfeito (requires_new) não apaga o que a transação de fora gravou', :aggregate_failures do
      atualizado({ 'campo' => 'valor', 'condicao' => 'mudou' })

      Crm::Card.transaction do
        card.update!(value_cents: 3_000_000)
        Crm::Card.transaction(requires_new: true) do
          Crm::Card.find(card.id).update!(custom_attributes: { 'plano' => 'ouro' })
          card.update!(value_cents: 9_000_000)
          raise ActiveRecord::Rollback
        end
      end

      expect(jobs_da_automacao).to eq(1)
      dados = ActiveJob::Arguments.deserialize(enqueued_jobs.find { |job| job[:job] == Autonomia::Automacao::EventoDoCardJob }[:args]).first
      expect(dados.dig('changed_attributes', 'mudancas')).to eq('valor' => ['mudou:'])
    end
  end

  # #2750, revisão: o valor de venda é protegido (#2597). O job, a fila e o log do ActiveJob guardam os argumentos; o
  # evento leva só que o valor mudou e quais condições casaram, conferidas no commit.
  describe 'o valor de venda fora do evento' do
    def argumentos_do_job = enqueued_jobs.find { |job| job[:job] == Autonomia::Automacao::EventoDoCardJob }[:args]

    it 'o evento não leva o valor, nem em centavos nem em reais, e o gatilho dispara', :aggregate_failures do
      definicao = atualizado({ 'campo' => 'valor', 'condicao' => 'passou_de', 'valor' => '50000' })
      atualizado({ 'campo' => 'valor', 'condicao' => 'maior_que', 'valor' => '90000' })

      card.update!(value_cents: 6_543_210)

      expect(argumentos_do_job.to_json).not_to include('6543210', '65432.1', '1000000', '10000.0')
      dados = ActiveJob::Arguments.deserialize(argumentos_do_job).first
      expect(dados.dig('changed_attributes', 'mudancas')).to eq('valor' => ['passou_de:50000'])
      drenar
      expect(vezes(definicao)).to eq(1)
    end

    it 'sem condição no valor, o evento diz só que o valor mudou', :aggregate_failures do
      atualizado({ 'campo' => 'atributo', 'chave' => 'plano', 'condicao' => 'mudou' })

      card.update!(value_cents: 6_543_210, custom_attributes: { 'plano' => 'ouro' })

      dados = ActiveJob::Arguments.deserialize(argumentos_do_job).first
      expect(dados.dig('changed_attributes', 'mudancas')).to eq('valor' => [], 'atributo:plano' => [nil, 'ouro'])
    end
  end

  describe 'o salvar' do
    def problemas(mudanca, quem = admin)
      receita = { 'gatilho' => { 'tipo' => 'card.atualizado', 'mudanca' => mudanca }, 'passos' => [esperar_passo('p1')] }
      return :fora_do_esquema unless Autonomia::Automacao::Receita.esquema_valido?(receita)

      Autonomia::Automacao::Receita.new(receita, conta: account, account_user: account.account_users.find_by(user: quem)).problemas
    end

    it 'o esquema pede o valor nas condições com valor e a chave no campo personalizado', :aggregate_failures do
      expect(problemas({ 'campo' => 'valor', 'condicao' => 'passou_de' })).to eq(:fora_do_esquema)
      expect(problemas({ 'campo' => 'atributo', 'condicao' => 'mudou' })).to eq(:fora_do_esquema)
      expect(problemas({ 'campo' => 'valor', 'condicao' => 'mudou', 'valor' => '1' })).to eq(:fora_do_esquema)
      expect(problemas({ 'campo' => 'valor', 'condicao' => 'passou_de', 'valor' => '50000' })).to eq([])
    end

    it 'recusa campo que não é do card, número que não é número e o valor de venda para quem não o vê', :aggregate_failures do
      sem_valor = create(:user, account: account, role: :agent)
      funcao = create(:custom_role, account: account, permissions: %w[automation_manage crm_view crm_manage_pipelines])
      account.account_users.find_by(user: sem_valor).update!(custom_role: funcao)

      expect(problemas({ 'campo' => 'atributo', 'chave' => 'placa', 'condicao' => 'mudou' }))
        .to eq([I18n.t('autonomia.automacao.receita.campo_do_card_de_fora', campo: 'placa')])
      expect(problemas({ 'campo' => 'atributo', 'chave' => 'plano', 'condicao' => 'passou_de', 'valor' => '50.000,00' }))
        .to eq([I18n.t('autonomia.automacao.receita.mudanca_sem_numero')])
      expect(problemas({ 'campo' => 'atributo', 'chave' => 'plano', 'condicao' => 'igual', 'valor' => 'ouro' })).to eq([])
      expect(problemas({ 'campo' => 'valor', 'condicao' => 'mudou' }, sem_valor))
        .to eq([I18n.t('autonomia.automacao.receita.gatilho_valor_de_venda')])
    end
  end
end
