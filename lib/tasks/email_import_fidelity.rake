# Suíte de fidelidade do importador de modelos de e-mail (#1099, entrega D): escreve, para cada modelo de
# spec/fixtures/email_imports, a página do original limpo e a do importado (imagens em cinza, nada vindo da rede), mais o
# manifest.json com a área editável de cada um. As fotos e a diferença por faixa ficam com
# scripts/email-import-fidelity/shoot.mjs, que lê esta pasta e escreve report.md e report.json.
#
#   bundle exec rails "autonomia:email_import:fidelidade[tmp/email-import-fidelity]"
#   node scripts/email-import-fidelity/shoot.mjs tmp/email-import-fidelity
namespace :autonomia do
  namespace :email_import do
    desc 'Escreve as páginas (original limpo e importado) da suíte de fidelidade do importador de e-mail'
    task :fidelidade, [:out_dir] => :environment do |_task, args|
      out_dir = Rails.root.join(args[:out_dir].presence || 'tmp/email-import-fidelity')
      manifest = EmailImportFidelity::Pages.call(out_dir)
      manifest[:fixtures].each do |entry|
        ratio = entry[:editable_area_ratio] ? format('%.1f%%', entry[:editable_area_ratio] * 100) : entry[:error]
        puts "#{entry[:name].ljust(28)} área editável #{ratio}#{' (abaixo da meta)' if entry[:goal_met] == false}"
      end
      puts "Páginas em #{out_dir}"
    end
  end
end
