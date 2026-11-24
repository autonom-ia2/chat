# Os dados do segurado lidos do PDF que já está no seguro, na hora de cotar a renovação (E8.1, #3043). Os seguros que
# chegam do conector já vêm com o PDF da apólice, que ninguém leu. Quando a Entrada (Carteira::Cotacao::Entrada) diz
# que falta algum dado que a apólice traz (nascimento, sexo, CEP, placa ou classe de bônus), o PDF é lido UMA vez e o
# que ele diz preenche o que está vazio. Quem chama monta a Entrada de novo depois.
#
# Só lê quando tudo isto vale, nesta ordem:
# - falta algum dos cinco na Entrada, e a coluna dele está vazia no seguro (na empresa segurada, nascimento e sexo não
#   contam: o portal pede os do condutor, fora deste escopo);
# - o seguro tem PDF;
# - a leitura de PDF está liberada na conta (Carteira::Leitor::Liberado). Chave desligada: nada lido, nada cobrado;
# - o PDF ainda não foi lido para esta vigência. A marca é o passo `dados_lidos_pdf` da vigência, gravado com o seguro
#   travado ANTES da leitura: duas passadas ao mesmo tempo não pagam duas leituras, e a leitura que falha não é
#   tentada de novo (segue com o que tem: a cotação para em "faltou dado" e a equipe é avisada, como sempre).
#
# O que grava: só as colunas dos cinco que estão vazias, relidas com o seguro travado (o que alguém escreveu no meio
# fica; #3175: o que foi corrigido à mão também). Nunca sobrescreve e nunca toca nas outras colunas do seguro. Só o que
# o leitor deu como certo (`campos`): o que ele deixa "a confirmar" não entra por aqui. A história ganha só o passo da
# leitura, com a vigência: nenhum valor lido.
#
# #3175: o PDF que a busca no conector já leu na chegada (Carteira::Conector::LerPdf) não é lido de novo aqui: a resposta
# seria a mesma, e a leitura seria paga duas vezes.
#
# Nada do PDF vai para log nem para argumento de job: quem chama roda no job da cotação, com o id do seguro.
class Carteira::Cotacao::DadosDoPdf
  PASSO = 'dados_lidos_pdf'.freeze
  # O nome do que falta na Entrada (no formato do adapter) => a coluna do seguro que o PDF pode preencher.
  DA_ENTRADA = {
    'insured.birthDate' => :segurado_nascimento, 'insured.gender' => :segurado_sexo, 'address.zipCode' => :cep,
    'segurado.cep' => :cep, 'vehicle.plate' => :placa, 'quotation.bonusClass' => :bonus_classe, 'renovacao.bonus' => :bonus_classe
  }.freeze
  DA_PESSOA = %i[segurado_nascimento segurado_sexo].freeze

  # cliente: troca o cliente do modelo (os specs); a trava da conta vale do mesmo jeito.
  def initialize(apolice, cliente: nil)
    @apolice = apolice
    @account = apolice.account
    @cliente = cliente
  end

  # faltam: o que a Entrada disse que falta. -> true quando o PDF foi lido agora (vale montar a Entrada de novo).
  def call(faltam)
    return false unless vale_ler?(faltam) && marcar!

    resultado = ler
    gravar(resultado.campos) if resultado.lido?
    true
  end

  private

  def vale_ler?(faltam)
    colunas = do_segurado(Array(faltam).filter_map { |caminho| DA_ENTRADA[caminho.to_s] })
    colunas.any? { |coluna| @apolice[coluna].nil? } && @apolice.pdf.attached? && !Carteira::Conector::LerPdf.lido?(@apolice) &&
      Carteira::Leitor::Liberado.para?(@account)
  end

  # Na empresa segurada, nascimento e sexo ficam de fora.
  def do_segurado(colunas)
    @apolice.company_id ? colunas - DA_PESSOA : colunas
  end

  # A leitura desta vigência, marcada uma vez só, com o seguro travado.
  def marcar!
    @apolice.with_lock(requires_new: true) do
      next false if Carteira::Cotacao.passo(@apolice, PASSO)

      Carteira::Cotacao.registrar(@apolice, PASSO)
      true
    end
  end

  # Só os vazios, relidos com o seguro travado (Carteira::Pdf::Completar). O que foi corrigido à mão fica.
  def gravar(campos)
    colunas = do_segurado(Carteira::DadosDoSegurado::COLUNAS)
    Carteira::Pdf::Completar.new(@apolice, campos: colunas.map { |coluna| Carteira::Campos::COLUNAS.key(coluna) }).call(campos)
  end

  # O PDF do seguro, lido como a leitura de um item (Carteira::Leitor::DoSeguro).
  def ler
    Carteira::Leitor::DoSeguro.new(@apolice, cliente: @cliente).call
  end
end
