import ptBR from 'dashboard/i18n/locale/pt_BR/funcoesDaEquipe.json';

// #2308, especificação seção 3: uma palavra por coisa. Nenhum texto de FUNCOES_EQUIPE em pt_BR usa o
// vocabulário proibido ("entregue" só vale para conversa, e não casa com "entregar").
const PROIBIDAS = [
  'liberar',
  'entregar',
  'quadros de vendas',
  'cargo',
  'fila',
  'funil',
  'caixa',
  '(crm)',
  'prospecção',
  'participantes',
  'etapas',
  'opcional',
  'se quiser',
];

const textos = valor =>
  typeof valor === 'string' ? [valor] : Object.values(valor).flatMap(textos);

describe('vocabulário de FUNCOES_EQUIPE (pt_BR)', () => {
  it('nenhum texto usa palavra proibida', () => {
    const achados = textos(ptBR.FUNCOES_EQUIPE).flatMap(texto =>
      PROIBIDAS.filter(palavra => texto.toLowerCase().includes(palavra)).map(
        palavra => `${palavra}: ${texto}`
      )
    );

    expect(achados).toEqual([]);
  });

  it('a lista proibida é a da especificação', () => {
    expect(PROIBIDAS).toMatchSnapshot();
  });
});
