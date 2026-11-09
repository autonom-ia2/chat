# Os passos de IA no executor (#2500 F7): "decidir", "extrair", "escrever" e "resumir". Ficam fora do Executor para
# ele seguir sendo a lista dos passos; os métodos usam os dele (reconferir, impedida?, encerrar, registrar).
module Autonomia::Automacao::IaNoExecutor
  # A parada fora da janela (F4.4): o "escrever" ao cliente usa aqui, e a mensagem no Executor.
  include ::Autonomia::Automacao::JanelaFechada

  IA = {
    'decidir' => ::Autonomia::Automacao::PassoDeDecidir, 'extrair' => ::Autonomia::Automacao::PassoDeExtrair,
    'escrever' => ::Autonomia::Automacao::PassoDeEscrever, 'resumir' => ::Autonomia::Automacao::PassoDeResumir
  }.freeze

  private

  # Reconferem tudo como a ação. Sem a flag da F7 fecham sem chamar a IA (rollback); os que falam com gente (escrever ao
  # cliente, resumo em aviso) pedem também a da F4. O erro passageiro da IA tenta de novo, como a ação, e paga de novo:
  # nada foi mandado nem gravado antes da resposta. O "decidir" que espera a próxima resposta (G31) confere ao retomar
  # se ela chegou antes de ir à IA (DecidirDeNovo).
  def passo_de_ia(passo, classe)
    return retomar_decisao(passo) if @retomando && ::Autonomia::Automacao::DecidirDeNovo.espera?(passo)

    reconferir
    return if impedida?(passo['id'])
    return encerrar(passo['id'], 'parada', 'ia_desligada') unless ::Autonomia::Automacao::Motor.ia?(@account)
    if classe.fala_com_gente?(passo) && !::Autonomia::Automacao::Motor.mensagens?(@account)
      return encerrar(passo['id'], 'parada', 'mensagens_desligadas')
    end

    executor = classe.new(execucao: @execucao, passo: passo, alvo: alvo, acesso: @acesso)
    marcar_leitura(passo)
    depois_da_ia(passo, executor, com_marco_dos_anexos(executor, executor.executar))
  end

  # G46: o passo que leu os anexos novos grava o marco no registro, e a próxima leitura parte dele. Só quando o passo
  # andou (ok ou pulado): na nova tentativa de um erro passageiro, os mesmos anexos vão de novo.
  def com_marco_dos_anexos(executor, resultado)
    registro = executor.registro_dos_anexos
    return resultado unless registro && %i[ok pulado].include?(resultado.tipo)

    resultado.class.new(tipo: resultado.tipo, motivo: resultado.motivo, dados: resultado.dados.to_h.merge(registro))
  end

  # O "escrever" ao cliente com a janela fechada para antes de pagar a IA, como a mensagem (F4.4, #2573).
  def depois_da_ia(passo, executor, resultado)
    return parar_na_janela(passo, resultado) if janela_fechada?(resultado)

    case resultado.tipo
    when :ok, :pulado then resultado.dados['ramo'] ? seguir_pelo_caminho(passo, executor, resultado) : seguir_depois_da_acao(passo, resultado)
    when :permanente then encerrar(passo['id'], 'falhou', resultado.motivo, 'falhou', resultado.dados)
    when :sem_acesso, :laco then encerrar(passo['id'], 'parada', motivo_da_parada(resultado), 'falhou', resultado.dados)
    else tentar_de_novo(passo, resultado)
    end
  end

  # O registro com o caminho vem antes da nota do motivo: se a nota falhar, a automação segue pelo caminho, e o registro
  # diz `nota_faltou`. A nota nunca fica duplicada. O caminho marcado no `de_novo` não deixa nota: "ainda conversando"
  # (G31) e "falta algo" (G46) deixariam uma por mensagem, como o "nenhum" (#2578). Sem `desde`, espera a próxima
  # resposta (G31); com ele, segue pelo caminho, que volta ao "esperar até" (Roteiro, G46).
  def seguir_pelo_caminho(passo, executor, resultado)
    @tentativas = 0
    ramo = resultado.dados['ramo']
    registro = registrar(passo['id'], resultado.tipo == :pulado ? 'pulado' : 'ok', resultado.motivo, dados_do_caminho(passo, resultado.dados))
    if ::Autonomia::Automacao::DecidirDeNovo.marcado?(passo, ramo)
      return ::Autonomia::Automacao::DecidirDeNovo.espera?(passo) ? esperar_resposta(passo) : @roteiro.entrar_no_caminho(passo, ramo)
    end

    nota = anotar(executor, ramo)
    registro.update!(dados: registro.dados.merge(nota ? { 'nota_id' => nota.id } : { 'nota_faltou' => true })) unless nota == false
    @roteiro.entrar_no_caminho(passo, ramo)
  end

  # A nota do motivo; false quando não há nota a deixar (não houve pergunta à IA, ou a IA escolheu "nenhum"), nil quando
  # falhou. A falha fica no log só com a classe do erro: a mensagem pode trazer o texto da conversa.
  def anotar(executor, ramo)
    executor.anotar(ramo) || false
  rescue StandardError => e
    Rails.logger.error("[automacao][motor] nota do decidir falhou execucao=#{@execucao.id} passo=#{@passo_atual} #{e.class}")
    nil
  end
end
