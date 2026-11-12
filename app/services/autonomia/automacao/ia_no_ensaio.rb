# Um passo de IA no ensaio (Ensaio, #2500 F7): o que a IA faria, só com o que a receita diz, e quantos anexos leria
# (G20). Nenhuma IA é chamada e nada é baixado. Devolve [faria, dados], como os outros `ensaiar`.
# - O passo que manda mensagem ou aviso (regras da F4) sem a mensagem automática ligada na conta não sairia, como no
#   motor; no card sem conversa, pula (ComIa#impedido, #2631).
# - O "escrever" ao cliente confere o canal antes da IA (#2609, EnvioNoEnsaio#do_canal). O resumo que sai pelo "avisar"
#   segue as regras dele (#2552, PassoDeAviso.ensaiar).
class Autonomia::Automacao::IaNoEnsaio
  # `conversa`: a do alvo, a que o "mensagem" abriria no card sem conversa (ainda não gravada) ou nil.
  def initialize(conta:, conversa:, envio:)
    @conta = conta
    @conversa = conversa
    @envio = envio
  end

  def ensaiar(passo, valores)
    classe = ::Autonomia::Automacao::IaNoExecutor::IA.fetch(passo['tipo'])
    return ['mensagens_desligadas'] if classe.fala_com_gente?(passo) && !::Autonomia::Automacao::Motor.mensagens?(@conta)
    return ['sem_conversa'] if @conversa.nil?

    fora = canal(passo, classe, valores)
    return fora if fora

    ninguem, reserva = ::Autonomia::Automacao::PassoDeAviso.ensaiar(passo, @conversa)
    return [ninguem] if ninguem

    ["ia_#{passo['tipo']}", classe.ensaiar(passo).merge(anexos(passo, classe), { reserva: reserva }.compact)]
  end

  # G20: com `le: anexos`, quantos anexos desta conversa a IA leria, ou o motivo de o passo pular, como o motor. A
  # conversa que o "mensagem" abriria ainda não tem anexo.
  def anexos(passo, classe)
    return {} unless ::Autonomia::Automacao::AnexosDaConversa.le?(passo)
    return { anexos: 0 } if @conversa.new_record?

    lidos = ::Autonomia::Automacao::AnexosDaConversa.new(@conversa)
    motivo = lidos.motivo(modelo: classe::MODELO)
    motivo ? { anexos_motivo: motivo } : { anexos: lidos.quantos }
  end

  private

  def canal(passo, classe, valores)
    @envio.do_canal(passo, valores, modelo: nil) if passo['tipo'] == 'escrever' && classe.fala_com_gente?(passo)
  end
end
