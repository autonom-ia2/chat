# A cotação da renovação fechou (E8, #2901). A leitura que fechou é gravada na execução (a Medida conta as seguradoras
# acionadas e as com preço) e a execução termina. Depois:
# - a melhor oferta: a de menor prêmio entre as que cotaram com preço TOTAL (`resultado_por_seguradora` do handle); preço
#   mensal ou sem base não entra na comparação com o valor do ano passado;
# - a proposta: o comparativo em PDF que a ferramenta gerou, baixado pela mesma entrega de arquivo do publicador
#   (Tools::EntregaDeArquivo, com o nome "Proposta de renovação.pdf") e guardado como anexo de uma NOTA PRIVADA na
#   conversa da cotação: aparece nas mídias do card e o cliente não vê;
# - `proposta_pronta` com `premio_centavos`, `seguradora` (o nome) e `nota` (o id da nota). No modo `sozinho`, a proposta
#   sai já (Carteira::Cotacao::Proposta); no `pessoa`, espera o clique em "Enviar" no card.
# Sem preço nenhum: `proposta_nao_saiu` `sem_preco` e aviso. Com preço e sem PDF: `sem_pdf` e aviso (o modelo da proposta
# leva o PDF no topo).
class Carteira::Cotacao::Pronta
  NOME_DO_ARQUIVO = 'Proposta de renovação.pdf'.freeze
  PRONTA = 'proposta_pronta'.freeze
  Resultado = Autonomia::Insurance::ResultadoPorSeguradora

  def initialize(apolice, run, progresso)
    @apolice = apolice
    @run = run
    @progresso = progresso
  end

  def call
    @run.record_attempt!(handle: @progresso.handle) if @progresso.handle
    @run.finish!('done')
    melhor = melhor_oferta
    return nao_saiu('sem_preco', 'sem_preco') if melhor.nil?

    nota = guardar
    return nao_saiu('sem_pdf', 'proposta_nao_saiu') if nota.nil?

    Carteira::Cotacao.registrar(@apolice, PRONTA, premio_centavos: (melhor['premio']['amount'].to_d * 100).round.to_i,
                                                  seguradora: melhor['nome'], nota: nota.id)
    enviar_sozinha
  end

  private

  def melhor_oferta
    por_seguradora = @run.handle.to_h[Autonomia::Agents::Tools::Native::InsuranceQuote::RESULTADO_KEY]
    por_seguradora.to_h.values.select { |oferta| total?(oferta) }.min_by { |oferta| oferta['premio']['amount'].to_d }
  end

  def total?(oferta)
    oferta.is_a?(Hash) && oferta['desfecho'] == Resultado::COM_PRECO && oferta.dig('premio', 'basis') == 'total' &&
      oferta.dig('premio', 'amount').present?
  end

  def guardar
    url = Array(@progresso.deliveries).filter_map { |entrega| entrega.dig(Autonomia::Agents::Tools::EntregaDeArquivo::CHAVE, 'url') }.first
    return if url.blank?

    blob = Autonomia::Agents::Tools::EntregaDeArquivo.new(url: url, nome: NOME_DO_ARQUIVO).gravar(run_id: @run.id)
    nota(blob)
  rescue StandardError => e
    Rails.logger.warn("[carteira][cotacao] proposta nao guardada run=#{@run.id} #{e.class}")
    nil
  end

  def nota(blob)
    conversa = @run.conversation
    marca = { Carteira::Cotacao::MARCA => { apolice_id: @apolice.id, etapa: Carteira::Cotacao::ETAPA_PROPOSTA_GUARDADA } }
    mensagem = conversa.messages.new(account_id: conversa.account_id, inbox_id: conversa.inbox_id, message_type: :outgoing,
                                     private: true, content: I18n.t('carteira.cotacao.nota_da_proposta', locale: locale),
                                     content_attributes: marca)
    mensagem.attachments.new(account_id: conversa.account_id, file_type: :file, file: blob.signed_id)
    mensagem.save!
    mensagem
  end

  def enviar_sozinha
    config = Carteira::RenovacaoConfig.find_by(account_id: @apolice.account_id)
    return unless config&.quem_envia == Carteira::RenovacaoConfig::SOZINHO

    Carteira::Cotacao::Proposta.new(@apolice, config).enviar
  end

  def nao_saiu(motivo, aviso)
    Carteira::Cotacao.registrar(@apolice, Carteira::Cotacao::Cotar::NAO_SAIU, motivo: motivo)
    Carteira::Cotacao::Aviso.new(@apolice, aviso, detalhe: motivo).call
  end

  def locale
    @apolice.account.locale.presence || I18n.default_locale
  end
end
