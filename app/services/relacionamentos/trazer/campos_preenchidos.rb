# "Trazer minha lista" (#2896): anota o que cada linha da lista preencheu, na hora da gravação, para o "Desfazer"
# devolver só isso (Relacionamentos::CampoPreenchido). Roda dentro da transação da linha
# (ContactImports::Trazer::DestinosDaLinha#gravar): a linha que falha e é desfeita leva as anotações junto, e a que é
# gravada de novo anota de novo.
#
# - Da pessoa que a conta já tinha: o nome, o telefone e o e-mail que estavam vazios, cada informação acrescentada, a
#   cidade, a empresa a que a lista a ligou e a marca de cliente (só de quem não era cliente). De cada um vai o resumo
#   com segredo do valor como ficou gravado, nunca o valor.
# - Da pessoa que a lista criou não se anota campo nenhum: o Desfazer a apaga inteira, ou a deixa inteira quando alguém
#   já cuidou dela (Relacionamentos::Trazer::QuemFica). Anota-se o resumo dela inteira, como a linha a deixou
#   (`pessoa_criada`, Relacionamentos::Trazer::PessoaCriada): é por ele que o Desfazer sabe se alguém a editou depois.
#   Quando uma linha de baixo completa a pessoa que uma linha de cima criou, esse resumo é refeito.
# - Na planilha com seguros (E4, #2897), a mesma pessoa vem em várias linhas, e o seguro mais antigo dela pode estar
#   numa linha de baixo: a data de cliente vai para mais cedo (`postos.adiantou`). A marca de cliente que esta lista
#   anotou numa linha de cima passa a ser a da data nova, e o resumo da pessoa que ela criou é refeito. Sem isso o
#   Desfazer acharia que alguém mexeu. De quem já era cliente antes da lista nada é anotado: a data que a lista
#   adiantou nessa pessoa não volta (o valor de antes não é guardado; limite conhecido).
# - O telefone da empresa fica na empresa da linha, que pode ser de outras pessoas: é anotado seja a pessoa da linha
#   nova ou não.
class Relacionamentos::Trazer::CamposPreenchidos
  Campo = Relacionamentos::CampoPreenchido

  def initialize(importacao)
    @importacao = importacao
    @conta_id = importacao.account_id
    @criada = Relacionamentos::Trazer::PessoaCriada.new(importacao)
  end

  # linha: a linha da importação. gravada: CampaignImports::ContactRow::Result. informacoes: o que
  # ContactImports::CustomAttributes#merge! acrescentou, pela chave do atributo. postos:
  # ContactImports::Trazer::DestinosDaLinha::Postos.
  def registrar(linha, gravada, informacoes, postos)
    pessoa_id = gravada.contact.id
    dela = gravada.existing ? da_pessoa(gravada, informacoes, postos) : { Campo::PESSOA_CRIADA => @criada.conteudo(pessoa_id) }
    anotar(linha, pessoa_id, da_empresa(postos).merge(dela), postos)
    adiantar_cliente(pessoa_id, postos.adiantou) if postos.adiantou
    @criada.refazer(pessoa_id) if gravada.existing && (dela.any? || postos.adiantou)
  end

  private

  # A marca de cliente que esta lista anotou na pessoa passa a valer para a data de agora.
  def adiantar_cliente(pessoa_id, desde)
    anotacao = Campo.pendentes.da_importacao(@importacao).find_by(campo: Campo::CLIENTE, contact_id: pessoa_id)
    anotacao&.update!(valor_posto_hash: Campo.resumo(anotacao.campaign_import_row_id, Campo::CLIENTE, Campo.instante(desde)))
  end

  def anotar(linha, pessoa_id, valores, postos)
    return if valores.empty?

    agora = Time.current
    comum = { account_id: @conta_id, campaign_import_row_id: linha.id, contact_id: pessoa_id, created_at: agora, updated_at: agora }
    anotacoes = valores.map do |campo, valor|
      comum.merge(campo: campo, valor_posto_hash: Campo.resumo(linha.id, campo, valor),
                  tipo_anterior: (postos.cliente.tipo_anterior if campo == Campo::CLIENTE))
    end
    Campo.insert_all!(anotacoes) # rubocop:disable Rails/SkipsModelValidations -- uma escrita por linha, dentro da transação dela
  end

  def da_empresa(postos)
    { Campo::TELEFONE_DA_EMPRESA => postos.telefone_da_empresa }.compact
  end

  def da_pessoa(gravada, informacoes, postos)
    contato = gravada.contact
    da_ficha = Array(gravada.filled).to_h { |atributo| [Campo::DA_FICHA.key(atributo.to_s), contato[atributo]] }
    das_informacoes = informacoes.to_h.transform_keys { |chave| Campo.da_informacao(chave) }
    da_ficha.merge(das_informacoes, dos_destinos(gravada, postos))
  end

  def dos_destinos(gravada, postos)
    {
      Campo::CIDADE => postos.cidade,
      Campo::EMPRESA => (gravada.company.company.id if gravada.company&.linked?),
      Campo::CLIENTE => Campo.instante(postos.cliente&.desde)
    }.compact
  end
end
