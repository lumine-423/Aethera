import {WriterLease} from './writer-lease.mjs';
const commands=[];
const enqueue=value=>{if(commands.length<16)commands.push(value);};
const lease=new WriterLease(navigator.locks,state=>enqueue({type:'writer_state',state}));
lease.acquire('local-development-08').catch(()=>{});
addEventListener('pagehide',()=>lease.close(),{once:true});
addEventListener('pageshow',event=>{if(event.persisted)lease.acquire('local-development-08').catch(()=>{});});
window.rolecardPlatform=Object.freeze({
  ready(){if(parent!==window)parent.postMessage({channel:'aethera-player-shell',type:'ready'},location.origin);},
  writer_state(){return lease.state;},
  drain(){return JSON.stringify(commands.splice(0));},
  export_save(raw){
    if(typeof raw!=='string'||raw.length>2000000)return false;
    const url=URL.createObjectURL(new Blob([raw],{type:'application/json;charset=utf-8'}));
    const a=document.createElement('a');a.href=url;a.download='aethera-local-backup.json';a.click();
    setTimeout(()=>URL.revokeObjectURL(url),1000);return true;
  },
  import_save(){
    const input=document.createElement('input');input.type='file';input.accept='.json,application/json';
    input.onchange=async()=>{const file=input.files?.[0];if(!file)return;if(file.size>2000000){enqueue({type:'import_error',message:'备份文件超过2MB'});return;}try{enqueue({type:'import_save',raw:await file.text()});}catch{enqueue({type:'import_error',message:'无法读取备份'});}};
    input.click();
  },
  fullscreen(){const canvas=document.querySelector('canvas');if(document.fullscreenElement)document.exitFullscreen?.();else canvas?.requestFullscreen?.().catch(()=>{});},
});
