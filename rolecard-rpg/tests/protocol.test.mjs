import test from 'node:test';
import assert from 'node:assert/strict';
import vm from 'node:vm';
import {readFileSync} from 'node:fs';
import {validateRequest, parseStoryDirective, validateResult} from '../web/protocol.mjs';

const request = {protocol_version:1, request_id:'req-1', task_id:'probe.basic', source:'manual'};
const directive = '<RpgBattle>{"task_id":"probe.basic","event_key":"event-1"}</RpgBattle>';
const message = text => ({role:'assistant', finalized:true, text});

test('both request sources use the same strict contract', () => {
  assert.equal(validateRequest(request).task_id, validateRequest({...request, source:'story'}).task_id);
  assert.throws(() => validateRequest({...request, enemy_hp:0}), /unexpected_request_field/);
  assert.throws(() => validateRequest({...request, task_id:'arbitrary'}), /unknown_task/);
  assert.throws(() => validateRequest({...request, request_id:'<script>'}), /invalid_request_id/);
});
test('only finalized assistant directives are recognized', () => {
  assert.equal(parseStoryDirective(message(`普通剧情\n${directive}`)).event_key, 'event-1');
  assert.throws(() => parseStoryDirective({...message(directive), role:'user'}), /not_final_assistant/);
  assert.throws(() => parseStoryDirective({...message(directive), finalized:false}), /not_final_assistant/);
});
test('quoted examples and fenced directives cannot start a battle', () => {
  for (const text of [`\`\`\`json\n${directive}\n\`\`\``, `~~~\n${directive}\n~~~`, `> ${directive}`, `说明：${directive}`]) {
    assert.throws(() => parseStoryDirective(message(text)), /no_directive/);
  }
  assert.throws(() => parseStoryDirective(message(`\`\`\`\`markdown\n\`\`\`\n${directive}\n\`\`\`\``)), /no_directive/);
});
test('ambiguous and malformed directives are rejected', () => {
  assert.throws(() => parseStoryDirective(message(`${directive}\n${directive}`)), /multiple_directives/);
  assert.throws(() => parseStoryDirective(message('<RpgBattle>{bad}</RpgBattle>')), /invalid_directive_json/);
  assert.throws(() => parseStoryDirective(message('<RpgBattle>{"task_id":"probe.basic","event_key":"e","script":"alert(1)"}</RpgBattle>')), /unexpected_directive_field/);
});
test('result schema binds request and rejects unsupported values', () => {
  const result = {request_id:request.request_id,task_id:request.task_id,source:request.source,
    result_id:'req-1:result',content_version:'technical-fixture-01',outcome:'victory',turns:3,player_hp:4,enemy_hp:0};
  assert.deepEqual(validateResult(result,request),result);
  assert.throws(()=>validateResult({...result,source:'story'},request),/result_mismatch/);
  assert.throws(()=>validateResult({...result,player_hp:Infinity},request),/invalid_result/);
  assert.throws(()=>validateResult({...result,reward:999},request),/unexpected_result_field/);
});
test('v2 result validates actor/form/resource without changing v1 results',()=>{
 const result={request_id:request.request_id,task_id:request.task_id,source:request.source,result_id:'req-1:result',content_version:'technical-fixture-02',outcome:'victory',turns:3,player_hp:4,enemy_hp:0,actor_id:'rin',form_id:'released',energy:20};
 assert.deepEqual(validateResult(result,request),result);
 assert.throws(()=>validateResult({...result,energy:-1},request),/invalid_actor_result/);
 assert.throws(()=>validateResult({...result,actor_id:'injected'},request),/invalid_actor_result/);
 assert.throws(()=>validateResult({...result,content_version:'technical-fixture-01'},request),/unexpected_result_field/);
});
test('transport rejects wrong origin, source, token and unsupported fields', () => {
  const parent = {postMessage() {}};
  const listeners = {};
  const window = {};
  const token = '12345678-1234-1234-1234-123456789abc';
  const context = {window,parent,location:{search:`?parent_origin=http%3A%2F%2F127.0.0.1%3A8765&token=${token}`},
    URLSearchParams,addEventListener:(name,handler)=>listeners[name]=handler};
  vm.runInNewContext(readFileSync(new URL('../web/game-bridge.js', import.meta.url),'utf8'),context);
  const data = {channel:'sigil-rolecard-rpg',version:1,token,type:'start_task',request};
  const event = {source:parent,origin:'http://127.0.0.1:8765',data};
  listeners.message({...event,origin:'https://wrong.example'});
  listeners.message({...event,source:{}});
  listeners.message({...event,data:{...data,token:'wrong'}});
  listeners.message({...event,data:{...data,request:{...request,enemy_hp:0}}});
  assert.deepEqual(JSON.parse(window.rolecardRpgBridge.drain_commands()),[]);
  listeners.message(event);
  assert.equal(JSON.parse(window.rolecardRpgBridge.drain_commands())[0].request.request_id,'req-1');
  assert.deepEqual(JSON.parse(window.rolecardRpgBridge.drain_commands()),[]);
  assert.doesNotThrow(()=>listeners.message({...event,data:{...data,type:'restore_task',checkpoint:{content_version:'__proto__',commands:[],request}}}));
  assert.deepEqual(JSON.parse(window.rolecardRpgBridge.drain_commands()),[]);
});
