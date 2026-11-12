# As colunas da planilha de "Trazer minha lista" (#2896) e para onde cada uma vai. Lê o que o leitor de planilhas gravou
# em `schema_resolution` (as colunas e os quatro alvos: nome, telefone, e-mail e empresa) e o que a pessoa escolheu na
# tela para as outras colunas, guardado em `options['trazer']['destinos']` pelo índice da coluna.
#
# Coluna que não é alvo vira informação da pessoa, a menos que esteja marcada como "não guardar". Coluna sem título e sem
# nenhum valor não aparece: o leitor também não a guarda.
#
# `chaves_que_nao_guardam` é a única regra de quais colunas ficam de fora: a leitura (que não põe o valor na linha nem no
# resumo), a gravação (que não cria a informação) e a troca na tela (que apaga o valor das linhas) perguntam aqui.
class Relacionamentos::Trazer::Colunas
  ALVOS = { 'name' => 'nome', 'phone' => 'telefone', 'email' => 'email', 'company' => 'empresa' }.freeze
  INFORMACAO = 'informacao'.freeze
  NAO_GUARDAR = 'nao_guardar'.freeze

  # extras: [{ 'index' => 4, 'key' => 'Situação' }], como o leitor de planilhas entrega as colunas que não são alvo.
  def self.chaves_que_nao_guardam(opcoes, extras)
    destinos = opcoes.to_h.dig('trazer', 'destinos').to_h
    extras.filter_map { |extra| extra['key'] if destinos[extra['index'].to_s] == NAO_GUARDAR }
  end

  def initialize(importacao)
    @importacao = importacao
    @resolucao = importacao.schema_resolution.to_h
  end

  def call
    visiveis.map do |coluna|
      alvo = alvos.key(coluna['index'])
      alvo ? do_alvo(coluna, alvo) : extra(coluna)
    end
  end

  # { 'name' => 0, 'phone' => 1, 'email' => nil, 'company' => nil }
  def alvos
    @alvos ||= ALVOS.keys.index_with { |alvo| @resolucao.dig('targets', alvo, 'column') }
  end

  def indices
    visiveis.pluck('index')
  end

  def total
    todas.size
  end

  # As chaves (como estão em `extra_values` de cada linha) das colunas que a pessoa mandou não guardar.
  def chaves_que_nao_guardam
    self.class.chaves_que_nao_guardam(@importacao.options, extras)
  end

  # A chave da coluna em `extra_values`, ou nil quando ela é alvo ou não existe.
  def chave_da_extra(indice)
    extras.find { |extra| extra['index'] == indice }&.fetch('key')
  end

  def destino_da_extra(indice)
    destinos.fetch(indice.to_s, INFORMACAO)
  end

  private

  # As colunas que não são alvo, cada uma com a chave que o leitor lhe deu (as duas listas saem na mesma ordem).
  def extras
    @extras ||= begin
      fora_dos_alvos = visiveis.reject { |coluna| alvos.value?(coluna['index']) }
      fora_dos_alvos.zip(Array(@importacao.extra_columns)).map { |coluna, chave| { 'index' => coluna['index'], 'key' => chave } }
    end
  end

  def todas
    Array(@resolucao['columns'])
  end

  def visiveis
    @visiveis ||= todas.select do |coluna|
      alvos.value?(coluna['index']) || coluna['header'].present? || coluna['non_blank_count'].to_i.positive?
    end
  end

  # O leitor sugeriu a coluna sem certeza: a tela mostra como duvidosa até a pessoa escolher.
  def do_alvo(coluna, alvo)
    item = { indice: coluna['index'], nome: coluna['header'].to_s, destino: ALVOS.fetch(alvo) }
    @resolucao.dig('targets', alvo, 'confident') == false ? item.merge(duvidosa: true) : item
  end

  def extra(coluna)
    destino = destino_da_extra(coluna['index'])
    item = { indice: coluna['index'], nome: coluna['header'].to_s, destino: destino }
    destino == INFORMACAO ? item.merge(campo: { nome: coluna['header'].to_s, para_que_serve: '' }) : item
  end

  def destinos
    @destinos ||= @importacao.options.to_h.dig('trazer', 'destinos').to_h
  end
end
