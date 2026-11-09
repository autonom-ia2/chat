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

    # Revisão do #2780: escolher o card antes de olhar a visibilidade lia vazio quando o de topo era de outra caixa.
    it 'pula o card de topo que quem lê não vê e lê o próximo que ele vê', :aggregate_failures do
      oculto = account.crm_cards.create!(pipeline: documentacao.pipeline, stage: documentacao, title: 'De outra caixa', currency: 'BRL',
                                         status: :open, primary_conversation: conversa, contact: conversa.contact,
                                         inbox: create(:inbox, account: account))
      visivel = card(documentacao, titulo: 'Da caixa da conversa')
      funcao = create(:custom_role, account: account, permissions: %w[automation_manage crm_manage_pipelines])
      agente.account_users.find_by(account: account).update!(custom_role: funcao)
      create(:inbox_member, user: agente, inbox: conversa.inbox)

      expect(ler('card.titulo')).to eq(oculto.title)
      expect(ler('card.titulo', quem: agente)).to eq(visivel.title)
    end
  end

  describe 'a mensagem tem foto ou PDF' do
    def mensagem_com(arquivo, tipo, file_type, meta: {})
      mensagem = create(:message, conversation: conversa, account: account, message_type: :incoming, content: nil)
      upload = Rack::Test::UploadedFile.new(Rails.root.join("spec/assets/#{arquivo}"), tipo)
      mensagem.attachments.create!(account: account, file_type: file_type, file: upload, meta: meta)
      mensagem
    end

    # A régua do ex.14 (termos de aceite, passos 2 e 5): "a cada foto ou PDF que chega". O áudio não é documento.
    it 'diz sim para foto e PDF, e não para áudio, outro arquivo e texto', :aggregate_failures do
      texto = create(:message, conversation: conversa, account: account, message_type: :incoming, content: 'já mando')

      expect(ler('mensagem.tem_anexo', mensagem: mensagem_com('sample.png', 'image/png', :image))).to be(true)
      expect(ler('mensagem.tem_anexo', mensagem: mensagem_com('sample.pdf', 'application/pdf', :file))).to be(true)
      expect(ler('mensagem.tem_anexo', mensagem: mensagem_com('sample.mp3', 'audio/mpeg', :audio))).to be(false)
      expect(ler('mensagem.tem_anexo', mensagem: mensagem_com('contacts.csv', 'text/csv', :file))).to be(false)
      expect(ler('mensagem.tem_anexo', mensagem: texto)).to be(false)
    end

    # Revisão do #2780: a figurinha do WhatsApp chega como `image` (com `meta.is_sticker`) e não é documento; a imagem
    # sem arquivo (só o link externo) também não.
    it 'diz não para figurinha e para imagem sem arquivo, e sim para a foto', :aggregate_failures do
      figurinha = mensagem_com('booking_small.webp', 'image/webp', :image, meta: { 'is_sticker' => true })
      sem_arquivo = create(:message, conversation: conversa, account: account, message_type: :incoming, content: nil)
      sem_arquivo.attachments.create!(account: account, file_type: :image, external_url: 'https://example.com/foto.png')

      expect(ler('mensagem.tem_anexo', mensagem: figurinha)).to be(false)
      expect(ler('mensagem.tem_anexo', mensagem: sem_arquivo)).to be(false)
      expect(ler('mensagem.tem_anexo', mensagem: mensagem_com('booking_small.jpg', 'image/jpeg', :image))).to be(true)
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

    # Decisão 9 do Rodrigo (#2780, 09/11): o texto que a pessoa escreve pode levar o valor da venda, como o "Só se". A
    # permissão de quem salva fica no spec do #2597 (spec/enterprise/.../valor_de_venda_spec.rb).
    describe 'o valor da venda no texto escrito pela pessoa (#2780, decisão 9)' do
      let(:valor) { { '$valor' => 'card.valor' } }

      def gravar(id, folha)
        { 'id' => id, 'tipo' => 'acao', 'acao' => 'POST conversations/:id/custom_attributes', 'descricao' => 'Gravar',
          'caminho' => { 'id' => { '$valor' => 'conversa.id' } }, 'corpo' => { 'merge' => true, 'custom_attributes' => { 'valor' => folha } } }
      end

      it 'aceita o valor no "Só se", no texto da mensagem e do aviso e no atributo da conversa', :aggregate_failures do
        account.custom_attribute_definitions.create!(attribute_key: 'valor', attribute_display_name: 'Valor',
                                                     attribute_model: 'conversation_attribute', attribute_display_type: 'text')
        caro = { 'campo' => valor, 'op' => 'maior', 'valor' => 1000 }
        se = { 'id' => 's1', 'tipo' => 'se', 'condicao' => caro, 'entao' => [mensagem_passo('m1', 'Valor: ', valor)], 'senao' => [] }

        expect(problemas(se, avisar_passo('v1', { 'pessoas' => [admin.id] }, 'Valor: ', valor), filtros: [caro])).to eq([])
        expect(problemas(gravar('a1', valor), gravar('a2', { '$texto' => ['R$ ', valor] }))).to eq([])
      end
    end

    it 'aceita "tem anexo" só com uma das opções', :aggregate_failures do
      fora = { 'campo' => { '$valor' => 'mensagem.tem_anexo' }, 'op' => 'igual', 'valor' => 'pdf' }

      expect(problemas(filtros: [fora])).to include(a_string_including('mensagem.tem_anexo'))
    end
  end

  # #2780, decisão 9: com a chave de quem ligou, o texto e o corpo escritos pela pessoa levam o valor da venda.
  describe 'o valor da venda no texto, com a chave de quem ligou' do
    include ActiveJob::TestHelper

    before do
      ligar_motor(account)
      ligar_mensagens(account)
    end

    it 'a mensagem da automação de conversa sai com o valor', :aggregate_failures do
      card(documentacao).update!(value_cents: 250_000)
      definicao = automacao_ligada(account, admin, [mensagem_passo('m1', 'Valor: ', { '$valor' => 'card.valor' })],
                                   gatilho: { 'tipo' => 'mensagem.criada' })
      mensagem = create(:message, conversation: conversa, account: account, message_type: :incoming, content: 'oi')

      perform_enqueued_jobs(only: Autonomia::Automacao::AvancarJob) do
        Autonomia::Automacao::Partida.new(definicao: definicao, alvo: conversa, chave_gatilho: 'mensagem.criada', mensagem: mensagem).call
      end
      execucao = Autonomia::Automacao::Execucao.where(automacao: definicao).last

      expect(Autonomia::Automacao::Registro.where(execucao: execucao).pluck(:passo, :resultado)).to eq([%w[m1 ok]])
      expect(conversa.messages.where(message_type: :outgoing).pluck(:content).join).to include('2500')
    end

    it 'o texto e o corpo leem o valor, na conversa e no card', :aggregate_failures do
      do_card = card(documentacao)
      do_card.update!(value_cents: 250_000)
      folha = { 'custom_attributes' => { 'valor' => { '$valor' => 'card.valor' } } }

      [conversa, do_card].each do |alvo|
        valores = Autonomia::Automacao::Valores.new(alvo: alvo, quem: admin)
        expect(Autonomia::Automacao::Texto.new(['Valor: ', { '$valor' => 'card.valor' }], valores).montar).to include('2500')
        expect(Autonomia::Automacao::Corpo.new(folha, valores: valores, conta: account).montar.motivo).to be_nil
      end
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

    # Decisão 19: a âncora do "em outro registro" (o campo do card da conversa) e origem.card.* no ramo também leem o
    # card da conversa.
    it 'pausa sem a chave de funis quando a âncora ou o ramo (origem.card.*) leem o card da conversa', :aggregate_failures do
      funcao = create(:custom_role, account: account, permissions: %w[automation_manage crm_manage_pipelines])
      agente.account_users.find_by(account: account).update!(custom_role: funcao)
      create(:custom_attribute_definition, account: account, attribute_key: 'indicado_por', attribute_display_name: 'Indicado por',
                                           attribute_model: 'card_attribute', attribute_display_type: 'contato')
      aberto = { 'campo' => { '$valor' => 'origem.card.status' }, 'op' => 'igual', 'valor' => 'open' }
      se_aberto = { 'id' => 's1', 'tipo' => 'se', 'condicao' => aberto, 'entao' => [], 'senao' => [] }
      ancora = { 'de' => 'contato_do_campo', 'campo' => { '$valor' => 'card.atributos.indicado_por' }, 'usar' => 'contato' }
      ramo = ->(id, registro, passos) { { 'id' => id, 'tipo' => 'em_outro_registro', 'registro' => registro, 'passos' => passos } }
      pela_ancora = automacao_ligada(account, agente, [ramo.call('o1', ancora, [esperar_passo('p1')])], gatilho: { 'tipo' => 'mensagem.criada' })
      pela_origem = automacao_ligada(account, agente, [ramo.call('o2', { 'de' => 'cards_do_contato' }, [se_aberto])],
                                     gatilho: { 'tipo' => 'mensagem.criada' })

      expect([pela_ancora, pela_origem].map { |automacao| Autonomia::Automacao::Acesso.new(automacao).motivo }).to eq([nil, nil])
      funcao.update!(permissions: %w[automation_manage])

      expect([pela_ancora, pela_origem].map { |automacao| Autonomia::Automacao::Acesso.new(automacao.reload).motivo })
        .to eq(%w[sem_permissao_funil sem_permissao_funil])
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
