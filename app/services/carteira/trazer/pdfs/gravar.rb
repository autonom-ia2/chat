# A gravação do lote de PDFs (E6.3, #2899), no Carteira::TrazerPdfsJob: cada PDF pronto vira seguro na carteira.
#
# Para cada PDF pronto, numa transação só dele:
# 1. a pessoa: a da conta que é o segurado (pelo documento; sem documento, pelo telefone ou e-mail confirmados), ou a que
#    nasce agora (Carteira::Trazer::Pdfs::PessoaDoItem). A que nasce fica marcada no item (`pessoa_nova_em`): o Desfazer
#    só tira quem o lote criou;
# 2. o seguro, SEMPRE pelo gravador único (Carteira::Guardar, origem `pdf`, com a leitura), só com o que está certo. A
#    apólice que já existia é completada pela regra de sempre; a de outra pessoa, a repetida e a ambígua são recusadas;
# 3. o PDF passa do item para o seguro (o mesmo arquivo, sem cópia, com o nome `apolice-<id>.pdf`) quando o seguro é
#    novo ou ainda não tem PDF; a história ganha `pdf_anexado` com a leitura, para o Desfazer reconhecer.
# O PDF que dá recusa vira `nao_entrou` (o motivo é só contado) e os outros seguem. Rodar de novo continua de onde
# parou: o PDF que já entrou (`trazido`) não é gravado outra vez.
# No fim a leitura fica `trazida`, com quantos seguros e quantas pessoas entraram. Nada daqui vai para log além de ids.
class Carteira::Trazer::Pdfs::Gravar
  def initialize(leitura)
    @leitura = leitura
    @account = leitura.account
    @pessoas = Carteira::Trazer::Pdfs::PessoaDoItem.new(@account)
    # As pessoas que nasceram neste lote, pela chave do Conferir: o segundo PDF da mesma pessoa nova não cria outra.
    @criadas = {}
  end

  def call
    return unless @leitura.estado == 'trazendo'

    @leitura.itens.where(estado: 'lido').order(:posicao).each do |item|
      vista = vista(item)
      next unless vista.pronto?

      gravar(vista)
      @leitura.update!(updated_at: Time.current)
    end
    terminar
  end

  private

  # O PDF como o Conferir o vê agora: a pessoa que nasceu num PDF anterior do lote já conta como da conta.
  def vista(item)
    sem_pessoa = Carteira::Trazer::Pdfs::ItemDoConferir.new(item)
    pessoa = @pessoas.achar(sem_pessoa.lido) || @criadas[sem_pessoa.chave_da_pessoa]
    Carteira::Trazer::Pdfs::ItemDoConferir.new(item, pessoa: pessoa)
  end

  def gravar(vista)
    chave = Carteira::Trazer::Pdfs::ItemDoConferir.new(vista.item).chave_da_pessoa
    pessoa = Carteira::Apolice.transaction(requires_new: true) { trazer(vista) }
    @criadas[chave] ||= pessoa unless vista.pessoa
  rescue CustomExceptions::CarteiraRecusa => e
    nao_entrou(vista.item, e.codigo)
  rescue ActiveRecord::RecordInvalid
    nao_entrou(vista.item, 'invalido')
  end

  def trazer(vista)
    item = vista.item
    pessoa = vista.pessoa || @pessoas.criar!(vista.lido)
    resultado = guardar(vista, pessoa)
    passar_o_pdf(item, resultado)
    campos = vista.pessoa ? item.campos : item.campos.merge(Carteira::ItemLido::PESSOA_NOVA => Time.current.iso8601)
    item.update!(estado: 'trazido', apolice: resultado.apolice, contact: pessoa, campos: campos)
    pessoa
  end

  # A empresa segurada só existe no Enterprise: no OSS os donos de um documento são sempre pessoas, e ela vem nil.
  def guardar(vista, pessoa)
    Carteira::Guardar.new(@account, origem: 'pdf', user: @leitura.user, leitura: @leitura)
                     .call(vista.lido.dados_da_apolice, contato: pessoa, empresa: @pessoas.empresa(vista.lido))
  end

  def passar_o_pdf(item, resultado)
    apolice = resultado.apolice
    return unless item.pdf.attached?
    return if apolice.pdf.attached? || resultado.situacao == Carteira::Guardar::CANCELADA

    arquivo = item.pdf.blob
    arquivo.update!(filename: "apolice-#{apolice.id}.pdf")
    apolice.pdf = arquivo
    apolice.save!
    item.pdf.detach
    apolice.eventos.create!(tipo: Carteira::Pdf::ANEXADO, quando: Time.current, user: @leitura.user, valores: { leitura: @leitura.id })
  end

  def nao_entrou(item, codigo)
    item.update!(estado: 'nao_entrou')
    somar("motivo_#{codigo}")
  end

  def somar(chave, quanto = 1)
    @leitura.reload
    totais = @leitura.totais.to_h
    @leitura.update!(totais: totais.merge(chave => totais[chave].to_i + quanto))
  end

  def terminar
    trazidos = @leitura.itens.where(estado: 'trazido')
    novas = trazidos.where('carteira_leitura_itens.campos ->> ? IS NOT NULL', Carteira::ItemLido::PESSOA_NOVA)
    totais = @leitura.reload.totais.to_h.merge(
      'seguros' => trazidos.count, 'pessoas' => trazidos.distinct.count(:contact_id), 'pessoas_novas' => novas.distinct.count(:contact_id),
      'nao_entraram' => @leitura.itens.where(estado: 'nao_entrou').count
    )
    @leitura.update!(estado: 'trazida', confirmada_em: Time.current, totais: totais)
  end
end
