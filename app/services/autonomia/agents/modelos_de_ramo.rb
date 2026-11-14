# MODELOS DE AGENTE PRONTOS POR RAMO DE SEGURO (#2881). O modelo pronto é uma camada ACIMA do tipo do agente: ele nasce
# como `sdr` (sem tipo novo e sem migration) e traz o que o ramo já sabe — o roteiro, as perguntas da cotação, os
# documentos, as ferramentas grátis com a frase "Use quando" do ramo e as perguntas de teste.
#
# O conteúdo mora em `config/agentes_por_pacote/seguros/modelos/<chave>.yml` e `<chave>.md` (o roteiro). Cada par é
# conferido na leitura (`Leitor`, `Formato`): arquivo ausente ou fora do formato não derruba o Construtor, o modelo só
# deixa de existir (e fica no log). Um spec garante que os do piloto carregam.
#
# QUEM PODE USAR: conta com o pacote `seguros` (`Autonomia::Segmentos::Pacotes`) E com a flag `agente_modelos_seguro`.
# Fora disso tudo fica como antes: a chave do modelo é ignorada na abertura da conversa, sem erro. A Lia
# (`insurance_quote`) fica de fora de tudo.
#
# ONDE CADA PARTE VIVE:
#   - `Marca`: o que a conversa (`state['modelo_pronto']`) e o agente (`config['modelo_pronto']`) guardam — a chave do
#     modelo e as listas como o dono as deixou;
#   - `Rascunho`: o modelo de uma conversa (roteiro com as listas, ferramentas liberadas, o que a tela recebe);
#   - `Edicao`: o dono muda as listas antes de começar e, só perguntas e documentos, depois (#2976);
#   - `Instrucao`: as listas atuais nas instruções do agente que atende, montadas pelo servidor.
module Autonomia::Agents::ModelosDeRamo
  FLAG = 'agente_modelos_seguro'.freeze
  PASTA = Rails.root.join('config/agentes_por_pacote/seguros/modelos')
  # Com modelo pronto a entrevista do Construtor só pergunta o nome da corretora e com quais seguradoras ela trabalha:
  # o resto já vem no roteiro.
  TETO_DA_ENTREVISTA = 2
  # Limites de uma lista (perguntas, documentos, ferramentas), no arquivo e no que o dono edita.
  ITENS_MAX = 20
  ITEM_MAX = 300
  # As perguntas têm teto próprio (#3020): o ramo traz a lista inteira em blocos, quase toda desligada, e o dono liga
  # o que quer que o agente pergunte.
  PERGUNTAS_MAX = 200
  MAXIMOS = Hash.new(ITENS_MAX).merge('perguntas' => PERGUNTAS_MAX).freeze
  # No roteiro, cada marcador fica sozinho numa linha e é trocado pela lista numerada de mesmo nome.
  MARCADORES = { '{{PERGUNTAS_DA_COTACAO}}' => 'perguntas', '{{DOCUMENTOS}}' => 'documentos' }.freeze
  AGENTE_DE_COTACAO = 'insurance_quote'.freeze

  Ferramenta = Data.define(:fonte, :usar_quando)

  # `molde_das_perguntas`: uma entrada por pergunta, na ordem, já no formato da marca sem o `id`
  # ({ 'texto', 'tirada' } e, no modelo em blocos, 'bloco', 'se' e 'segue'; ver `Perguntas`).
  Modelo = Data.define(:chave, :tipo, :nome_padrao, :ramo, :seguradoras_sugeridas, :molde_das_perguntas, :documentos, :ja_vem,
                       :tambem, :premium, :teste, :roteiro) do
    # Só os textos, na ordem do arquivo (também os das perguntas que vêm desligadas).
    def perguntas
      molde_das_perguntas.pluck('texto')
    end

    # As ferramentas grátis do modelo, na ordem: as do "Já vem com" e depois as do "Também combina".
    def ferramentas
      ja_vem + tambem
    end
  end

  module_function

  # chave => Modelo, lidos uma vez por processo (na primeira pergunta, não no boot: a conferência usa o catálogo das
  # ferramentas prontas).
  def todos
    @todos ||= Leitor.new(PASTA).modelos
  end

  def buscar(chave)
    todos[chave.to_s]
  end

  def chaves
    todos.keys
  end

  def liberado?(account)
    account.present? && account.feature_enabled?(FLAG) &&
      Autonomia::Segmentos::Pacotes.camadas(account).include?(Autonomia::Agents::Nicho::SEGUROS)
  end

  # As chaves que a conta pode usar (a tela de escolha): todas, ou nenhuma.
  def liberados(account)
    liberado?(account) ? chaves : []
  end
end
