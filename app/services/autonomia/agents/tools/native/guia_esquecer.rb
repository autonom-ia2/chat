# O Guia APAGANDO uma anotação quando a pessoa pede para esquecer (#933).
#
# Fora do diário, como `anotar_lembranca`: não é mudança na conta. Só alcança as
# anotações que a pessoa vê (as dela e as da corretora); as da corretora, só
# administrador apaga.
class Autonomia::Agents::Tools::Native::GuiaEsquecer < Autonomia::Agents::Tools::Native::Base
  class << self
    def slug
      'apagar_lembranca'
    end

    def args_registraveis
      %w[id]
    end

    def description
      'Apaga uma anotação do bloco "O QUE VOCÊ JÁ SABE", pelo número (#), quando a pessoa pedir para ' \
        'esquecer ou disser que ela está errada. Não muda nada na conta.'
    end

    def params
      [{ 'name' => 'id', 'type' => 'string', 'description' => 'O número (#) da anotação.' }]
    end
  end

  def call
    return 'Não consigo apagar agora porque não sei quem está pedindo.' if @operador.nil?

    memoria = ::Autonomia::Guide::Memoria.visiveis(@operador.account, @operador.user).find_by(id: id)
    return "Não apaguei: não existe a anotação ##{@params['id']}." if memoria.nil?
    return 'Não apaguei: só administrador apaga o que vale para a corretora inteira.' if memoria.corretora? && !@operador.administrador?

    memoria.destroy!
    @operador.esquecida(memoria.id)
    "Apaguei a anotação ##{memoria.id}. Diga à pessoa, numa frase curta, que esqueceu."
  end

  private

  def id
    Integer(@params['id'].to_s.delete_prefix('#'), 10, exception: false)
  end
end
