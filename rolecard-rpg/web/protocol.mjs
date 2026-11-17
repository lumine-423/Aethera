export const PROTOCOL_VERSION = 1;
export const CHANNEL = 'sigil-rolecard-rpg';
export const TASK_ID = 'probe.basic';
const idPattern = /^[A-Za-z0-9._:-]{1,96}$/;
export const commandsByVersion = Object.freeze({
  'technical-fixture-01': Object.freeze(['attack','guard']),
  'technical-fixture-02': Object.freeze(['attack','guard','liberate','ultimate']),
});

export function validateRequest(value) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) throw new Error('invalid_request');
  if (value.protocol_version !== PROTOCOL_VERSION) throw new Error('unsupported_protocol');
  if (value.task_id !== TASK_ID) throw new Error('unknown_task');
  if (!['manual', 'story'].includes(value.source)) throw new Error('invalid_source');
  if (typeof value.request_id !== 'string' || !idPattern.test(value.request_id)) throw new Error('invalid_request_id');
  if (Object.keys(value).some(key => !['protocol_version', 'task_id', 'source', 'request_id'].includes(key))) {
    throw new Error('unexpected_request_field');
  }
  return {protocol_version: 1, request_id: value.request_id, task_id: TASK_ID, source: value.source};
}

// Prototype protocol: only a finalized assistant message, a whole-line directive,
// outside fenced code, with allowlisted declarative data. No eval or HTML execution.
export function parseStoryDirective(message) {
  if (message?.role !== 'assistant' || message.finalized !== true || typeof message.text !== 'string') {
    throw new Error('not_final_assistant_message');
  }
  if (message.text.length > 100000) throw new Error('message_too_large');
  let fence = null;
  const candidates = [];
  for (const line of message.text.split(/\r?\n/)) {
    const delimiter = line.match(/^\s*(```+|~~~+)(.*)$/);
    if (delimiter) {
      const kind = delimiter[1][0];
      const length = delimiter[1].length;
      if (fence && fence.kind === kind && length >= fence.length && !delimiter[2].trim()) fence = null;
      else if (!fence) fence = {kind,length};
      continue;
    }
    if (fence) continue;
    const match = line.match(/^<RpgBattle>(.{1,1024})<\/RpgBattle>$/);
    if (match) candidates.push(match[1]);
  }
  if (candidates.length !== 1) throw new Error(candidates.length ? 'multiple_directives' : 'no_directive');
  let directive;
  try { directive = JSON.parse(candidates[0]); } catch { throw new Error('invalid_directive_json'); }
  if (!directive || Array.isArray(directive) || typeof directive !== 'object') throw new Error('invalid_directive');
  if (directive.task_id !== TASK_ID) throw new Error('unknown_task');
  if (typeof directive.event_key !== 'string' || !idPattern.test(directive.event_key)) throw new Error('invalid_event_key');
  if (Object.keys(directive).some(key => !['task_id', 'event_key'].includes(key))) throw new Error('unexpected_directive_field');
  return {task_id: TASK_ID, event_key: directive.event_key};
}

export function validateResult(result, request) {
    if (!result || typeof result !== 'object' || Array.isArray(result)) throw new Error('invalid_result');
    if (result.result_id !== `${request.request_id}:result` || result.task_id !== request.task_id || result.source !== request.source) {
      throw new Error('result_mismatch');
    }
    if (result.request_id !== request.request_id || !Object.hasOwn(commandsByVersion,result.content_version) ||
        !['victory', 'defeat', 'cancelled'].includes(result.outcome) || !Number.isInteger(result.turns) || result.turns < 0 || result.turns > 32 ||
        !Number.isInteger(result.player_hp) || result.player_hp < 0 || result.player_hp > 10 ||
        !Number.isInteger(result.enemy_hp) || result.enemy_hp < 0 || result.enemy_hp > 9) {
      throw new Error('invalid_result');
    }
    const modern = result.content_version === 'technical-fixture-02';
    if (modern && (result.actor_id !== 'rin' || !['base','released'].includes(result.form_id) || !Number.isInteger(result.energy) || result.energy < 0 || result.energy > 100)) throw new Error('invalid_actor_result');
    const keys = ['request_id','result_id','task_id','source','content_version','outcome','turns','player_hp','enemy_hp',...(modern ? ['actor_id','form_id','energy'] : [])];
    if (Object.keys(result).some(key => !keys.includes(key))) {
      throw new Error('unexpected_result_field');
    }
    return structuredClone(result);
}
