# O PDF de cada seguro que uma busca no conector trouxe (E7, #2900), no Carteira::Conector::PdfsJob: BLOCO por execução,
# um pedido ao conector por vez.
#
# Para cada registro na fila (Carteira::Conector::PdfsPendentes: os que viraram seguro e os `igual` de um seguro que já
# estava na carteira), cujo seguro ainda não tem PDF: pede o endereço do documento (`portfolio_document`), baixa pelo
# SafeFetch (sem redirecionamento, com prazo e teto de tamanho) e guarda no seguro com o nome neutro de sempre
# (`apolice-<id>.pdf`), deixando o passo `pdf_anexado` com a leitura, que é por onde o Desfazer reconhece o PDF que a busca
# pôs. O passo é do sistema: sem nome de pessoa (#3175). O seguro que ganhou PDF no meio do caminho fica com o dele.
#
# #3175: o portal entrega parte dos documentos como ZIP com nome `.pdf`. O arquivo que começa com `PK` é aberto e o PDF de
# dentro é o que vai para o seguro (Carteira::Conector::PdfDoZip: um PDF só, com teto descompactado). Arquivo que não é PDF
# nem ZIP é recusado (`nao_e_pdf`). Depois de guardar, o PDF é lido UMA vez num job próprio, que completa o que está vazio
# no seguro (Carteira::Conector::LerPdfJob).
#
# O ENDEREÇO DO PDF NÃO TEM AUTENTICAÇÃO E LEVA O NOME DO SEGURADO: vai direto do conector para o download e nunca para
# log, argumento de job, cache, resposta da API ou modelo. O `pdf_ref` leva o número da apólice: mesma regra. A falha de
# um PDF não trava os outros: conta uma tentativa e o registro volta depois (até o teto de tentativas do seguro). No
# registro, só ids e o código da recusa ou a classe do erro.
class Carteira::Conector::BaixarPdf
  BLOCO = 10
  TETO_BYTES = 40.megabytes
  PRAZO_SEGUNDOS = 30
  ABERTURA_SEGUNDOS = 5
  ASSINATURA = '%PDF-'.b.freeze
  Recusa = Carteira::Conector::PdfDoZip::Recusa
  PENDENTES = Carteira::Conector::PdfsPendentes

  def initialize(leitura, portal: nil)
    @leitura = leitura
    @portal = portal || Carteira::Conector::Portal.new(leitura.account)
    @pendentes = PENDENTES.new(leitura)
  end

  # :continua quando sobrou PDF para o próximo bloco agora; :mais_tarde quando só sobrou nova tentativa, depois da espera
  # (PdfsPendentes::ESPERA); :terminou no fim.
  def bloco
    return :terminou unless @leitura.estado == 'trazida'

    lote = @pendentes.agora.limit(BLOCO).to_a
    lote.each { |item| baixar(item) }
    return :continua if lote.size == BLOCO && @pendentes.agora.exists?

    @pendentes.mais_tarde? ? :mais_tarde : :terminou
  end

  private

  def baixar(item)
    apolice = @pendentes.apolice_de(item)
    fim = tentar(apolice, item)
    @pendentes.terminar(item, apolice, fim) if fim
  rescue StandardError => e
    # O conector, a rede, o armazenamento ou um arquivo que não serve: só este fica sem PDF, por enquanto.
    motivo = e.is_a?(Recusa) ? e.message : e.class.name
    Rails.logger.warn("[carteira][conector][pdf] item=#{item.id} sem_pdf: #{motivo}")
    @pendentes.falhou(item, apolice, motivo)
  end

  # O fim do registro na fila, ou nil quando ele não chegou a tentar (o teto já foi, e ele sai como `desistiu`).
  def tentar(apolice, item)
    return PENDENTES::SEM_SEGURO if apolice.nil?
    return PENDENTES::JA_TINHA if apolice.pdf.attached?
    return PENDENTES::DESISTIU unless @pendentes.cabe_tentar?(apolice)

    guardar(apolice, Carteira::ItemLido.new(item).valor('pdf_ref')) ? PENDENTES::BAIXADO : PENDENTES::JA_TINHA
  end

  # true quando o PDF foi guardado agora.
  def guardar(apolice, pdf_ref)
    url = @portal.documento(pdf_ref)['url']
    raise Recusa, 'sem_endereco' if url.blank?

    guardou = false
    SafeFetch.fetch(url.to_s, validate_content_type: false, max_bytes: TETO_BYTES, max_redirects: 0, schemes: %w[https],
                              open_timeout: ABERTURA_SEGUNDOS, read_timeout: PRAZO_SEGUNDOS, total_timeout: PRAZO_SEGUNDOS) do |resposta|
      guardou = com_o_pdf(resposta.tempfile) { |pdf| anexar(apolice, pdf) }
    end
    Carteira::Conector::LerPdfJob.perform_later(apolice.id, @leitura.id) if guardou
    guardou
  end

  # O PDF baixado, ou o de dentro do ZIP (que é apagado depois de guardado).
  def com_o_pdf(arquivo)
    return yield(arquivo) unless Carteira::Conector::PdfDoZip.zip?(arquivo)

    pdf = Carteira::Conector::PdfDoZip.new(arquivo, teto: TETO_BYTES).call
    yield(pdf)
  ensure
    pdf&.close!
  end

  def anexar(apolice, arquivo)
    raise Recusa, 'nao_e_pdf' unless arquivo.read(ASSINATURA.bytesize) == ASSINATURA

    arquivo.rewind
    apolice.with_lock(requires_new: true) do
      next false if apolice.pdf.attached?

      apolice.pdf = { io: arquivo, filename: "apolice-#{apolice.id}.pdf", content_type: Carteira::Pdf::TIPO, identify: false }
      apolice.save!
      apolice.eventos.create!(tipo: Carteira::Pdf::ANEXADO, quando: Time.current, user: nil, valores: { leitura: @leitura.id })
      true
    end
  end
end
