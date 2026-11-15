# "Desfazer" um lote de PDFs trazido (E6.3, #2899): `pedir` confere e põe na fila (Carteira::DesfazerPdfsJob, só com
# o id); `call` é o job. Primeiro os seguros (Carteira::Trazer::Pdfs::SegurosDoLote: o que o lote completou volta, o
# que ele criou e ninguém mexeu sai), depois as pessoas que o lote criou e em que ninguém tocou
# (Carteira::Trazer::Pdfs::QuemFica), pelo apagar de sempre (Contacts::BulkDeleteService). No fim a leitura fica
# `desfeita`, com quantos seguros e quantas pessoas ficaram.
#
# Só o lote trazido, dentro da guarda dos itens (sem eles não se sabe quem o lote criou), pode ser desfeito
# (`nao_pode_desfazer`). Cada seguro e cada pessoa são conferidos de novo logo antes de mudar: quem ganhou conversa, card
# ou nota no meio fica. O que der errado fica e os outros seguem; no registro vai só o id e a classe do erro. Rodar de
# novo não repete nada.
class Carteira::Trazer::Pdfs::Desfazer
  def self.pode?(leitura)
    leitura.estado == 'trazida' && leitura.confirmada_em.present? &&
      leitura.confirmada_em > Carteira::Leitura::DIAS_DE_GUARDA_DOS_ITENS.days.ago
  end

  def initialize(leitura, quem: nil)
    @leitura = leitura
    @conta = leitura.account
    @quem = quem
  end

  def pedir
    @leitura.with_lock do
      next if @leitura.estado == 'desfazendo'
      raise CustomExceptions::CarteiraRecusa.new('nao_pode_desfazer'), cause: nil unless self.class.pode?(@leitura)

      @leitura.update!(estado: 'desfazendo', user: @quem || @leitura.user)
    end
    Carteira::DesfazerPdfsJob.perform_later(@leitura.id)
  end

  def call
    return unless @leitura.estado == 'desfazendo'

    seguros = Carteira::Trazer::Pdfs::SegurosDoLote.new(@leitura)
    voltar(seguros)
    tirar(seguros)
    pessoas_que_ficaram = apagar_as_pessoas
    terminar(seguros, pessoas_que_ficaram)
  end

  def previa
    seguros = Carteira::Trazer::Pdfs::SegurosDoLote.new(@leitura).previa
    saem = 0
    ficam = 0
    Carteira::Trazer::Pdfs::QuemFica.new(@leitura).em_blocos do |sairiam, ficariam|
      saem += sairiam.size
      ficam += ficariam.size
    end
    seguros.merge(pessoasSaem: saem, pessoasFicam: ficam)
  end

  private

  def voltar(seguros)
    seguros.que_voltam do |bloco|
      bloco.each do |apolice|
        arquivo = com_cuidado(apolice) { devolver(seguros, apolice) }
        # O arquivo vai para a limpeza só depois de a transação fechar (mesmo padrão de Carteira::Pdf#tirar).
        arquivo&.purge_later
      end
    end
  end

  def devolver(seguros, apolice)
    volta = seguros.volta(apolice)
    return unless volta

    apolice.update!(volta[:colunas]) if volta[:colunas].any?
    arquivo = soltar_o_pdf(apolice) if volta[:tirar_pdf]
    seguros.passos_do_lote_em(apolice).delete_all
    arquivo
  end

  # Solta o PDF da apólice e devolve o arquivo, que quem chama manda limpar depois do commit.
  def soltar_o_pdf(apolice)
    return unless apolice.pdf.attached?

    arquivo = apolice.pdf.blob
    apolice.pdf.detach
    arquivo
  end

  def tirar(seguros)
    seguros.saem.in_batches(of: Carteira::Trazer::Pdfs::SegurosDoLote::BLOCO) do |apolices|
      apolices.each do |apolice|
        com_cuidado(apolice) do
          next unless seguros.sai?(apolice)

          # O has_one_attached limpa o arquivo depois do commit do destroy.
          apolice.destroy!
        end
      end
    end
  end

  def com_cuidado(apolice, &)
    apolice.with_lock(requires_new: true, &)
  rescue ActiveRecord::RecordNotFound
    nil
  rescue StandardError => e
    Rails.logger.warn("[carteira][pdfs][desfazer] apolice=#{apolice.id} kept: #{e.class.name}")
    nil
  end

  # Devolve quantas pessoas criadas pelo lote ficaram.
  def apagar_as_pessoas
    quem_fica = Carteira::Trazer::Pdfs::QuemFica.new(@leitura, seguros_ja_desfeitos: true)
    ficaram = 0
    quem_fica.em_blocos do |saem, ficam|
      ficaram += ficam.size
      saem.each { |id| ficaram += 1 unless apagar(id, quem_fica) }
    end
    ficaram
  end

  def apagar(id, quem_fica)
    return false if quem_fica.tem_conversa_card_ou_nota?(id)

    Contacts::BulkDeleteService.new(account: @conta, contact_ids: [id], user: @quem || @leitura.user).perform
    !@conta.contacts.exists?(id: id)
  rescue StandardError => e
    Rails.logger.warn("[carteira][pdfs][desfazer] contact=#{id} kept: #{e.class.name}")
    false
  end

  def terminar(seguros, pessoas_que_ficaram)
    totais = @leitura.reload.totais.to_h.merge('ficaram_seguros' => seguros.ainda_do_lote, 'ficaram_pessoas' => pessoas_que_ficaram)
    @leitura.update!(estado: 'desfeita', desfeita_em: Time.current, totais: totais)
  end
end
