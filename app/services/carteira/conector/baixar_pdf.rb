# O PDF de cada seguro que uma busca no conector trouxe (E7, #2900), no Carteira::Conector::PdfsJob: BLOCO por execução,
# um pedido ao conector por vez.
#
# Para cada registro trazido com `pdf_ref`, cujo seguro ainda não tem PDF: pede o endereço do documento
# (`portfolio_document`), baixa pelo SafeFetch (sem redirecionamento, com prazo e teto de tamanho, e só se o conteúdo é
# mesmo um PDF) e guarda no seguro com o nome neutro de sempre (`apolice-<id>.pdf`), deixando o passo `pdf_anexado` com a
# leitura, que é por onde o Desfazer reconhece o PDF que a busca pôs. O seguro que ganhou PDF no meio do caminho fica com
# o dele.
#
# O ENDEREÇO DO PDF NÃO TEM AUTENTICAÇÃO E LEVA O NOME DO SEGURADO: vai direto do conector para o download e nunca para
# log, argumento de job, cache, resposta da API ou modelo. O `pdf_ref` leva o número da apólice: mesma regra. A falha de
# um PDF não trava os outros: o registro fica marcado como tentado e o seguro segue sem PDF. No registro, só ids e a
# classe do erro.
class Carteira::Conector::BaixarPdf
  BLOCO = 10
  TENTADO = 'pdf_tentado_em'.freeze
  TETO_BYTES = 40.megabytes
  PRAZO_SEGUNDOS = 30
  ABERTURA_SEGUNDOS = 5
  ASSINATURA = '%PDF-'.freeze
  NaoEPdf = Class.new(StandardError)

  def initialize(leitura, portal: nil)
    @leitura = leitura
    @portal = portal || Carteira::Conector::Portal.new(leitura.account)
  end

  # :continua quando sobrou PDF para o próximo bloco; :terminou no fim.
  def bloco
    return :terminou unless @leitura.estado == 'trazida'

    pendentes = a_baixar.limit(BLOCO).to_a
    pendentes.each { |item| baixar(item) }
    pendentes.size == BLOCO && a_baixar.exists? ? :continua : :terminou
  end

  private

  def a_baixar
    @leitura.itens.where(estado: 'trazido').where.not(apolice_id: nil)
            .where("carteira_leitura_itens.campos ->> 'pdf_ref' IS NOT NULL").where('carteira_leitura_itens.campos ->> ? IS NULL', TENTADO)
            .order(:posicao)
  end

  def baixar(item)
    apolice = item.apolice
    guardar(apolice, Carteira::ItemLido.new(item).valor('pdf_ref')) unless apolice.pdf.attached?
  rescue StandardError => e
    # O conector, a rede, o armazenamento ou um arquivo que não é PDF: só este fica sem PDF.
    Rails.logger.warn("[carteira][conector][pdf] item=#{item.id} sem_pdf: #{e.class.name}")
  ensure
    marcar(item)
  end

  def guardar(apolice, pdf_ref)
    url = @portal.documento(pdf_ref)['url']
    raise NaoEPdf if url.blank?

    SafeFetch.fetch(url.to_s, validate_content_type: false, max_bytes: TETO_BYTES, max_redirects: 0, schemes: %w[https],
                              open_timeout: ABERTURA_SEGUNDOS, read_timeout: PRAZO_SEGUNDOS, total_timeout: PRAZO_SEGUNDOS) do |resposta|
      anexar(apolice, resposta.tempfile)
    end
  end

  def anexar(apolice, arquivo)
    raise NaoEPdf unless arquivo.read(ASSINATURA.bytesize) == ASSINATURA

    arquivo.rewind
    apolice.with_lock(requires_new: true) do
      next if apolice.pdf.attached?

      apolice.pdf = { io: arquivo, filename: "apolice-#{apolice.id}.pdf", content_type: Carteira::Pdf::TIPO, identify: false }
      apolice.save!
      apolice.eventos.create!(tipo: Carteira::Pdf::ANEXADO, quando: Time.current, user: @leitura.user, valores: { leitura: @leitura.id })
    end
  end

  def marcar(item)
    item.update!(Carteira::ItemLido.new(item).com(TENTADO => Time.current.iso8601))
  end
end
