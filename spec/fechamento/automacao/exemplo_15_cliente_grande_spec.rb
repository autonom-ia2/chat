require 'rails_helper'

# Fechamento do épico #2414 (F9.6), exemplo 15 dos termos de aceite: "Cliente grande, atendimento de dono".
#
# > "Pedido grande eu quero que eu mesmo atenda, rápido, e que ninguém deixe esfriar." — Carlos, dono da distribuidora
#
# Começa quando: card criado ou atualizado com valor acima de R$ 50 mil (G27, o card atualizado nasce do próprio card).
#   1. Se o contato já tem a etiqueta "cliente grande", para aqui: a automação roda uma vez por cliente.
#   2. Tira a conversa da agente de IA e passa para o Carlos.
#   3. Põe a etiqueta "cliente grande" no contato e marca a conversa como prioridade.
#   4. A IA resume para o Carlos o que o cliente pediu, o prazo e a forma de pagamento.
#   5. Manda ao cliente: "Seu pedido é especial. O Carlos, dono da empresa, vai te atender pessoalmente".
#   6. Manda o link da agenda do Carlos para uma ligação ainda hoje.
#   7. Espera o Carlos responder, por até 1 hora. Sem resposta: manda o resumo de novo ao Carlos e avisa o gerente.
#   8. Card ganho: põe a etiqueta "conta grande" e cria retorno de pós-venda para 15 dias.
#   9. Card perdido: a IA resume o motivo para o Carlos.
#
# Uma automação só, montada e ligada pelo Carlos pela API da tela. Etiqueta não tem espaço: "cliente-grande" e
# "conta-grande". Os passos 8 e 9 esperam o card fechar ("esperar até" ganho ou perdido): o motor pede um prazo, e vai o
# teto (3650 dias), que o esquema diz ser proteção contra erro de digitação, não limite de uso; a mudança do card acorda
# a espera (#2687). O cliente escreve pelo WhatsApp oficial, o que sai para ele para no receptor de teste, e a IA é o
# dublê. Desenho e lacunas: docs/automacao/F9-fechamento-20-exemplos.md.
RESUMO_DA_IA = 'Quer 400 caixas de óleo, entrega até sexta, pagamento em boleto 30 dias.'.freeze

RSpec.describe 'Fechamento #2414 · exemplo 15: cliente grande, atendimento de dono', :fechamento_automacao, type: :request do
  include ActiveJob::TestHelper

  around { |exemplo| with_modified_env(CRM_KANBAN_ENABLED: 'true', CRM_CALENDAR_MEETINGS_ENABLED: 'true') { exemplo.run } }

  let(:canal) { create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false) }
  let(:account) { canal.account }
  let(:carlos) { create(:user, account: account, role: :administrator, name: 'Carlos Dono') }
  let(:gerente) { create(:user, account: account, role: :agent, name: 'Marina Gerente') }
  let(:vendedor) { create(:user, account: account, role: :agent, name: 'Rafael Vendas') }
  let(:cliente) { create(:contact, account: account, name: 'Mercado Bom Preço', phone_number: '+5511900000015') }
  let(:contact_inbox) { create(:contact_inbox, inbox: inbox, contact: cliente, source_id: '5511900000015') }
  let(:conversa) do
    create(:conversation, account: account, inbox: inbox, contact: cliente, contact_inbox: contact_inbox,
                          ai_assignee: create(:agent_bot, account: account), status: :open)
  end
  let(:funil) { create_crm_pipeline(account: account, user: carlos, name: 'Vendas').first }
  let(:agenda) { create_booking_profile(account: account, host: carlos, title: 'Ligação com o Carlos') }
  let(:card) do
    account.crm_cards.create!(pipeline: funil, stage: funil.stages.first, inbox: inbox, contact: cliente, primary_conversation: conversa,
                              title: 'Pedido do Mercado', currency: 'BRL', value_cents: 1_000_000, owner: vendedor)
  end
  let(:automacao) { montar_automacao(carlos, account, nome: 'Cliente grande, atendimento de dono', receita: receita) }

  def inbox = canal.inbox
  def contato_id = { '$valor' => 'contato.id' }
  def conversa_id = { '$valor' => 'conversa.id' }
  def status_do_card(status) = { campo: { '$valor' => 'card.status' }, op: 'igual', valor: status }

  def etiqueta_no_contato(id, nome)
    { id: id, tipo: 'acao', acao: 'PATCH contacts/:contact_id/labels/alterar', descricao: "Pôr a etiqueta #{nome} no contato",
      caminho: { contact_id: contato_id }, corpo: { por: [nome] } }
  end

  def receita
    { gatilho: { tipo: 'card.atualizado', mudanca: { campo: 'valor', condicao: 'passou_de', valor: '50000' } },
      passos: [*passos_1_a_6, espera_do_carlos, *quando_fechar] }
  end

  # Passos 1 a 6.
  def passos_1_a_6
    [{ id: 'ja_e_grande', tipo: 'se', condicao: { campo: { '$valor' => 'contato.etiquetas' }, op: 'contem', valor: 'cliente-grande' },
       entao: [{ id: 'uma_vez', tipo: 'parar' }] },
     { id: 'para_o_carlos', tipo: 'acao', acao: 'POST conversations/:conversation_id/assignments', descricao: 'Passar para o Carlos',
       caminho: { conversation_id: conversa_id }, corpo: { assignee_id: carlos.id } },
     etiqueta_no_contato('cliente_grande', 'cliente-grande'),
     { id: 'prioridade', tipo: 'acao', acao: 'POST conversations/:id/toggle_priority', descricao: 'Marcar como prioridade',
       caminho: { id: conversa_id }, corpo: { priority: 'urgent' } },
     { id: 'resumo', tipo: 'resumir', le: %w[mensagens_recentes], linhas: 3,
       instrucao: 'Diga o que o cliente pediu, o prazo e a forma de pagamento.', destino: { avisar: { pessoas: [carlos.id] } } },
     { id: 'especial', tipo: 'mensagem', texto: ['Seu pedido é especial. O Carlos, dono da empresa, vai te atender pessoalmente'] },
     { id: 'agenda', tipo: 'mensagem', texto: ['Marque uma ligação com o Carlos ainda hoje: ', { '$valor' => 'conversa.link_da_agenda' }] }]
  end

  # Passo 7: o Carlos é o responsável da conversa desde o passo 2.
  def espera_do_carlos
    { id: 'espera_carlos', tipo: 'esperar_ate',
      condicao: { campo: { '$valor' => 'conversa.responsavel_respondeu' }, op: 'igual', valor: true },
      prazo: { valor: 1, unidade: 'horas' },
      se_vencer: [{ id: 'resumo_de_novo', tipo: 'avisar', para: { pessoas: [carlos.id] },
                    texto: ['O cliente grande ainda espera sua resposta. ', { '$valor' => 'ia.resumo' }] },
                  { id: 'avisa_gerente', tipo: 'avisar', para: { pessoas: [gerente.id] },
                    texto: ['O Carlos não respondeu em 1 hora o cliente grande ', { '$valor' => 'contato.nome' }, '.'] }] }
  end

  # Passos 8 e 9: espera o card fechar (o teto do prazo) e segue pelo que aconteceu.
  def quando_fechar
    perdido = { id: 'perdeu', tipo: 'se', condicao: status_do_card('lost'),
                entao: [{ id: 'motivo', tipo: 'resumir', le: %w[card], linhas: 2, instrucao: 'Diga o motivo da perda do pedido.',
                          destino: { avisar: { pessoas: [carlos.id] } } }] }
    [{ id: 'fechou', tipo: 'esperar_ate', condicao: { alguma: [status_do_card('won'), status_do_card('lost')] },
       prazo: { valor: 3650, unidade: 'dias' } },
     { id: 'ganhou', tipo: 'se', condicao: status_do_card('won'),
       entao: [etiqueta_no_contato('conta_grande', 'conta-grande'),
               { id: 'pos_venda', tipo: 'retorno', titulo: ['Pós-venda: ', { '$valor' => 'contato.nome' }], daqui: { valor: 15, unidade: 'dias' } }],
       senao: [perdido] }]
  end

  # Um job por vez, como no Sidekiq, com o job do evento do card (o card atualizado nasce no commit do card).
  def drenar
    drenados = [*FechamentoAutomacao::JOBS, Autonomia::Automacao::EventoDoCardJob]
    FechamentoAutomacao::LIMITE_DE_JOBS.times do
      job = enqueued_jobs.find { |item| drenados.include?(item[:job]) }
      return unless job

      enqueued_jobs.delete(job)
      job[:job].perform_now(*ActiveJob::Arguments.deserialize(job[:args]))
    end
    raise "a fila não esvaziou em #{FechamentoAutomacao::LIMITE_DE_JOBS} jobs"
  end

  # O vendedor muda o valor pela gaveta do card (o mesmo PATCH da tela).
  def vendedor_muda_o_valor(cents)
    patch "/api/v1/accounts/#{account.id}/crm/cards/#{card.id}", params: { value_cents: cents }, headers: auth_headers(vendedor), as: :json
    expect(response).to have_http_status(:ok)
    drenar
  end

  def passar(tempo)
    travel(tempo) do
      Autonomia::Automacao::VarreduraJob.perform_now
      drenar
      yield if block_given?
    end
  end

  def carlos_responde
    create(:message, conversation: conversa, account: account, inbox: inbox, message_type: :outgoing, sender: carlos,
                     content: 'Olá! Aqui é o Carlos. Já separei seu pedido.')
    drenar
  end

  def fechar(resultado, **extra)
    Crm::Cards::Closer.new(card: card.reload, actor: vendedor, result: resultado, **extra).perform
    drenar
  end

  def execucao = Autonomia::Automacao::Execucao.where(automacao_id: automacao['id']).sole
  def passos_feitos = historico_de(automacao).map(&:first)
  def mencoes_para(pessoa) = Notification.where(user: pessoa, notification_type: 'conversation_mention')
  def notas_para(pessoa) = conversa.messages.where(private: true).where('content LIKE ?', "%mention://user/#{pessoa.id}/%")
  def pedidos_de_resumo = ia_recebeu.select { |corpo| corpo.dig('text', 'format', 'name') == 'automacao_resumir' }
  def textos_ao_cliente = chamadas_para('graph.facebook.com').map { |chamada| chamada.corpo.dig('text', 'body') }

  before do
    account.update!(locale: 'pt_BR')
    flags_do_piloto(account)
    account.enable_features!('automacao_gatilhos', 'crm_booking_v2')
    [carlos, gerente, vendedor].each { |pessoa| create(:inbox_member, user: pessoa, inbox: inbox) }
    %w[cliente-grande conta-grande].each { |nome| create(:label, account: account, title: nome, description: "Cliente: #{nome}") }
    agenda
    receptor_whatsapp_cloud
    ia_responde(account, 'automacao_resumir' => { 'resumo' => RESUMO_DA_IA })
    create(:message, conversation: conversa, account: account, inbox: inbox, message_type: :incoming, sender: cliente,
                     content: 'Preciso de 400 caixas de óleo até sexta, pago no boleto 30 dias.')
    card
    ligar_automacao(carlos, account, automacao)
    clear_enqueued_jobs
  end

  after { Current.reset }

  context 'with o valor do card passando de R$ 50 mil (passos 2 a 7)' do
    before { vendedor_muda_o_valor(8_000_000) }

    it 'passo 2: tira a conversa da agente de IA e passa para o Carlos', :aggregate_failures do
      conversa.reload
      expect(conversa.assignee).to eq(carlos)
      expect(conversa.ai_assignee).to be_nil
    end

    it 'passo 3: põe a etiqueta "cliente grande" no contato e marca a conversa como prioridade', :aggregate_failures do
      expect(cliente.reload.label_list).to eq(['cliente-grande'])
      expect(conversa.reload.priority).to eq('urgent')
    end

    it 'passo 4: o Carlos recebe no sino o resumo do pedido, do prazo e da forma de pagamento', :aggregate_failures do
      expect(mencoes_para(carlos).count).to eq(1)
      expect(notas_para(carlos).sole.content).to include('Resumo', RESUMO_DA_IA)
      expect(pedidos_de_resumo.size).to eq(1)
      expect(pedidos_de_resumo.sole['instructions']).to include('Diga o que o cliente pediu, o prazo e a forma de pagamento.')
      expect(pedidos_de_resumo.to_json).to include('400 caixas de óleo')
    end

    it 'passos 5 e 6: o cliente recebe pelo WhatsApp oficial o aviso e o link da agenda do Carlos', :aggregate_failures do
      expect(chamadas_para('graph.facebook.com').map { |chamada| chamada.corpo['to'] }).to eq(%w[5511900000015 5511900000015])
      expect(textos_ao_cliente).to eq(['Seu pedido é especial. O Carlos, dono da empresa, vai te atender pessoalmente',
                                       "Marque uma ligação com o Carlos ainda hoje: #{Crm::BookingV2::ShortLink.url_for(agenda)}"])
    end

    it 'passo 7: fica esperando o Carlos, sem avisar a gerente', :aggregate_failures do
      expect(passos_feitos).to eq(%w[ja_e_grande para_o_carlos cliente_grande prioridade resumo especial agenda espera_carlos])
      expect(historico_de(automacao).map(&:second).uniq).to eq(['ok'])
      expect(execucao.estado).to eq('esperando')
      expect(mencoes_para(gerente)).to be_empty
    end

    it 'passo 7: o Carlos responde em 20 minutos; ninguém é avisado e a automação espera o card fechar', :aggregate_failures do
      passar(20.minutes) { carlos_responde }

      expect(passos_feitos).not_to include('resumo_de_novo', 'avisa_gerente')
      expect(passos_feitos.last).to eq('fechou')
      expect(execucao.reload.estado).to eq('esperando')
      expect(mencoes_para(gerente)).to be_empty
      expect(mencoes_para(carlos).count).to eq(1)
    end

    it 'passo 7: o vendedor responde no lugar do Carlos; a espera continua, porque o termo espera o Carlos', :aggregate_failures do
      passar(20.minutes) do
        create(:message, conversation: conversa, account: account, inbox: inbox, message_type: :outgoing, sender: vendedor,
                         content: 'Oi, já vou ver.')
        drenar
      end

      expect(passos_feitos.last).to eq('espera_carlos')
      expect(execucao.reload.estado).to eq('esperando')
    end

    it 'passo 7: sem resposta em 1 hora, o Carlos recebe o mesmo resumo de novo e a gerente é avisada', :aggregate_failures do
      passar(61.minutes)

      expect(passos_feitos.last(3)).to eq(%w[resumo_de_novo avisa_gerente fechou])
      expect(mencoes_para(carlos).count).to eq(2)
      expect(notas_para(carlos).order(:id).last.content).to include('O cliente grande ainda espera sua resposta.', RESUMO_DA_IA)
      expect(mencoes_para(gerente).count).to eq(1)
      expect(notas_para(gerente).sole.content).to include('O Carlos não respondeu em 1 hora o cliente grande Mercado Bom Preço.')
      expect(pedidos_de_resumo.size).to eq(1)
      expect(execucao.reload.estado).to eq('esperando')
    end

    it 'passo 8: card ganho põe a etiqueta "conta grande" e cria o retorno de pós-venda para 15 dias', :aggregate_failures do
      passar(20.minutes) { carlos_responde }

      travel(2.days) do
        fechar('won')

        expect(cliente.reload.label_list).to contain_exactly('cliente-grande', 'conta-grande')
        expect(Crm::FollowUp.sole).to have_attributes(card_id: card.id, title: 'Pós-venda: Mercado Bom Preço', status: 'pending')
        expect(Crm::FollowUp.sole.due_at).to be_within(1.minute).of(15.days.from_now)
        expect(passos_feitos.last(4)).to eq(%w[fechou ganhou conta_grande pos_venda])
        expect(passos_feitos).not_to include('motivo')
        expect(execucao.reload.estado).to eq('concluida')
      end
    end

    it 'passo 9: card perdido, a IA lê o card e resume o motivo para o Carlos', :aggregate_failures do
      passar(20.minutes) { carlos_responde }

      travel(2.days) { fechar('lost', lost_reason: 'Achou o frete caro e fechou com outro fornecedor') }

      expect(passos_feitos.last(4)).to eq(%w[fechou ganhou perdeu motivo])
      expect(pedidos_de_resumo.size).to eq(2)
      expect(pedidos_de_resumo.last.to_json).to include('Achou o frete caro e fechou com outro fornecedor')
      expect(pedidos_de_resumo.last['instructions']).to include('Diga o motivo da perda do pedido.')
      expect(mencoes_para(carlos).count).to eq(2)
      expect(cliente.reload.label_list).to eq(['cliente-grande'])
      expect(Crm::FollowUp.count).to eq(0)
      expect(execucao.reload.estado).to eq('concluida')
    end

    it 'o valor que sobe de novo não recomeça: a automação roda uma vez', :aggregate_failures do
      passar(20.minutes) do
        carlos_responde
        vendedor_muda_o_valor(9_000_000)
      end

      expect(Autonomia::Automacao::Execucao.where(automacao_id: automacao['id']).count).to eq(1)
    end
  end

  context 'with o card que já nasce com R$ 80 mil' do
    let(:card_novo) do
      account.crm_cards.create!(pipeline: funil, stage: funil.stages.first, inbox: inbox, contact: cliente, primary_conversation: conversa,
                                title: 'Outro pedido do Mercado', currency: 'BRL', value_cents: 8_000_000, owner: vendedor)
    end

    before do
      card_novo
      drenar
    end

    it 'começa também: card criado com valor acima de R$ 50 mil', :aggregate_failures do
      expect(execucao).to have_attributes(alvo_type: 'Crm::Card', alvo_id: card_novo.id)
      expect(passos_feitos.first(4)).to eq(%w[ja_e_grande para_o_carlos cliente_grande prioridade])
      expect(conversa.reload.assignee).to eq(carlos)
    end
  end

  context 'with o valor abaixo de R$ 50 mil' do
    before { vendedor_muda_o_valor(4_000_000) }

    it 'não começa' do
      expect(passos_feitos).to be_empty
    end
  end

  context 'with o contato que já tem a etiqueta "cliente grande" (passo 1)' do
    before do
      cliente.update!(label_list: ['cliente-grande'])
      vendedor_muda_o_valor(8_000_000)
    end

    it 'para aqui: não mexe na conversa, não avisa o Carlos e nada sai para o cliente', :aggregate_failures do
      expect(passos_feitos).to eq(%w[ja_e_grande uma_vez])
      conversa.reload
      expect(conversa.assignee).to be_nil
      expect(conversa.ai_assignee).to be_present
      expect(mencoes_para(carlos)).to be_empty
      expect(chamadas_para('graph.facebook.com')).to be_empty
    end
  end
end
