# Responde uma pergunta ao Guia fora da requisição (issue #572).
#
# Existe porque o `rack-timeout` de produção mata qualquer requisição aos 15
# segundos, e cada ida ao gpt-5.6-sol leva de 3 a 5. Dentro da requisição cabia
# uma leitura; uma pergunta que pedisse a segunda morria com erro 500. Aqui não
# há requisição para morrer, e o Guia lê quantas vezes precisar.
#
# Roda na fila `medium`, como a geração de e-mail, que faz o mesmo tipo de
# trabalho. Ocupa uma thread do Sidekiq enquanto pensa — e NENHUMA do painel.
#
# #861 — depois de responder, grava no turno da conversa a resposta e o
# diagnóstico do pedido (`Registro`). Aqui, e não durante o Guia: dentro de
# `Diario.gravando` toda escrita vira mudança do Guia, e o desfazer levaria junto
# o próprio registro.
class Autonomia::Guide::ChatJob < ApplicationJob
  queue_as :medium

  attr_reader :registro

  # A pergunta é de uma pessoa, num momento. Repetir sozinho, minutos depois,
  # entregaria uma resposta que ela já desistiu de esperar — e a tela só busca
  # durante a validade do pedido. Falhou, falhou: a tela diz, e ela pergunta de
  # novo se quiser.
  discard_on StandardError do |job, error|
    Rails.logger.error(
      "[autonomia][guide][chat_job] pedido=#{job.arguments.first} #{error.class}: #{error.message}\n" \
      "#{Array(error.backtrace).first(5).join("\n")}"
    )
    ::Autonomia::Guide::Pedido.falhar(job.arguments.first)
    # Só a classe do erro: a mensagem pode trazer o prompt ou dado da conta.
    diagnostico = (job.registro || ::Autonomia::Guide::Registro.new).diagnostico(erro: error.class.name)
    ::Autonomia::Guide::Turno.falhar(job.arguments.first, diagnostico)
  end

  # `pergunta` traz quem perguntou, o quê, o histórico da conversa, a tela em
  # que a pessoa estava e o idioma dela. O idioma vem da requisição: a frase do
  # botão de confirmar e o aviso de que apagar não tem volta saem do I18n, e o
  # job não herda o idioma de ninguém.
  def perform(pedido_id, pergunta)
    account = Account.find_by(id: pergunta['account_id'])
    user = User.find_by(id: pergunta['user_id'])
    return sem_dono(pedido_id) if account.nil? || user.nil?

    @registro = ::Autonomia::Guide::Registro.new
    resultado = @registro.ativo do
      I18n.with_locale(pergunta['locale']) do
        ::Autonomia::Guide::Chat.new(account: account, user: user, message: pergunta['mensagem'],
                                     history: pergunta['historico'], route_context: pergunta['tela'],
                                     route_params: pergunta['parametros'], arquivos: pergunta['arquivos'],
                                     registro: @registro).perform
      end
    end
    ::Autonomia::Guide::Pedido.concluir(pedido_id, resultado.to_h)
    ::Autonomia::Guide::Turno.concluir(pedido_id, resultado.to_h, diagnostico_de(resultado))
  end

  private

  def sem_dono(pedido_id)
    ::Autonomia::Guide::Pedido.falhar(pedido_id)
    ::Autonomia::Guide::Turno.falhar(pedido_id, ::Autonomia::Guide::Registro.new.diagnostico(erro: 'sem_conta_ou_pessoa'))
  end

  # O Guia fora do ar (`Chat#unavailable`) não levanta: devolve "indisponível".
  # O registro diz isso, para não parecer resposta.
  def diagnostico_de(resultado)
    @registro.diagnostico(erro: (resultado.available ? nil : 'indisponivel'))
  end
end
