# O passo "avisar" (#2414 F4): avisa a equipe, nunca o cliente. Vira uma nota privada na conversa que menciona cada
# pessoa (Nota): o sino, o push e o e-mail são os da menção, pela preferência de cada uma.
#
# Para quem: o responsável da conversa, os times (aberto pessoa a pessoa) e as pessoas escolhidas, só da conta. Fica
# só quem enxerga a conversa (D5), perguntado à política da conversa para cada pessoa: função personalizada e
# administrador mudam a resposta, e não basta estar na caixa. Quem não enxerga sai, e a lista vazia pula o passo com
# motivo. O texto, com os valores, só chega a quem passou. Alvo card (sem conversa) segue a política do card na F6.
class Autonomia::Automacao::PassoDeAviso
  Resultado = ::Autonomia::Automacao::PassoDeAcao::Resultado

  def initialize(execucao:, passo:, valores:, conversa:)
    @execucao = execucao
    @passo = passo
    @valores = valores
    @conversa = conversa
  end

  def executar
    texto = ::Autonomia::Automacao::Texto.new(@passo['texto'], @valores).montar
    return Resultado.new(tipo: :pulado, motivo: 'faltou_valor', dados: {}) if texto.nil?
    return Resultado.new(tipo: :pulado, motivo: 'texto_vazio', dados: {}) if texto.strip.empty?

    pessoas = ::Autonomia::Automacao::Nota.alcancaveis(@conversa, ids)
    return Resultado.new(tipo: :pulado, motivo: 'ninguem_para_avisar', dados: {}) if pessoas.empty?

    nota = ::Autonomia::Automacao::Nota.criar(conversa: @conversa, texto: texto, pessoas: pessoas, marca: marca)
    Resultado.new(tipo: :ok, dados: { 'mensagem_id' => nota.id, 'pessoas' => pessoas.map(&:id) })
  end

  private

  def ids
    para = @passo['para'].to_h
    times = Array(para['times'])
    [
      (@conversa.assignee_id if para['responsavel']),
      *(times.any? ? TeamMember.joins(:team).where(teams: { account_id: @conversa.account_id, id: times }).pluck(:user_id) : []),
      *Array(para['pessoas'])
    ]
  end

  def marca
    { automacao_id: @execucao.automacao_id, execucao_id: @execucao.id, passo: @passo['id'] }
  end
end
