# frozen_string_literal: true

# Gera o SQL, somente leitura, que conta em quantas contas ativas cada feature flag está ligada.
# Usado pela Orquestração na conferência do "ok, SHA" (docs/processo-de-release.md) e no
# levantamento de docs/liberacoes-por-conta.md.
#
#   ruby .github/scripts/feature_flags_por_conta.rb                    # todas as flags
#   ruby .github/scripts/feature_flags_por_conta.rb meta_ads_hub crm   # só as citadas
#
# O bit de cada flag segue app/models/concerns/featurable.rb: as flags são agrupadas pela coluna
# (`column` no features.yml, padrão `feature_flags`) e a n-ésima flag da coluna ocupa o bit n-1.
# Rodar sempre pelo psql da instância (regra: produção só por psql, nunca rails runner).

require 'yaml'

DEFAULT_COLUMN = 'feature_flags'
FEATURES_PATH = File.expand_path('../../config/features.yml', __dir__)

# Mesmo critério de featurable.rb (`feature['column'].presence || DEFAULT`), sem ActiveSupport.
def column_of(feature)
  column = feature['column'].to_s.strip
  column.empty? ? DEFAULT_COLUMN : column
end

def flag_rows(features)
  features.group_by { |feature| column_of(feature) }.flat_map do |column, list|
    list.each_with_index.map { |feature, index| [feature['name'], column, index] }
  end
end

def selected_rows(rows, names)
  return rows if names.empty?

  unknown = names - rows.map(&:first)
  abort "Flag desconhecida em config/features.yml: #{unknown.join(', ')}" if unknown.any?

  rows.select { |name, _column, _index| names.include?(name) }
end

def sql_for(rows)
  values = rows.map { |name, column, index| "('#{name}', '#{column}', #{index})" }.join(",\n  ")
  enabled = "((CASE f.col WHEN 'feature_flags' THEN a.feature_flags ELSE a.feature_flags_ext_1 END) & (1::bigint << f.idx)) <> 0"

  <<~PSQL
    \\pset format csv
    BEGIN READ ONLY;
    WITH f(name, col, idx) AS (VALUES
      #{values}),
    a AS (SELECT id, feature_flags, feature_flags_ext_1 FROM accounts WHERE status = 0)
    SELECT f.name,
           count(*) FILTER (WHERE #{enabled}) AS ligadas,
           count(*) AS ativas,
           string_agg(a.id::text, ' ' ORDER BY a.id) FILTER (WHERE #{enabled}) AS contas_ligadas
    FROM f CROSS JOIN a
    GROUP BY f.name
    ORDER BY f.name;
    ROLLBACK;
  PSQL
end

puts sql_for(selected_rows(flag_rows(YAML.safe_load(File.read(FEATURES_PATH))), ARGV))
