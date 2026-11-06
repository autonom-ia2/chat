# O passo "escrever" (#2500 F7): a IA escreve um texto com a instrução de quem montou a automação.
#
# - `destino: mensagem`: o texto sai ao cliente pelo passo "mensagem" (F4), com todas as regras dele: autor
#   "Automação", janela, contato que pediu para não receber, tweet e anti-laço. As conferências que não dependem do texto
#   vêm antes da IA: fora da janela, a execução para sem gastar (#2573). Pede também a flag da F4 (o executor confere).
# - `destino: sugestao`: o texto vira uma nota privada para a equipe revisar e mandar (D5 A).
class Autonomia::Automacao::PassoDeEscrever
  include ::Autonomia::Automacao::ComIa

  MODELO = ::Crm::Ai::Config::MODEL_SUMMARY
  INSTRUCOES = <<~TEXTO.freeze
    Escreva o texto que quem montou a automação pede na instrução, para o cliente desta conversa. Responda só com JSON no schema.
    Escreva no idioma da conversa. Nunca prometa preço, prazo, cobertura, aprovação ou condição que não estejam na instrução, e nunca fale em nome de outra pessoa.
  TEXTO
  SCHEMA = {
    name: 'automacao_escrever',
    schema: { type: 'object', additionalProperties: false, required: %w[texto], properties: { texto: { type: 'string' } } }
  }.freeze

  def self.fala_com_gente?(passo) = passo['destino'] == 'mensagem'

  # O ensaio (#2498) só diz para onde o texto iria: nenhuma IA é chamada.
  def self.ensaiar(passo) = { destino: passo['destino'] }

  # O que vai à IA: o mesmo na execução e no "Testar este passo" (#2500 C2).
  def self.consulta(passo, estado)
    { modelo: MODELO, instrucoes: "#{INSTRUCOES}\nInstrução: #{passo['instrucao']}", entrada: { conversa: estado.conversa }, schema: SCHEMA }
  end

  def executar
    negado = impedido
    return negado if negado

    mensagem = ::Autonomia::Automacao::PassoDeMensagem.new(execucao: @execucao, passo: @passo, alvo: @conversa) if mensagem?
    motivo = mensagem&.motivo_do_canal
    return ::Autonomia::Automacao::PassoDeMensagem.pulado(motivo) if motivo

    estado = leitura
    return nada_para_ler if estado.vazio?

    resposta, custo = perguntar(**self.class.consulta(@passo, estado))
    entregar(mensagem, resposta['texto'].to_s.strip, custo)
  rescue Falha => e
    falhou(e)
  end

  private

  def mensagem? = self.class.fala_com_gente?(@passo)

  def entregar(mensagem, texto, custo)
    return Resultado.new(tipo: :pulado, motivo: 'texto_vazio', dados: { 'ia' => custo }) if texto.empty?

    resultado = mensagem ? mensagem.mandar(texto) : Resultado.new(tipo: :ok, dados: { 'nota_id' => nota(frase(:sugestao, texto: texto)).id })
    Resultado.new(tipo: resultado.tipo, motivo: resultado.motivo, dados: resultado.dados.merge('ia' => custo))
  end
end
