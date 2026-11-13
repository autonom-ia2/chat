# O que a carteira de seguros soma à aba Pessoas da Lista de Relacionamentos (E4, #2897), só na conta que tem a carteira
# (Carteira::Acesso):
#   - o grupo "Só tem um seguro": a pessoa com exatamente um seguro valendo. Cancelado e vencido não contam, como nos
#     grupos de vencimento da aba Seguros, e o dia de hoje é o da conta;
#   - a busca da lista também acha a pessoa pelo número da apólice e pelo texto do bem segurado. É no bem que a placa
#     aparece hoje; coluna própria de placa só quando houver quem grave.
# Tudo no banco, dentro da consulta que a lista já faz: a carteira não cabe inteira no navegador.
#
# Na conta sem a carteira não soma nada (nem grupo, nem condição, nem consulta a mais): a lista fica como era, e o
# grupo pedido pelo endereço responde 422 como qualquer grupo que não existe.
class Carteira::NaListaDePessoas
  GRUPO = 'so_um_seguro'.freeze
  DA_PESSOA = 'carteira_apolices.contact_id = contacts.id'.freeze
  SO_UM_VALENDO = "(SELECT COUNT(*) FROM carteira_apolices WHERE #{DA_PESSOA} " \
                  "AND carteira_apolices.account_id = contacts.account_id AND #{Carteira::Consulta::VALENDO}) = 1".freeze
  # Onde a busca procura, como na aba Seguros: com letra, no número (como foi escrito e na forma de comparação) e no
  # bem; só com número, nos dígitos do número da apólice.
  TEXTOS = %w[carteira_apolices.numero carteira_apolices.numero_chave carteira_apolices.bem].freeze
  NUMEROS = %w[carteira_apolices.numero].freeze

  def initialize(account)
    @account = account
  end

  # { id do grupo => condição em SQL }, para somar aos grupos da lista.
  def grupos
    ligada? ? { GRUPO => SO_UM_VALENDO } : {}
  end

  # O dia de hoje da conta, que a condição do grupo usa pelo nome (`:hoje`).
  def cortes
    ligada? ? { hoje: Carteira::Selo.hoje(@account) } : {}
  end

  # `achados` é quem a busca da lista já achou dentro de `base`; aqui entra também quem tem um seguro que combina.
  def buscados(achados, base, termo)
    return achados unless ligada? && termo.present?

    achados.or(base.where(seguros_com(termo).arel.exists))
  end

  private

  def ligada?
    return @ligada if defined?(@ligada)

    @ligada = Carteira::Acesso.liberada?(@account)
  end

  # Os seguros da pessoa da linha, nesta conta, que combinam com o que foi digitado.
  def seguros_com(termo)
    da_pessoa = Carteira::Apolice.where(account_id: @account.id).where(DA_PESSOA)
    Relacionamentos::Busca.new(termo).aplicar(da_pessoa, textos: TEXTOS, numeros: NUMEROS)
  end
end
