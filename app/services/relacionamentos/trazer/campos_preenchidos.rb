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
# - O telefone da empresa fica na empresa da linha, que pode ser de outras pessoas: é anotado seja a pessoa da linha
#   nova ou não.
class Relacionamentos::Trazer::CamposPreenchidos
  Campo = Relacionamentos::CampoPreenchido

  def initialize(importacao)
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
    @criada.refazer(pessoa_id) if gravada.existing && dela.any?
  end

  private

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
