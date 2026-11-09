require 'rails_helper'

# Fechamento do épico #2414 (F9.6), exemplo 10 dos termos de aceite fora do WhatsApp oficial (#2701, F9 §6.2): "toda
# mensagem do cliente, em qualquer canal". O spec do exemplo (exemplo_10_cliente_bravo_spec.rb) prova cada passo pelo
# WhatsApp oficial; aqui a mesma receita roda com o cliente escrevendo pelo webhook real de cada canal.
#
# - Híbrido: a caixa é a da Cloud com a conexão do Híbrido. A mensagem do cliente entra pelo webhook da Cloud, e a
#   resposta, com a janela de 24 h aberta (o cliente acabou de escrever), sai pela Cloud e não pela WAHA.
# - Instagram: a mensagem entra pelo webhook do Instagram, e a resposta sai pela API do Instagram.
RSpec.describe 'Fechamento #2414 · exemplo 10 nos outros canais', :fechamento_automacao, type: :request do
  include ActiveJob::TestHelper

  let(:dona) { create(:user, account: account, role: :administrator, name: 'Carla Dona') }
  let(:fernanda) { create(:user, account: account, role: :agent, name: 'Fernanda Gerente') }

  # Os passos 1 a 5 do termo, como o exemplo 10 do WhatsApp oficial. O 6, o 7 e o 8 estão provados lá; o que muda de
  # canal para canal é a entrada e a saída.
  let(:receita) do
    {
      gatilho: { tipo: 'mensagem.criada', filtros: [{ campo: { '$valor' => 'mensagem.tipo' }, op: 'igual', valor: 'recebida' }] },
      passos: [{
        id: 'tom', tipo: 'decidir', le: %w[mensagens_recentes], pergunta: 'Qual é o tom desta mensagem do cliente?',
        caminhos: [
          { nome: 'Reclamação séria', chave: 'reclamacao_seria', descricao: 'reclama de algo grave, ameaça cancelar ou ir à justiça',
            passos: [
              { id: 'gerente', tipo: 'acao', acao: 'POST conversations/:conversation_id/assignments', descricao: 'Passar para a Fernanda',
                caminho: { conversation_id: { '$valor' => 'conversa.id' } }, corpo: { assignee_id: fernanda.id } },
              { id: 'prioridade', tipo: 'acao', acao: 'POST conversations/:id/toggle_priority', descricao: 'Marcar como prioridade',
                caminho: { id: { '$valor' => 'conversa.id' } }, corpo: { priority: 'urgent' } },
              { id: 'etiqueta_reclamacao', tipo: 'acao', acao: 'PATCH conversations/:conversation_id/labels/alterar',
                descricao: 'Pôr a etiqueta reclamacao', caminho: { conversation_id: { '$valor' => 'conversa.id' } },
                corpo: { por: ['reclamacao'] } },
              { id: 'resumo', tipo: 'resumir', le: %w[mensagens_recentes], linhas: 3, destino: { avisar: { pessoas: [fernanda.id] } } },
              { id: 'acalmar', tipo: 'mensagem',
                texto: ['Entendi, ', { '$valor' => 'contato.nome' }, '. A Fernanda, gerente, já está vendo seu caso'] }
            ] },
          { nome: 'Irritado', chave: 'irritado', descricao: 'está irritado, mas sem reclamação grave',
            passos: [{ id: 'etiqueta_atencao', tipo: 'acao', acao: 'PATCH conversations/:conversation_id/labels/alterar',
                       descricao: 'Pôr a etiqueta atencao', caminho: { conversation_id: { '$valor' => 'conversa.id' } },
                       corpo: { por: ['atencao'] } }] }
        ],
        nenhum: []
      }]
    }
  end

  let(:automacao) { montar_automacao(dona, account, nome: 'Cliente bravo vai para a gerente', receita: receita) }

  def tom(caminho) = { 'caminho' => caminho, 'motivo' => 'o tom da mensagem' }
  def conversa = inbox.conversations.sole
  def mencoes_para(pessoa) = Notification.where(user: pessoa, notification_type: 'conversation_mention')

  before do
    account.update!(locale: 'pt_BR')
    flags_do_piloto(account)
    # Sem distribuição automática: quem pega a conversa é a automação, não a fila da caixa.
    inbox.update!(enable_auto_assignment: false)
    create(:inbox_member, user: fernanda, inbox: inbox)
    create(:label, account: account, title: 'reclamacao', description: 'Reclamação séria do cliente')
    create(:label, account: account, title: 'atencao', description: 'Cliente irritado')
    ligar_automacao(dona, account, automacao)
    clear_enqueued_jobs
  end

  after { Current.reset }

  shared_examples 'o cliente bravo vai para a gerente' do
    before do
      ia_responde(account, 'automacao_decidir' => tom('reclamacao_seria'),
                           'automacao_resumir' => { 'resumo' => 'Paulo diz que foi cobrado duas vezes e quer o estorno hoje.' })
      cliente_escreve('Vocês me cobraram duas vezes! Se não estornarem hoje vou no Procon.')
    end

    it 'a mensagem que entrou pelo canal começa a automação: Fernanda, prioridade e etiqueta', :aggregate_failures do
      expect(conversa.messages.incoming.sole.content).to include('cobraram duas vezes')
      expect(conversa.assignee).to eq(fernanda)
      expect(conversa.priority).to eq('urgent')
      expect(conversa.label_list).to include('reclamacao')
    end

    it 'a Fernanda recebe no sino o resumo do problema' do
      expect(mencoes_para(fernanda).count).to eq(1)
    end

    it 'o histórico mostra cada passo feito, uma vez só', :aggregate_failures do
      expect(historico_de(automacao).map(&:first)).to eq(%w[tom gerente prioridade etiqueta_reclamacao resumo acalmar])
      expect(historico_de(automacao).map(&:second).uniq).to eq(['ok'])
    end

    it 'a resposta ao cliente sai pelo canal dele, com o nome dele, sem a palavra Automação', :aggregate_failures do
      expect(saidas.size).to eq(1)
      expect(texto_que_saiu(saidas.sole)).to eq('Entendi, Paulo. A Fernanda, gerente, já está vendo seu caso')
      expect(saidas.sole.corpo.to_json).not_to include('Automação')
      expect(conversa.messages.outgoing.where(private: false).sole.status).to eq('sent')
    end
  end

  shared_examples 'a mensagem normal não mexe em nada' do
    before do
      ia_responde(account, 'automacao_decidir' => tom('nenhum'))
      cliente_escreve('Bom dia! Qual o horário de vocês no sábado?')
    end

    it 'decide, para ali, e nada sai para o cliente', :aggregate_failures do
      expect(historico_de(automacao).map(&:first)).to eq(['tom'])
      expect([conversa.assignee, conversa.priority, conversa.label_list]).to eq([nil, nil, []])
      expect(saidas).to be_empty
    end
  end

  context 'with o WhatsApp Híbrido' do
    let(:canal) { create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false) }
    let(:account) { canal.account }
    let(:inbox) { canal.inbox }

    around do |exemplo|
      with_modified_env(WAHA_API_URL: FechamentoAutomacao::Canais::WAHA, WAHA_API_KEY: 'chave-do-fechamento',
                        WHATSAPP_HYBRID_ACCOUNT_IDS: '*') { exemplo.run }
    end

    before do
      WhatsappHybrid::Connection.create!(account: account, inbox: inbox, session_name: 'hybrid-fechamento', webhook_secret: 'segredo')
      WhatsappHybrid::Config.forget_inbox(inbox.id)
      receptor_whatsapp_cloud
      receptor_waha
    end

    def cliente_escreve(texto) = cliente_escreve_pela_cloud(canal, remetente: '5511900000002', nome: 'Paulo', texto: texto)
    def saidas = chamadas_para('graph.facebook.com')
    def texto_que_saiu(chamada) = chamada.corpo.dig('text', 'body')

    it 'a caixa é Híbrido de verdade (conexão do motor e conta liberada)' do
      expect(WhatsappHybrid::Config.hybrid_inbox?(inbox.id) && WhatsappHybrid::Config.account_allowed?(account.id)).to be(true)
    end

    it_behaves_like 'o cliente bravo vai para a gerente' do
      it 'com a janela aberta, a resposta sai pela Cloud para o número do cliente, e nada passa pela WAHA', :aggregate_failures do
        expect(saidas.sole.corpo).to include('to' => '5511900000002', 'type' => 'text')
        expect(chamadas_para_a_waha).to be_empty
      end
    end

    it_behaves_like 'a mensagem normal não mexe em nada'
  end

  context 'with o Instagram' do
    let(:canal) { create(:channel_instagram) }
    let(:account) { canal.account }
    let(:inbox) { canal.inbox }
    let(:cliente_no_instagram) { "ig-paulo-#{SecureRandom.hex(4)}" }

    before { receptor_instagram }

    def cliente_escreve(texto) = cliente_escreve_pelo_instagram(canal, remetente: cliente_no_instagram, nome: 'Paulo', texto: texto)
    def saidas = respostas_do_instagram
    def texto_que_saiu(chamada) = chamada.corpo.dig('message', 'text')

    it_behaves_like 'o cliente bravo vai para a gerente' do
      it 'a resposta vai para o Paulo no Instagram, pela conta da caixa', :aggregate_failures do
        expect(saidas.sole.caminho).to eq("/v22.0/#{canal.instagram_id}/messages")
        expect(saidas.sole.corpo.dig('recipient', 'id')).to eq(cliente_no_instagram)
      end
    end

    it_behaves_like 'a mensagem normal não mexe em nada'
  end
end
