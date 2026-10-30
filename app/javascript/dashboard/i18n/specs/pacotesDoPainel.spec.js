import { ref } from 'vue';
import { createI18n } from 'vue-i18n';
import ptBR from '../locale/pt_BR';
import segurosPtBR from '../pacotes/seguros/pt_BR.json';
import saudePtBR from '../pacotes/seguros/saude_beneficios/pt_BR.json';
import { camadasDoPacote, composeMessages } from '../pacotesDoPainel';
import { cardStatusLabel } from '../../routes/dashboard/crm/helpers/cardOutcome';
import { useCardDesfecho } from '../../routes/dashboard/crm/components/card/useCardDesfecho';

const deepFreeze = objeto => {
  Object.values(objeto).forEach(valor => {
    if (valor && typeof valor === 'object') deepFreeze(valor);
  });
  return Object.freeze(objeto);
};

// Caminho "A.B.C" de cada folha de texto.
const folhas = (objeto, prefixo = '') =>
  Object.entries(objeto).flatMap(([chave, valor]) => {
    const caminho = prefixo ? `${prefixo}.${chave}` : chave;
    if (valor && typeof valor === 'object') return folhas(valor, caminho);
    return [[caminho, valor]];
  });

const i18nComPacote = overlays =>
  createI18n({
    legacy: false,
    locale: 'pt_BR',
    fallbackLocale: 'pt_BR',
    messages: { pt_BR: composeMessages(ptBR, overlays) },
  });

describe('camadasDoPacote', () => {
  it.each([
    [null, []],
    [undefined, []],
    ['', []],
    ['seguros', ['seguros']],
    ['seguros.saude_beneficios', ['seguros', 'seguros/saude_beneficios']],
  ])('turns %j into %j', (nome, camadas) => {
    expect(camadasDoPacote(nome)).toEqual(camadas);
  });
});

describe('composeMessages', () => {
  const base = () =>
    deepFreeze({
      CRM: { WON: 'Ganho', LOST: 'Perdido', DEEP: { TITLE: 'Título' } },
      OTHER: 'Outro',
    });

  it('returns the very same base when there is no overlay', () => {
    const catalogo = base();
    expect(composeMessages(catalogo, [])).toBe(catalogo);
    expect(composeMessages(catalogo)).toBe(catalogo);
  });

  it('never changes the base nor the overlay (both frozen)', () => {
    const catalogo = base();
    const pacote = deepFreeze({ CRM: { WON: 'Seguro ativo' } });
    const composto = composeMessages(catalogo, [pacote]);
    expect(composto.CRM.WON).toBe('Seguro ativo');
    expect(catalogo.CRM.WON).toBe('Ganho');
    expect(pacote.CRM.WON).toBe('Seguro ativo');
    // Ramos sem troca continuam sendo os mesmos objetos do base.
    expect(composto.CRM.DEEP).toBe(catalogo.CRM.DEEP);
  });

  it('ignores a key the base does not have', () => {
    const catalogo = base();
    const composto = composeMessages(catalogo, [
      { CRM: { ORFA: 'x' }, NOVA: { A: 'y' } },
    ]);
    expect(composto).toBe(catalogo);
    expect(composto.CRM.ORFA).toBeUndefined();
    expect(composto.NOVA).toBeUndefined();
  });

  it('ignores text where the base has an object, and an object where it has text', () => {
    const catalogo = base();
    const composto = composeMessages(catalogo, [
      { CRM: { DEEP: 'texto', WON: { X: 'objeto' } } },
    ]);
    expect(composto).toBe(catalogo);
  });

  it('lets the most specific layer win, key by key', () => {
    const composto = composeMessages(base(), [
      { CRM: { WON: 'Seguro ativo', LOST: 'Não fechou' } },
      { CRM: { WON: 'Plano ativo' } },
    ]);
    expect(composto.CRM.WON).toBe('Plano ativo');
    expect(composto.CRM.LOST).toBe('Não fechou');
    expect(composto.OTHER).toBe('Outro');
  });

  it('keeps every real pt_BR text the real packs do not change', () => {
    const composto = composeMessages(ptBR, [segurosPtBR, saudePtBR]);
    const trocadas = new Set(
      [...folhas(segurosPtBR), ...folhas(saudePtBR)].map(([caminho]) => caminho)
    );
    const geral = folhas(ptBR);
    const resultado = new Map(folhas(composto));

    expect(resultado.size).toBe(geral.length);
    geral.forEach(([caminho, texto]) => {
      if (!trocadas.has(caminho)) expect(resultado.get(caminho)).toBe(texto);
    });
    expect(resultado.get('CRM_KANBAN.DRAWER.STATUS_WON')).toBe('Implantado');
    expect(resultado.get('CRM_KANBAN.DRAWER.STATUS_LOST')).toBe('Não fechou');
  });
});

// Ordem: nome que a conta deu ao desfecho > pacote > geral.
describe('the account name for the outcome beats the pack', () => {
  const funilComNome = {
    metadata: { outcome_labels: { success: 'Apólice emitida' } },
  };

  it('cardStatusLabel keeps the account name and uses the pack otherwise', () => {
    const { t } = i18nComPacote([segurosPtBR]).global;
    expect(cardStatusLabel(t, 'won', funilComNome)).toBe('Apólice emitida');
    expect(cardStatusLabel(t, 'won', {})).toBe('Seguro ativo');
    expect(cardStatusLabel(t, 'lost', funilComNome)).toBe('Não fechou');
  });

  it('useCardDesfecho keeps the account name and uses the pack otherwise', () => {
    const { t } = i18nComPacote([segurosPtBR]).global;
    const card = ref({ status: 'open' });

    const comNome = useCardDesfecho({ t, card, funil: ref(funilComNome) });
    expect(comNome.rotuloGanhar.value).toBe('Apólice emitida');
    expect(comNome.rotuloPerder.value).toBe('Não fechou');

    const semNome = useCardDesfecho({ t, card, funil: ref({}) });
    expect(semNome.rotuloGanhar.value).toBe('Fechou o seguro');
  });

  it('without a pack the general text stays', () => {
    const { t } = i18nComPacote([]).global;
    expect(cardStatusLabel(t, 'won', {})).toBe('Ganho');
    const semNome = useCardDesfecho({
      t,
      card: ref({ status: 'open' }),
      funil: ref({}),
    });
    expect(semNome.rotuloGanhar.value).toBe('Ganhou');
  });
});
