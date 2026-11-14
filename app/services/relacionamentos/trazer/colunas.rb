# As colunas da planilha de "Trazer minha lista" (#2896) e para onde cada uma vai. Lê o que o leitor de planilhas gravou
# em `schema_resolution` (as colunas e os quatro alvos: nome, telefone, e-mail e empresa) e o que a pessoa escolheu na
# tela para as outras colunas, guardado em `options['trazer']['destinos']` pelo índice da coluna.
#
# Coluna que não é alvo vira informação da pessoa (com o nome e o "para que serve" que a pessoa escreveu, guardados em
# `options['trazer']['campos']`), a menos que a pessoa tenha escolhido outro destino: cidade, telefone da empresa, cliente
# ou "não guardar". Coluna sem título e sem nenhum valor não aparece: o leitor também não a guarda.
#
# O destino "telefone da empresa" só existe com coluna de empresa na planilha e Empresas ligada na conta (`tem_empresa?`).
#
# `chaves_que_nao_guardam` é a única regra de quais colunas ficam de fora: a leitura (que não põe o valor na linha nem no
# resumo), a gravação (que não cria a informação) e a troca na tela (que apaga o valor das linhas) perguntam aqui.
class Relacionamentos::Trazer::Colunas
  ALVOS = { 'name' => 'nome', 'phone' => 'telefone', 'email' => 'email', 'company' => 'empresa' }.freeze
  INFORMACAO = 'informacao'.freeze
  NAO_GUARDAR = 'nao_guardar'.freeze
  # Para onde vai a coluna que não é alvo. "informacao" é o padrão e não fica escrito.
  TELEFONE_DA_EMPRESA = 'telefone_da_empresa'.freeze
  EXTRAS = [INFORMACAO, NAO_GUARDAR, 'cidade', TELEFONE_DA_EMPRESA, 'cliente'].freeze
  TELEFONE_DA_PESSOA = 'da_pessoa'.freeze

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

  # Para onde vai a coluna deste índice: um dos quatro alvos ou o destino da coluna que não é alvo.
  def destino(indice)
    alvo = alvos.key(indice)
    alvo ? ALVOS.fetch(alvo) : destino_da_extra(indice)
  end

  # O telefone da empresa só tem para onde ir quando a planilha tem coluna de empresa e a conta tem Empresas. Quem vai
  # trocar uma coluna pergunta com os alvos como ficariam depois da troca.
  def tem_empresa?(com_os_alvos = alvos)
    com_os_alvos['company'].present? && CampaignImports::CompanyLinker.available?(@importacao.account)
  end

  # As chaves (em `extra_values`) das colunas que vão para este destino, na ordem da planilha.
  def chaves_do_destino(destino)
    extras.filter_map { |extra| extra['key'] if destino_da_extra(extra['index']) == destino }
  end

  # Os índices das colunas que vão para este destino, na ordem da planilha.
  def indices_do_destino(destino)
    extras.filter_map { |extra| extra['index'] if destino_da_extra(extra['index']) == destino }
  end

  # { chave da coluna => { 'nome' =>, 'para_que_serve' => } } das informações a que a pessoa deu nome ou descrição.
  def campos_por_chave
    extras.each_with_object({}) do |extra, por_chave|
      campo = conferencia.campos[extra['index'].to_s]
      por_chave[extra['key']] = campo if campo
    end
  end

  def titulo(indice)
    todas.find { |coluna| coluna['index'] == indice }&.fetch('header').to_s
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

  # O leitor sugeriu a coluna sem certeza: a tela mostra como duvidosa até a pessoa escolher. A coluna de telefone
  # deixa de ser duvidosa quando a pessoa responde que o telefone é da pessoa.
  def do_alvo(coluna, alvo)
    item = { indice: coluna['index'], nome: coluna['header'].to_s, destino: ALVOS.fetch(alvo) }
    duvidosa?(coluna, alvo) ? item.merge(duvidosa: true) : item
  end

  def duvidosa?(coluna, alvo)
    return false unless @resolucao.dig('targets', alvo, 'confident') == false

    respostas = conferencia.respostas
    !(alvo == 'phone' && respostas['telefone'] == TELEFONE_DA_PESSOA && respostas['coluna_telefone'] == coluna['index'])
  end

  def extra(coluna)
    destino = destino_da_extra(coluna['index'])
    item = { indice: coluna['index'], nome: coluna['header'].to_s, destino: destino }
    destino == INFORMACAO ? item.merge(campo: campo(coluna)) : item
  end

  def campo(coluna)
    escrito = conferencia.campos[coluna['index'].to_s].to_h
    { nome: escrito['nome'].presence || coluna['header'].to_s, para_que_serve: escrito['para_que_serve'].to_s }
  end

  def destinos
    @destinos ||= conferencia.destinos
  end

  def conferencia
    @conferencia ||= ContactImports::Trazer::Conferencia.new(@importacao)
  end
end
