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

  # O que vem depois do "acalmar": nada aqui; o passo 6 (G11) põe a espera pela Fernanda.
  let(:depois_de_acalmar) { [] }

  # A receita como o Guia ou o editor gravariam (passos 1 a 5 e 7 do termo; o 6 no contexto dele).
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
                texto: ['Entendi, ', { '$valor' => 'contato.nome' }, '. A Fernanda, gerente, já está vendo seu caso'] },
              *depois_de_acalmar
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

    # Passo 6 (G11, a metade "a equipe respondeu"): depois do "acalmar", espera a Fernanda responder por até 30
    # minutos; sem resposta, avisa a dona com o mesmo resumo: o que a IA escreveu no passo "resumo" (`ia.resumo`, G28,
    # #2679), sem outra ida à IA. O eco do "acalmar" não conta como resposta da equipe.
    context 'with a espera pela resposta da Fernanda (passo 6)' do
      let(:depois_de_acalmar) do
        [{ id: 'espera_fernanda', tipo: 'esperar_ate',
           condicao: { campo: { '$valor' => 'conversa.equipe_respondeu' }, op: 'igual', valor: true },
           prazo: { valor: 30, unidade: 'minutos' },
           se_vencer: [{ id: 'resumo_dona', tipo: 'avisar', para: { pessoas: [dona.id] },
                         texto: ['Ninguém respondeu o cliente bravo em 30 minutos. ', { '$valor' => 'ia.resumo' }] }] }]
      end

      def execucao = Autonomia::Automacao::Execucao.where(automacao_id: automacao['id']).sole

      def passar(tempo)
        travel(tempo) do
          Autonomia::Automacao::VarreduraJob.perform_now
          rodar_jobs
          yield if block_given?
        end
      end

      it 'depois do "acalmar", fica esperando a Fernanda, sem avisar a dona', :aggregate_failures do
        expect(execucao.estado).to eq('esperando')
        expect(historico_de(automacao).map(&:first).last(2)).to eq(%w[acalmar espera_fernanda])
        expect(mencoes_para(dona)).to be_empty
      end

      it 'a Fernanda responde em 10 minutos: a espera termina e a dona não é avisada', :aggregate_failures do
        passar(10.minutes) do
          create(:message, conversation: conversa, account: account, inbox: inbox, message_type: :outgoing, sender: fernanda,
                           content: 'Paulo, aqui é a Fernanda. Já pedi o estorno.')
          rodar_jobs
        end

        expect(execucao.reload.estado).to eq('concluida')
        expect(historico_de(automacao).map(&:first)).not_to include('resumo_dona')
        expect(mencoes_para(dona)).to be_empty
      end

      it 'ninguém responde em 30 minutos: a dona recebe no sino o mesmo resumo', :aggregate_failures do
        passar(31.minutes)

        expect(execucao.reload.estado).to eq('concluida')
        expect(historico_de(automacao).last.first(2)).to eq(%w[resumo_dona ok])
        expect(mencoes_para(dona).count).to eq(1)
        avisos = conversa.messages.where(private: true).where('content LIKE ?', "%mention://user/#{dona.id}/%")
        expect(avisos.sole.content).to include('cobrado duas vezes')
        expect(ia_recebeu.count { |corpo| corpo.dig('text', 'format', 'name') == 'automacao_resumir' }).to eq(1)
      end
    end

    # Passo 2 (G15): "tirar ele da mão do robô". Passar a conversa para a Fernanda tira a agente de IA dela: a plataforma
    # solta o robô quando uma pessoa assume (Conversation#reset_agent_bot_when_assignee_present).
    context 'with a agente de IA atendendo (passo 2)' do
      let(:robo) { create(:agent_bot, account: account) }
      let(:conversa) do
        create(:conversation, account: account, inbox: inbox, contact: paulo, contact_inbox: contact_inbox, ai_assignee: robo, status: :open)
      end

      it 'passo 2: tira a conversa da agente de IA', :aggregate_failures do
        conversa.reload
        expect(historico_de(automacao).map(&:first)).to include('gerente')
        expect(conversa.assignee).to eq(fernanda)
        expect(conversa.ai_assignee).to be_nil
      end
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

    # O "nenhum se aplica" do "decidir" não deixa nota (#2578): a mensagem normal não enche a conversa de notas.
    it 'para aqui: nada muda na conversa, nada sai para o cliente e nenhuma nota para a equipe', :aggregate_failures do
      conversa.reload
      expect([conversa.assignee, conversa.priority, conversa.label_list]).to eq([rafael, nil, []])
      expect(chamadas_para('graph.facebook.com')).to be_empty
      expect(historico_de(automacao).map(&:first)).to eq(['tom'])
      expect(conversa.messages.outgoing.where(private: false)).to be_empty
      expect(conversa.messages.where(private: true)).to be_empty
    end
  end

  it 'passo 8: conversa resolvida com a etiqueta reclamação vira card no quadro "Melhorias" com o resumo' do
    abertas = FechamentoAutomacao::Lacunas.abertas(%w[G4])
    pending 'lacuna G4: criar card num funil/etapa não é passo da Automação livre (POST crm/cards fora da lista)'
    expect(abertas).to be_empty
  end
end
