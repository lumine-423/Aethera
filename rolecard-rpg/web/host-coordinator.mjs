import {validateRequest, validateResult, TASK_ID, commandsByVersion} from './protocol.mjs';

const clone = value => structuredClone(value);
const plain = value => value && typeof value === 'object' && !Array.isArray(value);
const canonical = value => Array.isArray(value) ? value.map(canonical) : plain(value) ? Object.fromEntries(Object.keys(value).sort().map(key => [key,canonical(value[key])])) : value;
const same = (a,b) => JSON.stringify(canonical(a)) === JSON.stringify(canonical(b));
const validId = value => typeof value === 'string' && /^[A-Za-z0-9._:-]{1,96}$/.test(value);
const MAX_REQUESTS = 128;

export function contextKey(context) {
  if (!plain(context) || !['card_id','chat_id','branch_id'].every(key => validId(context[key]))) throw new Error('invalid_context');
  return JSON.stringify([context.card_id,context.chat_id,context.branch_id]);
}

export function validateCheckpoint(value, request) {
  if (!plain(value) || !Object.hasOwn(commandsByVersion,value.content_version) || !same(validateRequest(value.request),request)) throw new Error('checkpoint_mismatch');
  if (!Array.isArray(value.commands) || value.commands.length > 32 || value.commands.some(command => !commandsByVersion[value.content_version].includes(command))) throw new Error('invalid_checkpoint_commands');
  if (!['', 'cancelled'].includes(value.terminal ?? '')) throw new Error('invalid_checkpoint_terminal');
  if (Object.keys(value).some(key => !['request','commands','content_version','terminal'].includes(key))) throw new Error('unexpected_checkpoint_field');
  return clone({request,commands:value.commands,content_version:value.content_version,terminal:value.terminal ?? ''});
}

// One immutable card/chat/branch binding per instance. The real host must supply
// that identity; this module does not guess swipe lineage from a display name.
export class HostCoordinator {
  constructor(store, context, idFactory = () => crypto.randomUUID()) {
    this.store = store;
    this.key = contextKey(context);
    this.context = clone(context);
    this.idFactory = idFactory;
    this.inspect();
  }
  inspect() {
    const saved = this.store.read(this.key);
    if (!saved) return {schema_version:1,revision:0,active_id:null,requests:{},story_bindings:{},results:{}};
    if (saved.schema_version !== 1 || !Number.isSafeInteger(saved.revision) || saved.revision < 0 ||
        !plain(saved.requests) || !plain(saved.results) || !plain(saved.story_bindings)) throw new Error('invalid_journal');
    if (Object.keys(saved.requests).length > MAX_REQUESTS) throw new Error('journal_capacity');
    // Validate all persisted links before exposing any task. Corruption must be
    // visible and recoverable; never silently reset someone else's progress.
    try {
      if (Object.keys(saved).some(key => !['schema_version','revision','active_id','requests','story_bindings','results'].includes(key))) throw new Error();
      const active = [];
      for (const [id, record] of Object.entries(saved.requests)) {
        if (!plain(record) || Object.keys(record).some(key => !['request','checkpoint','status'].includes(key)) ||
            !['active','completed'].includes(record.status)) throw new Error();
        const request = validateRequest(record.request);
        if (request.request_id !== id) throw new Error();
        if (record.checkpoint !== null) validateCheckpoint(record.checkpoint,request);
        if (record.status === 'active') active.push(id);
        else if (!Object.hasOwn(saved.results,id)) throw new Error();
      }
      if (active.length > 1 || (saved.active_id === null ? active.length !== 0 : active.length !== 1 || active[0] !== saved.active_id)) throw new Error();
      for (const [id, result] of Object.entries(saved.results)) {
        const record = saved.requests[id];
        if (!Object.hasOwn(saved.requests,id) || record.status !== 'completed') throw new Error();
        const clean = validateResult(result,record.request);
        if (!record.checkpoint || record.checkpoint.content_version !== clean.content_version || record.checkpoint.commands.length !== clean.turns ||
            ((record.checkpoint.terminal === 'cancelled') !== (clean.outcome === 'cancelled'))) throw new Error();
      }
      for (const [binding,id] of Object.entries(saved.story_bindings)) {
        if (binding.length > 512 || !Object.hasOwn(saved.requests,id) || saved.requests[id].request.source !== 'story') throw new Error();
        const fields = JSON.parse(binding);
        if (!Array.isArray(fields) || fields.length !== 4 || !Number.isInteger(fields[0]) || fields[0] < 0 ||
            !Number.isInteger(fields[1]) || fields[1] < 0 || !validId(fields[2]) || !validId(fields[3])) throw new Error();
      }
    } catch { throw new Error('invalid_journal_links'); }
    return clone(saved);
  }
  #change(updater) {
    const current = this.inspect();
    const next = clone(current);
    const output = updater(next);
    next.revision = current.revision + 1;
    this.store.write(this.key,current.revision,next);
    return output;
  }
  #open(source, binding = null) {
    let response;
    this.#change(document => {
      const existingId = binding ? document.story_bindings[binding] : null;
      if (existingId) {
        const record = document.requests[existingId];
        if (!record) throw new Error('invalid_story_binding');
        response = {request:clone(record.request), duplicate:true, result:clone(document.results[existingId] ?? null)};
        return;
      }
      if (document.active_id) throw new Error('battle_busy');
      if (Object.keys(document.requests).length >= MAX_REQUESTS) throw new Error('journal_capacity');
      const request = validateRequest({protocol_version:1,request_id:this.idFactory(),task_id:TASK_ID,source});
      if (document.requests[request.request_id]) throw new Error('request_id_collision');
      document.requests[request.request_id] = {request,checkpoint:null,status:'active'};
      document.active_id = request.request_id;
      if (binding) document.story_bindings[binding] = request.request_id;
      response = {request:clone(request),duplicate:false,result:null};
    });
    return response;
  }
  openManual() { return this.#open('manual'); }
  openStory(binding) {
    if (!plain(binding) || !Number.isInteger(binding.message_id) || binding.message_id < 0 ||
        !Number.isInteger(binding.swipe_id) || binding.swipe_id < 0 || !validId(binding.content_fingerprint) || !validId(binding.event_key)) throw new Error('invalid_story_binding');
    return this.#open('story',JSON.stringify([binding.message_id,binding.swipe_id,binding.content_fingerprint,binding.event_key]));
  }
  saveCheckpoint(requestId,checkpoint) {
    return this.#change(document => {
      const record = document.requests[requestId];
      if (!record || record.status !== 'active' || document.active_id !== requestId) throw new Error('inactive_checkpoint');
      const clean = validateCheckpoint(checkpoint,record.request);
      const previous = record.checkpoint;
      if (previous && previous.content_version !== clean.content_version) throw new Error('checkpoint_version_change');
      if (previous && (clean.commands.length < previous.commands.length ||
          previous.commands.some((command,index) => clean.commands[index] !== command))) throw new Error('checkpoint_regression');
      if (previous?.terminal && clean.terminal !== previous.terminal) throw new Error('checkpoint_regression');
      record.checkpoint = clean;
      return {saved:true};
    });
  }
  commit(result) {
    return this.#change(document => {
      const record = document.requests[result?.request_id];
      if (!record) throw new Error('unregistered_result');
      const clean = validateResult(result,record.request);
      const previous = document.results[clean.request_id];
      if (previous) {
        if (!same(previous,clean)) throw new Error('result_conflict');
        return {duplicate:true,total:Object.keys(document.results).length};
      }
      if (document.active_id !== clean.request_id) throw new Error('inactive_result');
      if (!record.checkpoint || record.checkpoint.content_version !== clean.content_version || record.checkpoint.commands.length !== clean.turns) throw new Error('result_without_checkpoint');
      if ((record.checkpoint.terminal === 'cancelled') !== (clean.outcome === 'cancelled')) throw new Error('terminal_mismatch');
      document.results[clean.request_id] = clone(clean);
      record.status = 'completed';
      document.active_id = null;
      return {duplicate:false,total:Object.keys(document.results).length};
    });
  }
  resumeCommand() {
    const document = this.inspect();
    if (!document.active_id) return null;
    const record = document.requests[document.active_id];
    if (!record || record.status !== 'active') throw new Error('invalid_active_request');
    return record.checkpoint ? {type:'restore_task',request:record.request,checkpoint:record.checkpoint} : {type:'start_task',request:record.request};
  }
  summary() {
    return Object.values(this.inspect().results).map(result => ({task_id:result.task_id,outcome:result.outcome,turns:result.turns,result_id:result.result_id}));
  }
}

export function createLocalProbeStore(storage) {
  const prefix = 'sigil-rpg-development-journal-v1:';
  return {
    read(key) { const raw = storage.getItem(prefix+key); return raw === null ? null : JSON.parse(raw); },
    write(key,expectedRevision,next) {
      const raw = storage.getItem(prefix+key);
      const current = raw === null ? null : JSON.parse(raw);
      if ((current?.revision ?? 0) !== expectedRevision) throw new Error('stale_revision');
      storage.setItem(prefix+key,JSON.stringify(next));
    },
  };
}

// Dependency-injected adapter for the *verified installed* TH variable surface.
// Not mounted or called against the real card by the local harness.
export function createTavernStore(api,assertCurrentContext) {
  const namespace = 'sigil_rpg_v1';
  const option = {type:'chat'};
  function namespaceOf(variables) {
    const value = variables[namespace];
    if (!value) return {schema_version:1,scopes:{}};
    if (value.schema_version !== 1 || !plain(value.scopes)) throw new Error('unsupported_namespace');
    return value;
  }
  return {
    read(key) { assertCurrentContext(key); return clone(namespaceOf(api.getVariables(option)).scopes[key] ?? null); },
    write(key,expectedRevision,next) {
      assertCurrentContext(key);
      // Synchronous updater: no await between identity/revision validation and merge.
      api.updateVariablesWith(variables => {
        assertCurrentContext(key);
        const owned = clone(namespaceOf(variables));
        if ((owned.scopes[key]?.revision ?? 0) !== expectedRevision) throw new Error('stale_revision');
        owned.scopes[key] = clone(next);
        return {...variables,[namespace]:owned};
      },option);
    },
  };
}
