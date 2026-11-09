# O "para" do avisar e do resumir avisando (#2486) que não vale nesta receita: time ou pessoa que não são da conta.
# "Quem atende a reunião" vale em qualquer gatilho (G61): fora dos de reunião, é a próxima reunião marcada do contato
# (PassoDeAviso#quem_atende). Saiu da Receita para ela caber no tamanho.
class Autonomia::Automacao::DestinatariosDoAviso
  def initialize(conta, tipo_do_gatilho)
    @conta = conta
    @tipo_do_gatilho = tipo_do_gatilho
  end

  # Frases para a pessoa corrigir; vazio = pode salvar.
  def problemas(id, para)
    para = para.to_h
    times = Array(para['times']) - @conta.teams.where(id: para['times']).pluck(:id)
    pessoas = Array(para['pessoas']) - @conta.users.where(id: para['pessoas']).pluck(:id)
    times.map { |time| texto(:time_de_fora, passo: id, id: time) } +
      pessoas.map { |pessoa| texto(:pessoa_de_fora, passo: id, id: pessoa) }
  end

  private

  def texto(chave, **valores) = I18n.t("autonomia.automacao.receita.#{chave}", **valores)
end
