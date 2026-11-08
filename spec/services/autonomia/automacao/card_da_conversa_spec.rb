require 'rails_helper'

# #2716: o gatilho de conversa lê o card da conversa, só para ler, e o filtro da mensagem sabe se ela tem anexo.
RSpec.describe 'Automação livre: o card da conversa e o anexo da mensagem', :automacao_motor do # rubocop:disable RSpec/DescribeClass
  around { |example| with_modified_env(CRM_KANBAN_ENABLED: 'true') { example.run } }

  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agente) { create(:user, account: account, role: :agent) }
  let(:funil_e_etapa) { create_crm_pipeline(account: account, user: admin) }
  let(:documentacao) { create_crm_stage(account: account, pipeline: funil_e_etapa.first, name: 'Documentação', position: 1) }
  let(:conversa) { create(:conversation, account: account, status: :open) }

  def card(etapa, status: :open, titulo: 'Seguro auto')
    account.crm_cards.create!(pipeline: etapa.pipeline, stage: etapa, title: titulo, currency: 'BRL', status: status,
                              primary_conversation: conversa, contact: conversa.contact, inbox: conversa.inbox)
  end

  def ler(caminho, quem: admin, mensagem: nil)
    Autonomia::Automacao::Valores.new(alvo: conversa, quem: quem, mensagem: mensagem).ler(caminho)
  end

  describe 'ler o card da conversa' do
    it 'lê o assunto atual: o card aberto antes do que já fechou', :aggregate_failures do
      card(funil_e_etapa.last, status: :won, titulo: 'Seguro antigo')
      atual = card(documentacao)

      expect(ler('card.etapa_id')).to eq(documentacao.id)
      expect(ler('card.funil_id')).to eq(documentacao.pipeline_id)
      expect(ler('card.titulo')).to eq(atual.title)
    end

    it 'lê vazio sem a chave de funis de quem lê, sem pessoa e sem card', :aggregate_failures do
      expect(ler('card.etapa_id')).to be_nil
      card(documentacao)

      expect(ler('card.etapa_id', quem: agente)).to be_nil
      expect(ler('card.etapa_id', quem: nil)).to be_nil
      expect(ler('card.etapa_id')).to eq(documentacao.id)
    end

    it 'lê vazio para quem tem a chave de funis mas não vê o card (fora da caixa da conversa)', :aggregate_failures do
      card(documentacao)
      funcao = create(:custom_role, account: account, permissions: %w[automation_manage crm_manage_pipelines])
      agente.account_users.find_by(account: account).update!(custom_role: funcao)

      expect(ler('card.etapa_id', quem: agente)).to be_nil
      create(:inbox_member, user: agente, inbox: conversa.inbox)
      expect(ler('card.etapa_id', quem: agente)).to eq(documentacao.id)
    end
  end

  describe 'a mensagem tem anexo' do
    it 'diz sim só quando a mensagem traz arquivo', :aggregate_failures do
      com = create(:message, conversation: conversa, account: account, message_type: :incoming, content: nil)
      pdf = Rack::Test::UploadedFile.new(Rails.root.join('spec/assets/sample.pdf'), 'application/pdf')
      com.attachments.create!(account: account, file_type: :file, file: pdf)
      sem = create(:message, conversation: conversa, account: account, message_type: :incoming, content: 'já mando')

      expect(ler('mensagem.tem_anexo', mensagem: com)).to be(true)
      expect(ler('mensagem.tem_anexo', mensagem: sem)).to be(false)
    end
  end

  describe 'o salvar' do
    def problemas(*passos, filtros: [])
      receita = { 'gatilho' => { 'tipo' => 'mensagem.criada', 'filtros' => filtros }, 'passos' => passos }
      Autonomia::Automacao::Receita.new(receita, conta: account, account_user: nil).problemas
    end

    before do
      ligar_motor(account)
      ligar_mensagens(account)
    end

    it 'aceita o card no filtro, no "Só se" e no texto', :aggregate_failures do
      filtro = { 'campo' => { '$valor' => 'card.etapa_id' }, 'op' => 'igual', 'valor' => documentacao.id }
      anexo = { 'campo' => { '$valor' => 'mensagem.tem_anexo' }, 'op' => 'igual', 'valor' => true }
      se = { 'id' => 's1', 'tipo' => 'se', 'condicao' => filtro, 'entao' => [], 'senao' => [] }

      expect(problemas(se, mensagem_passo('m1', 'Seu card: ', { '$valor' => 'card.titulo' }), filtros: [filtro, anexo])).to eq([])
    end

    it 'recusa o card no caminho e o id dele no corpo: a automação de conversa não age no card', :aggregate_failures do
      mover = { 'id' => 'a1', 'tipo' => 'acao', 'acao' => 'POST crm/cards/:id/move', 'descricao' => 'Mover',
                'caminho' => { 'id' => { '$valor' => 'card.id' } }, 'corpo' => { 'stage_id' => documentacao.id } }
      nota = { 'id' => 'a2', 'tipo' => 'acao', 'acao' => 'POST conversations/:id/custom_attributes', 'descricao' => 'Gravar',
               'caminho' => { 'id' => { '$valor' => 'conversa.id' } },
               'corpo' => { 'custom_attributes' => { 'card' => { '$valor' => 'card.id' } } } }
      frase = ->(passo) { I18n.t('autonomia.automacao.receita.card_da_conversa_so_le', passo: passo, caminho: 'card.id') }

      expect(problemas(mover)).to include(frase.call('a1'))
      expect(problemas(nota)).to include(frase.call('a2'))
    end

    it 'aceita copiar um campo do card no corpo: é ler' do
      account.custom_attribute_definitions.create!(attribute_key: 'card', attribute_display_name: 'Card',
                                                   attribute_model: 'conversation_attribute', attribute_display_type: 'text')
      copiar = { 'id' => 'a3', 'tipo' => 'acao', 'acao' => 'POST conversations/:id/custom_attributes', 'descricao' => 'Gravar',
                 'caminho' => { 'id' => { '$valor' => 'conversa.id' } },
                 'corpo' => { 'merge' => true, 'custom_attributes' => { 'card' => { '$valor' => 'card.titulo' } } } }

      expect(problemas(copiar)).to eq([])
    end

    it 'aceita "tem anexo" só com uma das opções', :aggregate_failures do
      fora = { 'campo' => { '$valor' => 'mensagem.tem_anexo' }, 'op' => 'igual', 'valor' => 'pdf' }

      expect(problemas(filtros: [fora])).to include(a_string_including('mensagem.tem_anexo'))
    end
  end

  describe 'quem ligou' do
    it 'pausa quando perde a chave de funis, em vez de ler o card vazio', :aggregate_failures do
      funcao = create(:custom_role, account: account, permissions: %w[automation_manage crm_manage_pipelines])
      agente.account_users.find_by(account: account).update!(custom_role: funcao)
      filtro = { 'campo' => { '$valor' => 'card.etapa_id' }, 'op' => 'igual', 'valor' => documentacao.id }
      automacao = automacao_ligada(account, agente, [esperar_passo('p1')], gatilho: { 'tipo' => 'mensagem.criada', 'filtros' => [filtro] })
      sem_card = automacao_ligada(account, agente, [esperar_passo('p1')], gatilho: { 'tipo' => 'mensagem.criada' })

      expect(Autonomia::Automacao::Acesso.new(automacao).motivo).to be_nil
      funcao.update!(permissions: %w[automation_manage])

      expect(Autonomia::Automacao::Acesso.new(automacao.reload).motivo).to eq('sem_permissao_funil')
      expect(Autonomia::Automacao::Acesso.new(sem_card.reload).motivo).to be_nil
    end

    it 'a execução que começou numa versão que lê o card também pede a chave, mesmo que a versão ativa não leia mais' do
      funcao = create(:custom_role, account: account, permissions: %w[automation_manage crm_manage_pipelines])
      agente.account_users.find_by(account: account).update!(custom_role: funcao)
      filtro = { 'campo' => { '$valor' => 'card.etapa_id' }, 'op' => 'igual', 'valor' => documentacao.id }
      automacao = automacao_ligada(account, agente, [esperar_passo('p1')], gatilho: { 'tipo' => 'mensagem.criada', 'filtros' => [filtro] })
      Autonomia::Automacao::Execucao.create!(account: account, automacao: automacao, versao: automacao.versao_ativa, alvo: conversa,
                                             chave_gatilho: 'mensagem.criada', cursor: 'p1')
      automacao.salvar_versao!(receita: { 'gatilho' => { 'tipo' => 'mensagem.criada' }, 'passos' => [esperar_passo('p1')] }, autor: agente)
      funcao.update!(permissions: %w[automation_manage])

      expect(Autonomia::Automacao::Acesso.new(automacao.reload).motivo).to eq('sem_permissao_funil')
    end
  end
end
