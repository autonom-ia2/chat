# O Guia falando com a própria plataforma, pela porta da frente.
#
# Ler e executar passando pelo mesmo endpoint que a interface chama é o que
# garante que a permissão aplicada é a real: mesmo controller, mesmo Pundit,
# mesmo isolamento de conta. Nenhuma regra é reimplementada aqui.
#
# A primeira versão fazia isso por HTTP em 127.0.0.1. Correto, e caro: cada
# mensagem do Guia segurava DUAS das cinco threads do Puma — a de fora,
# bloqueada esperando, e a de dentro, trabalhando. Medido em produção (Puma em
# modo único, `Min threads: 5`), três pessoas usando o Guia ao mesmo tempo
# travavam o dashboard inteiro, não só o Guia.
#
# Aqui o pedido roda na MESMA thread, pela pilha completa do Rails. A fidelidade
# é a mesma — autenticação por token, before_actions, Pundit, tudo — e o custo
# volta a ser de uma thread por mensagem.
class Autonomia::Guide::ChamadaInterna
  Resposta = Struct.new(:codigo, :corpo, keyword_init: true)

  CAMPOS_DO_CURRENT = %i[user account account_user contact inbox].freeze

  def initialize(user:)
    @user = user
  end

  def chamar(metodo, caminho, corpo: nil, filtros: {})
    preservado = estado_do_current
    status, _cabecalhos, corpo_resposta = ::Rails.application.call(ambiente(metodo, caminho, corpo, filtros))

    Resposta.new(codigo: status.to_s, corpo: ler(corpo_resposta))
  ensure
    # O pedido de dentro escreve no Current (mesmo usuário, mesma conta) e, se
    # levantar, o tratador de exceção o zera. Sem isto, o pedido de FORA seguiria
    # sem usuário — um efeito colateral invisível e difícil de rastrear.
    restaurar(preservado)
  end

  private

  def ambiente(metodo, caminho, corpo, filtros)
    ::Rack::MockRequest.env_for(
      "http://interno#{caminho}#{consulta(filtros)}",
      :method => metodo.to_s.upcase,
      :input => corpo.present? ? ::JSON.generate(corpo) : '',
      'CONTENT_TYPE' => 'application/json',
      'HTTP_API_ACCESS_TOKEN' => @user.access_token.token,
      'HTTP_ACCEPT' => 'application/json'
    )
  end

  def consulta(filtros)
    return '' if filtros.blank?

    "?#{filtros.to_query}"
  end

  def ler(corpo_resposta)
    texto = +''
    corpo_resposta.each { |pedaco| texto << pedaco.to_s }
    texto
  ensure
    corpo_resposta.close if corpo_resposta.respond_to?(:close)
  end

  def estado_do_current
    CAMPOS_DO_CURRENT.index_with { |campo| ::Current.public_send(campo) }
  end

  def restaurar(preservado)
    preservado.each { |campo, valor| ::Current.public_send("#{campo}=", valor) }
  end
end
