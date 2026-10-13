# A mensagem escrita da conversa aberta (#1335): os campos na sintaxe do catálogo (`{{cliente.primeiro_nome}}`,
# `{{publico.<coluna>}}`), conferidos por estrutura, sem ler linguagem e sem regex.
#
# - Link só por campo (decisão do Rodrigo). Trava só o inequívoco ("://" ou "www." no texto fixo); o "ponto entre
#   letras" da heurística do redator (`Ai::Redacao::Canais::WhatsappTexto.link_inventado?`) só AVISA, porque no texto
#   da pessoa ele erra ("Sr.Paulo", "Ltda.São Paulo") e não pode travar a campanha (Orquestração com o Agendamento).
# - Campo no começo ou no fim vale: texto livre não passa pela análise da Meta.
# - `preencher` devolve nil quando falta o valor de algum campo: a pessoa recebe o modelo, nunca um texto pela metade.
class CampaignJourney::ConversaAberta::Texto
  MAX_CHARS = 1000
  CHAVES_FIXAS = %w[cliente.primeiro_nome cliente.nome minha_empresa.nome minha_empresa.site].freeze

  class << self
    # columns: os cabeçalhos das colunas extras do Público (`campaign_imports.extra_columns`).
    def chaves_permitidas(columns)
      CHAVES_FIXAS + colunas(columns).keys
    end

    # { chave do texto => chave do catálogo }. A chave no texto não tem espaço (`Ai::Redacao::Chaves` recusa
    # `{{publico.Link da oferta}}`): o cabeçalho entra com "_" no lugar dos espaços e volta ao cabeçalho real aqui.
    def colunas(columns)
      Array(columns).to_h do |column|
        [TemplateFields::Catalog.audience_key(column.to_s.split.join('_')), TemplateFields::Catalog.audience_key(column.to_s)]
      end
    end

    # nil quando o texto serve; senão o motivo (símbolo).
    def problema(texto, permitidas:)
      texto = texto.to_s
      return :vazio if texto.strip.empty?
      return :longo if texto.length > MAX_CHARS
      return :malformado if Ai::Redacao::Chaves.malformado?(texto)
      return :chave_fora_da_lista unless (Ai::Redacao::Chaves.extrair(texto) - permitidas).empty?

      :link_digitado if link_inequivoco?(texto)
    end

    # :parece_link quando só a heurística de domínio acusa (a pessoa pode seguir); nil nos outros casos.
    def aviso(texto)
      return if link_inequivoco?(texto)

      :parece_link if Ai::Redacao::Canais::WhatsappTexto.link_inventado?(texto)
    end

    # colunas: o `colunas(columns)` do Público, para achar o cabeçalho real de cada `{{publico.*}}`.
    def preencher(texto, resolver, colunas: {})
      valores = Ai::Redacao::Chaves.extrair(texto).uniq.index_with { |chave| resolver.value(colunas.fetch(chave, chave)).presence }
      return if valores.values.any?(&:nil?)

      Ai::Redacao::Chaves.preencher(texto) { |chave| valores[chave] }
    end

    private

    def link_inequivoco?(texto)
      fixo = Ai::Redacao::Chaves.partes(texto).reject(&:chave?).map(&:valor).join(' ').downcase
      Ai::Redacao::Canais::WhatsappTexto::ENDERECO.any? { |marca| fixo.include?(marca) }
    end
  end
end
