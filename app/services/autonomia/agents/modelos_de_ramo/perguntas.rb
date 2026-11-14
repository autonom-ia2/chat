# AS PERGUNTAS DA COTAÇÃO DE UM MODELO LIDO DO DISCO (#3020), nos dois formatos do arquivo. Um dos dois, nunca os dois:
#
#   perguntas:                      # lista corrida: todas ligadas, sem bloco (os modelos do piloto)
#     - "Qual o CNPJ da empresa?"
#
#   blocos:                         # em blocos: a tela agrupa, e o dono liga e desliga cada pergunta
#     - nome: "O prédio"
#       perguntas:
#         - texto: "Quantos elevadores existem no condomínio?"
#           ligada: true            # já vem ligada. Sem o campo, vem desligada: o dono liga se quiser
#         - texto: "Qual a marca deles?"
#           se: "houver elevadores" # a condição. O agente recebe "Se houver elevadores: Qual a marca deles?"
#           segue: true             # depende da pergunta de cima: fica embaixo dela na tela e desliga com ela
#
# Devolve o molde: uma entrada por pergunta, na ordem, no formato que a marca guarda sem o `id`
# ({ 'texto', 'tirada' } e, no modelo em blocos, 'bloco', 'se' e 'segue'). Fora do formato, levanta
# `Formato::Invalido` com o nome do campo; nunca o texto do arquivo.
class Autonomia::Agents::ModelosDeRamo::Perguntas
  CAMPOS = %w[perguntas blocos].freeze
  CAMPOS_DO_BLOCO = %w[nome perguntas].freeze
  CAMPOS_DA_PERGUNTA = %w[texto ligada se segue].freeze
  SIM_OU_NAO = [true, false, nil].freeze
  BLOCOS_MAX = 20
  NOME_DO_BLOCO_MAX = 60
  CONDICAO_MAX = 160

  # `texto`: a conferência de texto do `Formato` (texto, não vazio, dentro do limite), para as duas falarem igual.
  def initialize(dados:, texto:)
    @dados = dados
    @texto = texto
  end

  def molde
    negar('perguntas: use perguntas ou blocos, um dos dois') unless CAMPOS.one? { |campo| @dados.key?(campo) }

    itens = @dados.key?('blocos') ? dos_blocos : corridas
    maximo = Autonomia::Agents::ModelosDeRamo::PERGUNTAS_MAX
    negar("perguntas: passa de #{maximo} itens") if itens.size > maximo
    negar('perguntas: nenhuma vem ligada') if itens.all? { |item| item['tirada'] }
    itens.freeze
  end

  private

  def negar(motivo)
    raise Autonomia::Agents::ModelosDeRamo::Formato::Invalido, motivo
  end

  def lista(valor, campo)
    negar("#{campo}: não é lista") unless valor.is_a?(Array)
    valor
  end

  def corridas
    lista(@dados['perguntas'], 'perguntas').map do |item|
      { 'texto' => @texto.call(item, 'perguntas', Autonomia::Agents::ModelosDeRamo::ITEM_MAX), 'tirada' => false }.freeze
    end
  end

  def dos_blocos
    blocos = lista(@dados['blocos'], 'blocos')
    negar("blocos: passa de #{BLOCOS_MAX} blocos") if blocos.size > BLOCOS_MAX

    nomes = blocos.map { |bloco| nome_do(bloco) }
    negar('blocos: nome de bloco repetido') if nomes.uniq.size != nomes.size
    blocos.zip(nomes).flat_map { |bloco, nome| do_bloco(bloco, nome) }
  end

  def nome_do(bloco)
    negar('blocos: cada bloco leva nome e perguntas') unless bloco.is_a?(Hash) && bloco.keys.map(&:to_s).sort == CAMPOS_DO_BLOCO

    @texto.call(bloco['nome'], 'blocos.nome', NOME_DO_BLOCO_MAX)
  end

  def do_bloco(bloco, nome)
    perguntas = lista(bloco['perguntas'], 'blocos.perguntas')
    negar('blocos.perguntas: bloco vazio') if perguntas.empty?

    perguntas.each_with_object([]) do |bruta, prontas|
      pronta = pergunta(bruta, nome)
      conferir_quem_segue!(pronta, prontas.reverse.find { |anterior| !anterior['segue'] }) if pronta['segue']
      prontas << pronta
    end
  end

  # A pergunta que segue outra precisa de uma acima dela no bloco (`mae`), e não vem ligada com a de cima desligada.
  def conferir_quem_segue!(pronta, mae)
    negar('blocos.perguntas: a primeira do bloco não segue outra') if mae.nil?
    negar('blocos.perguntas: ligada com a de cima desligada') if mae['tirada'] && !pronta['tirada']
  end

  def pergunta(bruta, nome)
    negar('blocos.perguntas: cada pergunta leva texto') unless bruta.is_a?(Hash) && bruta.key?('texto')

    sobra = bruta.keys.map(&:to_s) - CAMPOS_DA_PERGUNTA
    negar("blocos.perguntas: campo desconhecido: #{sobra.join(', ')}") if sobra.any?
    negar('blocos.perguntas: ligada e segue são sim ou não') unless [bruta['ligada'], bruta['segue']].all? { |valor| SIM_OU_NAO.include?(valor) }

    lugar = { 'bloco' => nome, 'se' => condicao(bruta['se']), 'segue' => bruta['segue'] == true }.compact_blank
    { 'texto' => @texto.call(bruta['texto'], 'blocos.perguntas.texto', Autonomia::Agents::ModelosDeRamo::ITEM_MAX),
      'tirada' => bruta['ligada'] != true }.merge(lugar).freeze
  end

  def condicao(valor)
    valor.nil? ? nil : @texto.call(valor, 'blocos.perguntas.se', CONDICAO_MAX)
  end
end
