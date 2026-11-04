# O passo "resumir" (#2500 F7): a IA resume a conversa em até `linhas` linhas (padrão 3).
#
# - `destino: nota`: uma nota privada, sem menção.
# - `destino: { avisar: ... }`: o resumo sai pelo passo "avisar" (F4), com as regras dele: só menciona quem vê a
#   conversa, e a lista vazia pula. Quem avisar é conferido antes da IA: ninguém para avisar, o passo pula sem gastar.
#   Pede também a flag da F4 (o executor confere).
class Autonomia::Automacao::PassoDeResumir
  include ::Autonomia::Automacao::ComIa

  MODELO = ::Crm::Ai::Config::MODEL_SUMMARY
  LINHAS = 3
  INSTRUCOES = <<~TEXTO.freeze
    Resuma a conversa para a equipe de atendimento, em português, em até %<linhas>d linhas curtas. Responda só com JSON no schema.
    Diga o que o cliente quer e em que pé está. Só o que está escrito: nunca invente.
  TEXTO
  SCHEMA = {
    name: 'automacao_resumir',
    schema: { type: 'object', additionalProperties: false, required: %w[resumo], properties: { resumo: { type: 'string' } } }
  }.freeze

  def self.fala_com_gente?(passo) = passo['destino'].is_a?(Hash)

  def executar
    negado = impedido
    return negado if negado

    aviso = ::Autonomia::Automacao::PassoDeAviso.new(execucao: @execucao, passo: passo_do_aviso, alvo: @conversa) if aviso?
    ninguem = aviso&.ninguem_para_avisar
    return ninguem if ninguem

    resposta, custo = perguntar(modelo: MODELO, instrucoes: format(INSTRUCOES, linhas: @passo['linhas'] || LINHAS),
                                entrada: { conversa: leitura.conversa }, schema: SCHEMA)
    entregar(aviso, resposta['resumo'].to_s.strip, custo)
  rescue Falha => e
    falhou(e)
  end

  private

  def aviso? = self.class.fala_com_gente?(@passo)

  def passo_do_aviso = { 'id' => @passo['id'], 'para' => @passo.dig('destino', 'avisar') }

  def entregar(aviso, texto, custo)
    return Resultado.new(tipo: :pulado, motivo: 'texto_vazio', dados: { 'ia' => custo }) if texto.empty?

    resumo = frase(:resumo, texto: texto)
    resultado = aviso ? aviso.avisar(resumo) : Resultado.new(tipo: :ok, dados: { 'nota_id' => nota(resumo).id })
    Resultado.new(tipo: resultado.tipo, motivo: resultado.motivo, dados: resultado.dados.merge('ia' => custo))
  end
end
