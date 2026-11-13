# As automações da Automação livre (#2414 F5, D2/D4): ver pede `automation_view`; montar, salvar, ligar e desligar pedem
# `automation_manage`. Sem função personalizada, só o administrador passa (AccountUser#permission_granted?).
# Testar um passo de IA (#2500 C2) chama a IA e paga: pede `automation_manage`, como montar. Os custos só se leem com
# `automation_view`; o valor em dinheiro ainda pede `financial_view`, conferido no controller (#1969).
# No CRM (#2499 F6.3/F6.5): "Automações deste card" pede `automation_view` e "Parar para este card", `automation_manage`
# (o controller confere também a CardPolicy); "Automações desta etapa" pede `automation_view` e a chave de funis, como a
# tela da etapa no "Editar funil".
class Autonomia::Automacao::DefinicaoPolicy < ApplicationPolicy
  def passos? = ver?
  def index? = ver?
  def show? = ver?
  def historico? = ver?
  def ensaio? = ver?
  def ensaio_novo? = ver?
  def create? = gerenciar?
  def update? = gerenciar?
  def ligar? = gerenciar?
  def desligar? = gerenciar?
  def testar_passo? = gerenciar?
  def agentes_de_ia? = gerenciar?
  # #2932/#2934: o que a tela dos passos novos pergunta enquanto monta (a chave de integrações o controller confere).
  def contar_lista? = gerenciar?
  def testar_consulta? = gerenciar?
  def consultas_prontas? = gerenciar?
  def custos? = ver?
  def custos_da_automacao? = ver?
  def do_card? = ver?
  def parar_no_card? = gerenciar?
  def da_etapa? = ver? && ::Autonomia::Automacao::RegraDoFunil.chave?(account_user)

  private

  def ver?
    account_user&.permission_granted?('automation_view') == true
  end

  def gerenciar?
    account_user&.permission_granted?('automation_manage') == true
  end
end
