# O que está pendurado num registro que o Guia criou, na hora de desfazer a criação (#3122).
#
# Desfazer uma criação apaga o registro pelo model, e os `dependent:` levam junto o que nasceu ligado a ele. O que o
# próprio Guia criou na mesma execução já saiu antes, porque o desfazer anda de trás para frente. Então o que ainda
# está pendurado é de outra pessoa, ou chegou depois: a conversa que o cliente abriu no contato que o Guia criou, o
# card que alguém pôs no funil novo. Isso não pode sumir com o desfazer — o registro fica, e o relatório diz por quê.
#
# Conta toda associação que o apagar alcançaria: as que apagam (`destroy`, `destroy_async`, `delete_all`, `delete`),
# as que soltam (`nullify`, que tira o vínculo que a pessoa fez) e as que recusam (`restrict_*`, que sem esta conferência
# viravam erro no meio do desfazer). `through` fica de fora: quem apaga é a associação de que ele depende.
class Autonomia::Guide::FilhosQueFicam
  DEPENDENTES = %i[destroy destroy_async delete_all delete nullify restrict_with_error restrict_with_exception].freeze
  TIPOS = %i[has_many has_one].freeze

  def self.algum?(registro)
    registro.class.reflect_on_all_associations.any? do |associacao|
      next false unless TIPOS.include?(associacao.macro) && DEPENDENTES.include?(associacao.options[:dependent])
      next false if associacao.through_reflection?

      registro.association(associacao.name).scope.exists?
    end
  end
end
