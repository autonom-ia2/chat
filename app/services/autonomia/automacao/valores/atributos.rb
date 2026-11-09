# Os atributos personalizados que a receita lê (#2414 F3): `contato.atributos.placa`. Cada base tem o atributo do
# próprio modelo, e o salvar confere que a chave existe na conta. A chave do atributo pode ter ponto.
#
# Saiu de `Valores`, que segue sendo a porta dos caminhos (`Valores.atributo`, `Valores::MODELOS`).
class Autonomia::Automacao::Valores::Atributos
  # Como ler os atributos de cada base.
  LEITURA = {
    'conversa.atributos' => ->(conversa) { conversa.custom_attributes },
    'contato.atributos' => ->(contato) { contato.custom_attributes },
    'card.atributos' => ->(card) { card.custom_attributes }
  }.freeze

  # O modelo do atributo personalizado de cada base, para conferir ao salvar que a chave existe na conta.
  MODELOS = {
    'conversa.atributos' => 'conversation_attribute',
    'contato.atributos' => 'contact_attribute',
    'card.atributos' => 'card_attribute'
  }.freeze

  class << self
    # "contato.atributos.placa" => ["contato.atributos", "placa"].
    def do_caminho(caminho)
      base = LEITURA.keys.find { |prefixo| caminho.to_s.start_with?("#{prefixo}.") }
      chave = base && caminho.to_s.delete_prefix("#{base}.")
      [base, chave] if chave.present?
    end

    # O atributo da conta que o caminho lê existe? Caminho que não é atributo responde true.
    def definido?(caminho, conta)
      base, chave = do_caminho(caminho)
      base.nil? || conta.custom_attribute_definitions.exists?(attribute_model: MODELOS.fetch(base), attribute_key: chave)
    end

    # O caminho lê um atributo do tipo data da conta? A data calculada no corpo (G16) só parte de um deles: os campos
    # fixos não têm data.
    def data?(caminho, conta)
      base, chave = do_caminho(caminho)
      base.present? && conta.custom_attribute_definitions.exists?(attribute_model: MODELOS.fetch(base), attribute_key: chave,
                                                                  attribute_display_type: :date)
    end

    # O valor do atributo no objeto da base (a conversa, o contato ou o card).
    def ler(base, chave, objeto) = LEITURA.fetch(base).call(objeto).to_h[chave]
  end
end
