# Guardar o PDF anexado e lido (E6.2, #2899), com os campos que a pessoa escolheu trocar pelo que o PDF diz (`usar`).
# É o gravador do anexar, sobre o seguro da rota: não procura a apólice pela seguradora e pelo número como o gravador
# único (Carteira::Guardar), porque quem escolheu o seguro foi a pessoa.
#
# - A leitura é a do anexar deste seguro, já lida (Carteira::Pdf::Ler). Outra, de outro seguro, ou que já saiu
#   (guardada, limpa pela guarda) responde `leitura_expirou`; a que ainda está lendo, `leitura_nao_pronta`.
# - `usar` só aceita nomes de campos da gaveta (Carteira::Campos); outro nome é pedido inválido. O campo que não é mais
#   mudança (o seguro foi corrigido no meio) é ignorado. Vazio é "Manter como está": guarda só o PDF.
# - Cada campo escolhido recebe o valor do PDF. O campo corrigido à mão continua marcado como corrigido (decisão D3: foi
#   decisão de gente). A vigência que termina antes de começar é recusada (`termina_antes`), sem gravar nada; a
#   seguradora, o número e o fim que já são de outro seguro da conta, `apolice_repetida`.
# - Com campo mudado, a história ganha `chegou_de_novo_pdf` com o antes e o depois; a origem do seguro sobe para `pdf`
#   quando era mais fraca (a planilha), como no gravador único.
# - O PDF do item vai para o seguro (troca o que estava, como guardar outro PDF) e a história ganha `pdf_anexado`. O
#   arquivo não é copiado: o mesmo arquivo passa do item para o seguro, e a leitura sai.
# Tudo numa transação, com o seguro travado.
class Carteira::Pdf::Aceitar
  DE_NOVO = Carteira::Guardar::DE_NOVO_DA.fetch('pdf')
  FORCA = Carteira::Guardar::FORCA

  def initialize(apolice, user:)
    @apolice = apolice
    @user = user
  end

  def call(leitura_id, usar)
    usar = Array(usar).map(&:to_s)
    recusar('pedido_invalido') unless (usar - Carteira::Campos::COLUNAS.keys).empty?

    @apolice.with_lock(requires_new: true) { guardar(item_da(leitura_id), usar) }
    @apolice
  rescue ActiveRecord::RecordNotUnique
    recusar('apolice_repetida')
  end

  private

  def item_da(leitura_id)
    item = Carteira::LeituraItem.where(leitura_id: Carteira::Leitura.do_anexar.select(:id))
                                .find_by(leitura_id: leitura_id, account_id: @apolice.account_id, apolice_id: @apolice.id)
    recusar('leitura_expirou') unless item&.pdf&.attached? && %w[lendo lido].include?(item.estado)
    recusar('leitura_nao_pronta') if item.estado == 'lendo'
    item
  end

  def guardar(item, usar)
    o_que_mudou = Carteira::Pdf::OQueMudou.new(@apolice, item)
    trocar(o_que_mudou.valores.slice(*usar))
    passar_o_pdf(item)
    item.leitura.destroy!
  end

  def trocar(valores)
    return if valores.empty?

    novos = valores.transform_keys { |campo| coluna(campo) }
    conferir_vigencia(novos)
    mudancas = valores.map { |campo, depois| { campo: campo, antes: Carteira::Campos.guardado(@apolice[coluna(campo)]), depois: depois } }
    @apolice.update!(com_as_chaves(novos).merge(origem: origem))
    @apolice.eventos.create!(tipo: DE_NOVO, quando: Time.current, user: @user, valores: {}, mudancas: mudancas)
  end

  def coluna(campo)
    Carteira::Campos::COLUNAS.fetch(campo)
  end

  # A seguradora e o número levam a forma de comparação junto, como quem grava.
  def com_as_chaves(novos)
    chaves = {}
    chaves[:seguradora_chave] = Carteira::Chave.seguradora(novos[:seguradora]) if novos.key?(:seguradora)
    chaves[:numero_chave] = Carteira::Chave.numero(novos[:numero]).presence if novos.key?(:numero)
    novos.merge(chaves)
  end

  def conferir_vigencia(novos)
    comeca = novos.fetch(:inicio_vigencia, @apolice.inicio_vigencia)
    termina = novos.fetch(:fim_vigencia, @apolice.fim_vigencia)
    recusar('termina_antes') if comeca && termina && Date.parse(termina.to_s) < Date.parse(comeca.to_s)
  end

  # A fonte mais forte que já escreveu fica sendo a origem (conector > pdf > planilha); a feita à mão continua à mão.
  def origem
    return @apolice.origem if (FORCA.index(@apolice.origem) || FORCA.size) >= FORCA.index('pdf')

    'pdf'
  end

  def passar_o_pdf(item)
    arquivo = item.pdf.blob
    @apolice.pdf = arquivo
    @apolice.save!
    item.pdf.detach
    @apolice.eventos.create!(tipo: Carteira::Pdf::ANEXADO, quando: Time.current, user: @user)
  end

  def recusar(codigo)
    raise CustomExceptions::CarteiraRecusa.new(codigo), cause: nil
  end
end
