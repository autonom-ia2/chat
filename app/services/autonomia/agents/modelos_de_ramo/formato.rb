# A conferência de um modelo pronto lido do disco (#2881). Devolve o `Modelo` ou levanta `Invalido` com o motivo (nome
# de campo e chave de ferramenta; nunca o texto do arquivo). O que confere:
#   - só campos conhecidos, e todos os obrigatórios; `chave` igual ao nome do arquivo; `tipo` com roteiro geral;
#   - textos e listas dentro do limite (até 20 itens de até 300 letras; a frase "Use quando" no limite do "Incluir");
#   - as perguntas, em lista corrida (`perguntas`) ou em blocos (`blocos`), um dos dois (`Perguntas`);
#   - `ja_vem` e `tambem`: ferramenta do catálogo, da vitrine e grátis, sem repetir. Premium nunca entra aqui: consulta
#     paga só entra no agente pela escolha de uma pessoa, na vitrine;
#   - `premium`: só sugestão de cartão pago, e por isso só chave de cartão Premium;
#   - `teste`: as 3 perguntas de teste;
#   - o roteiro (`.md`) CRU em até 8.000 bytes, com cada marcador uma única vez e sozinho na linha, e com o trecho do
#     conhecimento do ramo (`Conhecimento`). O teto vale antes
#     da troca dos marcadores: o que o dono acrescenta depois é limitado por quantidade e tamanho de item.
class Autonomia::Agents::ModelosDeRamo::Formato
  OBRIGATORIOS = %w[chave tipo nome_padrao ramo documentos ja_vem teste].freeze
  OPCIONAIS = %w[seguradoras_sugeridas tambem premium].freeze
  CONHECIDOS = (OBRIGATORIOS + OPCIONAIS + Autonomia::Agents::ModelosDeRamo::Perguntas::CAMPOS).freeze
  CAMPOS_DA_FERRAMENTA = %w[fonte usar_quando].freeze
  SEM_ROTEIRO_GERAL = %w[custom insurance_quote].freeze
  NOME_MAX = 120
  ROTEIRO_MAX = 8_000
  TESTES = 3

  class Invalido < StandardError; end

  def initialize(chave:, dados:, roteiro:)
    @chave = chave
    @dados = dados
    @roteiro = roteiro
  end

  def modelo
    conferir_campos!
    modelo = Autonomia::Agents::ModelosDeRamo::Modelo.new(chave: @chave, tipo: tipo, roteiro: roteiro, **textos, **listas, **prontas)
    negar('ferramenta repetida em ja_vem e tambem') if modelo.ferramentas.map(&:fonte).uniq.size != modelo.ferramentas.size
    modelo
  end

  private

  def negar(motivo)
    raise Invalido, motivo
  end

  def conferir_campos!
    negar('o arquivo não é uma lista de campos') unless @dados.is_a?(Hash)

    nomes = @dados.keys.map(&:to_s)
    negar("campo desconhecido: #{(nomes - CONHECIDOS).join(', ')}") if (nomes - CONHECIDOS).any?
    negar("falta o campo: #{(OBRIGATORIOS - nomes).join(', ')}") if (OBRIGATORIOS - nomes).any?
    negar('chave diferente do nome do arquivo') unless @dados['chave'] == @chave
  end

  def tipo
    tipos = Autonomia::Agents::Agent::AGENT_TYPES - SEM_ROTEIRO_GERAL
    negar('tipo sem roteiro geral') unless tipos.include?(@dados['tipo'])

    @dados['tipo']
  end

  def textos
    { nome_padrao: texto(@dados['nome_padrao'], 'nome_padrao', NOME_MAX), ramo: texto(@dados['ramo'], 'ramo', NOME_MAX),
      seguradoras_sugeridas: seguradoras }
  end

  def seguradoras
    return ''.freeze if @dados['seguradoras_sugeridas'].nil?

    texto(@dados['seguradoras_sugeridas'], 'seguradoras_sugeridas', Autonomia::Agents::ModelosDeRamo::ITEM_MAX)
  end

  def listas
    teste = lista('teste')
    negar("teste: são #{TESTES} perguntas") unless teste.size == TESTES

    { molde_das_perguntas: Autonomia::Agents::ModelosDeRamo::Perguntas.new(dados: @dados, texto: method(:texto)).molde,
      documentos: lista('documentos'), teste: teste }
  end

  def prontas
    { ja_vem: ferramentas('ja_vem'), tambem: ferramentas('tambem'), premium: premium }
  end

  def texto(valor, campo, maximo)
    negar("#{campo}: não é texto") unless valor.is_a?(String)

    limpo = valor.strip
    negar("#{campo}: vazio") if limpo.empty?
    negar("#{campo}: passa de #{maximo} letras") if limpo.length > maximo
    limpo.freeze
  end

  # A lista do campo (nil no opcional que não veio = lista vazia), já conferida como lista dentro do limite.
  def itens(campo)
    valor = @dados[campo].nil? && OPCIONAIS.include?(campo) ? [] : @dados[campo]
    negar("#{campo}: não é lista") unless valor.is_a?(Array)
    negar("#{campo}: passa de #{Autonomia::Agents::ModelosDeRamo::ITENS_MAX} itens") if valor.size > Autonomia::Agents::ModelosDeRamo::ITENS_MAX
    valor
  end

  def lista(campo)
    itens(campo).map { |item| texto(item, campo, Autonomia::Agents::ModelosDeRamo::ITEM_MAX) }.freeze
  end

  def ferramentas(campo)
    itens(campo).map { |item| ferramenta(item, campo) }.freeze
  end

  def ferramenta(item, campo)
    negar("#{campo}: cada ferramenta leva fonte e usar_quando") unless item.is_a?(Hash) && item.keys.map(&:to_s).sort == CAMPOS_DA_FERRAMENTA

    fonte = item['fonte'].to_s
    conferir_fonte_gratis!(fonte, campo)
    frase = texto(item['usar_quando'], "#{campo}.usar_quando", Autonomia::FerramentasProntas::Incluir::MAX_USAR_QUANDO)
    Autonomia::Agents::ModelosDeRamo::Ferramenta.new(fonte: fonte.freeze, usar_quando: frase)
  end

  def conferir_fonte_gratis!(chave, campo)
    negar("#{campo}: ferramenta Premium (#{chave})") if cartoes_premium.include?(chave)

    fonte = Autonomia::FerramentasProntas::Catalogo.buscar(chave)
    negar("#{campo}: ferramenta fora do catálogo (#{chave})") if fonte.nil?
    negar("#{campo}: ferramenta fora da vitrine (#{chave})") unless fonte.na_vitrine?
  end

  def premium
    chaves = itens('premium').map(&:to_s)
    negar("premium: não é cartão Premium (#{(chaves - cartoes_premium).join(', ')})") if (chaves - cartoes_premium).any?

    chaves.uniq.map(&:freeze).freeze
  end

  # Também o cartão Premium que está todo desligado na fonte: a chave dele segue válida para quando voltar.
  def cartoes_premium
    @cartoes_premium ||= Autonomia::FerramentasProntas::Catalogo.premium_no_codigo.map(&:chave)
  end

  def roteiro
    negar('roteiro: não é texto UTF-8') unless @roteiro.is_a?(String) && @roteiro.valid_encoding?
    negar('roteiro: vazio') if @roteiro.strip.empty?
    negar("roteiro: passa de #{ROTEIRO_MAX} bytes") if @roteiro.bytesize > ROTEIRO_MAX

    conferir_marcadores!
    negar('roteiro: falta o conhecimento do ramo') unless Autonomia::Agents::ModelosDeRamo::Conhecimento.completo?(@roteiro)
    @roteiro.strip.freeze
  end

  # Cada marcador aparece uma vez só, e essa vez é a linha inteira (`scan` com texto, sem expressão regular).
  def conferir_marcadores!
    linhas = @roteiro.lines.map(&:strip)
    Autonomia::Agents::ModelosDeRamo::MARCADORES.each_key do |marcador|
      sozinho = linhas.count(marcador) == 1 && @roteiro.scan(marcador).size == 1
      negar("roteiro: marcador #{marcador} uma vez, sozinho na linha") unless sozinho
    end
  end
end
