require 'rails_helper'

# O que a pessoa tem aberto, selecionado e filtrado (#934), do navegador até o job.
#
# O servidor só confere a FORMA: o que passa daqui ainda é lido com a permissão
# da pessoa antes de chegar ao Guia. Mas o que não tem forma não chega nem lá.
RSpec.describe 'Guia da Plataforma — contexto da tela', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:rota) { "/api/v1/accounts/#{account.id}/autonomia/guide/chat" }

  before { allow(Autonomia::Guide::Seed).to receive(:eligible?).and_return(true) }

  def perguntar(params)
    post rota, params: { message: 'move esses para Cotação', route_context: 'crm_kanban_index' }.merge(params),
               headers: admin.create_new_auth_token, as: :json
  end

  def contexto_enviado(params)
    enviado = nil
    allow(Autonomia::Guide::ChatJob).to receive(:perform_later) { |_pedido, pergunta| enviado = pergunta }
    perguntar(params)
    enviado
  end

  it 'leva aberto, selecionados e filtros ao job, com a rota de sempre na chave antiga', :aggregate_failures do
    pergunta = contexto_enviado(tela: { rota: 'crm_kanban_index', aberto: [{ recurso: 'crm/cards', id: 881 }],
                                        selecionados: { recurso: 'crm/cards', ids: [881, '882'], total: 12 },
                                        filtros: { pipeline_id: 3, stage_ids: [7], status: 'open' } })

    expect(pergunta['tela']).to eq('crm_kanban_index')
    expect(pergunta['contexto_tela']).to eq(
      'rota' => 'crm_kanban_index', 'aberto' => [{ 'recurso' => 'crm/cards', 'id' => 881 }],
      'selecionados' => { 'recurso' => 'crm/cards', 'ids' => [881, 882], 'total' => 12 },
      'filtros' => { 'pipeline_id' => 3, 'stage_ids' => [7], 'status' => 'open' }
    )
  end

  # AC-CT1, um caso por linha.
  describe 'o que o servidor descarta' do
    it 'recurso fora do catálogo' do
      pergunta = contexto_enviado(tela: { aberto: [{ recurso: 'admin/users', id: 1 }, { recurso: 'crm/cards', id: 2 }],
                                          selecionados: { recurso: 'super_admin/accounts', ids: [1] } })

      expect(pergunta['contexto_tela']).to eq('aberto' => [{ 'recurso' => 'crm/cards', 'id' => 2 }])
    end

    it 'id que não é inteiro ou não é positivo' do
      pergunta = contexto_enviado(tela: { aberto: [{ recurso: 'crm/cards', id: 'abc' }, { recurso: 'crm/cards', id: 0 },
                                                   { recurso: 'crm/cards', id: 1.5 }],
                                          selecionados: { recurso: 'crm/cards', ids: [-3, '7x', 5, nil, 'DROP TABLE'] } })

      expect(pergunta['contexto_tela']).to eq('selecionados' => { 'recurso' => 'crm/cards', 'ids' => [5], 'total' => 1 })
    end

    it 'a conta, que o Guia já sabe qual é' do
      pergunta = contexto_enviado(tela: { filtros: { accountId: 999, account_id: 999, status: 'open' } })

      expect(pergunta['contexto_tela']['filtros']).to eq('status' => 'open')
    end

    it 'o 4º aberto e o 51º selecionado', :aggregate_failures do
      pergunta = contexto_enviado(tela: { aberto: (1..4).map { |id| { recurso: 'crm/cards', id: id } },
                                          selecionados: { recurso: 'crm/cards', ids: (1..60).to_a, total: 60 } })

      expect(pergunta['contexto_tela']['aberto'].pluck('id')).to eq([1, 2, 3])
      expect(pergunta['contexto_tela']['selecionados']).to eq('recurso' => 'crm/cards', 'ids' => (1..50).to_a, 'total' => 60)
    end

    it 'filtro que não é valor simples, e o que passa de 15' do
      filtros = { aninhado: { a: 1 }, lista_de_objetos: [{ a: 1 }] }.merge((1..20).index_by { |i| "f#{i}" })

      pergunta = contexto_enviado(tela: { filtros: filtros })

      expect(pergunta['contexto_tela']['filtros']).to eq((1..15).index_by { |i| "f#{i}" })
    end

    it 'filtro que passa de 1 KB' do
      pergunta = contexto_enviado(tela: { filtros: { busca: 'x' * 1_100, status: 'open' } })

      expect(pergunta['contexto_tela']['filtros']).to eq('status' => 'open')
    end

    it 'tela que não é objeto' do
      expect(contexto_enviado(tela: 'crm_kanban_index')['contexto_tela']).to eq({})
    end
  end

  # AC-CT2 — o front antigo (só `route_context` e `route_params`) continua igual, até o bloco "Registro aberto".
  it 'aceita o formato antigo e o Guia recebe o mesmo bloco de antes', :aggregate_failures do
    query = nil
    allow(Autonomia::Guide::Seed).to receive(:ready_agent_for).and_return(instance_double(Autonomia::Agents::Agent))
    allow(Autonomia::Agents::Retriever).to receive(:new).and_return(instance_double(Autonomia::Agents::Retriever, retrieve: []))
    allow(Autonomia::Agents::Answerer).to receive(:new) do |**kwargs|
      query = kwargs[:query]
      instance_double(Autonomia::Agents::Answerer,
                      answer: Autonomia::Agents::AnswerResult.new(reply: 'ok', confidence: 1.0, handoff: { should: false }))
    end

    perform_enqueued_jobs(only: Autonomia::Guide::ChatJob) do
      post rota, params: { message: 'liga esta', route_context: 'automacoes_editar', route_params: { accountId: account.id, id: '42' } },
                 headers: admin.create_new_auth_token, as: :json
    end

    expect(query).to include('Tela atual: automacoes_editar. Registro aberto na tela: id=42.')
    expect(query).not_to include('O QUE A PESSOA ESTÁ VENDO')
  end
end
