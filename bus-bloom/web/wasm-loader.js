// Export packaging replaces the manifest. Compressed transport is optional.
(() => {
 const files = {};
 const build = 'tablet2-20261019';
 const originalFetch = window.fetch.bind(window);
 const loaded = new Map();
 const total = Object.values(files).reduce((n,f)=>n+f.size,0);
 let timer;
 const panel = document.createElement('div');
 panel.id='cargo-loading';
 panel.innerHTML='<div class="cargo-track" role="progressbar" aria-valuemin="0" aria-valuemax="100" aria-label="Loading"><div class="cargo-fill"></div></div><div class="cargo-label" role="status"></div>';
 const label=panel.querySelector('.cargo-label'), fill=panel.querySelector('.cargo-fill'), track=panel.querySelector('.cargo-track');
 const translations = {}; // Injected from reviewed localization during packaging.
 let savedLanguage='';
 try { savedLanguage=localStorage.getItem('cargo-language')||''; } catch (_) {}
 const language=(new URLSearchParams(location.search).get('lang')||savedLanguage||navigator.language||'en').toLowerCase().replace('_','-').split('-')[0];
 const strings=translations[language]||translations.en||{'loading.start':'Starting…','loading.error':'Unable to load. Check your connection and try again.','loading.retry':'Retry'};
 panel.lang=translations[language]?language:'en';
 panel.dir=language==='ar'?'rtl':'ltr';
 let failed=false;
 label.textContent='0%';
 document.body.appendChild(panel);
 const progress = () => {
  const bytes = [...loaded.values()].reduce((a,b)=>a+b,0);
  if(failed)return;
  const percent=total>0?Math.min(100,Math.floor(bytes/total*100)):0;
  fill.style.width=percent+'%';track.setAttribute('aria-valuenow',String(percent));
  label.textContent=bytes>=total ? strings['loading.start'] : percent+'%';
 };
 window.CargoBoot = {
  done(){clearTimeout(timer);panel.remove();},
  fail(error){if(failed)return;failed=true;clearTimeout(timer);label.textContent=strings['loading.error'];console.error(error);const b=document.createElement('button');b.textContent=strings['loading.retry'];b.onclick=()=>location.reload();panel.appendChild(b);}
 };
 timer=setTimeout(()=>window.CargoBoot.fail('Запуск занимает слишком долго. Попробуйте перезагрузить страницу.'),180000);
 async function part(url,key,packed,init) {
  let error;
  for(let attempt=0;attempt<3;attempt++) {
   const controller=new AbortController();
   const timeout=setTimeout(()=>controller.abort(),45000);
   try {
    const response=await originalFetch(url,{...init,cache:'no-store',signal:controller.signal});
    if(!response.ok)throw new Error(`Ошибка загрузки (${response.status}).`);
    if((response.headers.get('Content-Type')||'').includes('text/html'))throw new Error('Проверьте вход в свой аккаунт ChatGPT в Safari.');
    let body=response.body;
    if(packed)body=body.pipeThrough(new DecompressionStream('gzip'));
    const buffers=[];let length=0;
    const reader=body.getReader();
    for(;;){const {done,value}=await reader.read();if(done)break;buffers.push(value);length+=value.length;loaded.set(key,length);progress();}
    const data=new Uint8Array(length);let offset=0;
    for(const buffer of buffers){data.set(buffer,offset);offset+=buffer.length;}
    return data;
   } catch(e){error=e;loaded.delete(key);progress();}
   finally {clearTimeout(timeout);}
  }
  throw error;
 }
 window.fetch=async (input,init)=>{
  const url=new URL(input instanceof Request?input.url:String(input),location.href);
  const name=url.pathname.split('/').pop();const file=files[name];
  if(url.origin!==location.origin||!file)return originalFetch(input,init);
  if(typeof DecompressionStream==='undefined'){ const error=new Error('Обновите браузер для запуска игры.'); window.CargoBoot.fail(error); throw error; }
  const packed=true;
  const stream=new ReadableStream({async start(controller){
   try {
    for(let i=0;i<file.parts;i++){
     const target=new URL(`${name}.part${i}${packed?'.gzdata':''}`,url);
     target.searchParams.set('v',build);
     const data=await part(target,`${name}:${i}`,packed,init);
     const expected=Math.min(file.chunk_size,file.size-i*file.chunk_size);
     if(data.length!==expected)throw new Error('Файл загружен не полностью. Обновите страницу.');
     controller.enqueue(data);
    }
    controller.close();
   }catch(error){controller.error(error);window.CargoBoot.fail(error);}
  }});
  return new Response(stream,{headers:{'Content-Type':file.mime,'Content-Length':String(file.size)}});
 };
})();
