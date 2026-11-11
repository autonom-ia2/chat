# #2858 F5 — grava o `dados` REAL das cinco bases baixadas (planos de saúde, aeronaves, transportadoras, placas solares e
# focos de queimada), para o spec de cobertura do resultado do "Experimente"
# (app/javascript/dashboard/routes/dashboard/autonomia/agentes/specs/vitrine/resultadoDasFontes.spec.js).
#
# Cada base é importada do arquivo OFICIAL real (`Bases::Importacao`, a mesma da rodada) no banco de TESTE, e cada
# consulta passa pelo próprio adaptador do servidor: o provedor da base, o `refinar` da consulta e o `Resposta.enxugar`.
# No fim, as tabelas das bases e as travas são limpas (o banco de teste volta vazio). Sem IA, sem conta, sem contador.
#
# O repositório é público: pessoa física nunca entra (a base já não guarda), e o nome e o documento de quem pode ser
# MEI (a empresa dona da aeronave, a transportadora) saem trocados por exemplos fictícios (ANONIMIZACAO), assim como a
# matrícula e o número de série da aeronave, que levam ao dono pelo RAB.
#
# Uso (só no ambiente de teste; baixa ~300 MB das fontes oficiais e leva uns 10 minutos):
#   RAILS_ENV=test bundle exec rails runner script/ferramentas_prontas/gravar_dados_reais_das_bases.rb [base ...]
abort('rode com RAILS_ENV=test') unless Rails.env.test?
Rails.cache = ActiveSupport::Cache::NullStore.new

module DadosReaisDasBases
  DESTINO = Rails.root.join('app/javascript/dashboard/routes/dashboard/autonomia/agentes/specs/vitrine/dados-reais')
  Bases = Autonomia::FerramentasProntas::Bases
  TABELAS = %w[autonomia_prontas_bases autonomia_prontas_operadoras_ans autonomia_prontas_aeronaves
               autonomia_prontas_geracao_distribuida autonomia_prontas_transportadores autonomia_prontas_focos_queimada].freeze
  # Com a máscara, como a fonte devolve.
  CNPJS_DE_EXEMPLO = %w[11222333000181 11444777000161 33444555000181]
                     .map { |cnpj| Autonomia::FerramentasProntas::Fontes::Cnpj.formatado(cnpj) }.freeze

  # Empresa que pode ser MEI (o nome é o da pessoa): nome, CNPJ e registro viram exemplo; situação, datas e lugar ficam.
  EMPRESAS = lambda do |dados, chave_da_lista, rotulo|
    lista = dados[chave_da_lista].each_with_index.map do |item, indice|
      item.merge({ 'nome' => ("#{rotulo} EXEMPLO #{indice + 1} LTDA" if item.key?('nome')),
                   'cnpj' => (CNPJS_DE_EXEMPLO[indice % CNPJS_DE_EXEMPLO.size] if item.key?('cnpj')),
                   'rntrc' => (format('%09d', indice + 1) if item.key?('rntrc')) }.compact)
    end
    dados.merge(chave_da_lista => lista)
  end
  LISTAS_DE_EMPRESAS = %w[proprietarios_empresas operadores_empresas].freeze
  # A matrícula e o número de série levam à aeronave (e ao dono) pelo RAB público: saem trocados por exemplos. A
  # matrícula de exemplo começa por Q depois do prefixo, combinação que o Anexo 7 da OACI não deixa registrar (confunde
  # com o código Q), e é conferida na base importada: se existir, a gravação para.
  MATRICULA_DE_EXEMPLO = 'PPQZZ'.freeze
  SERIE_DE_EXEMPLO = 'EXEMPLO-0001'.freeze
  AERONAVE = lambda do |dados|
    abort("a matrícula de exemplo #{MATRICULA_DE_EXEMPLO} existe no RAB: troque") if Bases::Aeronave.exists?(matricula: MATRICULA_DE_EXEMPLO)

    aeronaves = dados['aeronaves'].map do |aeronave|
      exemplo = aeronave.merge({ 'matricula' => MATRICULA_DE_EXEMPLO,
                                 'numero_de_serie' => (SERIE_DE_EXEMPLO if aeronave.key?('numero_de_serie')) }.compact)
      LISTAS_DE_EMPRESAS.reduce(exemplo) do |atual, chave|
        atual.key?(chave) ? EMPRESAS.call(atual, chave, 'AVIACAO') : atual
      end
    end
    dados.merge('aeronaves' => aeronaves)
  end

  ANONIMIZACAO = {
    'planos_de_saude' => :sem_pessoa_fisica, # operadoras de plano de saúde, pessoas jurídicas registradas na ANS
    'aeronaves' => AERONAVE,
    'transportadoras' => ->(dados) { EMPRESAS.call(dados, 'registros', 'TRANSPORTADORA') },
    'geracao_solar' => :sem_pessoa_fisica, # só a soma por CEP e município
    'queimadas' => :sem_pessoa_fisica # focos de satélite
  }.freeze

  module_function

  # [base, nome no arquivo, consulta, argumentos (ou um bloco que acha o pedido na base importada)].
  def casos
    [
      ['queimadas', 'focos', 'focos', -> { cidade_com_mais_focos }],
      ['planos_de_saude', 'operadora', 'operadora', { 'nome' => 'unimed campinas' }],
      ['planos_de_saude', 'operadora_cancelada', 'operadora', -> { { 'registro_ans' => cancelada } }],
      ['aeronaves', 'aeronave', 'aeronave', -> { { 'matricula' => aeronave_de_empresa } }],
      ['geracao_solar', 'cep', 'cep', -> { { 'cep' => cep_com_mais_sistemas } }],
      ['geracao_solar', 'cidade', 'cidade', { 'cidade' => 'Campinas', 'uf' => 'sp' }],
      ['transportadoras', 'registro', 'registro', -> { { 'rntrc' => transportadora } }],
      ['transportadoras', 'registro_pelo_nome', 'registro', { 'nome' => 'transportes rapido' }]
    ]
  end

  def rodar(escolhidas)
    limpar
    escolhidos = casos.select { |base, *| escolhidas.blank? || escolhidas.include?(base) }
    # Base por base: importa e já grava, e a falha de uma fonte não perde o que as outras gravaram.
    escolhidos.group_by(&:first).each do |base, do_caso|
      importar(base)
      do_caso.each { |_base, nome, consulta, argumentos| gravar(base, nome, consulta, argumentos) }
    end
  ensure
    limpar
  end

  def importar(base)
    resultado = Bases::Importacao.new(Bases.buscar(base)).call
    estado = Bases::Estado.find_by(base: base)
    abort("#{base}: a importação real não entrou (#{resultado}, #{estado&.motivo_da_falha})") unless resultado == :atualizada

    puts "importada #{base}: #{estado.linhas} linhas"
  end

  def gravar(base, nome, consulta_nome, argumentos)
    fonte = Autonomia::FerramentasProntas::Catalogo.buscar(base)
    consulta = fonte.consulta(consulta_nome)
    pedido = argumentos.respond_to?(:call) ? argumentos.call : argumentos
    params, campo = consulta.conferir(pedido)
    abort("#{base}.#{nome}: pedido inválido (#{campo})") if params.nil?

    provedor = consulta.provedores.first
    dados = consulta.refinar(provedor.new(nil, prazo: consulta.prazo_por_fonte).consultar(consulta, consulta.para_a_fonte(params)), params)
    escrever(base, nome, provedor.nome, dados)
    puts "OK #{base}.#{nome} via #{provedor.nome}"
  end

  def escrever(base, nome, provedor, dados)
    decisao = ANONIMIZACAO.fetch(base)
    limpo = Autonomia::FerramentasProntas::Resposta.enxugar(decisao == :sem_pessoa_fisica ? dados : decisao.call(dados))
    arquivo = DESTINO.join("#{base}.json")
    atual = File.exist?(arquivo) ? JSON.parse(File.read(arquivo)) : {}
    FileUtils.mkdir_p(DESTINO)
    File.write(arquivo, "#{JSON.pretty_generate(atual.merge(nome => { 'provedor' => provedor, 'dados' => limpo }))}\n")
  end

  def cidade_com_mais_focos
    codigo = Bases::FocoDeQueimada.where(detectado_em: 1.day.ago.beginning_of_day..).group(:codigo_municipio).order(Arel.sql('COUNT(*) DESC'))
                                  .limit(1).pick(:codigo_municipio)
    municipio = Autonomia::FerramentasProntas::Municipios.por_codigo(codigo)
    { 'cidade' => municipio.nome, 'uf' => municipio.uf.downcase, 'dias' => 1 }
  end

  def cancelada
    Bases::Operadora.where(ativa: false).order(cancelada_em: :desc).pick(:registro_ans)
  end

  def aeronave_de_empresa
    Bases::Aeronave.where("dados ? 'proprietarios_empresas' AND dados ? 'operadores_empresas' AND dados ? 'gravames'")
                   .order(:matricula).pick(:matricula)
  end

  def cep_com_mais_sistemas
    Bases::GeracaoDistribuida.where.not(cep: nil).group(:cep).order(Arel.sql('SUM(quantidade) DESC')).limit(1).pick(:cep)
  end

  def transportadora
    Bases::Transportador.where(categoria: 'empresa', equiparado: true).where.not(nome: nil).order(:rntrc).pick(:rntrc)
  end

  def limpar
    TABELAS.each { |tabela| ActiveRecord::Base.connection.execute("DELETE FROM #{tabela}") }
    Bases.importadores.each { |importador| Redis::Alfred.delete("#{Bases::Importacao::TRAVA}:#{importador.chave}") }
  end
end

Time.use_zone('America/Sao_Paulo') { DadosReaisDasBases.rodar(ARGV) }
