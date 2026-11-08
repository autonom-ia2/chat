# O "para" do avisar e do resumir avisando (#2486) que não vale nesta receita: time ou pessoa que não são da conta, e
# "quem atende a reunião" (G32) fora dos gatilhos de reunião. Saiu da Receita para ela caber no tamanho.
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
      pessoas.map { |pessoa| texto(:pessoa_de_fora, passo: id, id: pessoa) } + da_reuniao_fora(id, para)
  end

  private

  def da_reuniao_fora(id, para)
    return [] if !para['da_reuniao'] || ::Autonomia::Automacao::Gatilhos.de_reuniao?(@tipo_do_gatilho)

    [texto(:da_reuniao_so_no_gatilho, passo: id)]
  end

  def texto(chave, **valores) = I18n.t("autonomia.automacao.receita.#{chave}", **valores)
end
