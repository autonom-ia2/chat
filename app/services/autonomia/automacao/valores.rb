# Os valores que uma receita lê do alvo (#2414 F3, ADR-001 2.3): `{"$valor": "conversa.status"}`.
#
# A lista de caminhos é fechada: a receita só lê o que está aqui, e o salvar recusa caminho desconhecido. Não é Liquid
# nem texto livre; cada caminho é um campo do modelo. Os atributos personalizados entram pela chave
# (`contato.atributos.placa`). Card entra com os gatilhos de card (F6).
class Autonomia::Automacao::Valores
  CAMPOS = {
    'conversa.id' => ->(conversa) { conversa.id },
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

  ATRIBUTOS = {
    'conversa.atributos' => ->(conversa) { conversa.custom_attributes },
    'contato.atributos' => ->(conversa) { conversa.contact&.custom_attributes }
  }.freeze

  class << self
    def caminho_valido?(caminho)
      CAMPOS.key?(caminho.to_s) || atributo(caminho).present?
    end

    # "contato.atributos.placa" => ["contato.atributos", "placa"]. A chave do atributo pode ter ponto.
    def atributo(caminho)
      base = ATRIBUTOS.keys.find { |prefixo| caminho.to_s.start_with?("#{prefixo}.") }
      chave = base && caminho.to_s.delete_prefix("#{base}.")
      [base, chave] if chave.present?
    end
  end

  def initialize(conversa:)
    @conversa = conversa
  end

  def ler(caminho)
    return CAMPOS.fetch(caminho.to_s).call(@conversa) if CAMPOS.key?(caminho.to_s)

    base, chave = self.class.atributo(caminho)
    raise ArgumentError, "caminho desconhecido: #{caminho}" unless base

    ATRIBUTOS.fetch(base).call(@conversa).to_h[chave]
  end
end
