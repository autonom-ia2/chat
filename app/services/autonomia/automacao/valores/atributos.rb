# Os atributos personalizados que a receita lê (#2414 F3): `contato.atributos.placa`. Cada base tem o atributo do
# próprio modelo, e o salvar confere que a chave existe na conta. A chave do atributo pode ter ponto.
#
# Saiu de `Valores`, que segue sendo a porta dos caminhos (`Valores.atributo`, `Valores::MODELOS`).
#
# O campo do card do tipo pessoa da equipe (G62, #2829) guarda o id da pessoa e dá mais dois valores: o nome
# (`card.atributos.original.nome`) e se ela está ausente agora (`card.atributos.original.ausente`, pelo "ausente até"
# dela, como a G23). A pessoa é achada na conta do card, nunca só pelo id. Chave com ponto vale primeiro: se a conta
# tem um campo chamado `original.nome`, o caminho lê esse campo.
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

  CARD = 'card.atributos'.freeze
  SUFIXOS_DA_PESSOA = %w[nome ausente].freeze
  AUSENTE = 'ausente'.freeze

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
      return true if base.nil? || conta.custom_attribute_definitions.exists?(attribute_model: MODELOS.fetch(base), attribute_key: chave)

      pessoa, = da_pessoa(base, chave)
      pessoa.present? && campo_pessoa?(conta, pessoa)
    end

    # "card.atributos.original.ausente": lê se a pessoa do campo está ausente (true/false, fechado como a G23).
    def ausente_da_pessoa?(caminho)
      base, chave = do_caminho(caminho)
      da_pessoa(base, chave).last == AUSENTE
    end

    # O caminho lê um atributo do tipo data da conta? A data calculada no corpo (G16) só parte de um deles: os campos
    # fixos não têm data.
    def data?(caminho, conta)
      base, chave = do_caminho(caminho)
      base.present? && conta.custom_attribute_definitions.exists?(attribute_model: MODELOS.fetch(base), attribute_key: chave,
                                                                  attribute_display_type: :date)
    end

    # O caminho lê um atributo do tipo contato da conta (decisão 16)? O "em outro registro" (G18) acha o contato ligado
    # pelo id guardado num deles.
    def contato?(caminho, conta)
      base, chave = do_caminho(caminho)
      base.present? && conta.custom_attribute_definitions.exists?(attribute_model: MODELOS.fetch(base), attribute_key: chave,
                                                                  attribute_display_type: :contato)
    end

    # O valor do atributo no objeto da base (a conversa, o contato ou o card). No campo de pessoa, também o nome e a
    # ausência dela.
    def ler(base, chave, objeto)
      atributos = LEITURA.fetch(base).call(objeto).to_h
      return atributos[chave] if atributos.key?(chave)

      pessoa, sufixo = da_pessoa(base, chave)
      return unless pessoa && campo_pessoa?(objeto.account, pessoa)

      da_pessoa_no_card(objeto.account_id, atributos[pessoa], sufixo)
    end

    private

    # ["original", "nome"] para "original.nome" no card; nil fora do card ou sem sufixo de pessoa.
    def da_pessoa(base, chave)
      return [nil, nil] unless base == CARD

      sufixo = SUFIXOS_DA_PESSOA.find { |item| chave.to_s.end_with?(".#{item}") }
      sufixo ? [chave.to_s.delete_suffix(".#{sufixo}"), sufixo] : [nil, nil]
    end

    def campo_pessoa?(conta, chave)
      conta.custom_attribute_definitions.exists?(attribute_model: :card_attribute, attribute_key: chave, attribute_display_type: :pessoa)
    end

    def da_pessoa_no_card(conta_id, id, sufixo)
      pessoa = id.present? && ::AccountUser.find_by(account_id: conta_id, user_id: id)
      return pessoa.present? && ::AccountUser.ausente_na_conta?(conta_id, pessoa.user_id) if sufixo == AUSENTE

      pessoa.presence&.user&.name
    end
  end
end
