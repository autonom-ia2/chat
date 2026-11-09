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

    describe 'o valor da venda só decide (#2780, Rodrigo 09/11)' do
      let(:valor) { { '$valor' => 'card.valor' } }
      let(:caro) { { 'campo' => valor, 'op' => 'maior', 'valor' => 1000 } }

      def so_decide(passo) = I18n.t('autonomia.automacao.receita.valor_protegido_so_decide', passo: passo, caminho: 'card.valor')

      def gravar(id, folha)
        { 'id' => id, 'tipo' => 'acao', 'acao' => 'POST conversations/:id/custom_attributes', 'descricao' => 'Gravar',
          'caminho' => { 'id' => { '$valor' => 'conversa.id' } }, 'corpo' => { 'merge' => true, 'custom_attributes' => { 'valor' => folha } } }
      end

      it 'aceita o valor da venda no "Só se" do gatilho e na condição de um passo' do
        se = { 'id' => 's1', 'tipo' => 'se', 'condicao' => caro, 'entao' => [mensagem_passo('m1', 'Cliente especial')], 'senao' => [] }

        expect(problemas(se, filtros: [caro])).to eq([])
      end

      it 'recusa o valor da venda no texto da mensagem, do aviso e do retorno', :aggregate_failures do
        retorno = { 'id' => 'r1', 'tipo' => 'retorno', 'titulo' => ['Ligar: ', valor], 'daqui' => { 'valor' => 1, 'unidade' => 'dias' },
                    'para' => { 'quem' => 'responsavel' } }

        expect(problemas(mensagem_passo('m1', 'Valor: ', valor))).to include(so_decide('m1'))
        expect(problemas(avisar_passo('v1', { 'pessoas' => [admin.id] }, 'Valor: ', valor))).to include(so_decide('v1'))
        expect(problemas(retorno)).to include(so_decide('r1'))
      end

      it 'recusa o valor da venda num atributo da conversa, copiado ou dentro de um texto', :aggregate_failures do
        account.custom_attribute_definitions.create!(attribute_key: 'valor', attribute_display_name: 'Valor',
                                                     attribute_model: 'conversation_attribute', attribute_display_type: 'text')

        expect(problemas(gravar('a1', valor))).to include(so_decide('a1'))
        expect(problemas(gravar('a2', { '$texto' => ['R$ ', valor] }))).to include(so_decide('a2'))
      end

      it 'na automação de card também: aceita na condição e recusa no texto da mensagem', :aggregate_failures do
        de_card = lambda do |passo|
          receita = { 'gatilho' => { 'tipo' => 'card.ganho' }, 'passos' => [passo] }
          Autonomia::Automacao::Receita.new(receita, conta: account, account_user: admin.account_users.first).problemas
        end
        se = { 'id' => 's1', 'tipo' => 'se', 'condicao' => caro, 'entao' => [mensagem_passo('m2', 'Cliente especial')], 'senao' => [] }

        expect(de_card.call(se)).not_to include(so_decide('s1'), so_decide('m2'))
        expect(de_card.call(mensagem_passo('m1', 'Valor: ', valor))).to include(so_decide('m1'))
      end
    end

    it 'aceita "tem anexo" só com uma das opções', :aggregate_failures do
      fora = { 'campo' => { '$valor' => 'mensagem.tem_anexo' }, 'op' => 'igual', 'valor' => 'pdf' }

      expect(problemas(filtros: [fora])).to include(a_string_including('mensagem.tem_anexo'))
    end
  end

  # #2780: a versão gravada antes da decisão, com o valor da venda no texto, não o escreve ao rodar. O "Só se" segue
  # decidindo por ele.
  describe 'a versão antiga com o valor da venda no texto' do
    include ActiveJob::TestHelper

    before do
      ligar_motor(account)
      ligar_mensagens(account)
    end

    def versao_antiga(passos)
      definicao = create(:autonomia_automacao, account: account, ligada_por: admin)
      versao = definicao.versoes.new(account: account, numero: 1, autor: admin, digest: SecureRandom.hex(32),
                                     receita: { 'gatilho' => { 'tipo' => 'mensagem.criada' }, 'passos' => passos })
      versao.save!(validate: false)
      definicao.update!(versao_ativa: versao, ativa: true)
      definicao
    end

    it 'decide pelo valor, mas a mensagem que o escreveria pula sem mandar nada', :aggregate_failures do
      card(documentacao).update!(value_cents: 250_000)
      valor = { '$valor' => 'card.valor' }
      se = { 'id' => 's1', 'tipo' => 'se', 'condicao' => { 'campo' => valor, 'op' => 'maior', 'valor' => 1000 },
             'entao' => [mensagem_passo('m1', 'Valor: ', valor)], 'senao' => [] }
      definicao = versao_antiga([se])
      mensagem = create(:message, conversation: conversa, account: account, message_type: :incoming, content: 'oi')

      perform_enqueued_jobs(only: Autonomia::Automacao::AvancarJob) do
        Autonomia::Automacao::Partida.new(definicao: definicao, alvo: conversa, chave_gatilho: 'mensagem.criada', mensagem: mensagem).call
      end
      execucao = Autonomia::Automacao::Execucao.where(automacao: definicao).last

      expect(Autonomia::Automacao::Registro.where(execucao: execucao).order(:id).pluck(:passo, :resultado, :motivo).last)
        .to eq(%w[m1 pulado faltou_valor])
      expect(conversa.messages.where(message_type: :outgoing).pluck(:content).join).not_to include('2500')
    end

    it 'o valor calculado do corpo também não o escreve, e a condição o lê', :aggregate_failures do
      card(documentacao).update!(value_cents: 250_000)
      contexto = Autonomia::Automacao::Contexto.de(conversa)
      valores = Autonomia::Automacao::Valores.new(alvo: contexto, quem: admin)
      folha = { 'custom_attributes' => { 'valor' => { '$valor' => 'card.valor' } } }
      corpo = Autonomia::Automacao::Corpo.new(folha, valores: valores, conta: account)

      expect(corpo.montar.motivo).to eq('faltou_valor')
      expect(Autonomia::Automacao::Texto.new(['Valor: ', { '$valor' => 'card.valor' }], valores).montar).to be_nil
      expect(valores.ler('card.valor')).to eq(2500)
    end

    # Decisão 3 do Rodrigo (09/11): vale em qualquer automação, não só na de conversa. No card, quem ligou com a chave
    # lê o valor para decidir, mas não o escreve.
    it 'na automação de card, quem tem a chave lê o valor para decidir e não o escreve', :aggregate_failures do
      do_card = card(documentacao)
      do_card.update!(value_cents: 250_000)
      valores = Autonomia::Automacao::Valores.new(alvo: do_card, quem: admin)

      expect(valores.ler('card.valor')).to eq(2500)
      expect(valores.ler_para_escrever('card.valor')).to be_nil
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
