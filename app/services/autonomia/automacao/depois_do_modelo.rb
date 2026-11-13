# A reunião (#2935) e a pesquisa (#2936) com a janela de 24 h fechada: sai o modelo aprovado no lugar da pergunta (como
# no passo "mensagem", decisão do Rodrigo de 12/11), e a pergunta de verdade (os horários, as notas) vai quando o
# cliente responder ao modelo, porque a resposta dele abre a janela da conversa.
#
# - A espera com o modelo guarda `fase: modelo`: a pergunta ainda não saiu.
# - Só pergunta com a janela da conversa do passo aberta. A Escuta acorda a execução com a mensagem do cliente em
#   qualquer conversa dele (o e-mail, o Instagram), e a janela desta pode continuar fechada: aí não manda nada e volta a
#   esperar com o mesmo prazo, a partir de um marco novo (a mesma volta da resposta ambígua).
# - Nunca um segundo modelo: depois do modelo, a pergunta sai sem o modelo da receita. Se a janela fechar no meio, nada
#   sai e a espera continua.
module Autonomia::Automacao::DepoisDoModelo
  MODELO = 'modelo'.freeze

  private

  def esperando_o_modelo?(pedido) = pedido.dados['fase'] == MODELO

  # A fase da espera depois de mandar: com o modelo no lugar, a pergunta ainda não saiu.
  def fase(mandado) = (mandado.dados[MODELO] ? { 'fase' => MODELO } : {})

  # A janela da conversa em que a pergunta vai sair, pela mesma pergunta do passo "mensagem" (o número novo incluso).
  def janela_ainda_fechada?
    motivo = ::Autonomia::Automacao::PassoDeMensagem.new(execucao: @execucao, passo: @passo, alvo: @alvo).motivo_do_canal
    ::Autonomia::Automacao::PassoDeMensagem::MOTIVOS_DE_JANELA.include?(motivo)
  end

  # O que a pergunta não sair por janela fechada devolve (MensagemComOpcoes sem modelo).
  def janela_fechou?(mandado) = mandado.dados['janela'] == 'fechada'

  def passo_sem_modelo = @passo.except(MODELO)

  def esperar_a_janela(leitor) = ::Autonomia::Automacao::PassoDeAcao::Resultado.new(tipo: :esperar, dados: { 'marco' => leitor.marco_novo })
end
