# O FORMULÁRIO DO ESPECIALISTA, GERADO DO ADAPTER — entrega 2 do Agente de Cotação, termos 1 a 4.
#
# Até 10/09/2026 o `cotar_seguro` tinha dez parâmetros digitados à mão em Ruby, e em auto só cinco
# chegavam ao portal. O adapter aceita ~90. O modelo entendia o pedido do cliente, escrevia num
# campo de texto solto, e o campo era ignorado (medido em seis conversas). Aqui o formulário nasce
# do `quote/schema` que o adapter entregou na sincronização da conexão: cada campo com a descrição
# em português (escrita lá, uma vez) e os valores aceitos. NADA de auto é digitado neste
# repositório — nem nome de campo, nem código, nem padrão. O que é escrito aqui é só o rótulo de
# cada GRUPO e a lista curta do que NÃO se expõe ao modelo.
#
# A forma é ANINHADA (`vehicle: { plate }`), como o adapter lê — e é isso que faz a montagem da
# entrada (`QuoteInput#de_auto`) ser mecânica: o grupo vai como veio, sem tradução, sem lista de
# nomes para envelhecer. A guarda de travessia (termo 4) confere que todo campo declarado aqui
# chega ao envio.
#
# O FORMULÁRIO DE UM RAMO QUE NÃO É AUTO (chat#591, fase 2 do piloto de residencial) sai da mesma
# classe, por `do_ramo`, com três diferenças, e nenhuma delas é nome de campo:
#   só a origem `cliente` vira parâmetro: `derivado` o adapter busca, `escolha` tem padrão seguro. O
#     agente que pergunta tudo o que o formulário tem é o defeito que a adapters#34 nomeia;
#   `valores` viram `enum`: o modelo escolhe da lista em vez de escrever o rótulo;
#   o formulário RECUSA MONTAR quando um campo de cliente vem sem descrição, com crase ou travessão na
#     descrição, fora de grupo, ou com valores que não cabem no tipo (`FormularioInvalido`). Campo novo
#     no adapter sem descrição quebra, não some; o que acontece depois está em `Declaracao#formulario_do_ramo`.
# Auto continua em `de_auto` como era: ele expõe as três origens, e o manual do especialista de auto
# foi escrito contando com isso.
class Autonomia::Insurance::Parametros
  # O schema de um ramo que não dá para oferecer ao modelo. A mensagem traz ramo e caminho dos
  # campos, nunca valor de nada.
  class FormularioInvalido < StandardError; end

  # O rótulo de cada grupo do adapter. Grupo novo no adapter sem rótulo aqui entra mesmo assim
  # (com um rótulo genérico) — o campo não pode sumir em silêncio — e a spec avisa.
  GRUPOS = {
    'insured' => 'Quem contrata o seguro (o segurado).',
    'address' => 'Endereço de residência do segurado.',
    'vehicle' => 'O veículo: identificação, uso, guarda, dispositivos e condutor jovem.',
    'driver' => 'O condutor principal, quando NÃO é o segurado. Obrigatório em cotação de empresa.',
    'truck' => 'Só caminhão: carroceria, carga e circulação.',
    'coverage' => 'Coberturas e franquia. Só o que o cliente pediu; o resto tem padrão seguro.',
    'quotation' => 'Vigência e apólice anterior (renovação).'
  }.freeze
  ROTULO_GENERICO = 'Campos de %s.'.freeze

  # O QUE O MODELO NÃO ESCREVE, e por quê:
  #   comissão — é da conexão da corretora (`InsuranceQuote#commission_percent`); um agente que a
  #              informasse mudaria o que a corretora ganha por cotação;
  #   seguradoras a consultar — decisão do PO (10/09/2026): todas as habilitadas, sempre.
  NAO_EXPOSTOS = %w[commissionPercent insurerCodes].freeze

  # Os tipos do adapter no vocabulário do JSON Schema.
  TIPOS = { 'texto' => 'string', 'numero' => 'number', 'booleano' => 'boolean', 'lista' => 'array',
            'objeto' => 'object' }.freeze

  # -> a lista de parâmetros (um `object` por grupo) na forma que `Native::Base#objeto` monta.
  # Vazio quando não há schema — a ferramenta fica só com os parâmetros comuns.
  def self.de_auto(schema)
    new(schema).grupos
  end

  # -> o formulário de um ramo que não é auto; vazio sem schema. Levanta `FormularioInvalido`.
  def self.do_ramo(schema)
    new(schema, ramo: true).tap(&:conferir!).grupos
  end

  # O que a crase e o travessão fazem numa descrição: o modelo os copia para o WhatsApp (modos de
  # falha C5 e "nada de travessão de IA"). Método de string, sem regex.
  PROIBIDOS_NA_DESCRICAO = ['`', '—', '–'].freeze
  ORIGEM_DO_CLIENTE = 'cliente'.freeze

  def initialize(schema, ramo: false)
    @campos = Array(schema.to_h['campos']).map { |campo| campo.to_h.deep_stringify_keys }
    @ramo = ramo
    @nome_do_ramo = schema.to_h['product'] || schema.to_h['ramo']
  end

  # Um `object` por grupo; campo de RAIZ do adapter (sem ponto) entra plano, com o nome dele — a
  # travessia (`quote_input_travessia_spec`) é quem reprova se a montagem da entrada não o levar,
  # que é o que se quer: campo novo quebra, não some.
  def grupos
    aninhados, raizes = expostos.partition { |campo| campo['campo'].include?('.') }
    por_grupo = aninhados.group_by { |campo| campo['campo'].split('.', 2).first }
    objetos = por_grupo.map do |nome, folhas|
      { 'name' => nome, 'type' => 'object', 'required' => false,
        'description' => GRUPOS.fetch(nome) { format(ROTULO_GENERICO, nome) },
        'properties' => folhas.map { |campo| folha(campo) } }
    end
    objetos + raizes.map { |campo| folha(campo) }
  end

  # Os caminhos pontuados que o formulário declara — o que a guarda de travessia (termo 4) confere
  # contra o que o envio monta.
  def caminhos
    expostos.pluck('campo')
  end

  # Os grupos (a raiz de cada caminho) que o formulário declara: é o que `QuoteInput#de_ramo` leva do
  # que o modelo escreveu para a entrada, sem lista de nomes digitada aqui.
  def nomes_dos_grupos
    caminhos.map { |caminho| caminho.split('.', 2).first }.uniq
  end

  # Todos os defeitos juntos na mensagem: quem corrige o adapter vê a lista inteira de uma vez, e
  # não um campo por rodada.
  def conferir!
    defeitos = expostos.filter_map { |campo| defeito(campo) }
    return if defeitos.empty?

    raise FormularioInvalido, "ramo #{@nome_do_ramo}: #{defeitos.join('; ')}"
  end

  private

  def expostos
    @expostos ||= @campos.reject { |campo| NAO_EXPOSTOS.include?(campo['campo']) }
                         .select { |campo| !@ramo || campo['origem'] == ORIGEM_DO_CLIENTE }
  end

  # CAMPO FORA DE GRUPO NÃO EXISTE NUM RAMO: o adapter lê os campos do ramo de `segurado` e de
  # `configuracoes` (`contratoGenerico`). Um campo de cliente sem ponto seria declarado ao modelo e
  # descartado pelo adapter; por isso recusa em vez de entrar.
  def defeito(campo)
    caminho = campo['campo'].to_s
    descricao = campo['descricao'].to_s
    return "#{caminho} fora de grupo" unless caminho.include?('.')
    return "#{caminho} sem descricao" if descricao.strip.empty?
    return "#{caminho} com crase ou travessao na descricao" if PROIBIDOS_NA_DESCRICAO.any? { |sinal| descricao.include?(sinal) }

    "#{caminho} com valores fora do tipo" if campo['valores'].present? && enum(campo).nil?
  end

  def folha(campo)
    base = { 'name' => campo['campo'].split('.', 2).last, 'type' => TIPOS.fetch(campo['tipo'], 'string'),
             'required' => false, 'description' => campo['descricao'].to_s }
    return base unless @ramo && campo['valores'].present?

    base.merge('enum' => enum(campo))
  end

  # As CHAVES de `valores` são o que o adapter aceita; o rótulo de cada uma já está na descrição. Em
  # campo numérico vai o número, em texto o texto. Outro tipo com valores, ou chave que não é número
  # num campo numérico: nil, e `defeito` recusa o formulário.
  def enum(campo)
    chaves = campo['valores'].to_h.keys.map(&:to_s)
    case TIPOS.fetch(campo['tipo'], 'string')
    when 'string' then chaves
    when 'number' then numeros(chaves)
    end
  end

  def numeros(chaves)
    convertidos = chaves.map { |chave| Integer(chave, exception: false) || Float(chave, exception: false) }
    convertidos.all? ? convertidos : nil
  end
end
