# O passo "resumir" (#2500 F7): a IA resume a conversa em até `linhas` linhas (padrão 3).
#
# - `destino: nota`: uma nota privada, sem menção.
# - `destino: { avisar: ... }`: o resumo sai pelo passo "avisar" (F4), com as regras dele: só menciona quem vê a
#   conversa, e a lista vazia pula. Quem avisar é conferido antes da IA: ninguém para avisar, o passo pula sem gastar.
#   Pede também a flag da F4 (o executor confere).
#
# O resumo fica também na execução (ComIa#guardar, #2679): um passo seguinte manda "o mesmo resumo" como `ia.<passo>`,
# sem outra ida à IA.
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

  # O ensaio (#2498) só diz para onde o resumo iria: nenhuma IA é chamada.
  def self.ensaiar(passo) = { destino: fala_com_gente?(passo) ? 'avisar' : 'nota' }

  # O que vai à IA: o mesmo na execução e no "Testar este passo" (#2500 C2).
  # A instrução da pessoa (G41, opcional) vem depois do texto fixo, como no "escrever".
  def self.consulta(passo, estado)
    instrucoes = format(INSTRUCOES, linhas: passo['linhas'] || LINHAS)
    instrucoes = "#{instrucoes}\nInstrução: #{passo['instrucao']}" if passo['instrucao'].present?
    { modelo: MODELO, instrucoes: instrucoes, entrada: { conversa: estado.conversa }, schema: SCHEMA }
  end

  def executar
    negado = impedido
    return negado if negado

    aviso = ::Autonomia::Automacao::PassoDeAviso.new(execucao: @execucao, passo: passo_do_aviso, alvo: @conversa) if aviso?
    estado = leitura
    pular = antes_da_ia(aviso, estado)
    return pular if pular

    resposta, custo = perguntar(**self.class.consulta(@passo, estado))
    entregar(aviso, resposta['resumo'].to_s.strip, custo)
  rescue Falha => e
    falhou(e)
  end

  private

  def aviso? = self.class.fala_com_gente?(@passo)

  # O que pula sem pagar a IA: ninguém para avisar, ou nada para ler.
  def antes_da_ia(aviso, estado) = aviso&.ninguem_para_avisar || (nada_para_ler if estado.vazio?)

  def passo_do_aviso = { 'id' => @passo['id'], 'para' => @passo.dig('destino', 'avisar') }

  def entregar(aviso, texto, custo)
    return Resultado.new(tipo: :pulado, motivo: 'texto_vazio', dados: { 'ia' => custo }) if texto.empty?

    guardar(texto)
    resumo = frase(:resumo, texto: texto)
    resultado = aviso ? aviso.avisar(resumo) : Resultado.new(tipo: :ok, dados: { 'nota_id' => nota(resumo).id })
    Resultado.new(tipo: resultado.tipo, motivo: resultado.motivo, dados: resultado.dados.merge('ia' => custo))
  end
end
