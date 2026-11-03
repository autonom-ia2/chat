# Os valores que uma receita lê do alvo (#2414 F3, ADR-001 2.3): `{"$valor": "conversa.status"}`.
#
# A lista de caminhos é fechada: a receita só lê o que está aqui, e o salvar recusa caminho desconhecido. Não é Liquid
# nem texto livre; cada caminho é um campo do modelo. Os atributos personalizados entram pela chave
# (`contato.atributos.placa`). Card entra com os gatilhos de card (F6). A mensagem do gatilho `mensagem.criada` só
# existe no filtro do gatilho (`mensagem.tipo`: recebida, enviada ou nota; `mensagem.privada`); nos passos ela já
# passou, e o salvar recusa ler a mensagem fora dali.
class Autonomia::Automacao::Valores
  # `conversa.id` é o número que a pessoa vê (#123) e o que as rotas da conversa recebem, não o id do banco.
  CAMPOS = {
    'conversa.id' => ->(conversa) { conversa.display_id },
    'conversa.status' => ->(conversa) { conversa.status },
    'conversa.prioridade' => ->(conversa) { conversa.priority },
    'conversa.caixa_id' => ->(conversa) { conversa.inbox_id },
    'conversa.responsavel_id' => ->(conversa) { conversa.assignee_id },
    'conversa.time_id' => ->(conversa) { conversa.team_id },
    'conversa.etiquetas' => ->(conversa) { conversa.label_list },
    'contato.id' => ->(conversa) { conversa.contact&.id },
    'contato.nome' => ->(conversa) { conversa.contact&.name },
    'contato.email' => ->(conversa) { conversa.contact&.email },
    'contato.telefone' => ->(conversa) { conversa.contact&.phone_number },
    'contato.empresa_id' => ->(conversa) { conversa.contact&.company_id },
    'contato.etiquetas' => ->(conversa) { conversa.contact&.label_list }
  }.freeze

  # A mensagem que disparou o gatilho, para o filtro separar a do cliente da resposta da equipe e da nota.
  MENSAGEM = {
    'mensagem.tipo' => lambda do |mensagem|
      next 'nota' if mensagem.private?

      mensagem.incoming? ? 'recebida' : 'enviada'
    end,
    'mensagem.privada' => ->(mensagem) { mensagem.private? }
  }.freeze

  ATRIBUTOS = {
    'conversa.atributos' => ->(conversa) { conversa.custom_attributes },
    'contato.atributos' => ->(conversa) { conversa.contact&.custom_attributes }
  }.freeze

  # O modelo do atributo personalizado de cada base, para conferir ao salvar que a chave existe na conta.
  MODELOS = { 'conversa.atributos' => 'conversation_attribute', 'contato.atributos' => 'contact_attribute' }.freeze

  class << self
    def caminho_valido?(caminho)
      CAMPOS.key?(caminho.to_s) || MENSAGEM.key?(caminho.to_s) || atributo(caminho).present?
    end

    def da_mensagem?(caminho) = MENSAGEM.key?(caminho.to_s)

    # O atributo da conta que o caminho lê existe? Caminho que não é atributo responde true.
    def atributo_definido?(caminho, conta)
      base, chave = atributo(caminho)
      base.nil? || conta.custom_attribute_definitions.exists?(attribute_model: MODELOS.fetch(base), attribute_key: chave)
    end

    # "contato.atributos.placa" => ["contato.atributos", "placa"]. A chave do atributo pode ter ponto.
    def atributo(caminho)
      base = ATRIBUTOS.keys.find { |prefixo| caminho.to_s.start_with?("#{prefixo}.") }
      chave = base && caminho.to_s.delete_prefix("#{base}.")
      [base, chave] if chave.present?
    end
  end

  def initialize(conversa:, mensagem: nil)
    @conversa = conversa
    @mensagem = mensagem
  end

  def ler(caminho)
    return CAMPOS.fetch(caminho.to_s).call(@conversa) if CAMPOS.key?(caminho.to_s)
    return @mensagem && MENSAGEM.fetch(caminho.to_s).call(@mensagem) if MENSAGEM.key?(caminho.to_s)

    base, chave = self.class.atributo(caminho)
    raise ArgumentError, "caminho desconhecido: #{caminho}" unless base

    ATRIBUTOS.fetch(base).call(@conversa).to_h[chave]
  end
end
