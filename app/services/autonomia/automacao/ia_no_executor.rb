# Os passos de IA no executor (#2500 F7): "decidir", "extrair", "escrever" e "resumir". Ficam fora do Executor para
# ele seguir sendo a lista dos passos; os métodos usam os dele (reconferir, impedida?, encerrar, registrar).
module Autonomia::Automacao::IaNoExecutor
  IA = {
    'decidir' => ::Autonomia::Automacao::PassoDeDecidir, 'extrair' => ::Autonomia::Automacao::PassoDeExtrair,
    'escrever' => ::Autonomia::Automacao::PassoDeEscrever, 'resumir' => ::Autonomia::Automacao::PassoDeResumir
  }.freeze

  private

  # Reconferem tudo como a ação. Sem a flag da F7 fecham sem chamar a IA (rollback); os que falam com gente (escrever ao
  # cliente, resumo em aviso) pedem também a da F4. O erro passageiro da IA tenta de novo, como a ação, e paga de novo:
  # nada foi mandado nem gravado antes da resposta.
  def passo_de_ia(passo, classe)
    reconferir
    return if impedida?(passo['id'])
    return encerrar(passo['id'], 'parada', 'ia_desligada') unless ::Autonomia::Automacao::Motor.ia?(@account)
    if classe.fala_com_gente?(passo) && !::Autonomia::Automacao::Motor.mensagens?(@account)
      return encerrar(passo['id'], 'parada', 'mensagens_desligadas')
    end

    executor = classe.new(execucao: @execucao, passo: passo, alvo: alvo, acesso: @acesso)
    depois_da_ia(passo, executor, executor.executar)
  end

  def depois_da_ia(passo, executor, resultado)
    case resultado.tipo
    when :ok, :pulado then resultado.dados['ramo'] ? seguir_pelo_caminho(passo, executor, resultado) : seguir_depois_da_acao(passo, resultado)
    when :permanente then encerrar(passo['id'], 'falhou', resultado.motivo, 'falhou', resultado.dados)
    when :sem_acesso, :laco then encerrar(passo['id'], 'parada', motivo_da_parada(resultado), 'falhou', resultado.dados)
    else tentar_de_novo(passo, resultado)
    end
  end

  # O registro com o caminho vem antes da nota do motivo: se a nota falhar, a automação segue pelo caminho, e o registro
  # diz `nota_faltou`. A nota nunca fica duplicada.
  def seguir_pelo_caminho(passo, executor, resultado)
    @tentativas = 0
    registro = registrar(passo['id'], 'ok', nil, resultado.dados)
    nota = anotar(executor, resultado.dados['ramo'])
    registro.update!(dados: registro.dados.merge(nota ? { 'nota_id' => nota.id } : { 'nota_faltou' => true })) unless nota == false
    @roteiro.entrar_no_caminho(passo, resultado.dados['ramo'])
  end

  # A nota do motivo; false quando não havia motivo (não houve pergunta à IA), nil quando falhou. A falha fica no log só
  # com a classe do erro: a mensagem pode trazer o texto da conversa.
  def anotar(executor, ramo)
    executor.anotar(ramo) || false
  rescue StandardError => e
    Rails.logger.error("[automacao][motor] nota do decidir falhou execucao=#{@execucao.id} passo=#{@passo_atual} #{e.class}")
    nil
  end
end
