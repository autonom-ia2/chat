# O passo "ação da plataforma" de uma execução (#2414 F3). Monta o pedido com os valores do alvo, executa como quem
# ligou (AcoesDoMotor) e anota cada linha que mudou no caderno do Guia: a mudança aparece no histórico e se desfaz como
# no Guia, por 5 dias (F3.8). O caderno fica com quem ligou.
#
# O resultado diz o que o executor faz depois (F3.6, F3.7):
# - :ok segue;
# - :pulado segue, com o motivo (faltou um valor do alvo);
# - :permanente para a execução (4xx: a etiqueta não existe, o corpo não serve);
# - :sem_acesso pausa a automação (401/403: quem ligou não alcança mais);
# - :passageiro tenta de novo (5xx, erro sem resposta).
class Autonomia::Automacao::PassoDeAcao
  Resultado = Struct.new(:tipo, :motivo, :dados, keyword_init: true)

  def initialize(execucao:, passo:, valores:, acesso:)
    @execucao = execucao
    @passo = passo
    @valores = valores
    @acesso = acesso
  end

  def executar
    caminho = caminho_resolvido
    return Resultado.new(tipo: :pulado, motivo: 'faltou_valor', dados: {}) if caminho.values.any?(&:blank?)

    caderno = ::Autonomia::Guide::Execucao.abrir(account: @execucao.account, user: @acesso.usuario)
    acoes = ::Autonomia::Automacao::AcoesDoMotor.new(execucao: @execucao, account_user: @acesso.account_user)
    resultado = no_caderno(caderno) { acoes.executar(@passo['acao'], dados(caminho)) }
    classificar(resultado, acoes.codigo, caderno)
  rescue ::Autonomia::Guide::Acoes::Recusada => e
    Rails.logger.info("[automacao][passo] recusado execucao=#{@execucao.id} passo=#{@passo['id']} #{e.class}: #{e.message}")
    Resultado.new(tipo: :permanente, motivo: 'acao_recusada', dados: {})
  end

  private

  def no_caderno(caderno, &)
    resultado = ::Autonomia::Guide::Diario.gravando(caderno, caderno.passos.size, &)
    caderno.registrar_passo(acao: @passo['acao'], frase: @passo['descricao'], feito: resultado.ok, registro: resultado.registro)
    resultado
  end

  def caminho_resolvido
    @passo['caminho'].to_h.transform_values do |valor|
      valor.is_a?(Hash) ? @valores.ler(valor['$valor']) : valor
    end
  end

  def dados(caminho)
    { caminho: caminho, corpo: @passo['corpo'].to_h, descricao: @passo['descricao'] }
  end

  def classificar(resultado, codigo, caderno)
    dados = { 'acao' => @passo['acao'], 'codigo' => codigo, 'registro' => resultado.registro, 'caderno_id' => caderno.id }
    return Resultado.new(tipo: :ok, dados: dados) if resultado.ok
    return Resultado.new(tipo: :sem_acesso, motivo: 'quem_ligou_sem_acesso', dados: dados) if [401, 403].include?(codigo)
    return Resultado.new(tipo: :permanente, motivo: 'erro_permanente', dados: dados) if codigo.to_i.between?(400, 499)

    Resultado.new(tipo: :passageiro, motivo: 'erro_passageiro', dados: dados)
  end
end
