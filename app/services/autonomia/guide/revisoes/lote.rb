# Um pedaço da revisão (#3158, B8b): até 10 conversas ou 20 s, e o `RevisaoJob` se reenfileira para o próximo.
#
# O estado mora no banco: cada conversa lida avança `posicao` e grava o motivo, e o que morrer no meio é retomado
# pelo `RevisoesVigiaJob` de onde parou, sem ler de novo. Entre uma conversa e outra o status é lido no banco: a
# pessoa parou (escrevendo no Guia, #3143), o lote para.
#
# Conversa que não abre (apagada, sem mensagem legível, IA sem resposta) conta em `falhas` e a revisão segue. Sem
# chave de IA, ou com 5 falhas seguidas da IA, a revisão inteira para como `falhou`, com o motivo.
class Autonomia::Guide::Revisoes::Lote
  CONTINUAR = :continuar
  FIM = :fim
  POR_LOTE = 10
  TEMPO = 20.seconds
  FALHAS_SEGUIDAS = 5
  REVISAO = ::Autonomia::Guide::Revisao

  def initialize(revisao)
    @revisao = revisao
    @revisor = ::Autonomia::Guide::Revisoes::Revisor.new(revisao)
    @seguidas = 0
    # O custo das vezes anteriores ("ler as que faltam"); o revisor soma só o deste lote.
    @custo_anterior = revisao.custo.to_d
  end

  def rodar
    inicio = Time.current
    POR_LOTE.times do
      parada = passo
      return parada if parada
      break if Time.current - inicio > TEMPO
    end
    @revisao.proximo_id.nil? ? terminar : CONTINUAR
  rescue ::Autonomia::Guide::Revisoes::Revisor::SemChave
    falhar('sem_chave')
    FIM
  end

  private

  # Uma conversa. -> FIM quando a revisão acabou ou parou; nil para seguir.
  def passo
    return FIM unless rodando?
    return terminar if @revisao.proximo_id.nil?

    ler(@revisao.proximo_id)
    return nil if @seguidas < FALHAS_SEGUIDAS

    falhar('ia')
    FIM
  end

  def ler(conversa_id)
    conversa = @revisao.account.conversations.find_by(id: conversa_id)
    leitor = conversa && ::Autonomia::Guide::Revisoes::Leitor.new(conversa)
    return avancar(nil) if leitor.nil? || leitor.vazia?

    avancar(@revisor.revisar(conversa).merge('conversa_id' => conversa.id, 'numero' => conversa.display_id))
    @seguidas = 0
  rescue ::Autonomia::Guide::Revisoes::Revisor::Falhou => e
    Rails.logger.warn("[autonomia][guide][revisao] revisao=#{@revisao.id} conversa=#{conversa_id} #{e.message}")
    @seguidas += 1
    avancar(nil)
  end

  # Uma conversa a mais: lida (com o resultado) ou que não abriu (nil).
  def avancar(resultado)
    @revisao.update_columns( # rubocop:disable Rails/SkipsModelValidations
      posicao: @revisao.posicao + 1,
      lidas: @revisao.lidas + (resultado ? 1 : 0),
      falhas: @revisao.falhas + (resultado ? 0 : 1),
      resultados: resultado ? @revisao.resultados + [resultado] : @revisao.resultados,
      custo: @custo_anterior + @revisor.custo.to_d,
      batimento_em: Time.current, updated_at: Time.current
    )
  end

  def rodando?
    REVISAO.where(id: @revisao.id).pick(:status) == REVISAO::RODANDO
  end

  def terminar
    @revisao.mudar!(REVISAO::RODANDO, REVISAO::CONCLUIDA)
    FIM
  end

  def falhar(motivo)
    @revisao.mudar!(REVISAO::RODANDO, REVISAO::FALHOU, motivo: motivo)
  end
end
