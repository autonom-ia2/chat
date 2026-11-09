# O passo "resumir" (#2500 F7): a IA resume a conversa em até `linhas` linhas (padrão 3).
#
# - `destino: nota`: uma nota privada, sem menção.
# - `destino: { avisar: ... }`: o resumo sai pelo passo "avisar" (F4), com as regras dele: só menciona quem vê a
#   conversa, e a lista vazia pula. Quem avisar é conferido antes da IA: ninguém para avisar, o passo pula sem gastar.
#   Pede também a flag da F4 (o executor confere).
#
# O resumo fica também na execução (ComIa#guardar, #2679): um passo seguinte manda "o mesmo resumo" como `ia.<passo>`,
# sem outra ida à IA.
#
# G42 (#2721): lê também o que a própria execução mandou ao cliente (EnviosDaExecucao): o e-mail em conversa própria, o
# modelo recusado (marcado como não entregue) e as respostas nessas conversas, só das que quem ligou vê. A resposta de
# outra conversa só entra se todos que veem a conversa do alvo também a veem, e o resumo que a leu não fica guardado.
#
# G67 (#2844, exemplo 17, passo 6: "o que aconteceu durante as férias"): na execução, as mensagens vão desde o começo
# dela, nunca menos que as 5 de sempre, até MAX_MENSAGENS_DO_PERIODO, as mais recentes; as além das 5 mais recentes vão
# cortadas em MAX_CARACTERES_ANTERIORES. Passou do teto, a IA recebe quantas ficaram de fora (omitted_older_messages) e
# diz que o resumo começa depois delas. O "Testar este passo" não tem execução: lê a janela de sempre.
class Autonomia::Automacao::PassoDeResumir
  include ::Autonomia::Automacao::ComIa

  MODELO = ::Crm::Ai::Config::MODEL_SUMMARY
  LINHAS = 3
  # G67: o teto do período, para a entrada da IA não crescer sem fim numa execução longa (40 mensagens, ~46 mil caracteres).
  MAX_MENSAGENS_DO_PERIODO = 40
  MAX_CARACTERES_ANTERIORES = 600
  INSTRUCOES = <<~TEXTO.freeze
    Resuma a conversa para a equipe de atendimento, em português, em até %<linhas>d linhas curtas. Responda só com JSON no schema.
    Diga o que o cliente quer e em que pé está. Só o que está escrito: nunca invente.
    Em automation_sends estão as mensagens que esta automação mandou ao cliente; com not_delivered, o canal recusou e ela não chegou.
    Com omitted_older_messages, as mensagens mais antigas do período ficaram de fora por tamanho: diga que o resumo começa depois delas.
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
    estado = leitura_da_execucao
    pular = antes_da_ia(aviso, estado)
    return pular if pular

    resposta, custo = perguntar(**self.class.consulta(@passo, estado))
    entregar(aviso, resposta['resumo'].to_s.strip, custo)
  rescue Falha => e
    falhou(e)
  end

  private

  def aviso? = self.class.fala_com_gente?(@passo)

  # G42: a leitura do passo com o que a execução tentou (EnviosDaExecucao).
  def leitura_da_execucao
    @envios = ::Autonomia::Automacao::EnviosDaExecucao.new(execucao: @execucao, conversa: @conversa, leituras: @passo['le'])
    ::Autonomia::Automacao::LeituraDaExecucao.new(leitura, @envios)
  end

  # O que pula sem pagar a IA: ninguém para avisar, ou nada para ler.
  def antes_da_ia(aviso, estado) = aviso&.ninguem_para_avisar || (nada_para_ler if estado.vazio?)

  def passo_do_aviso = { 'id' => @passo['id'], 'para' => @passo.dig('destino', 'avisar') }

  # G67: o período da execução, com o teto.
  def janela
    { periodo: { desde: @execucao.created_at, teto: MAX_MENSAGENS_DO_PERIODO }, max_caracteres_anteriores: MAX_CARACTERES_ANTERIORES }
  end

  def entregar(aviso, texto, custo)
    return Resultado.new(tipo: :pulado, motivo: 'texto_vazio', dados: { 'ia' => custo }) if texto.empty?

    guardar(texto) unless @envios.outras_lidas?
    resumo = frase(:resumo, texto: texto)
    resultado = aviso ? aviso.avisar(resumo) : Resultado.new(tipo: :ok, dados: { 'nota_id' => nota(resumo).id })
    fora = { 'conversas_fora' => @envios.fora.presence }.compact
    Resultado.new(tipo: resultado.tipo, motivo: resultado.motivo, dados: resultado.dados.merge('ia' => custo, **fora))
  end
end
