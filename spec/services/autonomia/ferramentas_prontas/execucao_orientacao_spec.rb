require 'rails_helper'

# #2858 — regra "QI 70" do Rodrigo (11/11/2026): o dado técnico que dá para deduzir, o agente deduz; pergunta ao cliente
# só o que muda o resultado e não dá para deduzir. A recusa de parâmetro diz qual dos dois é, por parâmetro.
RSpec.describe Autonomia::FerramentasProntas::Execucao do
  let(:account) { create(:account) }
  let(:agent) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Bot', agent_type: 'custom', status: :active, enabled: true,
                                     instruction: 'Atenda.')
  end

  before do
    resolver_hosts_das_prontas
    ligar_prontas(account)
    ligar_consultas(account)
    account.enable_features!(Autonomia::FerramentasProntas::Fontes::Ncm::FLAG)
  end

  def recusa(fonte, argumentos)
    executar_pronta(incluir_pronta(fonte, conta: account, agente: agent), argumentos)
  end

  it 'dado deduzivel: manda corrigir sem perguntar ao cliente, e diz como' do
    saida = recusa('cidades', 'consulta' => 'cidades', 'uf' => 'Minas')

    expect(saida).to include('situacao' => 'pedido_invalido', 'campo' => 'uf')
    expect(saida['orientacao']).to include('Não pergunte ao cliente', 'cidade')
    expect(saida['orientacao']).not_to include('Confira com o cliente')
  end

  it 'dado que nao da para deduzir: manda perguntar ao cliente' do
    saida = recusa('cpf', 'cpf' => '1234')

    expect(saida).to include('situacao' => 'pedido_invalido', 'campo' => 'cpf')
    expect(saida['orientacao']).to include('pergunte ao cliente', 'CPF')
  end

  it 'DDD fora do plano: tira do telefone, e so pergunta se nao for do Brasil' do
    expect(recusa('ddd', 'ddd' => '20')['orientacao']).to include('Não pergunte ao cliente', 'telefone')
  end

  it 'consulta fora da lista: corrige escolhendo uma das consultas' do
    saida = recusa('fipe', 'consulta' => 'placa', 'tipo' => 'carros')

    expect(saida).to include('campo' => 'consulta')
    expect(saida['orientacao']).to include('Não pergunte ao cliente', 'marcas', 'modelos', 'preco')
  end

  it 'todo parametro do catalogo que vai a fonte tem orientacao propria (deduza ou pergunte)' do
    sem = Autonomia::FerramentasProntas::Catalogo.todas.flat_map do |fonte|
      fonte.consultas.flat_map(&:parametros).uniq(&:nome).reject(&:local?).reject(&:orientacao).map { |param| "#{fonte.chave}.#{param.nome}" }
    end

    expect(sem).to eq([])
  end

  it 'o texto generico fica so como padrao do que nao tem orientacao' do
    saida = JSON.parse(Autonomia::FerramentasProntas::Resposta.pedido_invalido('qualquer'))

    expect(saida['orientacao']).to include('Confira com o cliente')
  end
end
