require 'rails_helper'

# #1361 — o portão de confiança do Testar e do Copiloto trocava pela mensagem padrão a resposta que se apoia no
# que uma ferramenta acabou de devolver: a confirmação da agenda, o estoque, a carência lida da apólice. O dado
# lido de um sistema neste turno passa a valer como base, como a leitura da conta no Guia (#593). Quem diz que a
# ferramenta recusou é o registro de recusas (`Tools::Recusa`), nunca o texto da saída. Promessa não conta.
RSpec.describe Autonomia::Agents::Answerer do
  let(:account) { create(:account) }
  let(:agent) do
    Autonomia::Agents::Agent.create!(
      account: account, name: 'Bot', agent_type: 'custom', status: :active, enabled: true,
      instruction: 'Atenda o cliente.', config: { 'with_knowledge' => false },
      fallback_message: 'Não tenho informação confiável. Vou chamar alguém da equipe.'
    )
  end

  def resposta_do_modelo(reply, confidence: 0.9, should_handoff: false, handoff_reason: nil)
    { reply: reply, confidence: confidence, should_handoff: should_handoff, handoff_reason: handoff_reason,
      used_snippet_ids: [], answered_from_knowledge: false }.to_json
  end

  # O modelo chama as ferramentas `chamadas` (se houver) e responde `texto`.
  def modelo_responde(texto, chamadas: [])
    allow(Crm::Ai::CredentialResolver).to receive(:new)
      .and_return(instance_double(Crm::Ai::CredentialResolver, resolve: 'ai-credential'))
    client = instance_double(Crm::Ai::ResponsesClient)
    allow(client).to receive(:create_with_tool_executor) do |**_kwargs, &executor|
      executor.call(chamadas) if chamadas.any? && executor
      { text: texto }
    end
    allow(Crm::Ai::ResponsesClient).to receive(:new).and_return(client)
  end

  def chamada(nome, id = 'c1')
    { 'name' => nome, 'call_id' => id, 'arguments' => '{}' }
  end

  def testar
    described_class.new(agent: agent, query: 'pergunta do cliente').answer
  end

  def ferramenta_http(slug)
    Autonomia::Agents::Tool.create!(account: account, agent: agent, name: slug.humanize, slug: slug,
                                    endpoint_url: "https://api.example.com/#{slug}", param_schema: [])
  end

  def http_devolve(saida)
    allow(Autonomia::Agents::Tools::HttpExecutor).to receive(:new)
      .and_return(instance_double(Autonomia::Agents::Tools::HttpExecutor, call: saida))
  end

  # Uma ferramenta nativa no catálogo do agente, sem a página de agendamento de verdade: o que se testa é o
  # portão, não a agenda. `execute` faz o que a nativa faria: devolve o texto e, numa recusa, registra.
  def nativa(slug, async: false, &execucao)
    bound = instance_double(Autonomia::Agents::Tools::Bound, slug: slug, async?: async,
                                                             openai_schema: { type: 'function', name: slug, parameters: {} })
    allow(bound).to receive(:execute, &execucao)
    allow(Autonomia::Agents::Tools::Bound).to receive(:for_agent).and_return([bound])
  end

  def barrou?(resultado)
    resultado.handoff[:should] && resultado.reply == agent.fallback_message
  end

  describe 'com dado devolvido por ferramenta' do
    # No Testar não há conversa e `agendar_reuniao` recusa; o que a agenda devolve ali são os horários livres.
    it 'deixa passar os horários livres da agenda', :aggregate_failures do
      nativa('horarios_disponiveis') do
        { horarios: [{ inicio: '2026-10-14T11:00:00-03:00', quando: 'terça, 14/10, às 11:00', pessoa_id: 7,
                       pessoa_nome: 'Ana' }] }.to_json
      end
      modelo_responde(resposta_do_modelo('Tenho terça, 14/10, às 11:00 com a Ana. Pode ser?'),
                      chamadas: [chamada('horarios_disponiveis')])

      resultado = testar

      expect(resultado.handoff[:should]).to be(false)
      expect(resultado.reply).to eq('Tenho terça, 14/10, às 11:00 com a Ana. Pode ser?')
    end

    it 'deixa passar o estoque lido da ferramenta HTTP', :aggregate_failures do
      ferramenta_http('consulta_estoque')
      http_devolve({ produto: 'Tênis', unidades: 3, preco: 89 }.to_json)
      modelo_responde(resposta_do_modelo('Temos 3 unidades por R$ 89.'), chamadas: [chamada('consulta_estoque')])

      resultado = testar

      expect(resultado.handoff[:should]).to be(false)
      expect(resultado.reply).to eq('Temos 3 unidades por R$ 89.')
    end

    it 'deixa passar carência e franquia lidas da apólice', :aggregate_failures do
      ferramenta_http('consultar_apolice')
      http_devolve({ carencia_dias: 30, franquia: 'R$ 1.500' }.to_json)
      fala = 'A carência é de 30 dias e a franquia do seu plano é de R$ 1.500.'
      modelo_responde(resposta_do_modelo(fala), chamadas: [chamada('consultar_apolice')])

      resultado = testar

      expect(resultado.handoff[:should]).to be(false)
      expect(resultado.reply).to eq(fala)
    end

    it 'continua passando à equipe quando o próprio modelo pede' do
      ferramenta_http('consulta_estoque')
      http_devolve({ unidades: 3 }.to_json)
      modelo_responde(resposta_do_modelo('Temos 3 unidades. Vou chamar alguém.', should_handoff: true,
                                                                                 handoff_reason: 'human_requested'),
                      chamadas: [chamada('consulta_estoque')])

      expect(testar.handoff[:should]).to be(true)
    end

    it 'continua barrando a confiança baixa declarada pelo modelo' do
      ferramenta_http('consulta_estoque')
      http_devolve({ unidades: 3 }.to_json)
      modelo_responde(resposta_do_modelo('Temos 3 unidades por R$ 89.', confidence: 0.2),
                      chamadas: [chamada('consulta_estoque')])

      expect(barrou?(testar)).to be(true)
    end

    # O teto do "não achei" (0.29) não é falta de base: é o próprio modelo dizendo que não tem a resposta.
    it 'continua passando à equipe o "não tenho essa informação" com confiança alta' do
      ferramenta_http('consulta_estoque')
      http_devolve({ unidades: 3 }.to_json)
      modelo_responde(resposta_do_modelo('Não tenho essa informação sobre o prazo de entrega.', confidence: 0.95),
                      chamadas: [chamada('consulta_estoque')])

      expect(barrou?(testar)).to be(true)
    end
  end

  describe 'com recusa de ferramenta' do
    it 'barra como hoje a recusa em JSON (erro HTTP registrado)' do
      ferramenta_http('consulta_estoque')
      allow(Autonomia::Agents::Tools::HttpExecutor).to receive(:new).and_return(
        instance_double(Autonomia::Agents::Tools::HttpExecutor).tap do |executor|
          allow(executor).to receive(:call)
            .and_raise(Autonomia::Agents::Tools::HttpExecutor::Error.new('tool_http_error: 500', status: 500))
        end
      )
      modelo_responde(resposta_do_modelo('Temos 3 unidades por R$ 89.'), chamadas: [chamada('consulta_estoque')])

      expect(barrou?(testar)).to be(true)
    end

    it 'barra como hoje a recusa em texto, pelo registro e não pelo que o texto diz' do
      nativa('horarios_disponiveis') do
        Autonomia::Agents::Tools::Recusa.registrar('agenda_sem_horarios', slug: 'horarios_disponiveis')
        'Horário livre: terça às 11:00.'
      end
      modelo_responde(resposta_do_modelo('Tenho terça às 11:00. Pode ser?'),
                      chamadas: [chamada('horarios_disponiveis')])

      expect(barrou?(testar)).to be(true)
    end

    it 'barra quando uma ferramenta devolve dado e outra recusa no mesmo turno' do
      ferramenta_http('consulta_estoque')
      http_devolve({ unidades: 3 }.to_json)
      modelo_responde(resposta_do_modelo('Temos 3 unidades por R$ 89.'),
                      chamadas: [chamada('consulta_estoque'), chamada('ferramenta_que_nao_existe', 'c2')])

      expect(barrou?(testar)).to be(true)
    end

    # O formato da própria Recusa, chegando por HTTP 200 sem passar pelo registro: é erro, não dado.
    it 'barra o {"error": ...} devolvido com HTTP 200' do
      ferramenta_http('consulta_estoque')
      http_devolve({ error: 'produto_nao_encontrado' }.to_json)
      modelo_responde(resposta_do_modelo('Temos 3 unidades por R$ 89.'), chamadas: [chamada('consulta_estoque')])

      expect(barrou?(testar)).to be(true)
    end
  end

  # O Guia (quem chama com `operador`) tem regra própria: nunca retém a resposta (#914) e só a leitura da conta
  # tira os pisos da confiança (#593). A marca do #1361 não vale para ele.
  describe 'no Guia' do
    let(:guia) do
      conta, admin = create_account_and_user
      Autonomia::Guide::Contexto.new(account: conta, user: admin)
    end

    it 'mantém a confiança de hoje mesmo com dado de ferramenta', :aggregate_failures do
      ferramenta_http('consultar_apolice')
      http_devolve({ carencia_dias: 30 }.to_json)
      modelo_responde(resposta_do_modelo('A carência é de 30 dias.', confidence: 0.9),
                      chamadas: [chamada('consultar_apolice')])

      resultado = described_class.new(agent: agent, query: 'qual a carência?', operador: guia).answer

      expect(resultado.confidence).to eq(0.29)
      expect(resultado.handoff[:should]).to be(false)
    end
  end

  describe 'sem dado de sistema' do
    it 'barra como hoje o turno sem ferramenta' do
      modelo_responde(resposta_do_modelo('Temos 3 unidades por R$ 89.'))

      expect(barrou?(testar)).to be(true)
    end

    it 'deixa passar como hoje o turno sem ferramenta e sem fato do negócio', :aggregate_failures do
      modelo_responde(resposta_do_modelo('Olá! Como posso ajudar?'))

      resultado = testar

      expect(resultado.handoff[:should]).to be(false)
      expect(resultado.reply).to eq('Olá! Como posso ajudar?')
    end

    it 'não conta a promessa de uma ferramenta assíncrona' do
      nativa('cotar_seguro', async: true) { 'Consulta iniciada. Avise o cliente que você está buscando.' }
      modelo_responde(resposta_do_modelo('Estou consultando: o seu seguro custa R$ 89.'),
                      chamadas: [chamada('cotar_seguro')])

      expect(barrou?(testar)).to be(true)
    end

    ['', '   ', '{}', '[]', 'null', '{ }'].each do |vazia|
      it "não conta a resposta vazia #{vazia.inspect}" do
        ferramenta_http('consulta_estoque')
        http_devolve(vazia)
        modelo_responde(resposta_do_modelo('Temos 3 unidades por R$ 89.'), chamadas: [chamada('consulta_estoque')])

        expect(barrou?(testar)).to be(true)
      end
    end
  end
end
