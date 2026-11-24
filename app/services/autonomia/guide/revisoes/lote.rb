# Um pedaço da revisão (#3158, B8b): até 10 conversas ou 20 s, e o `RevisaoJob` se reenfileira para o próximo.
#
# O estado mora no banco: cada conversa lida avança `posicao` e grava o motivo (`Revisao#avancar!`, em SQL e só de
# onde a revisão está), e o que morrer no meio é retomado pelo `RevisoesVigiaJob` de onde parou, sem ler de novo. A
# pessoa parou (escrevendo no Guia, #3143): o avanço não grava e o lote para.
#
# A permissão é conferida de novo a cada lote, com a pessoa dona da revisão: quem perdeu a caixa entre a escolha e a
# leitura não recebe o motivo nem o link daquela conversa. Ela conta como "não abriu", como a conversa apagada.
#
# Conversa que não abre (apagada, sem acesso, sem mensagem legível, IA sem resposta) conta em `falhas` e a revisão
# segue. Sem chave de IA, ou com 5 falhas seguidas da IA, a revisão inteira para como `falhou`, com o motivo.
class Autonomia::Guide::Revisoes::Lote
  CONTINUAR = :continuar
  FIM = :fim
  POR_LOTE = 10
  TEMPO = 20.seconds
  FALHAS_SEGUIDAS = 5
  REVISAO = ::Autonomia::Guide::Revisao
  SEMAFORO = ::Autonomia::Guide::Revisoes::Semaforo

  def initialize(revisao)
    @revisao = revisao
    @revisor = ::Autonomia::Guide::Revisoes::Revisor.new(revisao)
    @seguidas = 0
    # O revisor soma o custo do lote; cada avanço grava só a diferença desde o último.
    @custo_gravado = 0.0
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

  # Uma conversa. -> FIM quando a revisão acabou, parou ou outra cadeia avançou; CONTINUAR quando perdeu a vaga
  # (o job espera outra); nil para seguir.
  def passo
    return FIM unless @revisao.status == REVISAO::RODANDO
    return terminar if @revisao.proximo_id.nil?
    # A vaga vence em 3 min; um lote com IA lenta passa disso. Renovar a cada conversa.
    return CONTINUAR unless SEMAFORO.entrar(@revisao)
    return FIM unless ler(@revisao.proximo_id)
    return nil if @seguidas < FALHAS_SEGUIDAS

    falhar('ia')
    FIM
  end

  # -> o que `avancar` devolveu: false quando a revisão parou ou outra cadeia já avançou.
  def ler(conversa_id)
    conversa = permitidas.find_by(id: conversa_id)
    leitor = conversa && ::Autonomia::Guide::Revisoes::Leitor.new(conversa)
    return avancar(nil) if leitor.nil? || leitor.vazia?

    resultado = @revisor.revisar(conversa).merge('conversa_id' => conversa.id, 'numero' => conversa.display_id)
    @seguidas = 0
    avancar(resultado)
  rescue ::Autonomia::Guide::Revisoes::Revisor::Falhou => e
    Rails.logger.warn("[autonomia][guide][revisao] revisao=#{@revisao.id} conversa=#{conversa_id} #{e.message}")
    @seguidas += 1
    avancar(nil)
  end

  def avancar(resultado)
    custo = @revisor.custo - @custo_gravado
    @custo_gravado = @revisor.custo
    @revisao.avancar!(resultado, custo: custo)
  end

  def permitidas
    @permitidas ||= Conversations::PermissionFilterService.new(
      @revisao.account.conversations, @revisao.user, @revisao.account, for_reading: true
    ).perform
  end

  def terminar
    @revisao.mudar!(REVISAO::RODANDO, REVISAO::CONCLUIDA)
    FIM
  end

  def falhar(motivo)
    @revisao.mudar!(REVISAO::RODANDO, REVISAO::FALHOU, motivo: motivo)
  end
end
