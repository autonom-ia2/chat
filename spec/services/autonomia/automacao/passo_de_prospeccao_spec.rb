require 'rails_helper'

# O passo "prospecção" (#2414 G21, #2706): buscar empresas pela Prospecção, esperar a conferência de WhatsApp e criar os
# cards; e marcar a recusa do lead. A busca roda sempre com o provedor de teste (MockProvider): nunca chama o Google.
RSpec.describe Autonomia::Automacao::PassoDeProspeccao, :automacao_motor do
  include ActiveJob::TestHelper

  around { |exemplo| with_modified_env(CRM_KANBAN_ENABLED: 'true') { exemplo.run } }

  let(:account) { create(:account) }
  let(:dona) { create(:user, account: account, role: :administrator, name: 'Débora') }
  let(:funil_e_etapa) { create_crm_pipeline(account: account, user: dona, name: 'Prospecção') }
  let(:etapa) { funil_e_etapa.last }
  let(:etiqueta) { create(:label, account: account, title: 'prospeccao-novembro') }
  let(:origem) do
    Autonomia::Prospecting::SearchRunner.new(account: account, user: dona,
                                             params: { query: 'escritório de contabilidade', location: 'Campinas, SP',
                                                       requested_limit: 3 }).perform.search
  end
  let(:buscar) do
    { 'id' => 'p1', 'tipo' => 'prospeccao', 'faz' => 'buscar', 'busca_id' => origem.id, 'quantas' => 3,
      'etapa_id' => etapa.id, 'etiquetas' => [etiqueta.id] }
  end
  let(:recusar) { { 'id' => 'r1', 'tipo' => 'prospeccao', 'faz' => 'recusar' } }
  let(:conversa) { create(:conversation, account: account, status: :open) }

  before do
    ligar_motor(account)
    account.enable_features!('automacao_gatilhos')
    Autonomia::Prospecting::Config.enable_for!(account)
    Autonomia::Prospecting::Setting.for_account(account).update!(provider: 'mock')
    allow(Autonomia::Prospecting::WhatsappVerifier).to receive(:available_for?).and_return(true)
  end

  after { Current.reset }

  def frase(chave, **valores) = I18n.t("autonomia.automacao.receita.#{chave}", passo: 'p1', **valores)

  # O gatilho da conta (conta.recorrente, G7): toda segunda às 8h, alvo = a própria conta.
  def conta_recorrente = { 'tipo' => 'conta.recorrente', 'frequencia' => 'semanal', 'dia_da_semana' => 1, 'hora' => 8 }

  def problemas(passo, gatilho: { 'tipo' => 'conversa.resolvida' }, quem: dona)
    receita = { 'gatilho' => gatilho, 'passos' => [passo] }
    Autonomia::Automacao::Receita.new(receita, conta: account, account_user: AccountUser.find_by(account: account, user: quem)).problemas
  end

  # A execução do recorrente da conta (G7): o alvo é a própria conta.
  def execucao_da_conta(passos = [buscar], por: dona)
    definicao = automacao_ligada(account, dona, passos, gatilho: conta_recorrente)
    execucao = Autonomia::Automacao::Partida.new(definicao: definicao, alvo: account, chave_gatilho: 'conta.recorrente').call
    # Quem ligou perdeu a chave depois de a execução começar: a rodada confere de novo.
    definicao.update!(ligada_por: por)
    execucao
  end

  # O recusar roda no alvo da conversa (o lead é o do contato dela).
  def execucao_na_conversa(passos = [recusar])
    comecar(automacao_ligada(account, dona, passos), conversa)
  end

  # Função com a Prospecção e o criar card, sem contact_manage: na tela, não põe etiqueta no contato.
  def agente_sem_contato
    agente = create(:user, account: account, role: :agent)
    funcao = create(:custom_role, account: account, permissions: %w[automation_manage prospecting_manage crm_view crm_manage_cards])
    account.account_users.find_by(user: agente).update!(custom_role: funcao)
    agente
  end

  def rodar(execucao, passo = buscar, por: dona)
    acesso = Autonomia::Automacao::Acesso.new(execucao.automacao.reload)
    expect(acesso.usuario).to eq(por)
    Autonomia::Automacao::PassoDeAcao.executar(execucao: execucao, passo: passo, valores: nil, acesso: acesso)
  end

  def buscas_da(execucao)
    Autonomia::Prospecting::Search.where("metadata -> 'automacao' ->> 'execucao_id' = ?", execucao.id.to_s)
  end

  def conferir(busca, verificados:, sem_whatsapp: [])
    leads = Autonomia::Prospecting::Lead.where(id: busca.metadata['lead_ids']).order(:search_rank).to_a
    { verified: verificados, not_whatsapp: sem_whatsapp }.each do |status, posicoes|
      posicoes.each do |posicao|
        lead = leads[posicao]
        lead.update!(metadata: lead.metadata.merge('whatsapp_verification' => { 'status' => status.to_s }))
      end
    end
    leads
  end

  describe 'ao salvar' do
    it 'recusa o buscar em gatilho de conversa ou de card: cada execução faria uma busca paga' do
      expect(problemas(buscar)).to eq([frase(:prospeccao_so_sem_alvo)])
      expect(problemas(buscar, gatilho: { 'tipo' => 'card.ganho' })).to include(frase(:prospeccao_so_sem_alvo))
    end

    it 'aceita o recusar em qualquer gatilho' do
      expect(problemas(recusar)).to be_empty
    end

    it 'recusa com a Prospecção desligada na conta' do
      Autonomia::Prospecting::Config.disable_for!(account)

      expect(problemas(recusar)).to eq([I18n.t('autonomia.automacao.receita.prospeccao_desligada', passo: 'r1')])
    end

    it 'recusa quem não tem a chave da Prospecção' do
      agente = create(:user, account: account, role: :agent)

      expect(problemas(recusar, quem: agente)).to eq([I18n.t('autonomia.automacao.receita.prospeccao_sem_permissao', passo: 'r1')])
    end

    context 'with o gatilho da conta (conta.recorrente, G7)' do
      def problemas(passo, quem: dona) = super(passo, gatilho: conta_recorrente, quem: quem)

      it 'o recusar pede alvo: no gatilho da conta não salva' do
        expect(problemas(recusar)).to include(I18n.t('autonomia.automacao.receita.passo_pede_alvo', passo: 'r1'))
      end

      it 'com etiquetas, recusa a função que cria card mas não muda contato (sem contact_manage)', :aggregate_failures do
        agente = agente_sem_contato

        expect(problemas(buscar, quem: agente)).to include(frase(:prospeccao_sem_permissao))
        expect(problemas(buscar.merge('etiquetas' => []), quem: agente)).not_to include(frase(:prospeccao_sem_permissao))
      end

      it 'recusa a etapa num funil que a função de quem salva não vê (acesso por funil do CRM)', :aggregate_failures do
        agente = agente_sem_contato
        sem_etiqueta = buscar.merge('etiquetas' => [])
        fechado = frase(:prospeccao_etapa_de_funil_fechado, id: etapa.id)
        expect(problemas(sem_etiqueta, quem: agente)).not_to include(fechado)

        caixa = create_crm_inbox(account: account, members: [agente])
        caixa_alheia = create_crm_inbox(account: account, name: 'Filial')
        vendas = create_crm_pipeline(account: account, user: dona, name: 'Vendas').first
        Crm::PipelineInbox.create!(account: account, inbox: caixa, pipeline: vendas)
        Crm::PipelineInbox.create!(account: account, inbox: caixa_alheia, pipeline: funil_e_etapa.first)
        acesso = Crm::InboxAgentAccess.create!(account: account, inbox: caixa, user: agente, all_pipelines: false, triage: false,
                                               only_own: false)
        acesso.agent_pipelines.create!(account: account, pipeline: vendas)

        expect(problemas(sem_etiqueta, quem: agente)).to include(fechado)
        expect(problemas(sem_etiqueta)).not_to include(fechado)
      end

      it 'aceita o buscar pronto' do
        expect(problemas(buscar)).to be_empty
      end

      it 'recusa busca, etapa e etiqueta que não são desta conta' do
        outra = create(:account)
        busca_de_fora = Autonomia::Prospecting::Search.create!(account: outra, query: 'x', location: 'y', provider: 'mock',
                                                               requested_limit: 1, status: :completed)
        passo = buscar.merge('busca_id' => busca_de_fora.id, 'etapa_id' => 999_999, 'etiquetas' => [888_888])

        expect(problemas(passo)).to contain_exactly(frase(:prospeccao_busca_de_fora, id: busca_de_fora.id),
                                                    frase(:etapa_do_card_de_fora, id: 999_999),
                                                    frase(:campanha_etiqueta_de_fora, id: 888_888))
      end
    end
  end

  describe 'buscar' do
    # Contrato com a G7: o conta.recorrente tem a conta como alvo e é o único gatilho que aceita o buscar.

    it 'roda a busca pela Prospecção, sem cache, e espera a conferência de WhatsApp', :aggregate_failures do
      origem
      execucao = execucao_da_conta

      resultado = nil
      expect { resultado = rodar(execucao) }.to have_enqueued_job(Autonomia::Prospecting::VerifyWhatsappJob)

      busca = buscas_da(execucao).sole
      expect(busca).not_to eq(origem)
      expect(busca.provider).to eq('mock')
      expect([busca.query, busca.location, busca.requested_limit]).to eq(['escritório de contabilidade', 'Campinas, SP', 3])
      expect(resultado.tipo).to eq(:esperar)
      expect(resultado.dados['ate']).to be_within(5.seconds).of(2.minutes.from_now)
    end

    it 'enquanto a conferência não termina, espera de novo sem rodar outra busca' do
      origem
      execucao = execucao_da_conta
      rodar(execucao)
      conferir(buscas_da(execucao).sole, verificados: [0])

      expect(rodar(execucao).tipo).to eq(:esperar)
      expect(buscas_da(execucao).count).to eq(1)
    end

    it 'conferida, cria um card por empresa com WhatsApp e põe as etiquetas no contato', :aggregate_failures do
      origem
      execucao = execucao_da_conta
      rodar(execucao)
      leads = conferir(buscas_da(execucao).sole, verificados: [0, 2], sem_whatsapp: [1])

      resultado = rodar(execucao)

      expect([resultado.tipo, resultado.motivo]).to eq([:ok, nil])
      expect(resultado.dados).to include('empresas' => 3, 'com_whatsapp' => 2, 'cards_criados' => 2, 'sem_resposta' => 0)
      cards = Crm::Card.where(account: account, stage: etapa)
      expect(cards.count).to eq(2)
      expect(leads.map { |lead| lead.reload.crm_card_id.present? }).to eq([true, false, true])
      expect(cards.map { |card| card.contact.label_list }).to all(eq(['prospeccao-novembro']))
    end

    it 'grava no registro os ids dos cards criados agora, nunca o do card que já existia (contrato com a G58)', :aggregate_failures do
      origem
      execucao = execucao_da_conta
      rodar(execucao)
      conferir(buscas_da(execucao).sole, verificados: [0, 2], sem_whatsapp: [1])

      resultado = rodar(execucao)

      expect(resultado.dados['card_ids']).to match_array(Crm::Card.where(account: account, stage: etapa).ids)
      expect(rodar(execucao).dados).to include('cards_criados' => 0, 'card_ids' => [])
    end

    it 'repetir a rodada não cria card de novo' do
      origem
      execucao = execucao_da_conta
      rodar(execucao)
      conferir(buscas_da(execucao).sole, verificados: [0], sem_whatsapp: [1, 2])
      rodar(execucao)

      resultado = rodar(execucao)

      expect(resultado.dados).to include('cards_criados' => 0, 'ja_tinham_card' => 1)
      expect(Crm::Card.where(account: account).count).to eq(1)
    end

    it 'passado o prazo, segue com quem já foi conferido e diz que faltou conferir', :aggregate_failures do
      origem
      execucao = execucao_da_conta
      rodar(execucao)
      conferir(buscas_da(execucao).sole, verificados: [1])

      resultado = travel(2.hours + 1.minute) { rodar(execucao) }

      expect([resultado.tipo, resultado.motivo]).to eq([:ok, 'conferencia_no_prazo'])
      expect(resultado.dados).to include('cards_criados' => 1, 'sem_resposta' => 2)
    end

    it 'a espera nunca passa do prazo' do
      origem
      execucao = execucao_da_conta
      rodar(execucao)
      busca = buscas_da(execucao).sole

      resultado = travel_to(busca.created_at + 2.hours - 30.seconds) { rodar(execucao) }

      expect(resultado.dados['ate']).to eq(busca.created_at + 2.hours)
    end

    it 'sem WhatsApp na conta para conferir, para antes de pagar a busca' do
      allow(Autonomia::Prospecting::WhatsappVerifier).to receive(:available_for?).and_return(false)
      origem
      execucao = execucao_da_conta

      resultado = rodar(execucao)

      expect([resultado.tipo, resultado.motivo]).to eq([:permanente, 'prospeccao_sem_whatsapp'])
      expect(buscas_da(execucao)).to be_empty
    end

    it 'sem a chave do Google configurada, para sem tentar de novo' do
      origem
      configuracao = Autonomia::Prospecting::Setting.for_account(account)
      configuracao.update!(provider: 'google_places')
      allow(configuracao).to receive(:google_places_configured?).and_return(false)
      allow(Autonomia::Prospecting::Setting).to receive(:for_account).and_return(configuracao)
      execucao = execucao_da_conta

      expect(rodar(execucao).motivo).to eq('prospeccao_sem_chave_google')
      expect(buscas_da(execucao)).to be_empty
    end

    it 'a busca que falhou depois de pagar o Google não é repetida' do
      origem
      execucao = execucao_da_conta
      Autonomia::Prospecting::Search.create!(account: account, query: 'x', location: 'y', provider: 'mock', requested_limit: 3,
                                             status: :failed, consumed_api_units: 2,
                                             metadata: { 'automacao' => { 'execucao_id' => execucao.id, 'passo' => 'p1' } })

      resultado = rodar(execucao)

      expect([resultado.tipo, resultado.motivo]).to eq([:permanente, 'busca_falhou_paga'])
      expect(buscas_da(execucao).count).to eq(1)
    end

    it 'a busca que ficou no meio (processo caiu na chamada ao Google) não é repetida' do
      origem
      execucao = execucao_da_conta
      Autonomia::Prospecting::Search.create!(account: account, query: 'x', location: 'y', provider: 'mock', requested_limit: 3,
                                             status: :pending,
                                             metadata: { 'automacao' => { 'execucao_id' => execucao.id, 'passo' => 'p1' } })

      resultado = rodar(execucao)

      expect([resultado.tipo, resultado.motivo]).to eq([:permanente, 'busca_interrompida'])
      expect(buscas_da(execucao).count).to eq(1)
    end

    it 'a fila da conferência que falha não perde a busca paga: espera e segue no prazo' do
      origem
      execucao = execucao_da_conta
      allow(Autonomia::Prospecting::LeadWorkQueue).to receive(:after_search).and_raise(Redis::CannotConnectError)

      expect(rodar(execucao).tipo).to eq(:esperar)
      expect(buscas_da(execucao).completed.count).to eq(1)
    end

    it 'o provedor fora do ar é erro passageiro: a ação tenta de novo' do
      origem
      execucao = execucao_da_conta
      allow(Autonomia::Prospecting::Providers::MockProvider).to receive(:new)
        .and_raise(Autonomia::Prospecting::SearchRunner::ProviderError, 'fora')

      resultado = rodar(execucao)

      expect([resultado.tipo, resultado.motivo]).to eq([:passageiro, 'busca_sem_resposta'])
    end

    it 'a busca que quem ligou não vê mais para a execução' do
      execucao = execucao_da_conta
      passo = buscar.merge('busca_id' => 999_999)

      resultado = rodar(execucao, passo)

      expect([resultado.tipo, resultado.motivo]).to eq([:permanente, 'busca_sumiu'])
    end

    # A Receita recusa o buscar fora do gatilho da conta; a receita que chegar assim mesmo pula ao rodar.
    it 'num alvo que não é a conta, pula sem buscar' do
      origem
      execucao = execucao_da_conta
      allow(execucao).to receive(:alvo).and_return(conversa)

      expect(rodar(execucao).motivo).to eq('prospeccao_so_sem_alvo')
      expect(buscas_da(execucao)).to be_empty
    end

    it 'quem ligou sem o mudar contato pausa antes de buscar e etiquetar', :aggregate_failures do
      agente = agente_sem_contato
      execucao = execucao_da_conta(por: agente)

      expect(rodar(execucao, por: agente).motivo).to eq('quem_ligou_sem_permissao_prospeccao')
      expect(buscas_da(execucao)).to be_empty
    end

    it 'quem ligou sem a chave da Prospecção pausa a automação' do
      agente = create(:user, account: account, role: :agent)
      execucao = execucao_da_conta(por: agente)

      expect(rodar(execucao, por: agente).tipo).to eq(:sem_acesso)
    end
  end

  describe 'recusar' do
    let(:contato) { conversa.contact }

    it 'grava a recusa no lead do contato, que deixa de receber campanhas', :aggregate_failures do
      lead = conferir(origem, verificados: []).first
      lead.update!(contact: contato)
      execucao = execucao_na_conversa

      resultado = rodar(execucao, recusar)

      expect(resultado.tipo).to eq(:ok)
      expect(resultado.dados).to eq('contato_id' => contato.id, 'leads' => [lead.id])
      expect(lead.reload.consent_refused_at).to be_present
      expect(lead.consent_refused_by).to eq(dona)
      expect(contato.reload).to be_opted_out
    end

    it 'contato que não veio da Prospecção pula, com o motivo' do
      execucao = execucao_na_conversa

      expect(rodar(execucao, recusar).motivo).to eq('sem_lead_da_prospeccao')
    end
  end
end
