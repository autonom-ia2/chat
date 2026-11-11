# #2858 — o que grava o `dados` REAL de cada fonte grátis das ferramentas prontas, para o spec de cobertura do resultado
# do "Experimente" (app/javascript/dashboard/routes/dashboard/autonomia/agentes/specs/vitrine/resultadoDasFontes.spec.js).
# Quem roda é `gravar_dados_reais.rb`, ao lado; aqui ficam os pedidos, a anonimização e a gravação (o spec carrega este).
#
# Uma chamada real por consulta, pelo próprio adaptador do servidor: os provedores da fonte na ordem de reserva, o
# `refinar` da consulta e o `Resposta.enxugar`, como na `Execucao`. Sem cache, sem conta, sem contador, sem IA e sem
# fonte paga.
#
# O repositório é público: cada fonte gravada está em ANONIMIZACAO, ou como :sem_pessoa_fisica ou com o anonimizador
# dela. Fonte fora da lista não é gravada (SemDecisao).
module DadosReaisDasProntas
  DESTINO = Rails.root.join('app/javascript/dashboard/routes/dashboard/autonomia/agentes/specs/vitrine/dados-reais')

  class SemDecisao < StandardError; end
  class PedidoDesconhecido < StandardError; end

  CASOS = [
    ['cep', 'endereco', { 'cep' => '01001-000' }],
    ['cep', 'por_endereco', { 'logradouro' => 'Avenida Paulista', 'cidade' => 'São Paulo' }],
    ['cnpj', 'empresa', { 'cnpj' => '33.000.167/0001-01' }],
    ['cpf', 'conferir', { 'cpf' => '111.444.777-35' }],
    ['fipe', 'marcas', { 'tipo' => 'carros' }],
    ['fipe', 'modelos', { 'tipo' => 'carros', 'marca' => '23', 'busca' => 'onix' }],
    ['fipe', 'preco', { 'tipo' => 'carros', 'codigo_fipe' => '004517-9', 'ano' => 2020 }],
    ['feriados', 'feriados', { 'ano' => 2026 }],
    ['feriados', 'dias_uteis', { 'ate' => '2026-11-30' }],
    ['banco_central', 'selic', {}],
    ['banco_central', 'ipca', {}],
    ['banco_central', 'dolar', {}],
    ['banco_central', 'focus', { 'indicador' => 'ipca' }],
    ['cidades', 'estados', {}],
    ['cidades', 'cidades', { 'uf' => 'ac' }],
    ['ddd', 'ddd', { 'ddd' => '34' }],
    ['localizacao', 'cidade', { 'latitude' => -18.9186, 'longitude' => -48.2772 }],
    ['bancos', 'banco', { 'codigo' => '341' }],
    ['bancos', 'por_nome', { 'nome' => 'Itaú' }],
    ['hospitais', 'estabelecimentos', { 'cidade' => 'Campinas', 'uf' => 'sp', 'tipo' => 'hospital' }],
    ['procedimentos', 'codigo', { 'codigo' => '10101012' }],
    ['procedimentos', 'busca', { 'busca' => 'hemograma' }],
    ['doencas', 'codigo', { 'codigo' => 'J45' }],
    ['doencas', 'busca', { 'busca' => 'asma' }],
    # O caso real do teste em produção (11/11/2026): a busca acha o grupo 0901.2, que abre nos códigos da nota.
    ['ncm', 'buscar', { 'busca' => 'café torrado' }],
    ['ncm', 'codigo', { 'codigo' => '0901.21.00' }],
    ['compras_governo', 'compras', { 'cidade' => 'Uberlândia', 'uf' => 'mg' }],
    ['estacoes', 'estacoes', { 'cidade' => 'Uberlândia', 'uf' => 'mg' }],
    # Vários dias: a lista de itens sem nome (identificados pela data) passa pelo spec de cobertura.
    ['chuva', 'chuva', { 'cidade' => 'Uberlândia', 'uf' => 'mg', 'de' => '2026-11-04', 'ate' => '2026-11-10' }],
    ['produtos_seguradoras', 'seguradoras', { 'busca' => 'Allianz' }],
    ['produtos_seguradoras', 'produtos', { 'seguradora' => 'Allianz', 'ramo' => 'transporte' }],
    ['corretor_susep', 'por_nome', { 'nome' => 'corretora de seguros', 'tipo_pessoa' => 'pj' }]
  ].freeze

  # CNPJ: o do MEI (empresário individual) tem o nome da pessoa na razão social, e a fonte não diz de antemão se é MEI.
  # Todo CNPJ gravado sai com número, razão social e nome fantasia de exemplo; situação, datas e atividade ficam.
  CNPJ = lambda do |dados|
    dados.merge('cnpj' => '11.222.333/0001-81', 'razao_social' => 'EMPRESA EXEMPLO LTDA',
                'nome_fantasia' => ('EXEMPLO' if dados.key?('nome_fantasia'))).compact
  end
  # Corretor: pode ser pessoa física; o nome e o registro de cada um viram exemplo (situação e ramos ficam).
  CORRETOR = lambda do |dados|
    corretores = dados['corretores'].each_with_index.map do |corretor, indice|
      corretor.merge('nome' => "CORRETORA EXEMPLO #{indice + 1} LTDA", 'registro_susep' => (100_000_001 + indice).to_s)
    end
    dados.merge('corretores' => corretores)
  end

  # Cada fonte: :sem_pessoa_fisica (o motivo ao lado) ou o anonimizador.
  ANONIMIZACAO = {
    'cep' => :sem_pessoa_fisica, # endereço público (praça, rua, faixa de número), sem morador
    'cnpj' => CNPJ,
    'cpf' => :sem_pessoa_fisica, # conta local sobre um número de exemplo; o dado não traz o CPF
    'fipe' => :sem_pessoa_fisica, # tabela de preços de veículos
    'feriados' => :sem_pessoa_fisica,
    'banco_central' => :sem_pessoa_fisica,
    'cidades' => :sem_pessoa_fisica,
    'ddd' => :sem_pessoa_fisica,
    'localizacao' => :sem_pessoa_fisica, # a sede do município mais próxima
    'bancos' => :sem_pessoa_fisica, # instituições financeiras
    'hospitais' => :sem_pessoa_fisica, # a fonte já tira o estabelecimento de pessoa física (natureza jurídica 4)
    'procedimentos' => :sem_pessoa_fisica,
    'doencas' => :sem_pessoa_fisica,
    'ncm' => :sem_pessoa_fisica,
    'compras_governo' => :sem_pessoa_fisica, # órgãos públicos; quem cadastrou (usuarioNome) a fonte já não manda
    'estacoes' => :sem_pessoa_fisica,
    'chuva' => :sem_pessoa_fisica,
    'produtos_seguradoras' => :sem_pessoa_fisica, # seguradoras e produtos
    'corretor_susep' => CORRETOR
  }.freeze

  module_function

  def anonimizar(chave, dados)
    decisao = ANONIMIZACAO.fetch(chave) do
      raise SemDecisao, "#{chave}: sem decisão de anonimização. Ponha a fonte em ANONIMIZACAO, como :sem_pessoa_fisica " \
                        '(com o motivo) ou com o anonimizador dela, antes de gravar.'
    end
    decisao == :sem_pessoa_fisica ? dados : decisao.call(dados)
  end

  def consultar(fonte, consulta, params)
    prontas = Autonomia::FerramentasProntas
    cliente = prontas::ClienteHttp.new(hosts: fonte.hosts, prazo_final: prontas::ClienteHttp.agora + consulta.prazo_total)
    falhas = []
    consulta.provedores.select { |provedor| provedor.aplica?(consulta, params) }.each do |provedor|
      dados = provedor.new(cliente, prazo: consulta.prazo_por_fonte).consultar(consulta, consulta.para_a_fonte(params))
      refinados = consulta.refinar(dados, params)
      return [provedor.nome, refinados, falhas] if refinados

      falhas << "#{provedor.nome}:refinar_vazio"
    rescue prontas::Provedor::NaoEncontrado
      falhas << "#{provedor.nome}:nao_encontrado"
    rescue prontas::Provedor::Falha => e
      falhas << "#{provedor.nome}:#{e.motivo}"
    end
    [nil, nil, falhas]
  end

  def gravar(chave, nome, provedor, dados)
    arquivo = DESTINO.join("#{chave}.json")
    atual = File.exist?(arquivo) ? JSON.parse(File.read(arquivo)) : {}
    limpo = Autonomia::FerramentasProntas::Resposta.enxugar(anonimizar(chave, dados))
    File.write(arquivo, "#{JSON.pretty_generate(atual.merge(nome => { 'provedor' => provedor, 'dados' => limpo }))}\n")
  end

  # Os pedidos escolhidos: todos, os de uma fonte ("ncm") ou uma consulta só ("banco_central.focus"). Pedido que não
  # está no CASOS aborta (sem isso, um nome errado gravava nada e parecia ter dado certo).
  def casos(escolhidas)
    conhecidos = CASOS.flat_map { |chave, nome, _argumentos| [chave, "#{chave}.#{nome}"] }
    desconhecidos = Array(escolhidas) - conhecidos
    raise PedidoDesconhecido, "#{desconhecidos.join(', ')}: não está no CASOS (fonte ou fonte.consulta)." if desconhecidos.any?

    CASOS.select do |chave, nome, _argumentos|
      escolhidas.blank? || escolhidas.include?(chave) || escolhidas.include?("#{chave}.#{nome}")
    end
  end

  # Confere a decisão de todas as fontes pedidas ANTES de chamar qualquer uma.
  def rodar(escolhidas)
    casos = casos(escolhidas)
    casos.map(&:first).uniq.each { |chave| anonimizar(chave, {}) unless ANONIMIZACAO[chave] }
    casos.each { |chave, nome, argumentos| rodar_um(chave, nome, argumentos) }
  end

  def rodar_um(chave, nome, argumentos)
    fonte = Autonomia::FerramentasProntas::Catalogo.buscar(chave)
    consulta = fonte.consulta(nome)
    params, campo = consulta.conferir(argumentos)
    return puts("PEDIDO INVÁLIDO #{chave}.#{nome}: #{campo}") if params.nil?

    provedor, dados, falhas = consultar(fonte, consulta, params)
    return puts("SEM RESPOSTA #{chave}.#{nome}: #{falhas.join(', ')}") if dados.nil?

    gravar(chave, nome, provedor, dados)
    puts "OK #{chave}.#{nome} via #{provedor}#{" (antes: #{falhas.join(', ')})" if falhas.any?}"
  end
end
