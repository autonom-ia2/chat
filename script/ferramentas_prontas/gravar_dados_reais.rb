# #2858 — grava o `dados` REAL de cada fonte grátis das ferramentas prontas, para o spec de cobertura do resultado do
# "Experimente" (app/javascript/dashboard/routes/dashboard/autonomia/agentes/specs/vitrine/resultadoDasFontes.spec.js).
#
# Uma chamada real por consulta, pelo próprio adaptador do servidor: os provedores da fonte na ordem de reserva, o
# `refinar` da consulta e o `Resposta.enxugar`, como na `Execucao`. Sem cache (o `Rails.cache` vira NullStore aqui), sem
# conta, sem contador, sem IA e sem fonte paga. Pessoa física sai anonimizada (o nome e o registro de cada corretor).
#
# Uso (ambiente de teste, nunca o de produção):
#   RAILS_ENV=test bundle exec rails runner script/ferramentas_prontas/gravar_dados_reais.rb [fonte ...]
# Sem fonte: todas as do CASOS. Com fonte (ex.: ncm compras_governo): só elas. Cada arquivo é reescrito por consulta.
FP = Autonomia::FerramentasProntas
DESTINO = Rails.root.join('app/javascript/dashboard/routes/dashboard/autonomia/agentes/specs/vitrine/dados-reais')

CASOS = [
  ['cep', 'endereco', { 'cep' => '01001-000' }],
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
  ['hospitais', 'estabelecimentos', { 'cidade' => 'Campinas', 'uf' => 'sp', 'tipo' => 'hospital' }],
  ['procedimentos', 'codigo', { 'codigo' => '10101012' }],
  ['procedimentos', 'busca', { 'busca' => 'hemograma' }],
  ['doencas', 'codigo', { 'codigo' => 'J45' }],
  ['doencas', 'busca', { 'busca' => 'asma' }],
  ['ncm', 'buscar', { 'busca' => 'parafuso' }],
  ['ncm', 'codigo', { 'codigo' => '7318.15.00' }],
  ['compras_governo', 'compras', { 'cidade' => 'Uberlândia', 'uf' => 'mg' }],
  ['estacoes', 'estacoes', { 'cidade' => 'Uberlândia', 'uf' => 'mg' }],
  ['chuva', 'chuva', { 'cidade' => 'Uberlândia', 'uf' => 'mg' }],
  ['produtos_seguradoras', 'seguradoras', { 'busca' => 'Allianz' }],
  ['produtos_seguradoras', 'produtos', { 'seguradora' => 'Allianz', 'ramo' => 'riscos_ciberneticos' }],
  ['corretor_susep', 'por_nome', { 'nome' => 'corretora de seguros', 'tipo_pessoa' => 'pj' }]
].freeze

# O corretor pode ser pessoa física: nome e registro trocados por exemplo (situação e ramos ficam os reais).
def anonimizar(chave, dados)
  return dados unless chave == 'corretor_susep'

  corretores = dados['corretores'].each_with_index.map do |corretor, indice|
    corretor.merge('nome' => "CORRETORA EXEMPLO #{indice + 1} LTDA", 'registro_susep' => (100_000_001 + indice).to_s)
  end
  dados.merge('corretores' => corretores)
end

def consultar(fonte, consulta, params)
  cliente = FP::ClienteHttp.new(hosts: fonte.hosts, prazo_final: FP::ClienteHttp.agora + consulta.prazo_total)
  falhas = []
  consulta.provedores.select { |provedor| provedor.aplica?(consulta, params) }.each do |provedor|
    dados = provedor.new(cliente, prazo: consulta.prazo_por_fonte).consultar(consulta, consulta.para_a_fonte(params))
    refinados = consulta.refinar(dados, params)
    return [provedor.nome, refinados, falhas] if refinados

    falhas << "#{provedor.nome}:refinar_vazio"
  rescue FP::Provedor::NaoEncontrado
    falhas << "#{provedor.nome}:nao_encontrado"
  rescue FP::Provedor::Falha => e
    falhas << "#{provedor.nome}:#{e.motivo}"
  end
  [nil, nil, falhas]
end

def gravar(chave, nome, provedor, dados)
  arquivo = DESTINO.join("#{chave}.json")
  atual = File.exist?(arquivo) ? JSON.parse(File.read(arquivo)) : {}
  novo = atual.merge(nome => { 'provedor' => provedor, 'dados' => FP::Resposta.enxugar(anonimizar(chave, dados)) })
  File.write(arquivo, "#{JSON.pretty_generate(novo)}\n")
end

abort('rode com RAILS_ENV=test') if Rails.env.production?
Rails.cache = ActiveSupport::Cache::NullStore.new
escolhidas = ARGV.presence

Time.use_zone('America/Sao_Paulo') do
  CASOS.each do |chave, nome, argumentos|
    next if escolhidas&.exclude?(chave)

    fonte = FP::Catalogo.buscar(chave)
    consulta = fonte.consulta(nome)
    params, campo = consulta.conferir(argumentos)
    next puts("PEDIDO INVÁLIDO #{chave}.#{nome}: #{campo}") if params.nil?

    provedor, dados, falhas = consultar(fonte, consulta, params)
    next puts("SEM RESPOSTA #{chave}.#{nome}: #{falhas.join(', ')}") if dados.nil?

    gravar(chave, nome, provedor, dados)
    puts "OK #{chave}.#{nome} via #{provedor}#{" (antes: #{falhas.join(', ')})" if falhas.any?}"
  end
end
