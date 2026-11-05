require 'rails_helper'

# Fechamento do épico #2414 (F9.6), exemplo 10 dos termos de aceite: "Cliente bravo vai direto para a gerente".
#
# > "Se um cliente estiver muito bravo, eu quero saber na hora e tirar ele da mão do robô." — Fernanda, gerente
#
# Montado como a dona montaria: pela API da tela, ligado por ela. O cliente escreve pelo WhatsApp oficial, o despacho
# da plataforma leva o evento ao motor, a IA (dublê) decide e resume, e o que sai para o cliente para no receptor de
# teste (F9.7). Desenho e lacunas: docs/automacao/F9-fechamento-20-exemplos.md.
RSpec.describe 'Fechamento #2414 · exemplo 10: cliente bravo vai direto para a gerente', :fechamento_automacao, type: :request do
  include ActiveJob::TestHelper

  let(:canal) { create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false) }
  let(:account) { canal.account }
  let(:inbox) { canal.inbox }
  let(:dona) { create(:user, account: account, role: :administrator, name: 'Carla Dona') }
  let(:fernanda) { create(:user, account: account, role: :agent, name: 'Fernanda Gerente') }
  let(:rafael) { create(:user, account: account, role: :agent, name: 'Rafael Vendas') }
  let(:paulo) { create(:contact, account: account, name: 'Paulo', email: 'paulo@exemplo.com', phone_number: '+5511900000001') }
  let(:contact_inbox) { create(:contact_inbox, inbox: inbox, contact: paulo, source_id: '5511900000001') }
  let(:conversa) do
    create(:conversation, account: account, inbox: inbox, contact: paulo, contact_inbox: contact_inbox, assignee: rafael, status: :open)
  end

  # A receita como o Guia ou o editor gravariam (passos 1 a 5 e 7 do termo).
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
              etiqueta('etiqueta_reclamacao', 'reclamacao'),
              { id: 'resumo', tipo: 'resumir', le: %w[mensagens_recentes], linhas: 3, destino: { avisar: { pessoas: [fernanda.id] } } },
              { id: 'acalmar', tipo: 'mensagem',
                texto: ['Entendi, ', { '$valor' => 'contato.nome' }, '. A Fernanda, gerente, já está vendo seu caso'] }
            ] },
          { nome: 'Irritado', chave: 'irritado', descricao: 'está irritado, mas sem reclamação grave',
            passos: [
              etiqueta('etiqueta_atencao', 'atencao'),
              { id: 'avisar_responsavel', tipo: 'avisar', para: { responsavel: true },
                texto: ['O cliente ', { '$valor' => 'contato.nome' }, ' está irritado. Vale olhar com carinho.'] }
            ] }
        ],
        nenhum: []
      }]
    }
  end

  let(:automacao) { montar_automacao(dona, account, nome: 'Cliente bravo vai para a gerente', receita: receita) }

  def etiqueta(id, nome)
    { id: id, tipo: 'acao', acao: 'PATCH conversations/:conversation_id/labels/alterar', descricao: "Pôr a etiqueta #{nome}",
      caminho: { conversation_id: { '$valor' => 'conversa.id' } }, corpo: { por: [nome] } }
  end

  def tom(caminho) = { 'caminho' => caminho, 'motivo' => 'o tom da mensagem' }

  def mencoes_para(pessoa) = Notification.where(user: pessoa, notification_type: 'conversation_mention')

  before do
    account.update!(locale: 'pt_BR')
    flags_do_piloto(account)
    [fernanda, rafael].each { |agente| create(:inbox_member, user: agente, inbox: inbox) }
    create(:label, account: account, title: 'reclamacao', description: 'Reclamação séria do cliente')
    create(:label, account: account, title: 'atencao', description: 'Cliente irritado')
    receptor_whatsapp_cloud
    conversa
    ligar_automacao(dona, account, automacao)
    clear_enqueued_jobs
  end

  after { Current.reset }

  context 'with a reclamação séria' do
    before do
      ia_responde(account, 'automacao_decidir' => tom('reclamacao_seria'),
                           'automacao_resumir' => { 'resumo' => 'Paulo diz que foi cobrado duas vezes e quer o estorno hoje.' })
      cliente_escreve(conversa, 'Vocês me cobraram duas vezes! Se não estornarem hoje vou no Procon.')
    end

    it 'passa a conversa para a Fernanda, marca como prioridade e põe a etiqueta reclamação', :aggregate_failures do
      conversa.reload
      expect(conversa.assignee).to eq(fernanda)
      expect(conversa.priority).to eq('urgent')
      expect(conversa.label_list).to include('reclamacao')
    end

    it 'a Fernanda recebe no sino o resumo do problema' do
      expect(mencoes_para(fernanda).count).to eq(1)
      resumo = conversa.messages.where(private: true).find_by('content LIKE ?', '%mention://user/%')
      expect(resumo.content).to include('Resumo', 'cobrado duas vezes', "mention://user/#{fernanda.id}/")
    end

    it 'o cliente recebe pelo WhatsApp oficial a mensagem com o nome dele, sem a palavra Automação', :aggregate_failures do
      saidas = chamadas_para('graph.facebook.com')
      expect(saidas.size).to eq(1)
      expect(saidas.sole.corpo).to include('to' => '5511900000001', 'type' => 'text')
      expect(saidas.sole.corpo.dig('text', 'body')).to eq('Entendi, Paulo. A Fernanda, gerente, já está vendo seu caso')
      expect(saidas.sole.corpo.to_json).not_to include('Automação')
    end

    it 'a IA lê a conversa, mas nunca o e-mail nem o telefone do cliente', :aggregate_failures do
      expect(ia_recebeu.size).to eq(2)
      enviado = ia_recebeu.to_json
      expect(enviado).to include('cobraram duas vezes')
      expect(enviado).not_to include('paulo@exemplo.com', '5511900000001')
    end

    it 'o histórico mostra cada passo feito, uma vez só, e o custo da IA', :aggregate_failures do
      expect(historico_de(automacao).map(&:first)).to eq(%w[tom gerente prioridade etiqueta_reclamacao resumo acalmar])
      expect(historico_de(automacao).map(&:second).uniq).to eq(['ok'])
      custo = Autonomia::Automacao::Registro.find_by!(automacao_id: automacao['id'], passo: 'tom').dados['ia']
      expect(custo).to include('tokens_entrada' => 800, 'tokens_saida' => 120)
    end

    it 'passo 6: espera a Fernanda responder por até 30 minutos; sem resposta, avisa o dono com o mesmo resumo' do
      # Só a metade "a equipe respondeu" da G11 (receita do passo combinada com a frente Motor G, #2414).
      abertas = FechamentoAutomacao::Lacunas.valor?('conversa.equipe_respondeu') ? [] : %w[G11]
      pending 'lacuna G11: o "esperar até" não tem o valor conversa.equipe_respondeu. ' \
              'Quando passar: esperar_ate 30 minutos depois do "acalmar"; se vencer, resumir avisando a dona'
      expect(abertas).to be_empty
    end

    it 'passo 2: tira a conversa da agente de IA' do
      abertas = FechamentoAutomacao::Lacunas.abertas(%w[G15])
      pending 'lacuna G15: não está provado que a agente de IA (Agentes) deixa a conversa quando ela é atribuída a uma pessoa'
      expect(abertas).to be_empty
    end
  end

  context 'with o cliente irritado, sem reclamação grave' do
    before do
      ia_responde(account, 'automacao_decidir' => tom('irritado'))
      cliente_escreve(conversa, 'Já é a terceira vez que pergunto e ninguém me responde direito.')
    end

    it 'põe a etiqueta atenção e avisa o responsável, sem tirar a conversa dele', :aggregate_failures do
      conversa.reload
      expect(conversa.label_list).to include('atencao')
      expect(conversa.assignee).to eq(rafael)
      expect(mencoes_para(rafael).count).to eq(1)
      expect(chamadas_para('graph.facebook.com')).to be_empty
    end
  end

  context 'with uma mensagem normal' do
    before do
      ia_responde(account, 'automacao_decidir' => tom('nenhum'))
      cliente_escreve(conversa, 'Bom dia! Qual o horário de vocês no sábado?')
    end

    # A nota privada do "decidir" (F7.4) sai também no "nenhum se aplica": com o gatilho em toda mensagem do cliente,
    # cada mensagem normal ganha uma nota para a equipe. Registrado no doc (seção 7) para decisão.
    it 'para aqui: nada muda na conversa e nada sai para o cliente; fica só a nota da IA para a equipe', :aggregate_failures do
      conversa.reload
      expect([conversa.assignee, conversa.priority, conversa.label_list]).to eq([rafael, nil, []])
      expect(chamadas_para('graph.facebook.com')).to be_empty
      expect(historico_de(automacao).map(&:first)).to eq(['tom'])
      expect(conversa.messages.outgoing.where(private: false)).to be_empty
      expect(conversa.messages.where(private: true).count).to eq(1)
    end
  end

  it 'passo 8: conversa resolvida com a etiqueta reclamação vira card no quadro "Melhorias" com o resumo' do
    abertas = FechamentoAutomacao::Lacunas.abertas(%w[G4])
    pending 'lacuna G4: criar card num funil/etapa não é passo da Automação livre (POST crm/cards fora da lista)'
    expect(abertas).to be_empty
  end
end
