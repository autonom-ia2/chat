# O Guia ANOTANDO o que a pessoa ensinou, para as próximas conversas (#933).
#
# Grava fora do diário: não é mudança na conta, e quem desfaz é a pessoa, no
# painel "O que eu sei" ou no "Esquecer" do chip. O texto nunca vai para o
# registro de diagnóstico (`args_registraveis`): a pessoa pode ter ditado algo
# que não devia ser guardado em lugar nenhum além daqui.
#
# O que vale guardar é decisão do modelo, pela instrução. Aqui só valem o escopo
# (a da corretora é só de administrador) e o teto.
class Autonomia::Agents::Tools::Native::GuiaLembrar < Autonomia::Agents::Tools::Native::Base
  MEMORIA = ::Autonomia::Guide::Memoria
  CORRETORA = 'corretora'.freeze

  class << self
    def slug
      'anotar_lembranca'
    end

    def args_registraveis
      %w[de_quem substitui_id]
    end

    def description
      'Anota uma frase curta que você vai saber em TODAS as próximas conversas: um apelido (sempre com o ' \
        'id que você leu), um combinado ou o jeito de falar que a pessoa pediu. Use quando a pessoa pedir ' \
        'ou ensinar algo que vale daqui para frente. Para corrigir ou juntar uma anotação, passe ' \
        'substitui_id. Não muda nada na conta.'
    end

    def params
      [
        { 'name' => 'texto', 'type' => 'string',
          'description' => 'A frase, até 200 caracteres, na língua da pessoa. Ex.: "Funil do Zé = funil ' \
                           'Comercial (id 12)".' },
        { 'name' => 'de_quem', 'type' => 'string', 'enum' => %w[minha corretora],
          'description' => '"minha": vale só para quem pediu (o jeito dela). "corretora": vale para ' \
                           'todos da conta (apelidos e combinados da equipe); só administrador anota.' },
        { 'name' => 'substitui_id', 'type' => 'string', 'required' => false,
          'description' => 'O número (#) da anotação que esta substitui, para corrigir, juntar ou abrir ' \
                           'espaço quando o limite estiver cheio. Vazio para uma anotação nova.' }
      ]
    end
  end

  def call
    return recusa_sem_contexto if @operador.nil?

    texto = @params['texto'].to_s.squish
    recusa = recusa_do_pedido(texto)
    return recusa if recusa

    memoria = alvo
    return nao_achei if memoria.nil?
    return cheio if memoria.new_record? && escopo.count >= MEMORIA.teto(corretora: corretora?)

    anotar(memoria, texto)
  end

  private

  def recusa_do_pedido(texto)
    return 'Não anotei: a frase está vazia.' if texto.blank?
    return "Não anotei: passa de #{MEMORIA::TAMANHO} caracteres. Resuma e chame de novo." if texto.length > MEMORIA::TAMANHO

    so_administrador if corretora? && !@operador.administrador?
  end

  def corretora?
    @params['de_quem'].to_s == CORRETORA
  end

  def escopo
    @escopo ||= corretora? ? MEMORIA.da_corretora(@operador.account) : MEMORIA.pessoais(@operador.account, @operador.user)
  end

  def substitui_id
    Integer(@params['substitui_id'].to_s.delete_prefix('#'), 10, exception: false)
  end

  def alvo
    return escopo.new if @params['substitui_id'].blank?

    escopo.find_by(id: substitui_id)
  end

  def anotar(memoria, texto)
    memoria.update!(texto: texto, autor_id: @operador.user.id, turno_id: @operador.turno_id)
    @operador.anotada(memoria)
    "Anotado como ##{memoria.id}. Diga à pessoa, numa frase curta, que anotou."
  end

  def lista
    escopo.em_ordem.map(&:linha).join('; ')
  end

  def cheio
    "Não anotei: já são #{MEMORIA.teto(corretora: corretora?)} anotações, o limite. As atuais: #{lista}. " \
      'Para guardar esta, junte com uma parecida ou troque a menos útil, chamando de novo com substitui_id.'
  end

  def nao_achei
    "Não anotei: não existe a anotação ##{@params['substitui_id']} entre as #{corretora? ? 'da corretora' : 'da pessoa'}. " \
      "As atuais: #{lista.presence || 'nenhuma'}."
  end

  def so_administrador
    'Não anotei: só administrador anota o que vale para a corretora inteira. Se fizer sentido, anote como ' \
      '"minha" (vale só para esta pessoa) e diga isso a ela.'
  end

  def recusa_sem_contexto
    'Não consigo anotar agora porque não sei quem está pedindo.'
  end
end
