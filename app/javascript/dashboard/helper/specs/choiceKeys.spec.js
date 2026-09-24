import {
  choiceKeyAction,
  foldForTypeahead,
  sameChoice,
  typeaheadIndex,
} from '../choiceKeys';

const base = { open: false, active: -1, selected: 2, count: 5 };

describe('choiceKeyAction', () => {
  it('abre na opção selecionada com seta, Enter ou espaço', () => {
    ['ArrowDown', 'ArrowUp', 'Enter', ' '].forEach(key => {
      expect(choiceKeyAction({ ...base, key })).toEqual({
        type: 'open',
        active: 2,
      });
    });
  });

  it('abre no começo ou no fim com Home e End', () => {
    expect(choiceKeyAction({ ...base, key: 'Home' })).toEqual({
      type: 'open',
      active: 0,
    });
    expect(choiceKeyAction({ ...base, key: 'End' })).toEqual({
      type: 'open',
      active: 4,
    });
  });

  it('anda pela lista aberta sem passar das pontas', () => {
    const open = { ...base, open: true, active: 4 };
    expect(choiceKeyAction({ ...open, key: 'ArrowDown' })).toEqual({
      type: 'move',
      active: 4,
    });
    expect(choiceKeyAction({ ...open, key: 'ArrowUp' })).toEqual({
      type: 'move',
      active: 3,
    });
    expect(choiceKeyAction({ ...open, active: 0, key: 'PageUp' })).toEqual({
      type: 'move',
      active: 0,
    });
  });

  it('confirma com Enter, espaço e Alt+seta para cima; Tab confirma sem prender o foco', () => {
    const open = { ...base, open: true, active: 1 };
    expect(choiceKeyAction({ ...open, key: 'Enter' })).toEqual({
      type: 'commit',
      active: 1,
      keepDefault: false,
    });
    expect(choiceKeyAction({ ...open, key: 'ArrowUp', altKey: true })).toEqual({
      type: 'commit',
      active: 1,
      keepDefault: false,
    });
    expect(choiceKeyAction({ ...open, key: 'Tab' })).toEqual({
      type: 'commit',
      active: 1,
      keepDefault: true,
    });
  });

  it('fecha com Escape e ignora lista vazia', () => {
    expect(choiceKeyAction({ ...base, open: true, key: 'Escape' })).toEqual({
      type: 'close',
    });
    expect(choiceKeyAction({ ...base, count: 0, key: 'ArrowDown' })).toEqual({
      type: 'none',
    });
  });
});

describe('typeahead', () => {
  const labels = ['Menor', 'Pequeno', 'Padrão', 'Grande', 'Maior', 'Español'];

  it('ignora acento e maiúscula', () => {
    expect(foldForTypeahead('Padrão Ç')).toBe('padrao c');
    expect(typeaheadIndex(labels, 'espa', -1)).toBe(5);
  });

  it('acha pelo começo do rótulo a partir da opção seguinte', () => {
    expect(typeaheadIndex(labels, 'pad', 0)).toBe(2);
    expect(typeaheadIndex(labels, 'm', 0)).toBe(4);
  });

  it('a mesma letra repetida alterna entre as opções', () => {
    expect(typeaheadIndex(labels, 'pp', 1)).toBe(2);
    expect(typeaheadIndex(labels, 'pp', 2)).toBe(1);
  });

  it('devolve -1 quando nada começa com o texto', () => {
    expect(typeaheadIndex(labels, 'xyz', 0)).toBe(-1);
  });
});

describe('choiceKeyAction com opções desabilitadas', () => {
  const disabled = [false, true, false, true, false];
  const open = { open: true, selected: 0, count: 5, disabled };

  it('pula as desabilitadas ao andar pela lista', () => {
    expect(choiceKeyAction({ ...open, active: 0, key: 'ArrowDown' })).toEqual({
      type: 'move',
      active: 2,
    });
    expect(choiceKeyAction({ ...open, active: 4, key: 'ArrowUp' })).toEqual({
      type: 'move',
      active: 2,
    });
  });

  it('fica onde está quando não há habilitada naquela direção', () => {
    const lastEnabled = [false, false, true, true, true];
    expect(
      choiceKeyAction({
        ...open,
        disabled: lastEnabled,
        active: 1,
        key: 'ArrowDown',
      })
    ).toEqual({ type: 'move', active: 1 });
  });

  it('Home, End e página caem na habilitada mais próxima', () => {
    const edges = [true, false, false, false, true];
    expect(
      choiceKeyAction({ ...open, disabled: edges, active: 2, key: 'Home' })
    ).toEqual({ type: 'move', active: 1 });
    expect(
      choiceKeyAction({ ...open, disabled: edges, active: 2, key: 'End' })
    ).toEqual({ type: 'move', active: 3 });
    expect(
      choiceKeyAction({ ...open, disabled: edges, active: 2, key: 'PageDown' })
    ).toEqual({ type: 'move', active: 3 });
  });

  it('abre na primeira habilitada quando nada está escolhido', () => {
    expect(
      choiceKeyAction({
        open: false,
        active: -1,
        selected: -1,
        count: 3,
        disabled: [true, false, false],
        key: 'ArrowDown',
      })
    ).toEqual({ type: 'open', active: 1 });
  });
});

describe('sameChoice', () => {
  it('compara como o v-model do select nativo', () => {
    expect(sameChoice(5, '5')).toBe(true);
    expect(sameChoice(true, 'true')).toBe(true);
    expect(sameChoice('a', 'a')).toBe(true);
    expect(sameChoice(null, null)).toBe(true);
    expect(sameChoice(null, '')).toBe(false);
    expect(sameChoice(undefined, '')).toBe(false);
    expect(sameChoice(0, '')).toBe(false);
    expect(sameChoice(false, 0)).toBe(false);
  });
});
