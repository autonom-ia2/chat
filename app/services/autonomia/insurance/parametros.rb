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
class Autonomia::Insurance::Parametros
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

  def initialize(schema)
    @campos = Array(schema.to_h['campos']).map { |campo| campo.to_h.deep_stringify_keys }
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

  private

  def expostos
    @expostos ||= @campos.reject { |campo| NAO_EXPOSTOS.include?(campo['campo']) }
  end

  def folha(campo)
    { 'name' => campo['campo'].split('.', 2).last, 'type' => TIPOS.fetch(campo['tipo'], 'string'),
      'required' => false, 'description' => campo['descricao'].to_s }
  end
end
