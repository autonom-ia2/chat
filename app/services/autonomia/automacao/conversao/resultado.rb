# O que uma regra ou automação de etapa antiga vira (#2568, F9). Só leitura: monta a receita proposta e diz o que falta.
#
# - `receita`: a receita do motor novo, com o que já tem equivalente;
# - `faltas`: o que não tem equivalente hoje, cada uma com a chave (Mapa::FALTA) e a fase;
# - `ressalvas`: converte, mas o comportamento muda em algum detalhe que o dono precisa saber (F9.2).
#
# `convertivel?` só é verdadeiro sem falta nenhuma: uma regra pela metade nunca é convertida (F9.2, comportamento igual).
Autonomia::Automacao::Conversao::Resultado = Struct.new(:origem, :id, :ligada, :autor_conhecido, :receita, :faltas,
                                                        :ressalvas, keyword_init: true) do
  def convertivel? = faltas.empty?

  def fases = faltas.map { |falta| falta[:fase] }.uniq

  def to_h
    super.merge(convertivel: convertivel?, fases: fases)
  end
end
