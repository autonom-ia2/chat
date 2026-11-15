# Lê UM arquivo de uma leitura de PDF (E6, #2899) e guarda no item o que o leitor achou. Quem chama é o
# Carteira::LeituraJob, com o id do item; serve ao anexar (um item, já ligado ao seguro) e ao Trazer por PDFs (um item
# por arquivo).
#
# - O PDF do item é baixado para um arquivo temporário e lido com OCR (estamos num job). Quando o item já tem a pessoa
#   (o anexar), o CPF/CNPJ dela vai para o leitor escolher as páginas por valor exato; senão, o nome; senão, as
#   primeiras páginas (Carteira::Leitor::Paginas). Só essas páginas vão ao modelo.
# - O resultado vai para o item como Carteira::ItemLido.do_resultado manda (decisão D1): o que está a confirmar fica em
#   `campos` com o nome em `duvidas`. Lido vira `lido`; o arquivo que não é apólice, `recusado`; o resto, `falhou`.
# - A leitura conta, em `totais`, quantos itens foram lidos, recusados e quantos falharam, e por qual motivo
#   (`motivo_<motivo>`: só contagem). Quando não sobra item lendo, a leitura fica `lida`.
# - O item que esperou mais que PRAZO na fila não é lido: fica `falhou` com o motivo `demorou`, e a tela diz para
#   mandar de novo. É o tempo limite da leitura: ninguém espera para sempre.
#
# Erro que não é do arquivo nem do modelo (defeito nosso) marca o item como `falhou` (motivo `erro`) e sobe, para o job
# registrar. Nada do PDF vai para log: só ids, o estado e o motivo.
class Carteira::LerItem
  PRAZO = 15.minutes
  ESTADO_DO_RESULTADO = { nil => 'lido', Carteira::Leitor::Resultado::NAO_E_APOLICE => 'recusado' }.freeze
  TOTAL_DO_ESTADO = { 'lido' => 'lidos', 'recusado' => 'recusados', 'falhou' => 'falharam' }.freeze

  def initialize(item, cliente: nil)
    @item = item
    @leitura = item.leitura
    @account = item.account
    @cliente = cliente
  end

  def call
    return unless @item.estado == 'lendo'
    return gravar('falhou', motivo: :demorou) if @item.created_at < PRAZO.ago

    resultado = ler
    estado = ESTADO_DO_RESULTADO.fetch(resultado.recusa, 'falhou')
    gravar(estado, motivo: (resultado.motivo || resultado.recusa if estado == 'falhou'), **Carteira::ItemLido.do_resultado(resultado))
  rescue StandardError
    gravar('falhou', motivo: :erro) if @item.reload.estado == 'lendo'
    raise
  end

  private

  def ler
    leitor = Carteira::Leitor.new(account: @account, ocr: true, cliente: @cliente)
    @item.pdf.open { |arquivo| leitor.ler(arquivo.path, documento: documento, nome: @item.contact&.name) }
  rescue ActiveStorage::FileNotFoundError
    Carteira::Leitor::Resultado.recusado(Carteira::Leitor::Resultado::NAO_DEU, motivo: :sem_arquivo)
  end

  # O CPF ou o CNPJ da pessoa do item, só os dígitos, para escolher as páginas. Nunca vai para log nem para o job.
  def documento
    pessoa = @item.contact
    pessoa && Relacionamentos::Documentos.new(@account).ler(pessoa)&.valor
  end

  def gravar(estado, motivo: nil, campos: {}, duvidas: [])
    @item.update!(estado: estado, campos: campos, duvidas: duvidas)
    contar(estado, motivo)
    Rails.logger.info("[carteira][leitura] item=#{@item.id} estado=#{estado} motivo=#{motivo}")
  end

  # Com a leitura travada: dois itens que terminam juntos não perdem a conta um do outro, e o último fecha a leitura.
  def contar(estado, motivo)
    @leitura.with_lock do
      totais = somar(@leitura.totais.to_h, TOTAL_DO_ESTADO.fetch(estado))
      totais = somar(totais, "motivo_#{motivo}") if motivo
      fim = @leitura.estado == 'lendo' && !@leitura.itens.exists?(estado: 'lendo')
      @leitura.update!(totais: totais, estado: fim ? 'lida' : @leitura.estado)
    end
  end

  def somar(totais, chave)
    totais.merge(chave => totais[chave].to_i + 1)
  end
end
