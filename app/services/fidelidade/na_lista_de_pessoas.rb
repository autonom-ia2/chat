# O filtro `fidelidade` da aba Pessoas da Lista de Relacionamentos (#3100), para o "Ver quem está perto do prêmio" do
# painel da Fidelidade. Lê o saldo pronto (Fidelidade::Saldo) dentro da consulta que a lista já faz:
#   - `perto`: falta até 20% da meta, sem ter completado (Fidelidade::Programa#perto_a_partir, a régua do painel);
#   - `completo`: já juntou a meta e pode receber o prêmio.
# Sem cartão na conta, o filtro não acha ninguém.
class Fidelidade::NaListaDePessoas
  VALORES = %w[perto completo].freeze
  NO_SALDO = 'contacts.id IN (SELECT fidelidade_saldos.contact_id FROM fidelidade_saldos ' \
             'WHERE fidelidade_saldos.programa_id = ? AND fidelidade_saldos.saldo >= ? AND fidelidade_saldos.saldo < ?)'.freeze
  NINGUEM = 'FALSE'.freeze
  # "Completo" não tem teto: o maior saldo que a coluna guarda.
  SEM_TETO = (2**31) - 1

  def initialize(account)
    @account = account
  end

  def motivo_invalido(valor)
    "fidelidade desconhecido: #{valor}" unless valor.nil? || VALORES.include?(valor)
  end

  # A condição do filtro para o `where` da lista; nil sem filtro.
  def condicao(valor)
    return if valor.nil?

    programa = Fidelidade::Programa.da_conta(@account)
    return NINGUEM unless programa

    de, ate = valor == 'perto' ? [programa.perto_a_partir, programa.meta] : [programa.meta, SEM_TETO]
    [NO_SALDO, programa.id, de, ate]
  end
end
