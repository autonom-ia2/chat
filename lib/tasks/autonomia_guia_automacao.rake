# O catálogo de passos da Automação livre, gerado do código (#2414 F5, ADR-001 2.2).
#   bundle exec rails autonomia:guia:automacao         # gera lib/operator_guide/automacao-passos.json
#   bundle exec rails autonomia:guia:automacao:check   # falha se o versionado está fora de dia
namespace :autonomia do
  namespace :guia do
    desc 'Gera lib/operator_guide/automacao-passos.json, o catálogo de passos do editor e do Guia'
    task automacao: :environment do
      Autonomia::Automacao::Catalogo.escrever!
      puts "[guia:automacao] #{Autonomia::Automacao::Catalogo.todos['passos'].size} passos escritos em " \
           "#{Autonomia::Automacao::Catalogo::ARQUIVO.relative_path_from(Rails.root)}"
    end

    namespace :automacao do
      desc 'Falha se o catálogo de passos versionado não bate com o código'
      task check: :environment do
        next puts('[guia:automacao] em dia') unless Autonomia::Automacao::Catalogo.fora_de_dia?

        puts '[guia:automacao] fora de dia: rode `bundle exec rails autonomia:guia:automacao` e envie o resultado'
        exit(1)
      end
    end
  end
end
