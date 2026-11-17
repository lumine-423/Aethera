const frame=document.querySelector('iframe'),status=document.querySelector('#boot-status'),retry=document.querySelector('#retry');
let ready=false;
frame.addEventListener('load',()=>{status.textContent='正在启动游戏…';});
addEventListener('message',event=>{
  if(event.source!==frame.contentWindow||event.origin!==location.origin||event.data?.channel!=='aethera-player-shell')return;
  if(event.data.type==='ready'){ready=true;document.querySelector('#boot').hidden=true;}
  if(event.data.type==='error'){status.textContent='游戏启动失败，请重试。已有记录会保留。';retry.hidden=false;}
});
setTimeout(()=>{if(!ready){status.textContent='加载时间较长，请检查连接或重试。已有记录会保留。';retry.hidden=false;}},25000);
retry.onclick=()=>location.reload();
