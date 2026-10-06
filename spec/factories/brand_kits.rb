FactoryBot.define do
  factory :brand_kit do
    account
    sequence(:name) { |n| "Marca #{n}" }
    appearance do
      {
        palette: { primary: '#ff1f2d', accent: '#0ab9d1', ink: '#111827', muted: '#4b5563',
                   surface: '#ffffff', background: '#f4f6f8', tint: '#ffe4e6' },
        typography: { heading_font: 'MuseoModerno', body_font: 'Roboto' },
        social_links: [{ network: 'linkedin', url: 'https://www.linkedin.com/company/hub2you-insurtech' }],
        footer: { company_name: 'Hub2You', address: 'Av. Paulista, 1000 - São Paulo/SP' }
      }
    end
  end

  factory :brand_import_job do
    account
    url { 'https://hub2you.ai/' }
  end
end
