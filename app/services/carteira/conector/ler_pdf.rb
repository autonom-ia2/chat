# A leitura do PDF que a busca no conector acabou de guardar num seguro (#3175), no Carteira::Conector::LerPdfJob. O
# seguro do Agger chega quase vazio (sem valor, sem o que está segurado, com o tipo "Outro"); o PDF da apólice traz isso
# escrito. Ele é lido UMA vez, com o leitor que já está no ar (Carteira::Leitor::DoSeguro), e completa SÓ o que está
# vazio no seguro conhecido (Carteira::Pdf::Completar): o tipo (quando é "Outro") e o ramo, o valor, o que está
# segurado, e os dados do segurado da cotação (nascimento, sexo, CEP, placa e classe de bônus; na empresa segurada,
# nascimento e sexo ficam de fora). Nunca cria outro seguro (não passa pelo gravador único) e nunca sobrescreve.
#
# O telefone e o e-mail do segurado que o leitor acha saem sempre "a confirmar" e só valem depois de uma pessoa
# confirmar (Carteira::Leitor::Resultado). O seguro já guardado não tem onde mostrá-los para confirmar: aqui eles não
# são gravados em lugar nenhum.
#
# Só lê quando tudo isto vale, nesta ordem:
# - o seguro tem PDF, não está cancelado (o seguro cancelado não muda, como no gravador) e tem algo vazio para completar;
# - a leitura de PDF está liberada na conta (Carteira::Leitor::Liberado). Chave desligada: nada lido, nada cobrado,
#   nada marcado, e nada falha;
# - este PDF ainda não foi lido: a marca é o passo `pdf_lido`, depois do último `pdf_anexado` do seguro. Ela é gravada
#   com o seguro travado ANTES da leitura: duas passadas ao mesmo tempo não pagam duas leituras, e a leitura que falha
#   não é tentada de novo.
#
# O passo `pdf_lido` é do sistema (sem nome de pessoa) e leva a busca em `valores.leitura` (o Desfazer da busca devolve o
# que ele completou, como o resto da busca), o que mudou em `mudancas` (de nascimento, sexo e CEP, só que estavam vazios;
# os outros campos como na história do resto do seguro), `valores.lido` quando a leitura terminou e, quando não deu para
# ler, o código da recusa em `valores.recusa`. Um erro depois da marca vira `nao_deu_para_ler` no passo (nunca "nada em
# branco") e não é relido. Nenhum valor lido vai para log.
class Carteira::Conector::LerPdf
  PASSO = 'pdf_lido'.freeze
  NAO_DEU = Carteira::Leitor::Resultado::NAO_DEU
  CAMPOS = %w[tipo valor bem nascimento sexo cep placa bonus].freeze
  DA_PESSOA = %w[nascimento sexo].freeze

  # leitura: a busca no conector que guardou o PDF (ou nil). cliente: troca o cliente do modelo (os specs).
  def initialize(apolice, leitura: nil, cliente: nil)
    @apolice = apolice
    @leitura = leitura
    @cliente = cliente
    campos = apolice.company_id ? CAMPOS - DA_PESSOA : CAMPOS
    @completar = Carteira::Pdf::Completar.new(apolice, campos: campos, ramo: true)
  end

  # -> true quando o PDF foi lido agora.
  def call
    return false unless vale_ler?

    passo = marcar!
    return false unless passo

    ler_e_completar(passo)
    true
  end

  # Este PDF já foi lido: há um passo `pdf_lido` depois do último `pdf_anexado` do seguro. A cotação (DadosDoPdf) também
  # olha aqui, para não pagar de novo a leitura do mesmo PDF.
  def self.lido?(apolice)
    lido = apolice.eventos.where(tipo: PASSO).maximum(:id)
    pdf = apolice.eventos.where(tipo: Carteira::Pdf::ANEXADO).maximum(:id)
    lido.present? && (pdf.nil? || lido > pdf)
  end

  private

  # O erro na leitura ou ao completar vira `nao_deu_para_ler`. O registro do que mudou fica fora do rescue: se ele falhar
  # depois de o seguro mudar, o erro sobe (o job tenta de novo) em vez de o passo dizer que nada mudou.
  def ler_e_completar(passo)
    resultado = Carteira::Leitor::DoSeguro.new(@apolice, cliente: @cliente).call
    mudancas = resultado.lido? ? @completar.call(resultado.campos) : []
  rescue StandardError => e
    Rails.logger.warn("[carteira][conector][pdf_lido] apolice=#{@apolice.id} falhou: #{e.class.name}")
    passo.update!(valores: passo.valores.merge(recusa: NAO_DEU))
  else
    passo.update!(mudancas: mudancas.presence, valores: passo.valores.merge(recusa: resultado.recusa, lido: (true if resultado.lido?)).compact)
  end

  def vale_ler?
    @apolice.pdf.attached? && @apolice.cancelado_em.nil? && @completar.falta? && Carteira::Leitor::Liberado.para?(@apolice.account)
  end

  # O passo da leitura deste PDF, criado uma vez só, com o seguro travado; nil quando ele já foi lido.
  def marcar!
    @apolice.with_lock(requires_new: true) do
      next if self.class.lido?(@apolice)

      @apolice.eventos.create!(tipo: PASSO, quando: Time.current, user: nil, valores: @leitura ? { leitura: @leitura.id } : {})
    end
  end
end
