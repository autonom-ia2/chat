# O pedaço do schema da avaliação de card que a memória acrescenta (#1601, W4): `memoria_ops`. O modelo aponta o que
# foi dito e onde (ids locais); não há campo de fonte nem de status: isso é do código (Crm::Memoria::Escritor).
module Crm::Memoria::Esquema
  OPERACAO = {
    type: 'object',
    properties: {
      op: { type: 'string', enum: %w[adicionar atualizar invalidar] },
      grupo: { type: 'string', enum: %w[contato pedido conversa decisao] },
      chave: { type: 'string' },
      item_ref: { type: %w[string null] },
      valor: { type: 'string', maxLength: 300 },
      alvo_fato_id: { type: %w[integer null] },
      base_versao: { type: %w[integer null] },
      provas: { type: 'array', items: { type: 'string' } }
    },
    required: %w[op grupo chave item_ref valor alvo_fato_id base_versao provas],
    additionalProperties: false
  }.freeze

  module_function

  def com_memoria(schema)
    corpo = schema[:schema]
    schema.merge(
      schema: corpo.merge(properties: corpo[:properties].merge(memoria_ops: { type: 'array', items: OPERACAO }),
                          required: [*corpo[:required], 'memoria_ops'])
    ).freeze
  end
end
