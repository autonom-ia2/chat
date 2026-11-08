require 'rails_helper'

# #2083 — quando o pacote do perfil troca um rótulo do painel, o Guia e a Central daquele perfil não podem citar o
# nome antigo: na tela da conta o botão tem o nome novo. Rótulo de uma palavra só conta em negrito ("Vendas" solto é
# palavra comum); rótulo de duas ou mais palavras conta também em texto comum. No Guia o lugar é o fluxo.
# Coincidência com outra coisa (um campo, um menu, uma frase) entra em excecoes, com o motivo. Exceção que não
# acontece mais também falha, para a lista não guardar casos mortos.
# rubocop:disable RSpec/DescribeClass -- é o conteúdo dos pacotes, não uma classe (mesmo padrão de spec/config)
RSpec.describe 'rótulos trocados pelo pacote no Guia e na Central' do
  # rubocop:enable RSpec/DescribeClass
  perfis = %w[corretora saude_beneficios]

  # [perfil, rótulo da base, onde aparece ('guia: <fluxo>' ou id do artigo)] => motivo
  excecoes = {
    ['corretora', 'Quanto custa?', '13.29'] => 'título de pergunta frequente do artigo, não o chip do teste',
    ['saude_beneficios', 'Quanto custa?', '13.29'] => 'título de pergunta frequente do artigo, não o chip do teste',
    ['corretora', 'Nome da empresa', '09.10'] => 'campo company_name do contato, que o pacote não troca',
    ['saude_beneficios', 'Nome da empresa', '09.10'] => 'campo company_name do contato, que o pacote não troca',
    ['corretora', 'Nome da empresa', '09.03'] => 'campo company_name do contato, que o pacote não troca',
    ['saude_beneficios', 'Nome da empresa', '09.03'] => 'campo company_name do contato, que o pacote não troca',
    ['corretora', 'Em conversa', '08.09'] => 'frase "em conversa resolvida", não a etapa do funil',
    ['saude_beneficios', 'Em conversa', '08.09'] => 'frase "em conversa resolvida", não a etapa do funil',
    ['corretora', 'quer comprar', '10.12'] => 'frase "quem já quer comprar", não a ideia do funil',
    ['saude_beneficios', 'quer comprar', '10.12'] => 'frase "quem já quer comprar", não a ideia do funil',
    %w[corretora Vendas 13.20] => 'etapa Vendas do caminho do dinheiro (META_ADS_HUB TITLE_SALES), que o pacote não troca',
    %w[saude_beneficios Vendas 13.20] => 'etapa Vendas do caminho do dinheiro (META_ADS_HUB TITLE_SALES), que o pacote não troca',
    %w[corretora Cards 10.13] => 'contadores de cards do dashboard do CRM, não a aba da ficha do contato',
    %w[corretora Financeiro 01.01] => 'item Financeiro do menu lateral, não a família da Central',
    %w[corretora Financeiro 04.06] => 'perfil de função Financeiro, não a família da Central',
    %w[corretora Financeiro 17.01] => 'item Financeiro do menu lateral, não a família da Central',
    %w[saude_beneficios Plano 10.03] => 'cartão Plano do card (o plano de saúde), não o resumo da assinatura',
    %w[saude_beneficios Plano 10.08] => 'cartão Plano do card (o plano de saúde), não o resumo da assinatura',
    ['saude_beneficios', 'Plano', 'guia: Mover card, marcar como implantado ou que não fechou, resolver, cancelar ou reabrir'] =>
      'cartão Plano do card (o plano de saúde), não o resumo da assinatura',
    ['corretora', 'Novo card', 'guia: Criar um card pela ficha do contato'] =>
      'botão Novo card da ficha do contato, que não é CRM_KANBAN.ACTIONS.NEW_CARD'
  }

  folhas = lambda do |no, caminho = nil, saida = {}|
    no.each do |chave, valor|
      nome = caminho ? "#{caminho}.#{chave}" : chave
      valor.is_a?(Hash) ? folhas.call(valor, nome, saida) : saida[nome] = valor
    end
    saida
  end
  mesclar = ->(a, b) { a.merge(b) { |_, x, y| x.is_a?(Hash) && y.is_a?(Hash) ? mesclar.call(x, y) : y } }
  ler_json = ->(arquivo) { JSON.parse(File.read(arquivo, encoding: 'UTF-8')) }
  plano = ->(texto) { texto.split.join(' ') }

  # Artigo → texto que a conta vê: título e seções, com a camada seguros e a do perfil por cima da base.
  # As seções "Veja também" só listam outros artigos, pelo título deles.
  secoes = lambda do |arquivo|
    texto = File.read(arquivo, encoding: 'UTF-8')
    titulo = texto.lines.find { |linha| linha.start_with?('titulo:') }.to_s.split(':', 2).last.to_s.strip.delete('"')
    corpo = texto.split("\n---\n", 2).last.to_s
    [titulo, "\n#{corpo}".split("\n## ").drop(1).index_by { |secao| secao.lines.first.strip }]
  end

  painel = Rails.root.join('app/javascript/dashboard/i18n')
  base = folhas.call(painel.glob('locale/pt_BR/*.json').sort.reduce({}) { |acc, arquivo| mesclar.call(acc, ler_json.call(arquivo)) })
  seguros = folhas.call(ler_json.call(painel.join('pacotes/seguros/pt_BR.json')))

  perfis.each do |perfil|
    it "#{perfil}: o Guia e a Central não citam o rótulo antigo de um botão que o pacote renomeou" do
      camada = folhas.call(ler_json.call(painel.join("pacotes/seguros/#{perfil}/pt_BR.json")))
      trocados = base.filter_map do |chave, antigo|
        novo = camada[chave] || seguros[chave]
        antigo if novo && antigo.is_a?(String) && antigo != novo && antigo.size.between?(4, 40) && antigo.exclude?('{')
      end.uniq

      guia = Rails.root.join("lib/operator_guide/pacotes/seguros/#{perfil}/guia-produto.md").read
      lugares = guia.split("\n### ").drop(1).to_h { |fluxo| ["guia: #{fluxo.lines.first.strip}", plano.call(fluxo)] }
      Rails.root.glob('lib/central_de_ajuda/[0-9]*/*.md').each do |arquivo|
        id = arquivo.basename.to_s.split('-').first
        titulo, partes = secoes.call(arquivo)
        variantes = [Rails.root.glob("lib/central_de_ajuda_pacotes/seguros/[0-9]*/#{id}-*.md").first,
                     Rails.root.glob("lib/central_de_ajuda_pacotes/seguros/#{perfil}/*/#{id}-*.md").first].compact
        variantes.each do |variante|
          titulo_variante, partes_variante = secoes.call(variante)
          titulo = titulo_variante unless titulo_variante.empty?
          partes = partes.merge(partes_variante)
        end
        lugares[id] = plano.call([titulo, *partes.reject { |nome, _| nome.start_with?('Veja') }.values].join("\n"))
      end

      achados = trocados.flat_map do |rotulo|
        citado = ->(texto) { texto.include?("**#{rotulo}**") || (rotulo.include?(' ') && texto.include?(rotulo)) }
        lugares.filter_map { |lugar, texto| [perfil, rotulo, lugar] if citado.call(texto) }
      end
      esperadas = excecoes.keys.select { |dono, _, _| dono == perfil }

      expect(achados - esperadas).to be_empty, "rótulo antigo (perfil, rótulo, lugar): #{(achados - esperadas).inspect}"
      expect(esperadas - achados).to be_empty, "exceção que não acontece mais, tire de excecoes: #{(esperadas - achados).inspect}"
    end
  end
end
