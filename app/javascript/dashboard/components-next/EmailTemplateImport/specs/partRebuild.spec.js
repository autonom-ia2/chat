import { isRebuilding, rebuildButton, rebuildOf } from '../partRebuild';

const D = 'EMAIL_IMPORT.SCREEN.PART_DIALOG';
const data = (rebuilds, ai) => ({ rebuilds, ai_rebuild: ai });
const on = { available: true, left: 3 };

describe('partRebuild', () => {
  it('reads the state of a part and whether any is running', () => {
    const value = data({ 'trecho-1': { status: 'running' } }, on);
    expect(rebuildOf(value, 'trecho-1')).toEqual({ status: 'running' });
    expect(rebuildOf(value, 'trecho-2')).toBeNull();
    expect(isRebuilding(value)).toBe(true);
    expect(isRebuilding(data({ 'trecho-1': { status: 'done' } }, on))).toBe(
      false
    );
    expect(isRebuilding(null)).toBe(false);
  });

  it('offers the button only when the AI can still rebuild this part', () => {
    expect(rebuildButton(data({}, on), 'trecho-1')).toEqual({
      enabled: true,
      hint: `${D}.REBUILD_HINT`,
    });
    expect(
      rebuildButton(data({ 'trecho-1': { status: 'running' } }, on), 'trecho-1')
    ).toEqual({ enabled: false, hint: `${D}.RUNNING` });
    expect(
      rebuildButton(
        data({ 'trecho-1': { status: 'failed', reason: 'text_mismatch' } }, on),
        'trecho-1'
      )
    ).toEqual({ enabled: false, hint: `${D}.FAILED` });
    expect(
      rebuildButton(data({}, { available: true, left: 0 }), 'trecho-1')
    ).toEqual({ enabled: false, hint: `${D}.USED_UP` });
  });

  it('turns the button off, before any click, for a part the AI cannot rebuild', () => {
    const unfit = { available: true, left: 3, unfit: ['trecho-1'] };
    expect(rebuildButton(data({}, unfit), 'trecho-1')).toEqual({
      enabled: false,
      hint: `${D}.UNFIT`,
    });
    expect(rebuildButton(data({}, unfit), 'trecho-2')).toEqual({
      enabled: true,
      hint: `${D}.REBUILD_HINT`,
    });
  });

  it('keeps the product message when the AI is not configured', () => {
    expect(
      rebuildButton(data({}, { available: false, left: 0 }), 'trecho-1')
    ).toEqual({ enabled: false, hint: `${D}.SOON` });
    expect(rebuildButton({}, 'trecho-1')).toEqual({
      enabled: false,
      hint: `${D}.SOON`,
    });
  });
});
