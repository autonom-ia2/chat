require 'rails_helper'

# O Guia consultando a plataforma a partir da pergunta (#533, 2ª volta).
# Quem escolhe o recurso é o modelo; quem decide o que pode ser lido é a API,
# com o token de quem perguntou.
RSpec.describe Autonomia::Guide::Chat do
  let(:conta_e_admin) { create_account_and_user }
  let(:conta) { conta_e_admin.first }
  let(:admin) { conta_e_admin.last }
  let(:agente_ia) { instance_double(Autonomia::Agents::Agent) }

  let(:resultado_do_modelo) do
    instance_double(
      Autonomia::Agents::AnswerResult,
      reply: 'resposta', answered_from_knowledge: true, confidence: 0.9, handoff: {}, used_knowledge: []
    )
  end

  def preparar(recurso, conteudo)
    allow(Autonomia::Guide::Seed).to receive(:ready_agent_for).and_return(agente_ia)
    # Sem fluxo de diagnóstico entre os melhores: aqui o assunto é leitura.
    allow(Autonomia::Agents::Retriever).to receive(:new).and_return(
      instance_double(Autonomia::Agents::Retriever, retrieve: [])
    )
    allow(Autonomia::Guide::EscolhaDaConsulta).to receive(:new).and_return(
      instance_double(Autonomia::Guide::EscolhaDaConsulta,
                      para: recurso.nil? ? nil : { recurso: recurso, parametros: {} })
    )
    allow(Autonomia::Guide::Consulta).to receive(:new).and_return(
      instance_double(Autonomia::Guide::Consulta, catalogo: ['inboxes'], ler: conteudo)
    )
  end

  # Devolve a pergunta como ela chegou ao modelo que responde.
  def perguntar(mensagem, recurso: 'crm/pipelines', conteudo: '[{\"name\":\"Comercial\"}]')
    preparar(recurso, conteudo)
    query = nil
    allow(Autonomia::Agents::Answerer).to receive(:new) do |args|
      query = args[:query]
      instance_double(Autonomia::Agents::Answerer, answer: resultado_do_modelo)
    end

    described_class.new(account: conta, user: admin, message: mensagem).perform
    query.to_s
  end

  it 'responde com o que a conta tem, e não com o manual', :aggregate_failures do
    query = perguntar('Quais funis eu tenho?')

    expect(query).to include('[O QUE A CONTA TEM')
    expect(query).to include('crm/pipelines')
    expect(query).to include('Comercial')
  end

  it 'consulta qualquer recurso da plataforma, não uma lista de assuntos' do
    query = perguntar('Quantas caixas de entrada eu tenho?', recurso: 'inboxes',
                                                             conteudo: '[{"name":"WhatsApp"}]')

    expect(query).to include('WhatsApp')
  end

  # Em 20/09/2026 o Guia respondeu "não consigo criar o funil por você, porque o
  # Guia não altera a conta" — com o botão Confirmar logo abaixo. Quem escreve o
  # texto não sabia que a ação já tinha sido preparada.
  it 'avisa quem escreve o texto que a ação já vai ser oferecida' do
    allow(Autonomia::Guide::EscolhaDaAcao).to receive(:new).and_return(
      instance_double(Autonomia::Guide::EscolhaDaAcao,
                      para: { acao: 'POST crm/pipelines', dados: { corpo: { 'name' => 'Comercial' } } })
    )
    allow(Autonomia::Guide::Acoes).to receive(:new).and_return(
      instance_double(Autonomia::Guide::Acoes,
                      descrever: { frase: 'Criar o funil Comercial.', detalhe: 'Nome: Comercial', aviso: nil })
    )

    query = perguntar('cria um funil chamado Comercial')

    expect(query).to include('AÇÃO JÁ PREPARADA')
    expect(query).to include('NÃO diga que você não faz')
  end

  # Guarda contra a volta do filtro de palavra. Duas vezes o Guia entendeu a
  # pergunta e não foi buscar o dado porque ela não estava escrita do jeito que
  # uma lista minha esperava. Quem decide é quem lê a pergunta.
  it 'consulta mesmo quando a pergunta não usa "quais" nem "quantos"' do
    query = perguntar('Me fala sobre minhas caixas', recurso: 'inboxes',
                                                     conteudo: '[{"name":"WhatsApp"}]')

    expect(query).to include('WhatsApp')
  end

  # Quem diz "aqui não precisa de dado" é o modelo, devolvendo recurso nulo.
  it 'não consulta nada quando o modelo diz que a pergunta não precisa de dado' do
    expect(perguntar('Quais funis eu tenho?', recurso: nil)).not_to include('[O QUE A CONTA TEM')
  end

  it 'não injeta bloco vazio quando a consulta não devolve nada' do
    expect(perguntar('Quais funis eu tenho?', conteudo: '')).not_to include('[O QUE A CONTA TEM')
  end
end
