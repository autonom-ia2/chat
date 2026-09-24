# O Guia LENDO a Central de Ajuda, pela permissão de quem pergunta (issue #617).
#
# Antes disto o Guia só respondia pelo manual interno (`guia-produto.md`), que
# fala PARA quem opera a plataforma — cheio de nome de rota e de campo. A
# Central de Ajuda é o texto que a própria pessoa lê na tela, passo a passo, na
# língua da tela. Para "como faço X", ela é a fonte melhor: quem já escreveu o
# procedimento foi quem escreveu o artigo, e não vale reescrever aqui.
#
# Devolve o corpo do artigo para o modelo RESUMIR, não para ele repassar
# inteiro: a instrução do Guia pede poucas linhas, e o botão "ler o artigo
# completo" existe para quem quer o texto todo (#590, `mostrar_tela` guarda o
# mesmo tipo de estado; este guarda o artigo lido, do mesmo jeito).
class Autonomia::Agents::Tools::Native::GuiaCentral < Autonomia::Agents::Tools::Native::Base
  # Mesmo raciocínio do `GuiaLeitura::TETO`: abaixo do teto de saída da
  # ferramenta (`Tools::Bound::MAX_OUTPUT_CHARS`, 8.000), porque estourá-lo
  # corta no meio sem aviso nenhum chegar ao modelo.
  TETO = 6_000
  AVISO_DE_CORTE = ' […cortado por tamanho: o artigo continua na tela — use o botão que abre o artigo completo.]'.freeze

  class << self
    def slug
      'ler_da_central'
    end

    def description
      'Lê um artigo da Central de Ajuda — o passo a passo que a própria pessoa leria na tela. Use ' \
        'quando a pergunta for "como eu faço X": procure primeiro aqui, antes de responder pelo que ' \
        'você já sabe. Informe "ref" quando já souber qual artigo (de uma busca anterior ou dos ' \
        'fluxos que você recebeu); informe "termo" para buscar pelo que a pessoa perguntou. A busca ' \
        'por termo devolve a LISTA de resultados e o corpo do primeiro, só para você ler rápido — ' \
        'ele nem sempre é o artigo certo. Depois de buscar, chame de novo com o "ref" do artigo da ' \
        'lista que responde aquela parte da pergunta: só essa chamada por "ref" vira o link "Ler o ' \
        'artigo" que a pessoa vê.'
    end

    def params
      [
        { 'name' => 'termo', 'type' => 'string', 'required' => false,
          'description' => 'Palavras para buscar, como a pessoa perguntaria (ex.: "como conecto o ' \
                           'whatsapp"). Use quando não tiver a referência exata do artigo.' },
        { 'name' => 'ref', 'type' => 'string', 'required' => false,
          'description' => 'A referência do artigo, quando você já sabe qual é (ex.: "02.04" ou ' \
                           '"02-04"), vinda de uma busca anterior ou dos fluxos que você recebeu.' }
      ]
    end
  end

  def call
    return recusa_sem_contexto if @operador.nil?

    ref = @params['ref'].to_s.strip
    return por_ref(ref) if ref.present?

    termo = @params['termo'].to_s.strip
    return por_termo(termo) if termo.present?

    'Preciso de um termo de busca ou de uma referência de artigo para consultar a Central de Ajuda.'
  end

  private

  def leitura
    @leitura ||= ::Autonomia::CentralDeAjuda::Leitura.new(account: @operador.account, account_user: @operador.account_user)
  end

  # Só a leitura por REF regista o artigo no contexto (o que vira o link "Ler o
  # artigo" na tela, #617, #636). É a única chamada em que o modelo escolheu o
  # artigo — pela ref de uma busca anterior ou dos fluxos que recebeu.
  def por_ref(ref)
    artigo = leitura.artigo(ref)
    return "Não encontrei nenhum artigo da Central de Ajuda com a referência \"#{ref}\"." if artigo.nil?

    registrar(artigo)
    formatar(artigo)
  end

  # A busca por termo NÃO registra nada (medido na bateria real de 24/09/2026:
  # "criar etiqueta" trazia como primeiro resultado "Criar e editar uma Macro",
  # e esse virava o link errado). Ela só mostra a lista e o corpo do primeiro
  # PARA O MODELO LER — quem escolhe o artigo certo da lista é o modelo,
  # chamando de novo com `ref`.
  def por_termo(termo)
    resumos = leitura.buscar(termo)
    return "Não encontrei nada na Central de Ajuda para \"#{termo}\". Responda pelo que você já sabe." if resumos.empty?

    primeiro = leitura.artigo(resumos.first[:ref])
    [formatar_lista(resumos), primeiro && formatar(primeiro)].compact.join("\n\n")
  end

  def formatar_lista(resumos)
    linhas = resumos.map { |r| "- #{r[:ref]} #{r[:titulo]} — #{r[:descricao]}" }
    "Resultados na Central de Ajuda:\n#{linhas.join("\n")}"
  end

  def registrar(artigo)
    resumo = leitura.resumo(artigo)
    @operador.artigo_lido(ref: resumo[:ref], titulo: resumo[:titulo])
  end

  # Só formata e corta pelo teto — não registra nada (ver `registrar`).
  def formatar(artigo)
    resumo = leitura.resumo(artigo)
    cabendo("Artigo #{resumo[:ref]} — #{resumo[:titulo]}\n\n#{artigo.content}")
  end

  def cabendo(texto)
    return texto if texto.length <= TETO

    "#{texto[0, TETO - AVISO_DE_CORTE.length]}#{AVISO_DE_CORTE}"
  end

  # Sem saber a CONTA não há como filtrar o que a Central mostra (papel e
  # recursos ligados): acontece no Testar e no playground, sem ninguém logado.
  def recusa_sem_contexto
    'Não consigo consultar a Central de Ajuda agora porque não sei qual é a conta. Responda pelo que você já sabe.'
  end
end
