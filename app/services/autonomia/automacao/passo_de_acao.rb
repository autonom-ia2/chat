# O passo "ação da plataforma" de uma execução (#2414 F3). Monta o pedido com os valores do alvo, executa como quem
# ligou (AcoesDoMotor) e anota cada linha que mudou no caderno do Guia: a mudança aparece no histórico e se desfaz como
# no Guia, por 5 dias (F3.8). O caderno fica com quem ligou.
#
# O resultado diz o que o executor faz depois (F3.6, F3.7):
# - :ok segue;
# - :pulado segue, com o motivo: faltou um valor do alvo, a data lida não é data, ou o valor calculado no corpo (G16)
#   não cabe no campo (fora da lista de opções): nunca grava valor que a plataforma recusaria;
# - :permanente para a execução (4xx: a etiqueta não existe, o corpo não serve);
# - :sem_acesso pausa a automação (401/403, ou quem ligou perdeu a chave de automações ou, na ação de funil, a de
#   funis, #2633);
# - :passageiro tenta de novo (5xx, 408, 425, 429, erro sem resposta), menos quando o caderno mostra que a ação já
#   gravou alguma coisa: repetir faria de novo (criaria a etiqueta duas vezes), então fecha como permanente.
class Autonomia::Automacao::PassoDeAcao
  Resultado = Struct.new(:tipo, :motivo, :dados, keyword_init: true)
  # 4xx que passam: tempo esgotado, cedo demais e limite de pedidos.
  PASSAGEIROS = [408, 425, 429].freeze

  # `acoes`: a porta que executa. O passo "criar retorno" (G3) passa a dele, liberada só para o retorno.
  def initialize(execucao:, passo:, valores:, acesso:, acoes: ::Autonomia::Automacao::AcoesDoMotor)
    @execucao = execucao
    @passo = passo
    @valores = valores
    @acesso = acesso
    @acoes = acoes
  end

  def executar
    motor.conferir!(@passo['acao'])
    caminho = caminho_resolvido
    corpo = caminho.values.any?(&:blank?) ? pulado('faltou_valor') : corpo_pronto
    corpo.is_a?(Resultado) ? corpo : agir(caminho, corpo)
  rescue ::Autonomia::Automacao::AcoesDoMotor::SemPermissao => e
    Resultado.new(tipo: :sem_acesso, motivo: e.motivo, dados: {})
  rescue ::Autonomia::Guide::Acoes::Recusada => e
    Rails.logger.info("[automacao][passo] recusado execucao=#{@execucao.id} passo=#{@passo['id']} #{e.class}: #{e.message}")
    Resultado.new(tipo: :permanente, motivo: 'acao_recusada', dados: {})
  end

  private

  def agir(caminho, corpo)
    caderno = ::Autonomia::Guide::Execucao.abrir(account: @execucao.account, user: @acesso.usuario)
    resultado = no_caderno(caderno) { motor.executar(@passo['acao'], dados(caminho, corpo)) }
    classificar(resultado, motor.codigo, caderno)
  end

  def motor
    @motor ||= @acoes.new(execucao: @execucao, account_user: @acesso.account_user)
  end

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

  def pulado(motivo, dados = {}) = Resultado.new(tipo: :pulado, motivo: motivo, dados: dados)

  # O corpo com os valores calculados (G16), ou o pulo: valor vazio, data que não é data, valor que não cabe no campo.
  def corpo_pronto
    montado = ::Autonomia::Automacao::Corpo.new(@passo['corpo'], valores: @valores, conta: @execucao.account).montar
    return pulado(montado.motivo) if montado.motivo

    fora = fora_do_formato(montado.corpo)
    fora.any? ? pulado('valor_fora_do_formato', 'problemas' => fora) : montado.corpo
  end

  # O corpo literal o salvar já conferiu. O calculado só existe agora: confere com o valor de verdade (opção fora da
  # lista ou valor de outro tipo vira pulo com o motivo, nunca valor inválido gravado).
  def fora_do_formato(corpo)
    return [] unless ::Autonomia::Automacao::Corpo.calculado_em?(@passo['corpo'])

    ::Autonomia::Automacao::CampoDaAcao.problemas(@passo['acao'], @passo['corpo'].to_h, corpo, conta: @execucao.account)
  end

  def dados(caminho, corpo)
    { caminho: caminho, corpo: corpo, descricao: @passo['descricao'] }
  end

  def classificar(resultado, codigo, caderno)
    dados = { 'acao' => @passo['acao'], 'codigo' => codigo, 'registro' => resultado.registro, 'caderno_id' => caderno.id }
    return Resultado.new(tipo: :ok, dados: dados) if resultado.ok
    return Resultado.new(tipo: :sem_acesso, motivo: 'quem_ligou_sem_acesso', dados: dados) if [401, 403].include?(codigo)
    return Resultado.new(tipo: :permanente, motivo: 'erro_permanente', dados: dados) if permanente?(codigo)
    return Resultado.new(tipo: :permanente, motivo: 'erro_depois_de_gravar', dados: dados) if caderno.mudancas.exists?

    Resultado.new(tipo: :passageiro, motivo: 'erro_passageiro', dados: dados)
  end

  def permanente?(codigo)
    codigo.to_i.between?(400, 499) && PASSAGEIROS.exclude?(codigo)
  end
end
