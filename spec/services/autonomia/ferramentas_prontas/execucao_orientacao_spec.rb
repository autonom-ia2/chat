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
    account.enable_features!(Autonomia::FerramentasProntas::Fontes::Ncm::FLAG, Autonomia::FerramentasProntas::Bases::FLAG)
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

  it 'queimadas sem cidade e sem localizacao: pergunta o lugar; so a latitude: tira a longitude da mesma localizacao' do
    sem_lugar = recusa('queimadas', 'dias' => 2)
    so_latitude = recusa('queimadas', 'latitude' => -3.1)

    expect(sem_lugar).to include('campo' => 'cidade')
    expect(sem_lugar['orientacao']).to include('pergunte ao cliente', 'localização')
    expect(so_latitude).to include('campo' => 'longitude')
    expect(so_latitude['orientacao']).to include('Não pergunte ao cliente', 'localização')
  end

  it 'queimadas e placas solares: cidade com nome repetido diz os estados; UF errada corrige sem perguntar' do
    queimadas = recusa('queimadas', 'cidade' => 'Bom Jesus')
    solar = recusa('geracao_solar', 'consulta' => 'cidade', 'cidade' => 'Bom Jesus')
    uf_errada = recusa('queimadas', 'cidade' => 'Sorriso', 'uf' => 'SP')

    expect([queimadas, solar]).to all(include('campo' => 'uf', 'candidatos' => include('PI', 'RS')))
    expect(queimadas['orientacao']).to include('mais de um estado')
    expect(uf_errada).to include('campo' => 'uf', 'candidatos' => ['MT'])
    expect(uf_errada['orientacao']).to include('sem perguntar')
  end

  it 'queimadas e placas solares: a UF vale pelo nome do estado' do
    fontes = Autonomia::FerramentasProntas::Fontes
    queimadas, = fontes::Queimadas::FONTE.consulta('focos').conferir('cidade' => 'Sorriso', 'uf' => 'Mato Grosso')
    solar, = fontes::GeracaoSolar::FONTE.consulta('cidade').conferir('cidade' => 'Sorriso', 'uf' => 'Mato Grosso')

    expect([queimadas, solar]).to all(include('uf' => 'mt'))
  end

  it 'planos de saude e transportadoras sem nenhum dado: pergunta o nome; registro torto: usa o nome sem perguntar' do
    expect(recusa('planos_de_saude', {})['orientacao']).to include('pergunte ao cliente', 'operadora')
    expect(recusa('transportadoras', {})['orientacao']).to include('pergunte ao cliente', 'transportadora')
    expect(recusa('planos_de_saude', 'registro_ans' => '12')['orientacao']).to include('Não pergunte ao cliente', 'nome')
    expect(recusa('transportadoras', 'rntrc' => '12345678901')['orientacao']).to include('Não pergunte ao cliente', 'nome')
  end

  it 'aeronave com matricula fora do padrao brasileiro: pergunta a matricula' do
    saida = recusa('aeronaves', 'matricula' => 'N12345')

    expect(saida).to include('campo' => 'matricula')
    expect(saida['orientacao']).to include('pergunte ao cliente', 'PR-ABC')
  end

  it 'todo parametro do catalogo que vai a fonte, ou que e obrigatorio mesmo local, tem orientacao propria' do
    sem = Autonomia::FerramentasProntas::Catalogo.todas.flat_map do |fonte|
      obrigatorios = fonte.consultas.flat_map(&:obrigatorios)
      fonte.consultas.flat_map(&:parametros).uniq(&:nome)
           .select { |param| !param.local? || obrigatorios.include?(param) }
           .reject(&:orientacao).map { |param| "#{fonte.chave}.#{param.nome}" }
    end

    expect(sem).to eq([])
  end

  it 'a cidade das estacoes (local, mas e ela que acha o ponto) tambem tem orientacao' do
    expect(Autonomia::FerramentasProntas::Fontes::Estacoes::CIDADE.orientacao).to include('pergunte ao cliente')
  end

  it 'o texto generico fica so como padrao do que nao tem orientacao' do
    saida = JSON.parse(Autonomia::FerramentasProntas::Resposta.pedido_invalido('qualquer'))

    expect(saida['orientacao']).to include('Confira com o cliente')
  end
end
