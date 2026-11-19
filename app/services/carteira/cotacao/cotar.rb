# Cotar a renovação de um seguro (E8, #2901): depois do "Nada mudou" ou de DIAS_SEM_RESPOSTA sem resposta. O robô cota
# com `quem_cota` em `robo` e em `lia` (a Lia só responde depois, quando o segurado escrever).
#
# Antes da chamada paga, nesta ordem, e cada uma para aqui com `proposta_nao_saiu` na história e o aviso à equipe:
# 1. o portão, o card e o passo da vigência: já pedida (`proposta_pedida`) ou o segurado disse que mudou algo, nada a
#    fazer (sem evento);
# 2. a conexão com o portal e o Agente de Cotação da conta (`sem_conexao`, `sem_agente`);
# 3. o envio da proposta pode sair (Carteira::Cotacao::Envio#conferir!: recusa, caixa, modelo aprovado): proposta que não
#    sai não se paga (decisão D7). Motivo `envio`, com o do envio em `detalhe`;
# 4. a entrada (Carteira::Cotacao::Entrada): faltou dado, `faltou_dado` com os nomes dos campos. Antes de desistir, se
#    falta algum dado do segurado que a apólice traz e o seguro tem PDF, o PDF é lido uma vez nesta vigência
#    (Carteira::Cotacao::DadosDoPdf, E8.1 #3043) e a entrada é montada de novo com o que ele preencheu;
# 5. a conferência gratuita da ferramenta de cotação (`precheck` e `pedido` de Native::InsuranceQuote, a mesma instância,
#    uma chamada só, e o `start` também sai dela): o que ela diz que falta é `faltou_dado`; outra recusa dela vira o
#    motivo dela; sem resposta do
#    conferente (`pedido` nulo) é `conferencia_caiu`, e a cotação é tentada de novo depois de ESPERA_DA_CONFERENCIA, até
#    TENTATIVAS vezes (o aviso à equipe só na última).
#
# Passou: o passo `proposta_pedida` entra com o seguro travado (relido sob a trava: duas passadas não cotam duas vezes) e
# só então a cotação abre, numa execução normal da ferramenta (ToolRun `cotar_seguro` com o Agente de Cotação, na
# conversa do contato), que a Medida conta. A execução não avisa o cliente nem a Lia (`notify_customer: false`, sem
# prazo de varredura): quem acompanha é Carteira::Cotacao::AcompanharJob. Falha na abertura da cotação não tenta de novo
# (pode ter cotado no portal): `cotacao_falhou` e aviso.
class Carteira::Cotacao::Cotar
  TENTATIVAS = 3
  ESPERA_DA_CONFERENCIA = 30.minutes
  PRIMEIRA_LEITURA = 30.seconds
  PEDIDA = 'proposta_pedida'.freeze
  NAO_SAIU = 'proposta_nao_saiu'.freeze
  Quote = Autonomia::Agents::Tools::Native::InsuranceQuote

  def initialize(apolice, config, tentativa: 1)
    @apolice = apolice
    @config = config
    @tentativa = tentativa
  end

  def call
    return unless Carteira::Cotacao.aberta?(@apolice.account, @config) && @apolice.crm_card
    return if parar?

    conexao = Autonomia::Insurance::Connection.for_account(@apolice.account).find(&:usable?)
    return nao_saiu('sem_conexao') if conexao.nil?

    com_agente(conexao)
  rescue Carteira::Cotacao::Envio::NaoSaiu => e
    nao_saiu('envio', detalhe: e.message)
  end

  private

  def com_agente(conexao)
    agente = Carteira::Cotacao.agente(@apolice.account)
    return nao_saiu('sem_agente') if agente.nil?

    seguir(conexao, agente)
  end

  # A conferência é a da ferramenta (`precheck` e `pedido`, a mesma instância e uma chamada só ao conferente).
  def seguir(conexao, agente)
    Carteira::Cotacao::Envio.new(@apolice, @config).conferir!(Carteira::Cotacao::Proposta::FINALIDADE)
    entrada = montar_entrada(conexao)
    return faltou(entrada.faltam) if entrada.faltam.any?

    ferramenta = Quote.new(agent: agente, params: entrada.params)
    conferencia = ferramenta.precheck
    return recusada(conferencia) if conferencia
    return conferencia_caiu if ferramenta.pedido.nil?

    submeter(agente, entrada, ferramenta)
  end

  def montar_entrada(conexao)
    entrada = Carteira::Cotacao::Entrada.new(@apolice, conexao).call
    return entrada if entrada.faltam.empty? || !Carteira::Cotacao::DadosDoPdf.new(@apolice).call(entrada.faltam)

    Carteira::Cotacao::Entrada.new(@apolice.reload, conexao).call
  end

  def recusada(conferencia)
    return faltou(conferencia.faltando) if conferencia.motivo == 'faltam_dados' && conferencia.faltando.any?

    nao_saiu(conferencia.motivo)
  end

  def conferencia_caiu
    Carteira::Cotacao.registrar(@apolice, NAO_SAIU, motivo: 'conferencia_caiu', tentativa: @tentativa)
    if @tentativa < TENTATIVAS
      Carteira::Cotacao::CotarJob.set(wait: ESPERA_DA_CONFERENCIA).perform_later(@apolice.id, vigencia, @tentativa + 1)
    else
      Carteira::Cotacao::Aviso.new(@apolice, 'conferencia_caiu').call
    end
    nil
  end

  # A cotação sai pela MESMA ferramenta que conferiu: a conferência fica guardada nela, e o `start` não chama o conferente
  # de novo. Uma ferramenta nova conferiria outra vez, e o conferente que caísse ali deixaria a cotação paga sair sem
  # conferência. O `start` não lê a execução (`run`): ela só serve ao acompanhamento (AcompanharJob monta a sua).
  def submeter(agente, entrada, ferramenta)
    return unless pedir!

    run = abrir(agente, entrada)
    handle = ferramenta.start
    return recusada_no_envio(run, handle) if handle['quote_id'].blank?

    run.record_attempt!(handle: handle)
    Carteira::Cotacao::AcompanharJob.set(wait: PRIMEIRA_LEITURA).perform_later(run.id, @apolice.id)
  rescue StandardError => e
    run&.finish!('failed', failure_code: 'abertura')
    Rails.logger.warn("[carteira][cotacao] cotacao nao abriu apolice=#{@apolice.id} #{e.class}")
    nao_saiu('cotacao_falhou')
  end

  # O passo que trava a vigência: entra uma vez só, relido com o seguro travado.
  def pedir!
    @apolice.with_lock(requires_new: true) do
      next false if parar?

      Carteira::Cotacao.registrar(@apolice, PEDIDA)
      true
    end
  end

  def abrir(agente, entrada)
    conversa = Carteira::Cotacao::Envio.new(@apolice, @config).conversa
    escopo = { conversation_id: conversa.id, faixa: Autonomia::Insurance::Faixa.de(entrada.produto, entrada.params['item']) }
    run = Autonomia::Agents::ToolRun.open!(agent: agente, slug: Quote.slug, arguments: entrada.params, scope: escopo)
    raise ActiveRecord::RecordNotUnique, 'execucao ativa' if run.nil?

    run.promote!(expected_chunks: 0, notify_customer: false, expires_at: nil)
    run
  end

  # A ferramenta recusou no envio (o que falta, o ramo que a IA não cota): a execução fecha sem cotação.
  def recusada_no_envio(run, handle)
    run.finish!('failed', failure_code: handle['recusa'].to_s.first(60).presence || 'recusa')
    faltando = Array(handle['faltando']).map(&:to_s)
    handle['recusa'] == 'faltam_dados' && faltando.any? ? faltou(faltando) : nao_saiu(handle['recusa'].presence || 'recusa')
  end

  def parar?
    Carteira::Cotacao.passo(@apolice, PEDIDA) || Carteira::Cotacao.mudou?(@apolice)
  end

  def faltou(campos)
    nao_saiu('faltou_dado', faltam: campos.map(&:to_s).uniq, aviso: 'faltou_dado')
  end

  def nao_saiu(motivo, detalhe: nil, faltam: nil, aviso: 'proposta_nao_saiu')
    Carteira::Cotacao.registrar(@apolice, NAO_SAIU, { motivo: motivo, detalhe: detalhe, faltam: faltam }.compact)
    Carteira::Cotacao::Aviso.new(@apolice, aviso, detalhe: detalhe || motivo, faltam: faltam).call
    nil
  end

  def vigencia
    @apolice.fim_vigencia.iso8601
  end
end
