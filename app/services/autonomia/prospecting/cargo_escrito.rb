# O cargo do contato que a Prospecção escreve (#3176). Fica em `custom_attributes.job_title`, onde o card, o Decisor e a
# ficha o leem, e a marca WRITTEN_KEY guarda o que nós gravamos. Só troca o cargo quando o campo está vazio ou guarda o
# que nós gravamos; sem decisor (cargo nil), sai só o cargo que nós pusemos. O que o usuário digitou nunca é apagado.
class Autonomia::Prospecting::CargoEscrito
  KEY = 'job_title'.freeze
  WRITTEN_KEY = 'autonomia_prospecting_contact_job_title'.freeze

  def initialize(custom_attributes)
    @attributes = custom_attributes.to_h
  end

  # Os custom_attributes com o cargo novo, num hash novo; o recebido não muda.
  def com(cargo)
    return @attributes unless nosso?

    @attributes.merge(KEY => cargo, WRITTEN_KEY => cargo).compact
  end

  private

  def nosso?
    atual = @attributes[KEY]
    atual.blank? || atual == @attributes[WRITTEN_KEY]
  end
end
