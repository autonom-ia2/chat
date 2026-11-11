import {
  GRUPOS,
  camadaDoDestaque,
  MODELOS,
  emDestaque,
  modeloNaConta,
  modelosDaConta,
  tomDoGrupo,
} from '../modelos';
import pt from '../../../../../i18n/locale/pt_BR/automacaoModelos.json';
import en from '../../../../../i18n/locale/en/automacaoModelos.json';

// #2889 — os 20 modelos prontos: um por exemplo do épico #2414, cada um com texto nos dois idiomas, e o segmento da
// conta trocando ícone, grupo ou IA sem mexer nos outros.
const CORRETORA = ['seguros', 'seguros/corretora'];
const SAUDE = ['seguros', 'seguros/saude_beneficios'];

describe('modelos da porta de Automações', () => {
  it('tem 20 modelos com id único e grupo conhecido', () => {
    const ids = MODELOS.map(m => m.id);
    expect(ids).toHaveLength(20);
    expect(new Set(ids).size).toBe(20);
    const grupos = GRUPOS.map(g => g.id);
    MODELOS.forEach(m => expect(grupos).toContain(m.grupo));
  });

  it('cada modelo tem título e texto em pt_BR e en', () => {
    MODELOS.forEach(({ id }) => {
      [pt, en].forEach(catalogo => {
        const item = catalogo.AUTOMACAO_MODELOS.ITENS[id];
        expect(item?.TITULO, id).toBeTruthy();
        expect(item?.TEXTO, id).toBeTruthy();
      });
    });
  });

  it('a camada do segmento troca só o que declara', () => {
    const m03 = MODELOS.find(m => m.id === 'M03');
    expect(modeloNaConta(m03, [])).toMatchObject({
      ia: true,
      grupo: 'POS_VENDA',
    });
    expect(modeloNaConta(m03, CORRETORA)).toMatchObject({
      ia: false,
      grupo: 'POS_VENDA',
      icone: 'i-lucide-file-badge',
    });
    const m04 = modelosDaConta(SAUDE).find(m => m.id === 'M04');
    expect(m04.grupo).toBe('ATENDIMENTO');
  });

  it('conta sem segmento vê os modelos como estão', () => {
    expect(modelosDaConta([])).toEqual(MODELOS);
  });

  it('o destaque segue a camada mais específica, na ordem declarada', () => {
    const ids = camadas =>
      emDestaque(modelosDaConta(camadas), camadas).map(m => m.id);
    expect(ids([])).toEqual(['M02', 'M10', 'M14', 'M03', 'M06', 'M20']);
    expect(ids(CORRETORA)).toEqual(['M01', 'M04', 'M10', 'M14', 'M12', 'M16']);
    expect(ids(SAUDE)).toEqual(['M01', 'M03', 'M05', 'M08', 'M10', 'M14']);
    // Seguros sem perfil conhecido cai no geral.
    expect(ids(['seguros'])).toEqual(ids([]));
    // Seguradora e insurtech ainda não têm versão própria dos modelos: destaque e título gerais.
    expect(ids(['seguros', 'seguros/seguradora'])).toEqual(ids([]));
    expect(camadaDoDestaque(['seguros', 'seguros/insurtech'])).toBeNull();
    expect(camadaDoDestaque(CORRETORA)).toBe('seguros/corretora');
  });

  it('o tom vem do grupo e grupo desconhecido fica cinza', () => {
    expect(tomDoGrupo('VENDAS')).toBe('azul');
    expect(tomDoGrupo('NADA')).toBe('cinza');
  });
});
