require 'rails_helper'

# Fechamento do épico #2414 (#2570, Parte A): os itens "a conferir" provados contra o texto do aceite, pela API da
# tela e pelo motor de verdade. F4.4 e F5.4 não têm spec aqui: o veredito está no PR e nas Issues deles.
RSpec.describe 'Fechamento #2414 · itens a conferir', :automacao_motor, :fechamento_automacao, type: :request do
  include ActiveJob::TestHelper

  let(:account) { create(:account, locale: 'pt_BR') }
  let(:dona) { create(:user, account: account, role: :administrator, name: 'Carla Dona') }
  let(:conversa) { create(:conversation, account: account, status: :open) }

  before { flags_do_piloto(account) }

  after { Current.reset }

  def rodar(automacao, alvo = conversa)
    definicao = Autonomia::Automacao::Definicao.find(automacao['id'])
    perform_enqueued_jobs(only: Autonomia::Automacao::AvancarJob) { comecar(definicao, alvo) }
  end

  # F3.7: "Quem ligou perdeu acesso à caixa: a automação pausa e aparece 'Assumir e religar'." A pausa e o religar pelo
  # motor estão em spec/services/autonomia/automacao/executor_spec.rb ("tirado da caixa durante a espera"); aqui, o
  # que a tela recebe da API.
  describe 'F3.7 · quem ligou perdeu a caixa' do
    let(:funcao) { create(:custom_role, account: account, permissions: %w[automation_manage conversation_manage]) }
    let(:agente) { create(:user, account: account, role: :agent, name: 'Rafael Vendas') }
    let(:receita) do
      { gatilho: { tipo: 'conversa.resolvida' },
        passos: [esperar_passo('espera'), prioridade_passo('prioridade')] }
    end

    before do
      account.account_users.find_by(user: agente).update!(custom_role: funcao)
      create(:inbox_member, user: agente, inbox: conversa.inbox)
    end

    it 'pausa, o histórico diz "Assuma e religue", e quem pode religa pela API e passa a ser quem ligou', :aggregate_failures do
      automacao = montar_automacao(agente, account, nome: 'Prioridade depois de resolver', receita: receita)
      ligar_automacao(agente, account, automacao)
      rodar(automacao)
      InboxMember.find_by(user: agente, inbox: conversa.inbox).destroy!

      travel(1.day + 1.minute) { varrer }

      get "#{api_automacoes(account)}/#{automacao['id']}", headers: dona.create_new_auth_token, as: :json
      expect(response.parsed_body['ativa']).to be(false)
      get "#{api_automacoes(account)}/#{automacao['id']}/historico", headers: dona.create_new_auth_token, as: :json
      expect(response.body).to include('Quem ligou a automação não tem mais acesso aqui. Assuma e religue.')
      expect(conversa.reload.priority).to be_nil

      ligar_automacao(dona, account, automacao)
      expect(response.parsed_body['ligada_por']).to include('id' => dona.id)
    end
  end

  # F3.10: "Etiqueta e atributo criados pela automação levam descrição."
  describe 'F3.10 · o que a automação cria leva descrição' do
    let(:criar_etiqueta) do
      { id: 'etiqueta', tipo: 'acao', acao: 'POST labels', descricao: 'Criar a etiqueta pós-venda', corpo: { title: 'pos-venda' } }
    end
    let(:criar_atributo) do
      { id: 'atributo', tipo: 'acao', acao: 'POST custom_attribute_definitions', descricao: 'Criar o atributo placa',
        corpo: { attribute_display_name: 'Placa', attribute_key: 'placa', attribute_model: 'contact_attribute',
                 attribute_display_type: 'text' } }
    end

    def receita_com(*passos) = { gatilho: { tipo: 'conversa.resolvida' }, passos: passos }

    def recusada(receita)
      post api_automacoes(account), params: { nome: 'Sem descrição', receita: receita }, headers: dona.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      response.parsed_body['problemas']
    end

    it 'sem descrição, a tela recebe a recusa em frase e nada é salvo', :aggregate_failures do
      expect(recusada(receita_com(criar_etiqueta))).to include(a_string_including('falta description;', 'leva descrição'))
      expect(recusada(receita_com(criar_atributo))).to include(a_string_including('falta attribute_description;', 'leva descrição'))
      expect(Autonomia::Automacao::Definicao.where(account: account)).to be_empty
    end

    it 'com descrição, a etiqueta e o atributo nascem com ela', :aggregate_failures do
      etiqueta = criar_etiqueta.deep_merge(corpo: { description: 'Cliente que comprou' })
      atributo = criar_atributo.deep_merge(corpo: { attribute_description: 'Placa do carro do cliente' })
      automacao = montar_automacao(dona, account, nome: 'Cria o que precisa', receita: receita_com(etiqueta, atributo))
      ligar_automacao(dona, account, automacao)

      rodar(automacao)

      expect(account.labels.find_by!(title: 'pos-venda').description).to eq('Cliente que comprou')
      expect(account.custom_attribute_definitions.find_by!(attribute_key: 'placa').attribute_description).to eq('Placa do carro do cliente')
    end
  end

  # F4.4: "Fora da janela de 24 h do WhatsApp, o passo usa o caminho já validado ou para com o motivo; nunca falha
  # calado." Decisão do Rodrigo (#2573): fora da janela, a automação PARA nesse ponto, sem seguir sem mandar.
  describe 'F4.4 · fora da janela de 24 h, a automação para' do
    let(:canal) { create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false) }
    let(:account) { canal.account.tap { |conta| conta.update!(locale: 'pt_BR') } }
    let(:contato) { create(:contact, account: account, name: 'Paulo', phone_number: '+5511900000001') }
    let(:contact_inbox) { create(:contact_inbox, inbox: canal.inbox, contact: contato, source_id: '5511900000001') }
    let(:conversa) { create(:conversation, account: account, inbox: canal.inbox, contact: contato, contact_inbox: contact_inbox) }

    it 'a mensagem não sai, a execução fecha parada com o motivo, e o passo seguinte não roda', :aggregate_failures do
      create(:message, conversation: conversa, account: account, inbox: canal.inbox, message_type: :incoming, content: 'oi',
                       created_at: 30.hours.ago)
      receita = { gatilho: { tipo: 'conversa.resolvida' },
                  passos: [mensagem_passo('renovacao', 'Seu seguro vence este mês.'), prioridade_passo('depois')] }
      automacao = montar_automacao(dona, account, nome: 'Renovação', receita: receita)
      ligar_automacao(dona, account, automacao)

      execucao = rodar(automacao)

      expect(conversa.messages.outgoing.where(private: false)).to be_empty
      expect(execucao.reload.estado).to eq('parada')
      expect(historico_de(automacao).last).to eq(%w[renovacao falhou fora_da_janela])
      expect(conversa.reload.priority).to be_nil
    end
  end

  # F6.7: "Card movido pela automação não é desfeito pela IA do funil na avaliação seguinte, mesmo com 'Mover
  # automaticamente' ligado." As duas metades têm spec (spec/services/crm/ai/movimento_da_automacao_livre_spec.rb e
  # evaluator_movimento_da_automacao_spec.rb); aqui as duas juntas: o motor move e a IA do funil avalia em seguida.
  describe 'F6.7 · a IA do funil não desfaz o movimento da automação' do
    around { |exemplo| with_modified_env(CRM_KANBAN_ENABLED: 'true', CRM_AI_ENABLED: 'true') { exemplo.run } }

    let(:funil_e_etapa) do
      funil, etapa = create_crm_pipeline(account: account, user: dona)
      funil.update!(metadata: { 'ai' => { 'auto_move_enabled' => true } })
      [funil, etapa]
    end
    let(:proposta) { create_crm_stage(account: account, pipeline: funil_e_etapa.first, name: 'Proposta', position: 1) }
    let(:card) do
      account.crm_cards.create!(pipeline: funil_e_etapa.first, stage: funil_e_etapa.last, title: 'Pedido', currency: 'BRL',
                                primary_conversation: conversa, contact: conversa.contact)
    end

    it 'o motor leva o card para Proposta, e a avaliação seguinte da IA não o tira de lá', :aggregate_failures do
      mover = { id: 'mover', tipo: 'acao', acao: 'POST crm/cards/:id/move', descricao: 'Levar para Proposta',
                caminho: { id: card.id }, corpo: { stage_id: proposta.id } }
      automacao = montar_automacao(dona, account, nome: 'Resolvida vai para Proposta',
                                                  receita: { gatilho: { tipo: 'conversa.resolvida' }, passos: [mover] })
      ligar_automacao(dona, account, automacao)
      rodar(automacao)
      expect(card.reload.stage).to eq(proposta)

      allow(Crm::Ai::CredentialResolver).to receive(:new)
        .and_return(instance_double(Crm::Ai::CredentialResolver, configured?: true, resolve: { api_key: 'test' }))
      allow(Crm::Ai::StageClassifier).to receive(:new).and_return(
        instance_double(Crm::Ai::StageClassifier,
                        perform: { suggested_stage_id: funil_e_etapa.last.id, confidence: 0.99, reasoning: 'x', model_used: 'm' }
                                   .with_indifferent_access)
      )

      resultado = Crm::Ai::Evaluator.new(card: card, trigger: 'message').perform

      expect(resultado).to have_attributes(status: :skipped, error: 'automacao_mexeu_na_etapa')
      expect(card.reload.stage).to eq(proposta)
    end
  end
end
